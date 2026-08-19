-- Segundo Cerebro Fiscal, fase 2: activation gate.
--
-- Apply only after the three Edge Functions are deployed, the official PDF
-- smoke suite is retained, and ia_fiscal_attest_knowledge_runtime_ready has
-- stored its SHA-256.  This migration then enables the governed official-source
-- refresh for Cordeiropolis and Araras only; it cannot send taxpayer/client
-- communications and never bypasses the ingestion review gates.

begin;

do $$
declare
  v_runtime_gate_id uuid;
begin
  -- Serialize activation/configuration changes so the exact enabled tenant set
  -- cannot change between the precondition and the release-scoped update.
  lock table private.knowledge_automation_settings in share row exclusive mode;
  if not private.knowledge_runtime_is_verified() then
    raise exception using
      errcode = '55000',
      message = 'knowledge runtime release gate is not verified',
      hint = 'Deploy ingest/embed/search, run the smoke suite and attest its SHA-256 first.';
  end if;
  v_runtime_gate_id := private.current_knowledge_runtime_gate_id();
  perform 1
  from private.knowledge_runtime_release_gates gate
  where gate.project_ref = private.knowledge_scheduler_project_ref()
    and gate.id = v_runtime_gate_id
  for share;
  if not found then
    raise exception using
      errcode = '55000',
      message = 'current knowledge runtime gate changed during activation';
  end if;
  perform 1
  from private.knowledge_runtime_current_gates current_gate
  where current_gate.project_ref = private.knowledge_scheduler_project_ref()
    and current_gate.runtime_gate_id = v_runtime_gate_id
  for share;
  if not found then
    raise exception using
      errcode = '55000',
      message = 'current knowledge runtime gate changed during activation';
  end if;
  if not exists (
    select 1 from vault.secrets secret
    where secret.name = 'ia_fiscal_knowledge_project_url'
  ) then
    raise exception using
      errcode = '55000',
      message = 'knowledge scheduler project URL is not configured';
  end if;
  if not exists (
    select 1 from vault.secrets secret
    where secret.name = 'ia_fiscal_knowledge_scheduler_secret'
  ) then
    raise exception using
      errcode = '55000',
      message = 'knowledge scheduler secret is not configured';
  end if;
  if (
    select count(*)
    from (values
      ('cordeiropolis-sp'::text, 'active'::text),
      ('araras-sp'::text, 'homologation'::text)
    ) expected(slug, status)
    join public.municipalities municipality
      on municipality.slug = expected.slug
     and municipality.status = expected.status
  ) <> 2 then
    raise exception using
      errcode = '55000',
      message = 'target municipalities do not match the explicit release readiness profile';
  end if;
  if exists (
    select 1
    from private.knowledge_automation_settings setting
    join public.municipalities municipality
      on municipality.id = setting.municipality_id
    where setting.enabled
      and municipality.slug not in ('cordeiropolis-sp', 'araras-sp')
  ) then
    raise exception using
      errcode = '55000',
      message = 'a non-target municipality already has knowledge automation enabled';
  end if;
  if exists (
    select 1
    from public.municipalities municipality
    where municipality.slug in ('cordeiropolis-sp', 'araras-sp')
      and (
        not exists (
          select 1
          from private.legal_source_endpoints endpoint
          where endpoint.municipality_id = municipality.id
            and endpoint.status = 'active'
            and endpoint.content_mode = 'legal_body'
            and endpoint.citable_body
        )
        or not exists (
          select 1
          from private.legal_source_endpoints endpoint
          where endpoint.municipality_id = municipality.id
            and endpoint.status = 'active'
            and endpoint.content_mode = 'catalog_only'
            and not endpoint.citable_body
        )
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'target municipality has no active governed knowledge endpoint';
  end if;
end;
$$;

-- Semantic generation is retired for the installed English-only model.
-- Activation deliberately creates no embedding job (queued or otherwise);
-- the canonical scheduler dispatches governed ingestion only.
do $$
begin
  if exists (
    select 1
    from private.legal_embedding_jobs job
    where job.model_revision = 'gte-small-384-v1'
      and job.status in ('queued', 'processing', 'failed', 'dead_letter')
  ) then
    raise exception using
      errcode = '55000',
      message = 'retired semantic jobs remain claimable before activation';
  end if;
end;
$$;

-- Release-scoped activation is explicit and auditable.  A blocked upstream
-- remains scheduled: fetch health/circuit-breaker state is surfaced in the
-- snapshot and no blocked document is promoted or published automatically.
with target as (
  select municipality.id, municipality.timezone, municipality.status
  from (values
    ('cordeiropolis-sp'::text, 'active'::text),
    ('araras-sp'::text, 'homologation'::text)
  ) expected(slug, status)
  join public.municipalities municipality
    on municipality.slug = expected.slug
   and municipality.status = expected.status
), current_gate as (
  select private.current_knowledge_runtime_gate_id() as id
), enabled_settings as (
  insert into private.knowledge_automation_settings (
    municipality_id,
    enabled,
    cadence_minutes,
    local_run_time,
    timezone,
    next_run_at,
    last_run_status,
    last_safe_error_code
  )
  select
    target.id,
    true,
    1440,
    time '03:15',
    target.timezone,
    case
      when ((private.municipality_current_date(target.id) + time '03:15')
        at time zone target.timezone) > now()
        then ((private.municipality_current_date(target.id) + time '03:15')
          at time zone target.timezone)
      else ((private.municipality_current_date(target.id) + 1 + time '03:15')
        at time zone target.timezone)
    end,
    null,
    null
  from target
  on conflict (municipality_id) do update set
    enabled = true,
    cadence_minutes = 1440,
    local_run_time = time '03:15',
    timezone = excluded.timezone,
    next_run_at = excluded.next_run_at,
    last_safe_error_code = null,
    updated_at = now()
  returning municipality_id
)
insert into private.knowledge_schedule_activation_events (
  municipality_id,
  enabled,
  actor_kind,
  runtime_gate_id,
  reason_code,
  metadata
)
select
  enabled_settings.municipality_id,
  true,
  'release_migration',
  current_gate.id,
  'phase2_release_enabled_official_refresh',
  jsonb_build_object(
    'cadence_minutes', 1440,
    'local_run_time', '03:15',
    'client_communication_enabled', false,
    'municipality_status', target.status,
    'scope', 'internal_knowledge_refresh_only'
  )
from enabled_settings
join target on target.id = enabled_settings.municipality_id
cross join current_gate;

do $$
begin
  if (
    select count(*)
    from private.knowledge_automation_settings setting
    join public.municipalities municipality
      on municipality.id = setting.municipality_id
    where setting.enabled
      and municipality.slug in ('cordeiropolis-sp', 'araras-sp')
      and (
        (municipality.slug = 'cordeiropolis-sp' and municipality.status = 'active')
        or (municipality.slug = 'araras-sp' and municipality.status = 'homologation')
      )
  ) <> 2 or exists (
    select 1
    from private.knowledge_automation_settings setting
    join public.municipalities municipality
      on municipality.id = setting.municipality_id
    where setting.enabled
      and municipality.slug not in ('cordeiropolis-sp', 'araras-sp')
  ) then
    raise exception using
      errcode = '55000',
      message = 'release activation did not produce the exact two-tenant target set';
  end if;
  if (
    select count(distinct event.municipality_id)
    from private.knowledge_schedule_activation_events event
    where event.reason_code = 'phase2_release_enabled_official_refresh'
      and event.enabled
      and event.runtime_gate_id = private.current_knowledge_runtime_gate_id()
  ) <> 2 or exists (
    select 1
    from private.knowledge_schedule_activation_events event
    join public.municipalities municipality
      on municipality.id = event.municipality_id
    where event.reason_code = 'phase2_release_enabled_official_refresh'
      and event.enabled
      and event.runtime_gate_id = private.current_knowledge_runtime_gate_id()
      and event.metadata ->> 'municipality_status' is distinct from municipality.status
  ) then
    raise exception using
      errcode = '55000',
      message = 'release activation event did not retain municipality readiness status';
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

  perform cron.schedule(
    'ia-fiscal-knowledge-refresh-v2',
    '*/5 * * * *',
    'select private.ia_fiscal_dispatch_due_knowledge_work(20);'
  );
end;
$$;

commit;
