-- IA Fiscal MVP: integrity, tenant-safe API surface, mature-debt semantics,
-- domain-specific processing guards, idempotent jobs and truthful sandbox state.

-- ---------------------------------------------------------------------------
-- 1. Explicit API grants for the 2026 Supabase Data API defaults.
-- ---------------------------------------------------------------------------

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated;

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

-- These routines mutate fiscal state and are worker-only. Human actions remain
-- available through the AAL2/role-checked case, review and governance RPCs.
revoke execute on function public.ia_run_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) from authenticated;

grant execute on function public.ia_run_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Deterministic maturity rule for current-account entries.
-- ---------------------------------------------------------------------------

create or replace function private.current_account_entry_is_mature(
  p_direction text,
  p_due_on date,
  p_occurred_on date,
  p_as_of date,
  p_homologation_fallback boolean default false
)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select case
    when p_direction = 'credit'
      then p_occurred_on <= p_as_of
    when p_direction = 'debit' and p_due_on is not null
      then p_due_on <= p_as_of
    when p_direction = 'debit' and p_homologation_fallback
      then p_occurred_on <= p_as_of
    else false
  end;
$function$;

revoke all on function private.current_account_entry_is_mature(
  text, date, date, date, boolean
) from public, anon, authenticated;
grant execute on function private.current_account_entry_is_mature(
  text, date, date, date, boolean
) to service_role;

-- Patch the three existing deterministic functions in place. Assertions make
-- the migration fail safely if an earlier migration changed the expected code.
do $migration$
declare
  v_oid regprocedure;
  v_before text;
  v_after text;
  v_needle text;
begin
  v_oid := 'public.ia_run_current_account_detection(uuid,uuid,timestamptz,text,uuid)'::regprocedure;
  select pg_get_functiondef(v_oid) into v_before;
  v_needle := 'and e.competence_month between v_period_start and v_period_end';
  v_after := replace(
    v_before,
    v_needle,
    v_needle || E'\n      and private.current_account_entry_is_mature(\n' ||
      E'        e.direction, e.due_on, e.occurred_on, p_as_of::date, false\n' ||
      E'      )'
  );
  if v_after = v_before then
    raise exception 'current-account live maturity patch point not found';
  end if;
  execute v_after;

  v_oid := 'public.ia_run_homologation_current_account_detection(uuid,uuid,timestamptz,text,uuid)'::regprocedure;
  select pg_get_functiondef(v_oid) into v_before;
  v_after := replace(
    v_before,
    v_needle,
    v_needle || E'\n      and private.current_account_entry_is_mature(\n' ||
      E'        e.direction, e.due_on, e.occurred_on, p_as_of::date, true\n' ||
      E'      )'
  );
  if v_after = v_before then
    raise exception 'current-account homologation maturity patch point not found';
  end if;
  execute v_after;

  v_oid := 'public.ia_process_case_batch_item(uuid)'::regprocedure;
  select pg_get_functiondef(v_oid) into v_before;
  v_after := replace(
    v_before,
    '  if v_divergence.status = ''converted'' then',
    E'  if v_divergence.execution_mode <> ''live'' then\n' ||
    E'    raise exception ''homologation divergences require the sandbox processor'';\n' ||
    E'  end if;\n' ||
    E'  if v_divergence.divergence_type <> ''current_account_balance'' then\n' ||
    E'    raise exception ''divergence type % requires its domain-specific processor'',\n' ||
    E'      v_divergence.divergence_type;\n' ||
    E'  end if;\n\n' ||
    '  if v_divergence.status = ''converted'' then'
  );
  if v_after = v_before then
    raise exception 'case processor domain guard patch point not found';
  end if;
  v_before := v_after;
  v_after := replace(
    v_before,
    'and e.competence_month between v_divergence.period_start and v_divergence.period_end;',
    E'and e.competence_month between v_divergence.period_start and v_divergence.period_end\n' ||
    E'    and private.current_account_entry_is_mature(\n' ||
    E'      e.direction, e.due_on, e.occurred_on, current_date, false\n' ||
    E'    );'
  );
  if v_after = v_before then
    raise exception 'case processor maturity patch point not found';
  end if;
  execute v_after;
end;
$migration$;

-- CREATE OR REPLACE preserves grants, but restate worker-only privileges.
revoke execute on function public.ia_run_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) from public, anon, authenticated;
grant execute on function public.ia_run_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) to service_role;

revoke execute on function public.ia_run_homologation_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) from public, anon, authenticated;
grant execute on function public.ia_run_homologation_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) to service_role;

revoke execute on function public.ia_process_case_batch_item(uuid)
  from public, anon, authenticated;
grant execute on function public.ia_process_case_batch_item(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Queue idempotency: terminal jobs are never mutated by a duplicate enqueue.
-- ---------------------------------------------------------------------------

create or replace function private.enqueue_job(
  p_municipality_id uuid,
  p_job_type text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb,
  p_idempotency_key text,
  p_priority integer default 100,
  p_available_at timestamptz default now(),
  p_max_attempts integer default 5,
  p_correlation_id uuid default gen_random_uuid()
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job_id bigint;
begin
  insert into private.jobs (
    municipality_id, job_type, aggregate_type, aggregate_id, payload,
    idempotency_key, priority, available_at, max_attempts, correlation_id
  )
  values (
    p_municipality_id, p_job_type, p_aggregate_type, p_aggregate_id,
    coalesce(p_payload, '{}'::jsonb), p_idempotency_key, p_priority,
    p_available_at, p_max_attempts, p_correlation_id
  )
  on conflict (municipality_id, idempotency_key)
  do update set
    available_at = least(private.jobs.available_at, excluded.available_at),
    priority = least(private.jobs.priority, excluded.priority)
  where private.jobs.status in ('pending', 'retry')
  returning id into v_job_id;

  if v_job_id is null then
    select j.id into strict v_job_id
    from private.jobs j
    where j.municipality_id = p_municipality_id
      and j.idempotency_key = p_idempotency_key;
  end if;

  return v_job_id;
end;
$function$;

revoke all on function private.enqueue_job(
  uuid, text, text, uuid, jsonb, text, integer, timestamptz, integer, uuid
) from public, anon, authenticated;
grant execute on function private.enqueue_job(
  uuid, text, text, uuid, jsonb, text, integer, timestamptz, integer, uuid
) to service_role;


