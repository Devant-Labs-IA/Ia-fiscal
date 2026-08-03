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


