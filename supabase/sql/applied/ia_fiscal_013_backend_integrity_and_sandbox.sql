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

-- ---------------------------------------------------------------------------
-- 4. Truthful sandbox delivery state. Captured is not sent.
-- ---------------------------------------------------------------------------

alter table public.notifications
  add column if not exists delivery_mode text not null default 'external',
  add column if not exists external_delivery_attempted boolean not null default false;

alter table public.notification_recipients
  add column if not exists delivery_mode text not null default 'external',
  add column if not exists external_delivery_attempted boolean not null default false;

alter table public.notification_batches
  add column if not exists captured_notifications integer not null default 0;

alter table public.notifications
  drop constraint if exists notifications_delivery_mode_ck,
  add constraint notifications_delivery_mode_ck
    check (delivery_mode in ('external', 'sandbox_capture')),
  drop constraint if exists notifications_homologation_no_external_ck,
  add constraint notifications_homologation_no_external_ck
    check (not (
      execution_mode = 'homologation_test'
      and external_delivery_attempted
    ));

alter table public.notification_recipients
  drop constraint if exists notification_recipients_delivery_mode_ck,
  add constraint notification_recipients_delivery_mode_ck
    check (delivery_mode in ('external', 'sandbox_capture')),
  drop constraint if exists notification_recipients_sandbox_no_external_ck,
  add constraint notification_recipients_sandbox_no_external_ck
    check (not (
      delivery_mode = 'sandbox_capture'
      and external_delivery_attempted
    ));

alter table public.notification_batches
  drop constraint if exists notification_batches_captured_notifications_check,
  add constraint notification_batches_captured_notifications_check
    check (captured_notifications >= 0);

create or replace function private.normalize_homologation_case_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.execution_mode = 'homologation_test'
     and new.status = 'initial_notice_sent' then
    new.status := 'initial_notice_pending';
  end if;
  return new;
end;
$function$;

create or replace function private.normalize_homologation_notification_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.execution_mode = 'homologation_test' then
    new.delivery_mode := 'sandbox_capture';
    new.external_delivery_attempted := false;
    if new.status in ('queued', 'processing', 'sent') then
      new.status := 'prepared';
    end if;
    new.queued_at := null;
    new.sent_at := null;
  end if;
  return new;
end;
$function$;

create or replace function private.normalize_homologation_recipient_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_execution_mode text;
begin
  select n.execution_mode into strict v_execution_mode
  from public.notifications n
  where n.municipality_id = new.municipality_id
    and n.id = new.notification_id;

  if v_execution_mode = 'homologation_test' then
    new.delivery_mode := 'sandbox_capture';
    new.external_delivery_attempted := false;
    if new.status in ('queued', 'sent', 'delivered') then
      new.status := 'pending';
    end if;
    new.sent_at := null;
    new.delivered_at := null;
  end if;
  return new;
end;
$function$;

