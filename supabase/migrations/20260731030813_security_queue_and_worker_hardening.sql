-- IA Fiscal MVP: repair authenticated RLS, close private privilege escalation,
-- enforce semantic idempotency, bound queue retries and expose worker health.

-- ---------------------------------------------------------------------------
-- 1. RLS helper privileges.
-- ---------------------------------------------------------------------------

alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated;

-- Policies call this safe boolean helper directly. Without EXECUTE, RLS raises
-- 42501 instead of returning the permitted rows.
grant execute on function private.has_municipality_role(uuid, text[])
  to authenticated, service_role;
grant execute on function private.is_platform_administrator()
  to authenticated, service_role;

-- These internal mutators were reachable only because PostgreSQL grants
-- EXECUTE to PUBLIC by default. They are never client APIs.
revoke all on function private.consume_rate_limit(
  uuid, uuid, text, integer, integer
) from public, anon, authenticated;
revoke all on function private.next_case_number(uuid)
  from public, anon, authenticated;
revoke all on function private.reserve_email_capacity(
  uuid, uuid, integer, integer, text
) from public, anon, authenticated;
revoke all on function private.release_email_reservation_for_terminal_job()
  from public, anon, authenticated;
revoke all on function private.sync_email_reservation()
  from public, anon, authenticated;

grant execute on function private.consume_rate_limit(
  uuid, uuid, text, integer, integer
) to service_role;
grant execute on function private.next_case_number(uuid)
  to service_role;
grant execute on function private.reserve_email_capacity(
  uuid, uuid, integer, integer, text
) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Semantic idempotency for jobs.
-- ---------------------------------------------------------------------------

alter table private.jobs
  add column if not exists request_sha256 text;

update private.jobs j
set request_sha256 = encode(
  extensions.digest(
    jsonb_build_object(
      'municipality_id', j.municipality_id,
      'job_type', j.job_type,
      'aggregate_type', j.aggregate_type,
      'aggregate_id', j.aggregate_id,
      'payload', j.payload,
      'max_attempts', j.max_attempts
    )::text,
    'sha256'
  ),
  'hex'
)
where j.request_sha256 is null;

alter table private.jobs
  alter column request_sha256 set not null,
  drop constraint if exists jobs_request_sha256_ck,
  add constraint jobs_request_sha256_ck
    check (request_sha256 ~ '^[a-f0-9]{64}$');

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
  v_existing private.jobs%rowtype;
  v_request_sha256 text;
begin
  v_request_sha256 := encode(
    extensions.digest(
      jsonb_build_object(
        'municipality_id', p_municipality_id,
        'job_type', p_job_type,
        'aggregate_type', p_aggregate_type,
        'aggregate_id', p_aggregate_id,
        'payload', coalesce(p_payload, '{}'::jsonb),
        'max_attempts', p_max_attempts
      )::text,
      'sha256'
    ),
    'hex'
  );

  insert into private.jobs (
    municipality_id, job_type, aggregate_type, aggregate_id, payload,
    idempotency_key, priority, available_at, max_attempts, correlation_id,
    request_sha256
  )
  values (
    p_municipality_id, p_job_type, p_aggregate_type, p_aggregate_id,
    coalesce(p_payload, '{}'::jsonb), p_idempotency_key, p_priority,
    p_available_at, p_max_attempts, p_correlation_id, v_request_sha256
  )
  on conflict (municipality_id, idempotency_key) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    return v_job_id;
  end if;

  select j.* into strict v_existing
  from private.jobs j
  where j.municipality_id = p_municipality_id
    and j.idempotency_key = p_idempotency_key
  for update;

  if v_existing.request_sha256 <> v_request_sha256 then
    raise exception using
      errcode = '22023',
      message = 'idempotency_key_reused_with_different_request';
  end if;

  if v_existing.status in ('pending', 'retry') then
    update private.jobs j
    set available_at = least(j.available_at, p_available_at),
        priority = least(j.priority, p_priority)
    where j.id = v_existing.id;
  end if;

  return v_existing.id;
end;
$function$;

revoke all on function private.enqueue_job(
  uuid, text, text, uuid, jsonb, text, integer, timestamptz, integer, uuid
) from public, anon, authenticated;
grant execute on function private.enqueue_job(
  uuid, text, text, uuid, jsonb, text, integer, timestamptz, integer, uuid
) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Bounded lease recovery and dead letter.
-- ---------------------------------------------------------------------------

