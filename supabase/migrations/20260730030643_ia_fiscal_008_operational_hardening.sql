begin;

-- Supabase's event-trigger helper does not need to be exposed as an RPC.
revoke all on function public.rls_auto_enable() from public, anon, authenticated;

create table if not exists private.email_send_reservations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  recipient_id uuid not null,
  local_send_date date not null,
  month_start date not null
    check (month_start = date_trunc('month', month_start)::date),
  status text not null default 'reserved'
    check (status in ('reserved', 'consumed', 'released')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint email_send_reservations_recipient_fk
    foreign key (municipality_id, recipient_id)
    references public.notification_recipients(municipality_id, id) on delete cascade,
  constraint email_send_reservations_recipient_uq
    unique (municipality_id, recipient_id)
);

create index if not exists email_send_reservations_daily_idx
  on private.email_send_reservations (
    municipality_id, local_send_date, status, recipient_id
  );
create index if not exists email_send_reservations_monthly_idx
  on private.email_send_reservations (
    municipality_id, month_start, status, recipient_id
  );

alter table private.email_send_reservations enable row level security;
grant all on private.email_send_reservations to service_role;

drop trigger if exists private_jobs_set_updated_at on private.jobs;
create trigger private_jobs_set_updated_at
  before update on private.jobs
  for each row execute function private.set_updated_at();

create or replace function private.normalize_case_opening_batch_counts()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  select
    count(*)::integer,
    count(*) filter (where bi.status = 'opened')::integer,
    count(*) filter (where bi.status in ('blocked', 'excluded'))::integer
  into
    new.selected_count,
    new.opened_count,
    new.blocked_count
  from public.case_opening_batch_items bi
  where bi.municipality_id = new.municipality_id
    and bi.batch_id = new.id;

  if new.status = 'processing'
     and not exists (
       select 1
       from public.case_opening_batch_items bi
       where bi.municipality_id = new.municipality_id
         and bi.batch_id = new.id
         and bi.status in ('approved', 'revalidating')
     ) then
    new.status := 'completed';
  end if;

  return new;
end;
$$;

drop trigger if exists case_opening_batches_a_normalize_counts
  on public.case_opening_batches;
create trigger case_opening_batches_a_normalize_counts
  before update on public.case_opening_batches
  for each row execute function private.normalize_case_opening_batch_counts();

create or replace function private.reserve_email_capacity(
  p_municipality_id uuid,
  p_recipient_id uuid,
  p_daily_limit integer,
  p_monthly_limit integer,
  p_timezone text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_local_date date := (now() at time zone p_timezone)::date;
  v_month_start date := date_trunc(
    'month',
    (now() at time zone p_timezone)::date
  )::date;
  v_daily_count bigint;
  v_monthly_count bigint;
  v_status text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_municipality_id::text || ':initial-email-capacity',
      0
    )
  );

  select esr.status into v_status
  from private.email_send_reservations esr
  where esr.municipality_id = p_municipality_id
    and esr.recipient_id = p_recipient_id
  for update;

  if v_status in ('reserved', 'consumed') then
    return true;
  end if;

  select count(*) into v_daily_count
  from private.email_send_reservations esr
  where esr.municipality_id = p_municipality_id
    and esr.local_send_date = v_local_date
    and esr.status in ('reserved', 'consumed');

  select count(*) into v_monthly_count
  from private.email_send_reservations esr
  where esr.municipality_id = p_municipality_id
    and esr.month_start = v_month_start
    and esr.status in ('reserved', 'consumed');

  if v_daily_count >= p_daily_limit
     or v_monthly_count >= p_monthly_limit then
    return false;
  end if;

  insert into private.email_send_reservations (
    municipality_id,
    recipient_id,
    local_send_date,
    month_start,
    status
  )
  values (
    p_municipality_id,
    p_recipient_id,
    v_local_date,
    v_month_start,
    'reserved'
  )
  on conflict (municipality_id, recipient_id)
  do update set
    local_send_date = excluded.local_send_date,
    month_start = excluded.month_start,
    status = 'reserved',
    updated_at = now();

  return true;
end;
$$;

create or replace function private.sync_email_reservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.email_send_reservations esr
     set status = case
           when new.status in ('accepted', 'delivered') then 'consumed'
           when new.status = 'permanent_failure' then 'released'
           else esr.status
         end,
         updated_at = now()
   where esr.municipality_id = new.municipality_id
     and esr.recipient_id = new.recipient_id;
  return new;
end;
$$;

drop trigger if exists delivery_attempts_sync_email_reservation
  on private.delivery_attempts;
create trigger delivery_attempts_sync_email_reservation
  after insert on private.delivery_attempts
  for each row execute function private.sync_email_reservation();