create or replace function private.normalize_homologation_batch_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_execution_mode text;
begin
  select b.execution_mode into v_execution_mode
  from public.case_opening_batches b
  where b.municipality_id = new.municipality_id
    and b.id = new.case_opening_batch_id;

  if v_execution_mode = 'homologation_test' then
    new.sent_notifications := 0;
    new.captured_notifications := greatest(
      new.captured_notifications,
      new.total_notifications
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists a00_normalize_homologation_case_state
  on public.fiscal_cases;
create trigger a00_normalize_homologation_case_state
before insert or update on public.fiscal_cases
for each row execute function private.normalize_homologation_case_state();

drop trigger if exists a00_normalize_homologation_notification_state
  on public.notifications;
create trigger a00_normalize_homologation_notification_state
before insert or update on public.notifications
for each row execute function private.normalize_homologation_notification_state();

drop trigger if exists a00_normalize_homologation_recipient_state
  on public.notification_recipients;
create trigger a00_normalize_homologation_recipient_state
before insert or update on public.notification_recipients
for each row execute function private.normalize_homologation_recipient_state();

drop trigger if exists a00_normalize_homologation_batch_state
  on public.notification_batches;
create trigger a00_normalize_homologation_batch_state
before insert or update on public.notification_batches
for each row execute function private.normalize_homologation_batch_state();

revoke all on function private.normalize_homologation_case_state()
  from public, anon, authenticated;
revoke all on function private.normalize_homologation_notification_state()
  from public, anon, authenticated;
revoke all on function private.normalize_homologation_recipient_state()
  from public, anon, authenticated;
revoke all on function private.normalize_homologation_batch_state()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Every sandbox case receives an immutable, domain-aware finding.
-- ---------------------------------------------------------------------------

create or replace function private.ensure_homologation_case_finding(
  p_case_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_case public.fiscal_cases%rowtype;
  v_divergence public.divergences%rowtype;
  v_finding_id uuid;
  v_revalidation_id uuid;
  v_revalidation_number integer;
  v_missing_due_count integer := 0;
  v_snapshot jsonb;
  v_hash text;
begin
  select fc.* into strict v_case
  from public.fiscal_cases fc
  where fc.id = p_case_id
  for share;

  if v_case.execution_mode <> 'homologation_test' then
    return null;
  end if;

  select cf.id into v_finding_id
  from public.case_findings cf
  where cf.municipality_id = v_case.municipality_id
    and cf.case_id = v_case.id;
  if v_finding_id is not null then
    return v_finding_id;
  end if;

  select d.* into strict v_divergence
  from public.divergences d
  where d.municipality_id = v_case.municipality_id
    and d.id = v_case.divergence_id
    and d.execution_mode = 'homologation_test'
  for share;

  if v_divergence.divergence_type = 'current_account_balance' then
    select count(*) into v_missing_due_count
    from public.divergence_items di
    join public.current_account_entries e
      on e.municipality_id = di.municipality_id
     and e.id = di.current_account_entry_id
    where di.municipality_id = v_divergence.municipality_id
      and di.divergence_id = v_divergence.id
      and e.direction = 'debit'
      and e.due_on is null;
  end if;

  v_snapshot := jsonb_build_object(
    'divergence_type', v_divergence.divergence_type,
    'execution_mode', 'homologation_test',
    'external_delivery', false,
    'revalidated_at', now(),
    'assessed_amount', v_divergence.assessed_amount,
    'paid_amount', v_divergence.paid_amount,
    'other_credits_amount', v_divergence.other_credits_amount,
    'difference_amount', v_divergence.difference_amount,
    'source_snapshot', v_divergence.source_snapshot,
    'evidence_complete', v_missing_due_count = 0,
    'missing_due_date_count', v_missing_due_count
  );
  v_hash := encode(
    extensions.digest(v_snapshot::text, 'sha256'),
    'hex'
  );

  select coalesce(max(r.revalidation_number), 0) + 1
    into v_revalidation_number
  from public.divergence_revalidations r
  where r.municipality_id = v_divergence.municipality_id
    and r.divergence_id = v_divergence.id;

  insert into public.divergence_revalidations (
    municipality_id, divergence_id, revalidation_number,
    assessed_amount, paid_amount, other_credits_amount, difference_amount,
    eligible, block_reasons, source_snapshot, snapshot_sha256, performed_by
  )
  values (
    v_divergence.municipality_id, v_divergence.id, v_revalidation_number,
    v_divergence.assessed_amount, v_divergence.paid_amount,
    v_divergence.other_credits_amount, v_divergence.difference_amount,
    true,
    case
      when v_missing_due_count > 0 then jsonb_build_array(
        jsonb_build_object(
          'code', 'missing_due_date_homologation_fallback',
          'count', v_missing_due_count
        )
      )
      else '[]'::jsonb
    end,
    v_snapshot, v_hash, null
  )
  returning id into v_revalidation_id;

  insert into public.case_findings (
    municipality_id, case_id, divergence_id, rule_version_id,
    revalidation_id, assessed_amount, paid_amount, other_credits_amount,
    difference_amount, period_start, period_end, finding_snapshot,
    content_sha256
  )
  values (
    v_case.municipality_id, v_case.id, v_divergence.id,
    v_divergence.rule_version_id, v_revalidation_id,
    v_divergence.assessed_amount, v_divergence.paid_amount,
    v_divergence.other_credits_amount, v_divergence.difference_amount,
    v_divergence.period_start, v_divergence.period_end,
    v_snapshot, v_hash
  )
  returning id into v_finding_id;

  return v_finding_id;
end;
$function$;

create or replace function private.ensure_homologation_case_finding_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.ensure_homologation_case_finding(new.id);
  return new;
end;
$function$;

drop trigger if exists z90_ensure_homologation_case_finding
  on public.fiscal_cases;
create trigger z90_ensure_homologation_case_finding
after insert on public.fiscal_cases
for each row
when (new.execution_mode = 'homologation_test')
execute function private.ensure_homologation_case_finding_trigger();

revoke all on function private.ensure_homologation_case_finding(uuid)
  from public, anon, authenticated;
revoke all on function private.ensure_homologation_case_finding_trigger()
  from public, anon, authenticated;
grant execute on function private.ensure_homologation_case_finding(uuid)
  to service_role;

-- Correct previously captured sandbox records without altering their content.
update public.fiscal_cases
set status = 'initial_notice_pending'
where execution_mode = 'homologation_test'
  and status = 'initial_notice_sent';

update public.notifications
set delivery_mode = 'sandbox_capture',
    external_delivery_attempted = false,
    status = 'prepared',
    queued_at = null,
    sent_at = null
where execution_mode = 'homologation_test';

update public.notification_recipients nr
set delivery_mode = 'sandbox_capture',
    external_delivery_attempted = false,
    status = 'pending',
    sent_at = null,
    delivered_at = null
from public.notifications n
where n.municipality_id = nr.municipality_id
  and n.id = nr.notification_id
  and n.execution_mode = 'homologation_test';

update public.notification_batches nb
set sent_notifications = 0,
    captured_notifications = greatest(
      nb.captured_notifications,
      nb.total_notifications
    )
from public.case_opening_batches cb
where cb.municipality_id = nb.municipality_id
  and cb.id = nb.case_opening_batch_id
  and cb.execution_mode = 'homologation_test';

select private.ensure_homologation_case_finding(fc.id)
from public.fiscal_cases fc
where fc.execution_mode = 'homologation_test';

insert into public.case_events (
  municipality_id, case_id, event_type, visibility, actor_type, event_data
)
select
  fc.municipality_id,
  fc.id,
  'homologation_delivery_state_corrected',
  'staff',
  'service',
  jsonb_build_object(
    'external_delivery', false,
    'notification_state', 'sandbox_capture',
    'migration', 'ia_fiscal_013_backend_integrity_and_sandbox'
  )
from public.fiscal_cases fc
where fc.execution_mode = 'homologation_test'
  and not exists (
    select 1
    from public.case_events ce
    where ce.municipality_id = fc.municipality_id
      and ce.case_id = fc.id
      and ce.event_type = 'homologation_delivery_state_corrected'
  );

-- ---------------------------------------------------------------------------
-- 6. Search/read models: due evidence and finding coverage are explicit.
-- ---------------------------------------------------------------------------

create or replace view public.vw_current_account_period
with (security_invoker = true)
as
with period_amounts as (
  select
    e.municipality_id,
    e.taxpayer_id,
    e.competence_month,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit' and e.status = 'valid'
    ), 0)::numeric(18,2) as valor_emitido,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and e.due_on is not null
        and e.due_on <= current_date
    ), 0)::numeric(18,2) as valor_vencido,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and e.due_on is null
    ), 0)::numeric(18,2) as valor_sem_vencimento,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and e.due_on > current_date
    ), 0)::numeric(18,2) as valor_a_vencer,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind = 'payment'
        and e.status = 'valid'
        and e.occurred_on <= current_date
    ), 0)::numeric(18,2) as valor_pago,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind <> 'payment'
        and e.status = 'valid'
        and e.occurred_on <= current_date
    ), 0)::numeric(18,2) as outros_creditos,
    min(e.due_on) filter (where e.direction = 'debit') as primeiro_vencimento,
    max(e.due_on) filter (where e.direction = 'debit') as ultimo_vencimento,
    max(e.imported_at) as data_base,
    count(distinct e.source_system_id) as qtd_fontes
  from public.current_account_entries e
  group by e.municipality_id, e.taxpayer_id, e.competence_month
)
select
  p.municipality_id as municipio_id,
  p.taxpayer_id as contribuinte_id,
  t.tax_id,
  t.legal_name as razao_social,
  p.competence_month as competencia,
  p.valor_emitido,
  p.valor_pago,
  greatest(
    p.valor_vencido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as saldo_em_aberto,
  greatest(
    p.valor_vencido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as divergencia_conta_corrente,
  case
    when p.valor_sem_vencimento > 0 then 'dados_incompletos'
    when greatest(
      p.valor_vencido - p.valor_pago - p.outros_creditos, 0
    ) > 0 then 'em_aberto'
    when p.valor_a_vencer > 0 then 'a_vencer'
    else 'pago'
  end as status,
  (
    p.valor_sem_vencimento = 0
    and greatest(
      p.valor_vencido - p.valor_pago - p.outros_creditos, 0
    ) > 0
  ) as elegivel,
  'current-account-maturity-v2'::text as regra_versao,
  p.data_base,
  p.qtd_fontes,
  p.valor_vencido,
  p.valor_sem_vencimento,
  p.valor_a_vencer,
  greatest(
    p.valor_emitido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as saldo_reportado,
  p.primeiro_vencimento,
  p.ultimo_vencimento
from period_amounts p
join public.taxpayers t
  on t.municipality_id = p.municipality_id
 and t.id = p.taxpayer_id;

create or replace view public.vw_fiscal_divergence_search
with (security_invoker = true)
as
select
  d.municipality_id,
  d.id as divergence_id,
  d.taxpayer_id,
  t.tax_id,
  t.legal_name,
  d.divergence_type,
  d.period_start,
  d.period_end,
  d.difference_amount,
  d.threshold_amount,
  d.priority_score,
  d.status,
  d.execution_mode,
  d.as_of,
  d.rule_version_id,
  d.detection_run_id,
  d.block_reasons,
  rv.version as rule_version_number,
  rv.status as rule_version_status,
  r.code as rule_code,
  exists (
    select 1
    from public.case_findings cf
    where cf.municipality_id = d.municipality_id
      and cf.divergence_id = d.id
  ) as has_case_finding,
  (
    select count(*)
    from public.case_findings cf
    where cf.municipality_id = d.municipality_id
      and cf.divergence_id = d.id
  )::integer as case_finding_count
from public.divergences d
join public.taxpayers t
  on t.municipality_id = d.municipality_id
 and t.id = d.taxpayer_id
join public.divergence_rule_versions rv
  on rv.municipality_id = d.municipality_id
 and rv.id = d.rule_version_id
join public.divergence_rules r
  on r.municipality_id = rv.municipality_id
 and r.id = rv.rule_id;

revoke all on public.vw_current_account_period from anon, authenticated;
revoke all on public.vw_fiscal_divergence_search from anon, authenticated;
grant select on public.vw_current_account_period to authenticated, service_role;
grant select on public.vw_fiscal_divergence_search to authenticated, service_role;

comment on view public.vw_current_account_period is
  'Conta corrente com vencimento comprovado. Linhas sem due_on permanecem visíveis, mas inelegíveis.';
comment on view public.vw_fiscal_divergence_search is
  'Busca fiscal tenant-safe com cobertura explícita de achado imutável por processo.';
