-- Forward compensation for make_portuguese_lexical_search_canonical.
--
-- This is intentionally not an automatic down migration. It restores the
-- preserved database implementations only while automation is disabled,
-- unschedules the dispatcher, and converts a previously-processing lease to a
-- retryable failure rather than resurrecting a stale lock. The lexical index
-- and retained vectors remain intact as audit evidence.

begin;

lock table private.knowledge_automation_settings in share row exclusive mode;
lock table private.legal_embedding_jobs in share row exclusive mode;

do $$
begin
  if private.knowledge_runtime_is_verified() then
    raise exception using
      errcode = '55000',
      message = 'revoke the current knowledge runtime gate before lexical rollback';
  end if;
  if exists (
    select 1
    from private.knowledge_automation_settings setting
    where setting.enabled
  ) then
    raise exception using
      errcode = '55000',
      message = 'no knowledge automation setting may be enabled during lexical rollback';
  end if;
end;
$$;

do $$
declare
  v_existing_job_id bigint;
begin
  select job.jobid into v_existing_job_id
  from cron.job job
  where job.jobname = 'ia-fiscal-knowledge-refresh-v2';
  if v_existing_job_id is not null then
    perform cron.unschedule(v_existing_job_id);
  end if;
end;
$$;

-- Preserve the canonical implementations under inert names before restoring
-- their predecessors. This keeps the rollback itself forward-reversible.
alter function private.enqueue_legal_embedding_job()
  rename to enqueue_legal_embedding_job_lexical_ptbr_noop;
alter function private.enqueue_legal_embedding_job_pre_lexical_ptbr()
  rename to enqueue_legal_embedding_job;

drop trigger legal_chunks_enqueue_embedding on private.legal_chunks;
create trigger legal_chunks_enqueue_embedding
after insert on private.legal_chunks
for each row execute function private.enqueue_legal_embedding_job();

alter function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  rename to ia_fiscal_claim_legal_embedding_jobs_lexical_ptbr_noop;
alter function public.ia_fiscal_claim_legal_embedding_jobs_pre_lexical_ptbr(integer)
  rename to ia_fiscal_claim_legal_embedding_jobs;

alter function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) rename to ia_fiscal_hybrid_search_legal_knowledge_lexical_ptbr;
alter function public.ia_fiscal_hybrid_search_legal_knowledge_pre_lexical_ptbr(
  uuid, text, text, integer
) rename to ia_fiscal_hybrid_search_legal_knowledge;

alter function private.ia_fiscal_dispatch_due_knowledge_work(integer)
  rename to ia_fiscal_dispatch_due_knowledge_work_lexical_ptbr_ingest_only;
alter function private.ia_fiscal_dispatch_due_knowledge_work_pre_lexical_ptbr(integer)
  rename to ia_fiscal_dispatch_due_knowledge_work;

alter function public.ia_get_knowledge_operations_snapshot(uuid)
  rename to ia_get_knowledge_operations_snapshot_lexical_ptbr;
alter function public.ia_get_knowledge_operations_snapshot_pre_lexical_ptbr(uuid)
  rename to ia_get_knowledge_operations_snapshot;

-- Restore only jobs terminalized by the canonical migration. A processing
-- lease cannot safely be resurrected, so it becomes an immediately available
-- failed job with a specific compensation code.
with retirement as materialized (
  select distinct on (event.job_id)
    event.id as retirement_event_id,
    event.job_id,
    event.municipality_id,
    event.metadata ->> 'previous_status' as previous_status,
    nullif(event.metadata ->> 'previous_available_at', '')::timestamptz
      as previous_available_at,
    nullif(event.metadata ->> 'previous_safe_error_code', '')
      as previous_safe_error_code
  from private.legal_embedding_job_events event
  where event.safe_error_code = 'semantic_model_language_unsupported'
    and event.metadata ->> 'retirement_migration' =
      'make_portuguese_lexical_search_canonical'
    and event.metadata ->> 'previous_status' in (
      'queued', 'processing', 'failed', 'dead_letter'
    )
    and not exists (
      select 1
      from private.legal_embedding_job_events compensated
      where compensated.metadata ->> 'compensates_event_id' = event.id::text
    )
  order by event.job_id, event.id desc
), restored as (
  update private.legal_embedding_jobs job
  set status = case retirement.previous_status
        when 'processing' then 'failed'
        else retirement.previous_status
      end,
      available_at = case retirement.previous_status
        when 'processing' then now()
        else coalesce(retirement.previous_available_at, now())
      end,
      locked_at = null,
      completed_at = null,
      safe_error_code = case retirement.previous_status
        when 'processing' then 'semantic_retirement_rollback_processing_requeued'
        else retirement.previous_safe_error_code
      end,
      updated_at = now()
  from retirement
  where job.id = retirement.job_id
    and job.municipality_id = retirement.municipality_id
    and job.model_revision = 'gte-small-384-v1'
    and job.status = 'skipped'
    and job.safe_error_code = 'semantic_model_language_unsupported'
  returning
    job.id,
    job.municipality_id,
    job.status,
    job.attempts,
    job.safe_error_code,
    retirement.previous_status,
    retirement.retirement_event_id
)
insert into private.legal_embedding_job_events (
  municipality_id,
  job_id,
  event_type,
  attempt,
  safe_error_code,
  metadata
)
select
  restored.municipality_id,
  restored.id,
  case restored.status
    when 'queued' then 'queued'
    when 'dead_letter' then 'dead_lettered'
    else 'retried'
  end,
  restored.attempts,
  restored.safe_error_code,
  jsonb_build_object(
    'compensation', 'rollback_portuguese_lexical_search',
    'compensates_event_id', restored.retirement_event_id,
    'previous_status', restored.previous_status,
    'restored_status', restored.status,
    'automation_enabled', false,
    'dispatcher_scheduled', false
  )
from restored;

revoke all on function private.enqueue_legal_embedding_job()
  from public, anon, authenticated, service_role;
revoke all on function private.enqueue_legal_embedding_job_lexical_ptbr_noop()
  from public, anon, authenticated, service_role;
revoke all on function private.ia_fiscal_dispatch_due_knowledge_work(integer)
  from public, anon, authenticated, service_role;
revoke all on function private.ia_fiscal_dispatch_due_knowledge_work_lexical_ptbr_ingest_only(integer)
  from public, anon, authenticated, service_role;

revoke all on function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  to service_role;
revoke all on function public.ia_fiscal_claim_legal_embedding_jobs_lexical_ptbr_noop(integer)
  from public, anon, authenticated, service_role;

revoke all on function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) to authenticated;
revoke all on function public.ia_fiscal_hybrid_search_legal_knowledge_lexical_ptbr(
  uuid, text, text, integer
) from public, anon, authenticated, service_role;

revoke all on function public.ia_get_knowledge_operations_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_knowledge_operations_snapshot(uuid)
  to authenticated;
revoke all on function public.ia_get_knowledge_operations_snapshot_lexical_ptbr(uuid)
  from public, anon, authenticated, service_role;

commit;