create or replace function public.ia_claim_jobs(
  p_worker_id text,
  p_limit integer default 10,
  p_lease_seconds integer default 120
)
returns table (
  job_id bigint,
  municipality_id uuid,
  job_type text,
  aggregate_type text,
  aggregate_id uuid,
  payload jsonb,
  attempt_number integer,
  correlation_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;
  if nullif(trim(p_worker_id), '') is null then
    raise exception 'worker_id is required';
  end if;
  if p_limit not between 1 and 100
     or p_lease_seconds not between 30 and 900 then
    raise exception 'invalid claim limits';
  end if;

  update private.jobs j
  set status = 'dead_letter',
      locked_at = null,
      locked_by = null,
      lease_expires_at = null,
      completed_at = now(),
      last_error_code = 'lease_expired_attempts_exhausted',
      updated_at = now()
  where j.status = 'processing'
    and j.lease_expires_at < now()
    and j.attempt_count >= j.max_attempts;

  update private.jobs j
  set status = 'retry',
      locked_at = null,
      locked_by = null,
      lease_expires_at = null,
      available_at = now(),
      last_error_code = 'lease_expired',
      updated_at = now()
  where j.status = 'processing'
    and j.lease_expires_at < now()
    and j.attempt_count < j.max_attempts;

  update private.jobs j
  set status = 'dead_letter',
      completed_at = now(),
      last_error_code = coalesce(
        j.last_error_code,
        'attempts_exhausted_before_claim'
      ),
      updated_at = now()
  where j.status in ('pending', 'retry')
    and j.attempt_count >= j.max_attempts;

  return query
  with candidates as (
    select j.id
    from private.jobs j
    where j.status in ('pending', 'retry')
      and j.attempt_count < j.max_attempts
      and j.available_at <= now()
    order by j.priority, j.available_at, j.id
    limit p_limit
    for update skip locked
  ),
  claimed as (
    update private.jobs j
    set status = 'processing',
        attempt_count = j.attempt_count + 1,
        locked_at = now(),
        locked_by = p_worker_id,
        lease_expires_at = now() + make_interval(secs => p_lease_seconds),
        updated_at = now()
    from candidates c
    where j.id = c.id
    returning j.*
  )
  select
    c.id,
    c.municipality_id,
    c.job_type,
    c.aggregate_type,
    c.aggregate_id,
    c.payload,
    c.attempt_count,
    c.correlation_id
  from claimed c
  order by c.priority, c.id;
end;
$function$;

revoke all on function public.ia_claim_jobs(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.ia_claim_jobs(text, integer, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4. Worker heartbeat and queue health.
-- ---------------------------------------------------------------------------

create table if not exists public.worker_health (
  worker_name text primary key,
  last_worker_id text,
  status text not null default 'unknown'
    check (status in ('unknown', 'started', 'healthy', 'degraded', 'failed')),
  last_started_at timestamptz,
  last_completed_at timestamptz,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_claimed_count integer not null default 0
    check (last_claimed_count >= 0),
  pending_jobs integer not null default 0
    check (pending_jobs >= 0),
  dead_letter_jobs integer not null default 0
    check (dead_letter_jobs >= 0),
  oldest_pending_age interval,
  last_result jsonb not null default '{}'::jsonb
    check (jsonb_typeof(last_result) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.worker_health enable row level security;

drop policy if exists worker_health_select_staff
  on public.worker_health;
create policy worker_health_select_staff
on public.worker_health
for select
to authenticated
using (
  (select private.is_platform_administrator())
  or exists (
    select 1
    from public.municipality_memberships mm
    where mm.user_id = (select auth.uid())
      and mm.status = 'active'
      and mm.role in ('municipal_admin', 'supervisor')
  )
);

revoke all on public.worker_health from public, anon, authenticated;
grant select on public.worker_health to authenticated;
grant select, insert, update, delete on public.worker_health to service_role;

create or replace function public.ia_record_worker_heartbeat(
  p_worker_name text,
  p_worker_id text,
  p_stage text,
  p_claimed_count integer default 0,
  p_result jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_pending_jobs integer;
  v_dead_letter_jobs integer;
  v_oldest_pending_age interval;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;
  if nullif(trim(p_worker_name), '') is null
     or nullif(trim(p_worker_id), '') is null then
    raise exception 'worker identity is required';
  end if;
  if p_stage not in ('started', 'completed', 'failed') then
    raise exception 'invalid worker heartbeat stage';
  end if;
  if p_claimed_count < 0 then
    raise exception 'invalid claimed count';
  end if;

  select
    count(*) filter (where j.status in ('pending', 'retry'))::integer,
    count(*) filter (where j.status = 'dead_letter')::integer,
    max(now() - j.created_at) filter (
      where j.status in ('pending', 'retry')
    )
  into v_pending_jobs, v_dead_letter_jobs, v_oldest_pending_age
  from private.jobs j;

  insert into public.worker_health (
    worker_name, last_worker_id, status, last_started_at,
    last_completed_at, last_success_at, last_error_at,
    last_claimed_count, pending_jobs, dead_letter_jobs,
    oldest_pending_age, last_result, updated_at
  )
  values (
    p_worker_name,
    p_worker_id,
    case
      when p_stage = 'started' then 'started'
      when p_stage = 'completed' then 'healthy'
      else 'failed'
    end,
    case when p_stage = 'started' then now() end,
    case when p_stage = 'completed' then now() end,
    case when p_stage = 'completed' then now() end,
    case when p_stage = 'failed' then now() end,
    p_claimed_count,
    v_pending_jobs,
    v_dead_letter_jobs,
    v_oldest_pending_age,
    coalesce(p_result, '{}'::jsonb),
    now()
  )
  on conflict (worker_name) do update
  set last_worker_id = excluded.last_worker_id,
      status = excluded.status,
      last_started_at = coalesce(
        excluded.last_started_at,
        public.worker_health.last_started_at
      ),
      last_completed_at = coalesce(
        excluded.last_completed_at,
        public.worker_health.last_completed_at
      ),
      last_success_at = coalesce(
        excluded.last_success_at,
        public.worker_health.last_success_at
      ),
      last_error_at = coalesce(
        excluded.last_error_at,
        public.worker_health.last_error_at
      ),
      last_claimed_count = excluded.last_claimed_count,
      pending_jobs = excluded.pending_jobs,
      dead_letter_jobs = excluded.dead_letter_jobs,
      oldest_pending_age = excluded.oldest_pending_age,
      last_result = excluded.last_result,
      updated_at = now();
end;
$function$;

revoke all on function public.ia_record_worker_heartbeat(
  text, text, text, integer, jsonb
) from public, anon, authenticated;
grant execute on function public.ia_record_worker_heartbeat(
  text, text, text, integer, jsonb
) to service_role;

create or replace view public.api_worker_health
with (security_invoker = true)
as
select
  wh.worker_name,
  wh.status,
  wh.last_started_at,
  wh.last_completed_at,
  wh.last_success_at,
  wh.last_error_at,
  wh.last_claimed_count,
  wh.pending_jobs,
  wh.dead_letter_jobs,
  wh.oldest_pending_age,
  wh.updated_at,
  wh.last_result
from public.worker_health wh;

revoke all on public.api_worker_health from public, anon, authenticated;
grant select on public.api_worker_health to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Homologation can never reach the external notification worker.
-- ---------------------------------------------------------------------------

do $migration$
declare
  v_oid regprocedure;
  v_before text;
  v_after text;
  v_needle text;
begin
  v_oid := 'public.ia_get_notification_job_context(bigint)'::regprocedure;
  select pg_get_functiondef(v_oid) into v_before;
  v_needle := '  if v_case.status in (''cancelled'', ''resolved'', ''closed'') then';
  v_after := replace(
    v_before,
    v_needle,
    E'  if v_case.execution_mode <> ''live''\n' ||
    E'     or v_notification.execution_mode <> ''live''\n' ||
    E'     or v_notification.delivery_mode <> ''external''\n' ||
    E'     or v_recipient.delivery_mode <> ''external'' then\n' ||
    E'    v_reason := ''sandbox_delivery_forbidden'';\n' ||
    E'  elsif v_case.status in (''cancelled'', ''resolved'', ''closed'') then'
  );
  if v_after = v_before then
    raise exception 'notification context sandbox guard patch point not found';
  end if;
  execute v_after;
end;
$migration$;

create or replace function public.ia_mark_email_delivery_attempted(
  p_job_id bigint,
  p_worker_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job private.jobs%rowtype;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'send_initial_notice'
    and j.status = 'processing'
    and j.locked_by = p_worker_id
    and j.lease_expires_at > now()
  for update;

  update public.notification_recipients nr
  set external_delivery_attempted = true
  where nr.municipality_id = v_job.municipality_id
    and nr.id = v_job.aggregate_id
    and nr.delivery_mode = 'external';

  if not found then
    raise exception 'external delivery attempt is not allowed';
  end if;

  update public.notifications n
  set external_delivery_attempted = true
  from public.notification_recipients nr
  where nr.municipality_id = v_job.municipality_id
    and nr.id = v_job.aggregate_id
    and n.municipality_id = nr.municipality_id
    and n.id = nr.notification_id
    and n.execution_mode = 'live'
    and n.delivery_mode = 'external';

  if not found then
    raise exception 'live notification not found';
  end if;
end;
$function$;

revoke all on function public.ia_mark_email_delivery_attempted(bigint, text)
  from public, anon, authenticated;
grant execute on function public.ia_mark_email_delivery_attempted(bigint, text)
  to service_role;

