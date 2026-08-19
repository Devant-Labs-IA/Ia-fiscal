-- PostgreSQL 17 runtime fix: qualify the INSERT target in the events CTE before returning job_id.

create or replace function public.ia_fiscal_claim_legal_embedding_jobs(
  p_batch_size integer default 16
)
returns table (
  job_id uuid,
  municipality_id uuid,
  legal_chunk_id uuid,
  content_text text,
  source_sha256 text,
  attempt smallint,
  provider_code text,
  model text,
  model_revision text,
  dimensions integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_runtime_gate_id uuid;
  v_last_municipality_id uuid;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_batch_size not between 1 and 32 then
    raise exception 'embedding batch size must be between 1 and 32';
  end if;

  -- Fail closed before recovering a lease or claiming any work.  The key-share
  -- locks retained by this helper also serialize a concurrent gate revocation
  -- behind this short claim transaction.
  v_runtime_gate_id := private.lock_current_knowledge_runtime_gate_id();
  if v_runtime_gate_id is null then
    raise exception using
      errcode = '55000',
      message = 'knowledge runtime is not verified';
  end if;

  select cursor.last_municipality_id into strict v_last_municipality_id
  from private.legal_embedding_claim_cursors cursor
  where cursor.model_revision = 'gte-small-384-v1'
  for update;

  -- A worker can disappear after claiming. Recover expired leases before the
  -- next claim so no chunk remains in `processing` forever.
  with stale as (
    update private.legal_embedding_jobs job
    set status = case when job.attempts >= 5 then 'dead_letter' else 'failed' end,
        available_at = now(),
        locked_at = null,
        safe_error_code = 'embedding_lease_expired',
        updated_at = now()
    where job.status = 'processing'
      and job.locked_at < now() - interval '10 minutes'
      and exists (
        select 1
        from private.knowledge_automation_settings setting
        where setting.municipality_id = job.municipality_id
          and setting.enabled
      )
    returning job.*
  )
  insert into private.legal_embedding_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    safe_error_code
  )
  select
    stale.municipality_id,
    stale.id,
    case when stale.status = 'dead_letter' then 'dead_lettered' else 'retried' end,
    stale.attempts,
    'embedding_lease_expired'
  from stale;

  return query
  with ranked as materialized (
    select
      job.id,
      job.municipality_id,
      job.available_at,
      job.created_at,
      row_number() over (
        partition by job.municipality_id
        order by job.available_at, job.created_at, job.id
      ) as tenant_rank
    from private.legal_embedding_jobs job
    join private.knowledge_automation_settings setting
      on setting.municipality_id = job.municipality_id
     and setting.enabled
    where job.status in ('queued', 'failed')
      and job.available_at <= now()
  ), candidates as materialized (
    select
      job.id,
      ranked.municipality_id,
      ranked.tenant_rank,
      case
        when v_last_municipality_id is null
          or ranked.municipality_id > v_last_municipality_id then 0
        else 1
      end as tenant_wrap,
      ranked.available_at,
      ranked.created_at
    from private.legal_embedding_jobs job
    join ranked on ranked.id = job.id
    order by
      ranked.tenant_rank,
      case
        when v_last_municipality_id is null
          or ranked.municipality_id > v_last_municipality_id then 0
        else 1
      end,
      ranked.municipality_id,
      ranked.available_at,
      ranked.created_at,
      ranked.id
    for update of job skip locked
    limit p_batch_size
  ), claimed as (
    update private.legal_embedding_jobs job
    set status = 'processing',
        attempts = job.attempts + 1,
        locked_at = now(),
        safe_error_code = null,
        updated_at = now()
    from candidates
    where job.id = candidates.id
    returning job.*
  ), events as (
    insert into private.legal_embedding_job_events as claimed_event (
      municipality_id,
      job_id,
      event_type,
      attempt
    )
    select claimed.municipality_id, claimed.id, 'claimed', claimed.attempts
    from claimed
    returning claimed_event.job_id
  ), cursor_advanced as (
    update private.legal_embedding_claim_cursors cursor
    set last_municipality_id = (
          select candidate.municipality_id
          from candidates candidate
          order by
            candidate.tenant_rank desc,
            candidate.tenant_wrap desc,
            candidate.municipality_id desc,
            candidate.available_at desc,
            candidate.created_at desc,
            candidate.id desc
          limit 1
        ),
        updated_at = now()
    where cursor.model_revision = 'gte-small-384-v1'
      and exists (select 1 from candidates)
    returning cursor.model_revision
  )
  select
    claimed.id,
    claimed.municipality_id,
    claimed.legal_chunk_id,
    chunk.content_text,
    claimed.source_sha256,
    claimed.attempts,
    claimed.provider_code,
    claimed.model,
    claimed.model_revision,
    claimed.dimensions
  from claimed
  join private.legal_chunks chunk
    on chunk.municipality_id = claimed.municipality_id
   and chunk.id = claimed.legal_chunk_id
  join candidates candidate on candidate.id = claimed.id
  join events on events.job_id = claimed.id
  cross join cursor_advanced
  where chunk.content_sha256 = claimed.source_sha256;
end;
$$;