create or replace function private.release_email_reservation_for_terminal_job()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.job_type = 'send_initial_notice'
     and new.status in ('dead_letter', 'blocked_configuration', 'cancelled')
     and old.status is distinct from new.status then
    update private.email_send_reservations esr
       set status = 'released',
           updated_at = now()
     where esr.municipality_id = new.municipality_id
       and esr.recipient_id = new.aggregate_id
       and esr.status = 'reserved'
       and not exists (
         select 1
         from public.notification_recipients nr
         where nr.municipality_id = esr.municipality_id
           and nr.id = esr.recipient_id
           and nr.status in ('sent', 'delivered')
       );
  end if;
  return new;
end;
$$;

drop trigger if exists jobs_release_email_reservation on private.jobs;
create trigger jobs_release_email_reservation
  after update of status on private.jobs
  for each row execute function private.release_email_reservation_for_terminal_job();

create or replace function public.ia_get_notification_job_context(
  p_job_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.jobs%rowtype;
  v_recipient public.notification_recipients%rowtype;
  v_notification public.notifications%rowtype;
  v_case public.fiscal_cases%rowtype;
  v_channel public.notification_channel_settings%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_valid boolean := false;
  v_reason text;
  v_timezone text;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'send_initial_notice';

  select nr.* into strict v_recipient
  from public.notification_recipients nr
  where nr.municipality_id = v_job.municipality_id
    and nr.id = v_job.aggregate_id;

  select n.* into strict v_notification
  from public.notifications n
  where n.municipality_id = v_recipient.municipality_id
    and n.id = v_recipient.notification_id;

  select fc.* into strict v_case
  from public.fiscal_cases fc
  where fc.municipality_id = v_notification.municipality_id
    and fc.id = v_notification.case_id;

  if v_case.status in ('cancelled', 'resolved', 'closed') then
    v_reason := 'case_not_sendable';
  elsif v_notification.status in ('cancelled', 'sent') then
    v_reason := 'notification_not_sendable';
  elsif v_recipient.status not in ('pending', 'queued', 'failed') then
    v_reason := 'recipient_not_sendable';
  else
    select pv.* into v_policy
    from public.municipality_policy_versions pv
    where pv.municipality_id = v_job.municipality_id
      and pv.status = 'active';

    select cs.* into v_channel
    from public.notification_channel_settings cs
    where cs.municipality_id = v_job.municipality_id
      and cs.channel = 'email'
      and cs.status = 'active'
      and cs.kill_switch = false;

    if v_policy.id is null or not v_policy.auto_initial_notice_enabled then
      v_reason := 'notification_feature_disabled';
    elsif v_channel.id is null then
      v_reason := 'email_channel_disabled';
    else
      select m.timezone into strict v_timezone
      from public.municipalities m
      where m.id = v_job.municipality_id;
    end if;

    if v_reason is null and v_recipient.recipient_type = 'taxpayer' then
      select exists (
        select 1
        from public.party_contacts pc
        where pc.municipality_id = v_recipient.municipality_id
          and pc.id = v_recipient.contact_id
          and pc.taxpayer_id = v_case.taxpayer_id
          and pc.contact_type = 'email'
          and pc.status = 'verified'
          and pc.normalized_value = v_recipient.email_snapshot
          and pc.valid_from <= now()
          and (pc.valid_until is null or pc.valid_until > now())
      ) into v_valid;
      if not v_valid then v_reason := 'taxpayer_contact_invalid'; end if;
    elsif v_reason is null and v_recipient.recipient_type = 'accountant' then
      select exists (
        select 1
        from public.taxpayer_accountant_links tal
        join public.party_contacts pc
          on pc.municipality_id = tal.municipality_id
         and pc.id = v_recipient.contact_id
         and pc.accounting_firm_id = tal.accounting_firm_id
        where tal.municipality_id = v_recipient.municipality_id
          and tal.id = v_recipient.taxpayer_accountant_link_id
          and tal.taxpayer_id = v_case.taxpayer_id
          and tal.status = 'active'
          and tal.can_receive_initial_notice
          and tal.valid_from <= now()
          and (tal.valid_until is null or tal.valid_until > now())
          and pc.contact_type = 'email'
          and pc.status = 'verified'
          and pc.normalized_value = v_recipient.email_snapshot
          and pc.valid_from <= now()
          and (pc.valid_until is null or pc.valid_until > now())
      ) into v_valid;
      if not v_valid then v_reason := 'accountant_link_or_contact_invalid'; end if;
    end if;

    if v_reason is null and not private.reserve_email_capacity(
      v_job.municipality_id,
      v_recipient.id,
      least(v_policy.daily_initial_notice_limit, v_channel.daily_limit),
      v_channel.monthly_limit,
      v_timezone
    ) then
      v_reason := 'email_capacity_reached';
    end if;
  end if;

  if v_reason is not null then
    return jsonb_build_object(
      'allowed', false,
      'reason', v_reason,
      'recipient_id', v_recipient.id
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'job_id', v_job.id,
    'recipient_id', v_recipient.id,
    'recipient_type', v_recipient.recipient_type,
    'to', v_recipient.email_snapshot,
    'from_name', v_channel.sender_name,
    'from_email', v_channel.sender_email,
    'reply_to', v_channel.reply_to_email,
    'subject', v_notification.subject_snapshot,
    'text', v_notification.body_text_snapshot,
    'html', v_notification.body_html_snapshot,
    'idempotency_key', v_recipient.idempotency_key,
    'case_id', v_case.id,
    'notification_id', v_notification.id
  );
end;
$$;

create or replace function public.ia_mark_notification_job_blocked(
  p_job_id bigint,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.jobs%rowtype;
  v_recipient public.notification_recipients%rowtype;
  v_notification public.notifications%rowtype;
  v_recipient_status text;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'send_initial_notice';

  select nr.* into strict v_recipient
  from public.notification_recipients nr
  where nr.municipality_id = v_job.municipality_id
    and nr.id = v_job.aggregate_id
  for update;

  select n.* into strict v_notification
  from public.notifications n
  where n.municipality_id = v_recipient.municipality_id
    and n.id = v_recipient.notification_id
  for update;

  v_recipient_status := case
    when coalesce(p_reason, '') like 'email_provider_http_%' then 'failed'
    else 'cancelled'
  end;

  update public.notification_recipients
     set status = v_recipient_status,
         last_error_code = left(coalesce(p_reason, 'notification_blocked'), 120)
   where municipality_id = v_recipient.municipality_id
     and id = v_recipient.id
     and status not in ('sent', 'delivered');

  update public.notifications n
     set status = case
       when exists (
         select 1
         from public.notification_recipients nr
         where nr.municipality_id = n.municipality_id
           and nr.notification_id = n.id
           and nr.status in ('sent', 'delivered')
       ) then 'partially_failed'
       else 'failed'
     end
   where n.municipality_id = v_notification.municipality_id
     and n.id = v_notification.id
     and n.status not in ('sent', 'cancelled');

  insert into public.case_events (
    municipality_id,
    case_id,
    event_type,
    visibility,
    actor_type,
    event_data
  )
  values (
    v_notification.municipality_id,
    v_notification.case_id,
    'initial_alert_recipient_blocked',
    'staff',
    'service',
    jsonb_build_object(
      'notification_id', v_notification.id,
      'recipient_id', v_recipient.id,
      'recipient_type', v_recipient.recipient_type,
      'reason', left(coalesce(p_reason, 'notification_blocked'), 120)
    )
  );
end;
$$;

revoke all on function public.ia_mark_notification_job_blocked(bigint, text)
  from public, anon, authenticated;
grant execute on function public.ia_mark_notification_job_blocked(bigint, text)
  to service_role;

-- Add a covering index for every application foreign key that does not
-- already have one. Names are deterministic and collision-resistant.
do $$
declare
  r record;
  v_columns text;
  v_index_name text;
begin
  for r in
    select
      n.nspname as schema_name,
      c.relname as table_name,
      con.conname,
      con.conrelid,
      con.conkey
    from pg_catalog.pg_constraint con
    join pg_catalog.pg_class c on c.oid = con.conrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where con.contype = 'f'
      and n.nspname in ('public', 'private', 'audit')
      and not exists (
        select 1
        from pg_catalog.pg_index i
        where i.indrelid = con.conrelid
          and i.indisvalid
          and i.indisready
          and i.indnkeyatts >= cardinality(con.conkey)
          and not exists (
            select 1
            from unnest(con.conkey) with ordinality k(attnum, position)
            where i.indkey[k.position - 1] <> k.attnum
          )
      )
  loop
    select string_agg(pg_catalog.quote_ident(a.attname), ', ' order by k.position)
      into strict v_columns
    from unnest(r.conkey) with ordinality k(attnum, position)
    join pg_catalog.pg_attribute a
      on a.attrelid = r.conrelid
     and a.attnum = k.attnum;

    v_index_name := 'iafk_' || substr(
      pg_catalog.md5(r.schema_name || '.' || r.table_name || '.' || r.conname),
      1,
      20
    );
    execute format(
      'create index if not exists %I on %I.%I (%s)',
      v_index_name,
      r.schema_name,
      r.table_name,
      v_columns
    );
  end loop;
end;
$$;

commit;

