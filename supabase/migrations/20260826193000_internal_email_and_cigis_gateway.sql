-- Integração operacional de e-mail interno e contrato de acesso ao CIGIS.
-- Mantém o envio restrito à allowlist de usuários internos e preserva o CIGIS
-- como fonte de verdade dos dados fiscais transacionais.

create extension if not exists pgcrypto with schema extensions;

alter table public.homologation_notification_outbox
  add column if not exists reply_address extensions.citext,
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists delivered_at timestamptz,
  add column if not exists last_event_at timestamptz;

alter table public.homologation_notification_outbox
  drop constraint if exists homologation_notification_outbox_status_check;

alter table public.homologation_notification_outbox
  add constraint homologation_notification_outbox_status_check
  check (status in (
    'provider_pending',
    'processing',
    'sent',
    'delivered',
    'failed',
    'bounced',
    'cancelled'
  ));

alter table public.homologation_notification_outbox
  drop constraint if exists homologation_notification_outbox_attempt_count_check;

alter table public.homologation_notification_outbox
  add constraint homologation_notification_outbox_attempt_count_check
  check (attempt_count >= 0);

create unique index if not exists homologation_notification_outbox_provider_message_uq
  on public.homologation_notification_outbox (provider_code, provider_message_id)
  where provider_message_id is not null;

create table if not exists public.internal_email_inbox (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  outbox_id uuid not null,
  taxpayer_id uuid not null,
  case_id uuid,
  provider_code text not null default 'resend' check (provider_code = 'resend'),
  provider_email_id text not null,
  provider_message_id text,
  from_email extensions.citext not null,
  to_emails text[] not null default '{}'::text[],
  subject text not null default '',
  body_text text not null default '' check (char_length(body_text) <= 20000),
  attachments_count integer not null default 0 check (attachments_count >= 0),
  status text not null check (status in ('accepted', 'rejected')),
  safe_error_code text,
  received_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint internal_email_inbox_outbox_fk
    foreign key (municipality_id, outbox_id)
    references public.homologation_notification_outbox(municipality_id, id)
    on delete cascade,
  constraint internal_email_inbox_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id),
  constraint internal_email_inbox_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id),
  constraint internal_email_inbox_provider_email_uq
    unique (provider_code, provider_email_id),
  constraint internal_email_inbox_municipality_id_id_uq
    unique (municipality_id, id)
);

create index if not exists internal_email_inbox_taxpayer_idx
  on public.internal_email_inbox (
    municipality_id,
    taxpayer_id,
    received_at desc,
    id
  );

create index if not exists internal_email_inbox_case_idx
  on public.internal_email_inbox (
    municipality_id,
    case_id,
    received_at desc,
    id
  )
  where case_id is not null;

alter table public.internal_email_inbox enable row level security;

drop policy if exists internal_email_inbox_select_authorized
  on public.internal_email_inbox;
create policy internal_email_inbox_select_authorized
on public.internal_email_inbox
for select
to authenticated
using (
  private.can_access_taxpayer(municipality_id, taxpayer_id)
  and (
    case_id is null
    or private.can_access_case(municipality_id, case_id)
  )
);

revoke all on public.internal_email_inbox from public, anon, authenticated;
grant select on public.internal_email_inbox to authenticated;
grant all on public.internal_email_inbox to service_role;

drop trigger if exists internal_email_inbox_set_updated_at
  on public.internal_email_inbox;
create trigger internal_email_inbox_set_updated_at
before update on public.internal_email_inbox
for each row execute function private.set_updated_at();

drop trigger if exists internal_email_inbox_immutable_identity
  on public.internal_email_inbox;
create trigger internal_email_inbox_immutable_identity
before update on public.internal_email_inbox
for each row execute function private.prevent_tenant_or_id_change();

drop trigger if exists internal_email_inbox_audit
  on public.internal_email_inbox;
create trigger internal_email_inbox_audit
after insert or update or delete on public.internal_email_inbox
for each row execute function private.audit_row_change();

create or replace function private.ia_validate_internal_test_outbox()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.homologation_email_allowlist h
    where h.municipality_id = new.municipality_id
      and h.user_id = new.recipient_user_id
      and h.email = new.recipient_email
      and h.status = 'active'
  ) then
    raise exception 'internal recipient is not authorized'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.vw_taxpayer_regimes r
    where r.municipality_id = new.municipality_id
      and r.taxpayer_id = new.taxpayer_id
      and r.regime_verified
  ) then
    raise exception 'taxpayer regime must be verified before email dispatch'
      using errcode = '23514';
  end if;

  if not (
    exists (
      select 1
      from public.vw_taxpayer_360_debts d
      where d.municipality_id = new.municipality_id
        and d.taxpayer_id = new.taxpayer_id
    )
    or exists (
      select 1
      from public.vw_taxpayer_360_divergences d
      where d.municipality_id = new.municipality_id
        and d.taxpayer_id = new.taxpayer_id
    )
  ) then
    raise exception 'taxpayer has no verified debt or divergence context'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.ia_validate_internal_test_outbox()
  from public, anon, authenticated;
grant execute on function private.ia_validate_internal_test_outbox()
  to service_role;

drop trigger if exists homologation_notification_outbox_quality_gate
  on public.homologation_notification_outbox;
create trigger homologation_notification_outbox_quality_gate
before insert on public.homologation_notification_outbox
for each row execute function private.ia_validate_internal_test_outbox();

create or replace function public.ia_record_email_provider_event(
  p_municipality_id uuid,
  p_provider_event_id text,
  p_provider_message_id text,
  p_event_type text,
  p_payload_sha256 text,
  p_safe_payload jsonb,
  p_occurred_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_service_role() then
    raise exception 'service role required' using errcode = '42501';
  end if;

  insert into private.email_provider_events (
    municipality_id,
    provider_code,
    provider_event_id,
    provider_message_id,
    event_type,
    payload_sha256,
    safe_payload,
    occurred_at
  )
  values (
    p_municipality_id,
    'resend',
    left(trim(p_provider_event_id), 500),
    nullif(left(trim(coalesce(p_provider_message_id, '')), 500), ''),
    left(trim(p_event_type), 120),
    lower(trim(p_payload_sha256)),
    coalesce(p_safe_payload, '{}'::jsonb),
    p_occurred_at
  )
  on conflict (provider_code, provider_event_id) do nothing;

  return true;
end;
$$;

revoke all on function public.ia_record_email_provider_event(
  uuid, text, text, text, text, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.ia_record_email_provider_event(
  uuid, text, text, text, text, jsonb, timestamptz
) to service_role;

create or replace function public.ia_store_internal_inbound_email(
  p_outbox_id uuid,
  p_provider_email_id text,
  p_provider_message_id text,
  p_from_email text,
  p_to_emails text[],
  p_subject text,
  p_body_text text,
  p_attachments_count integer,
  p_received_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outbox public.homologation_notification_outbox%rowtype;
  v_inbox public.internal_email_inbox%rowtype;
  v_allowed boolean := false;
  v_status text;
  v_error text;
  v_thread_id uuid;
  v_message_id uuid;
  v_body text;
begin
  if not private.is_service_role() then
    raise exception 'service role required' using errcode = '42501';
  end if;

  select *
  into v_outbox
  from public.homologation_notification_outbox o
  where o.id = p_outbox_id;

  if not found then
    raise exception 'outbox not found' using errcode = 'P0002';
  end if;

  select exists (
    select 1
    from public.homologation_email_allowlist h
    where h.municipality_id = v_outbox.municipality_id
      and lower(h.email::text) = lower(trim(p_from_email))
      and h.status = 'active'
  ) into v_allowed;

  v_body := left(trim(coalesce(p_body_text, '')), 20000);

  if not v_allowed then
    v_status := 'rejected';
    v_error := 'sender_not_allowlisted';
  elsif coalesce(p_attachments_count, 0) > 0 then
    v_status := 'rejected';
    v_error := 'attachments_not_enabled';
  elsif char_length(v_body) < 1 then
    v_status := 'rejected';
    v_error := 'empty_message';
  else
    v_status := 'accepted';
    v_error := null;
  end if;

  insert into public.internal_email_inbox (
    municipality_id,
    outbox_id,
    taxpayer_id,
    case_id,
    provider_code,
    provider_email_id,
    provider_message_id,
    from_email,
    to_emails,
    subject,
    body_text,
    attachments_count,
    status,
    safe_error_code,
    received_at
  )
  values (
    v_outbox.municipality_id,
    v_outbox.id,
    v_outbox.taxpayer_id,
    v_outbox.case_id,
    'resend',
    left(trim(p_provider_email_id), 500),
    nullif(left(trim(coalesce(p_provider_message_id, '')), 500), ''),
    lower(trim(p_from_email))::extensions.citext,
    coalesce(p_to_emails, '{}'::text[]),
    left(coalesce(p_subject, ''), 500),
    v_body,
    greatest(coalesce(p_attachments_count, 0), 0),
    v_status,
    v_error,
    coalesce(p_received_at, now())
  )
  on conflict (provider_code, provider_email_id)
  do update set
    provider_message_id = excluded.provider_message_id,
    from_email = excluded.from_email,
    to_emails = excluded.to_emails,
    subject = excluded.subject,
    body_text = excluded.body_text,
    attachments_count = excluded.attachments_count,
    status = excluded.status,
    safe_error_code = excluded.safe_error_code,
    received_at = excluded.received_at,
    updated_at = now()
  returning * into v_inbox;

  if v_status = 'accepted' and v_outbox.case_id is not null then
    insert into public.case_threads (
      municipality_id,
      case_id,
      status
    )
    values (
      v_outbox.municipality_id,
      v_outbox.case_id,
      'open'
    )
    on conflict (municipality_id, case_id)
    do update set updated_at = now()
    returning id into v_thread_id;

    insert into public.case_messages (
      municipality_id,
      thread_id,
      case_id,
      sender_type,
      author_user_id,
      source_type,
      visibility,
      body,
      content_sha256,
      status,
      client_request_id,
      published_at
    )
    values (
      v_outbox.municipality_id,
      v_thread_id,
      v_outbox.case_id,
      'system',
      null,
      'system',
      'participants',
      v_body,
      encode(extensions.digest(convert_to(v_body, 'UTF8'), 'sha256'), 'hex'),
      'published',
      'internal-email:' || left(trim(p_provider_email_id), 180),
      coalesce(p_received_at, now())
    )
    on conflict (municipality_id, case_id, client_request_id) where client_request_id is not null
    do nothing
    returning id into v_message_id;
  end if;

  return jsonb_build_object(
    'inbox_id', v_inbox.id,
    'status', v_inbox.status,
    'safe_error_code', v_inbox.safe_error_code,
    'case_message_id', v_message_id
  );
end;
$$;

revoke all on function public.ia_store_internal_inbound_email(
  uuid, text, text, text, text[], text, text, integer, timestamptz
) from public, anon, authenticated;
grant execute on function public.ia_store_internal_inbound_email(
  uuid, text, text, text, text[], text, text, integer, timestamptz
) to service_role;

create or replace function public.ia_cigis_resolve_access(
  p_municipality_id uuid,
  p_taxpayer_id uuid default null,
  p_tax_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_taxpayer public.taxpayers%rowtype;
  v_role text;
  v_normalized_tax_id text;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  v_normalized_tax_id := regexp_replace(coalesce(p_tax_id, ''), '\D', '', 'g');

  select *
  into v_taxpayer
  from public.taxpayers t
  where t.municipality_id = p_municipality_id
    and (
      (p_taxpayer_id is not null and t.id = p_taxpayer_id)
      or (
        p_taxpayer_id is null
        and char_length(v_normalized_tax_id) between 11 and 14
        and regexp_replace(t.tax_id, '\D', '', 'g') = v_normalized_tax_id
      )
    )
  limit 1;

  if not found then
    raise exception 'taxpayer not found' using errcode = 'P0002';
  end if;

  if not private.can_access_taxpayer(p_municipality_id, v_taxpayer.id) then
    raise exception 'taxpayer access denied' using errcode = '42501';
  end if;

  if private.is_platform_administrator() then
    v_role := 'platform_admin';
  else
    select mm.role
    into v_role
    from public.municipality_memberships mm
    where mm.municipality_id = p_municipality_id
      and mm.user_id = (select auth.uid())
      and mm.status = 'active'
      and mm.valid_from <= now()
      and (mm.valid_until is null or mm.valid_until > now())
    limit 1;
  end if;

  if v_role is null and exists (
    select 1
    from public.taxpayer_user_links tul
    where tul.municipality_id = p_municipality_id
      and tul.taxpayer_id = v_taxpayer.id
      and tul.user_id = (select auth.uid())
      and tul.status = 'active'
      and tul.valid_from <= now()
      and (tul.valid_until is null or tul.valid_until > now())
  ) then
    v_role := 'taxpayer';
  end if;

  if v_role is null then
    v_role := 'accountant';
  end if;

  return jsonb_build_object(
    'authorized', true,
    'municipality_id', p_municipality_id,
    'taxpayer_id', v_taxpayer.id,
    'tax_id', regexp_replace(v_taxpayer.tax_id, '\D', '', 'g'),
    'role', v_role,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.ia_cigis_resolve_access(uuid, uuid, text)
  from public, anon;
grant execute on function public.ia_cigis_resolve_access(uuid, uuid, text)
  to authenticated, service_role;

comment on function public.ia_cigis_resolve_access(uuid, uuid, text) is
  'Resolve deterministicamente o contribuinte autorizado antes de qualquer chamada ao CIGIS. Não consulta o CIGIS e não amplia permissões.';
