-- Homologação realista do IA Fiscal:
-- 1) regime fiscal visível na experiência de débitos;
-- 2) allowlist derivada de usuários internos ativos;
-- 3) outbox de teste fail-closed;
-- 4) contexto de leitura autorizado para o Copiloto.
--
-- Esta migração não habilita entrega externa e não altera a trava mestra existente.

create extension if not exists pgcrypto with schema extensions;

create or replace function private.ia_normalize_tax_regime(
  p_metadata jsonb,
  p_simples_from date,
  p_simples_until date
)
returns text
language sql
stable
set search_path = ''
as $$
  with normalized as (
    select lower(
      coalesce(
        p_metadata ->> 'regime_fiscal',
        p_metadata ->> 'regime',
        p_metadata ->> 'tax_regime',
        p_metadata #>> '{fiscal,regime}',
        ''
      )
    ) as value
  )
  select case
    when p_simples_from is not null
      and p_simples_from <= current_date
      and (p_simples_until is null or p_simples_until >= current_date)
      then 'simples_nacional'
    when value like '%simples%' or value like '%pgdas%' then 'simples_nacional'
    when value like '%prestador%' then 'prestador'
    when value like '%informador%' or value like '%tomador%' then 'informador'
    else 'nao_informado'
  end
  from normalized;
$$;

revoke all on function private.ia_normalize_tax_regime(jsonb, date, date)
  from public, anon, authenticated;
grant execute on function private.ia_normalize_tax_regime(jsonb, date, date)
  to authenticated, service_role;

create or replace view public.vw_taxpayer_regimes
with (security_invoker = true)
as
select
  t.municipality_id,
  t.id as taxpayer_id,
  private.ia_normalize_tax_regime(
    t.source_metadata,
    tfp.simples_opted_from,
    tfp.simples_opted_until
  ) as regime_code,
  case private.ia_normalize_tax_regime(
    t.source_metadata,
    tfp.simples_opted_from,
    tfp.simples_opted_until
  )
    when 'simples_nacional' then 'Simples Nacional'
    when 'prestador' then 'Prestador de serviços'
    when 'informador' then 'Informador ou tomador'
    else 'Regime não informado'
  end as regime_label,
  case
    when tfp.simples_opted_from is not null then 'perfil_fiscal'
    when coalesce(
      t.source_metadata ->> 'regime_fiscal',
      t.source_metadata ->> 'regime',
      t.source_metadata ->> 'tax_regime',
      t.source_metadata #>> '{fiscal,regime}'
    ) is not null then 'origem_cadastral'
    else 'nao_verificada'
  end as regime_source,
  private.ia_normalize_tax_regime(
    t.source_metadata,
    tfp.simples_opted_from,
    tfp.simples_opted_until
  ) <> 'nao_informado' as regime_verified
from public.taxpayers t
left join public.taxpayer_fiscal_profiles tfp
  on tfp.municipality_id = t.municipality_id
 and tfp.taxpayer_id = t.id
where private.can_access_taxpayer(t.municipality_id, t.id);

revoke all on public.vw_taxpayer_regimes from public, anon;
grant select on public.vw_taxpayer_regimes to authenticated, service_role;

create table public.homologation_email_allowlist (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email extensions.citext not null,
  full_name text not null,
  role_snapshot text not null,
  source text not null default 'internal_user'
    check (source = 'internal_user'),
  status text not null default 'active'
    check (status in ('active', 'revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint homologation_email_allowlist_municipality_id_id_uq
    unique (municipality_id, id),
  constraint homologation_email_allowlist_user_uq
    unique (municipality_id, user_id),
  constraint homologation_email_allowlist_email_uq
    unique (municipality_id, email)
);

alter table public.homologation_email_allowlist enable row level security;

create policy homologation_email_allowlist_select_staff
on public.homologation_email_allowlist
for select
to authenticated
using (
  private.has_municipality_role(
    municipality_id,
    array[
      'municipal_admin',
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer',
      'support_readonly'
    ]::text[]
  )
);

revoke all on public.homologation_email_allowlist from public, anon, authenticated;
grant select on public.homologation_email_allowlist to authenticated;
grant all on public.homologation_email_allowlist to service_role;

create trigger homologation_email_allowlist_set_updated_at
before update on public.homologation_email_allowlist
for each row execute function private.set_updated_at();

create trigger homologation_email_allowlist_immutable_identity
before update on public.homologation_email_allowlist
for each row execute function private.prevent_tenant_or_id_change();

create trigger homologation_email_allowlist_audit
after insert or update or delete on public.homologation_email_allowlist
for each row execute function private.audit_row_change();

create or replace function private.ia_sync_homologation_internal_recipients(
  p_municipality_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (
    private.is_service_role()
    or private.is_platform_administrator()
    or private.has_municipality_role(
      p_municipality_id,
      array['municipal_admin', 'supervisor']::text[]
    )
  ) then
    raise exception 'homologation recipient synchronization denied'
      using errcode = '42501';
  end if;

  insert into public.homologation_email_allowlist (
    municipality_id,
    user_id,
    email,
    full_name,
    role_snapshot,
    source,
    status
  )
  select
    p_municipality_id,
    u.id,
    lower(u.email::text)::extensions.citext,
    coalesce(
      nullif(trim(p.full_name), ''),
      nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
      split_part(u.email::text, '@', 1)
    ),
    case
      when pa.user_id is not null then 'platform_admin'
      else coalesce(mm.role, 'support_readonly')
    end,
    'internal_user',
    'active'
  from auth.users u
  left join public.profiles p
    on p.user_id = u.id
  left join public.platform_administrators pa
    on pa.user_id = u.id
   and pa.active
   and pa.revoked_at is null
  left join public.municipality_memberships mm
    on mm.municipality_id = p_municipality_id
   and mm.user_id = u.id
   and mm.status = 'active'
   and mm.valid_from <= now()
   and (mm.valid_until is null or mm.valid_until > now())
  where u.email is not null
    and u.email_confirmed_at is not null
    and coalesce(p.status, 'active') = 'active'
    and (pa.user_id is not null or mm.id is not null)
  on conflict (municipality_id, user_id)
  do update set
    email = excluded.email,
    full_name = excluded.full_name,
    role_snapshot = excluded.role_snapshot,
    source = 'internal_user',
    status = 'active',
    updated_at = now();

  update public.homologation_email_allowlist h
  set status = 'revoked', updated_at = now()
  where h.municipality_id = p_municipality_id
    and h.status = 'active'
    and not exists (
      select 1
      from auth.users u
      left join public.profiles p
        on p.user_id = u.id
      left join public.platform_administrators pa
        on pa.user_id = u.id
       and pa.active
       and pa.revoked_at is null
      left join public.municipality_memberships mm
        on mm.municipality_id = p_municipality_id
       and mm.user_id = u.id
       and mm.status = 'active'
       and mm.valid_from <= now()
       and (mm.valid_until is null or mm.valid_until > now())
      where u.id = h.user_id
        and u.email is not null
        and u.email_confirmed_at is not null
        and coalesce(p.status, 'active') = 'active'
        and (pa.user_id is not null or mm.id is not null)
    );

  select count(*)::integer
  into v_count
  from public.homologation_email_allowlist h
  where h.municipality_id = p_municipality_id
    and h.status = 'active';

  return v_count;
end;
$$;

revoke all on function private.ia_sync_homologation_internal_recipients(uuid)
  from public, anon, authenticated;
grant execute on function private.ia_sync_homologation_internal_recipients(uuid)
  to authenticated, service_role;

do $$
declare
  v_municipality record;
begin
  for v_municipality in
    select m.id
    from public.municipalities m
    where m.status in ('homologation', 'active')
  loop
    perform private.ia_sync_homologation_internal_recipients(v_municipality.id);
  end loop;
end;
$$;

create or replace function public.ia_list_homologation_recipients(
  p_municipality_id uuid
)
returns table (
  user_id uuid,
  email text,
  full_name text,
  role text,
  source text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (
    private.is_platform_administrator()
    or private.has_municipality_role(
      p_municipality_id,
      array[
        'municipal_admin',
        'supervisor',
        'fiscal_auditor',
        'legal_reviewer',
        'support_readonly'
      ]::text[]
    )
  ) then
    raise exception 'homologation recipient access denied'
      using errcode = '42501';
  end if;

  perform private.ia_sync_homologation_internal_recipients(p_municipality_id);

  return query
  select
    h.user_id,
    h.email::text,
    h.full_name,
    h.role_snapshot,
    h.source
  from public.homologation_email_allowlist h
  where h.municipality_id = p_municipality_id
    and h.status = 'active'
  order by h.full_name, h.email;
end;
$$;

revoke all on function public.ia_list_homologation_recipients(uuid)
  from public, anon;
grant execute on function public.ia_list_homologation_recipients(uuid)
  to authenticated, service_role;

create table public.homologation_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  candidate_id text not null,
  taxpayer_id uuid not null,
  case_id uuid,
  recipient_user_id uuid not null references auth.users(id) on delete restrict,
  recipient_email extensions.citext not null,
  subject text not null check (char_length(trim(subject)) between 5 and 180),
  body_text text not null check (char_length(trim(body_text)) between 40 and 5000),
  body_sha256 text not null check (body_sha256 ~ '^[a-f0-9]{64}$'),
  client_request_id text not null,
  status text not null default 'provider_pending'
    check (status in ('provider_pending', 'processing', 'sent', 'failed', 'cancelled')),
  provider_code text,
  provider_message_id text,
  safe_error_code text,
  requested_by uuid not null references auth.users(id) on delete restrict,
  queued_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint homologation_notification_outbox_municipality_id_id_uq
    unique (municipality_id, id),
  constraint homologation_notification_outbox_request_uq
    unique (municipality_id, client_request_id),
  constraint homologation_notification_outbox_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id),
  constraint homologation_notification_outbox_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id)
);

create index homologation_notification_outbox_queue_idx
  on public.homologation_notification_outbox (
    municipality_id,
    status,
    queued_at,
    id
  )
  where status in ('provider_pending', 'processing');

create index homologation_notification_outbox_taxpayer_idx
  on public.homologation_notification_outbox (
    municipality_id,
    taxpayer_id,
    queued_at desc,
    id
  );

alter table public.homologation_notification_outbox enable row level security;

create policy homologation_notification_outbox_select_staff
on public.homologation_notification_outbox
for select
to authenticated
using (
  private.has_municipality_role(
    municipality_id,
    array[
      'municipal_admin',
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer',
      'support_readonly'
    ]::text[]
  )
);

revoke all on public.homologation_notification_outbox from public, anon, authenticated;
grant select on public.homologation_notification_outbox to authenticated;
grant all on public.homologation_notification_outbox to service_role;

create trigger homologation_notification_outbox_set_updated_at
before update on public.homologation_notification_outbox
for each row execute function private.set_updated_at();

create trigger homologation_notification_outbox_immutable_identity
before update on public.homologation_notification_outbox
for each row execute function private.prevent_tenant_or_id_change();

create trigger homologation_notification_outbox_audit
after insert or update or delete on public.homologation_notification_outbox
for each row execute function private.audit_row_change();

create or replace function public.ia_queue_homologation_notification(
  p_municipality_id uuid,
  p_candidate_id text,
  p_taxpayer_id uuid,
  p_recipient_user_id uuid,
  p_subject text,
  p_body text,
  p_client_request_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient public.homologation_email_allowlist%rowtype;
  v_outbox public.homologation_notification_outbox%rowtype;
  v_policy_test_mode boolean;
  v_case_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if not (
    private.is_platform_administrator()
    or private.has_municipality_role(
      p_municipality_id,
      array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
    )
  ) then
    raise exception 'homologation queue access denied'
      using errcode = '42501';
  end if;

  select coalesce((pv.operational_config ->> 'test_mode')::boolean, false)
  into v_policy_test_mode
  from public.municipality_policy_versions pv
  where pv.municipality_id = p_municipality_id
    and pv.status = 'active'
  order by pv.version desc
  limit 1;

  if not coalesce(v_policy_test_mode, false) then
    raise exception 'homologation test mode is not enabled'
      using errcode = '42501';
  end if;

  if nullif(trim(p_candidate_id), '') is null
    or char_length(trim(p_candidate_id)) > 200
    or nullif(trim(p_client_request_id), '') is null
    or char_length(trim(p_client_request_id)) > 200 then
    raise exception 'candidate and client request are required';
  end if;

  if not exists (
    select 1
    from public.vw_notification_recipient_candidates candidate
    where candidate.municipality_id = p_municipality_id
      and candidate.taxpayer_id = p_taxpayer_id
      and candidate.candidate_id::text = p_candidate_id
  ) then
    raise exception 'notification candidate does not match taxpayer'
      using errcode = '42501';
  end if;

  perform private.ia_sync_homologation_internal_recipients(p_municipality_id);

  select *
  into v_recipient
  from public.homologation_email_allowlist h
  where h.municipality_id = p_municipality_id
    and h.user_id = p_recipient_user_id
    and h.status = 'active';

  if not found then
    raise exception 'recipient is not in the internal homologation allowlist'
      using errcode = '42501';
  end if;

  if p_subject ~* '(https?://|www\.|href[[:space:]]*=|<a([[:space:]]|>))'
    or p_body ~* '(https?://|www\.|href[[:space:]]*=|<a([[:space:]]|>))' then
    raise exception 'links are prohibited in homologation email';
  end if;

  if p_subject ~* '(R\$|BRL|[0-9]{1,3}(\.[0-9]{3})*,[0-9]{2})'
    or p_body ~* '(R\$|BRL|[0-9]{1,3}(\.[0-9]{3})*,[0-9]{2})' then
    raise exception 'monetary values are prohibited in homologation email';
  end if;

  if p_subject ~* '\m(anexo|anexos|anexa|anexado|attachment|attachments)\M'
    or p_body ~* '\m(anexo|anexos|anexa|anexado|attachment|attachments)\M' then
    raise exception 'attachments are prohibited in homologation email';
  end if;

  select fc.id
  into v_case_id
  from public.fiscal_cases fc
  where fc.municipality_id = p_municipality_id
    and fc.taxpayer_id = p_taxpayer_id
  order by fc.opened_at desc, fc.id desc
  limit 1;

  insert into public.homologation_notification_outbox (
    municipality_id,
    candidate_id,
    taxpayer_id,
    case_id,
    recipient_user_id,
    recipient_email,
    subject,
    body_text,
    body_sha256,
    client_request_id,
    status,
    requested_by
  )
  values (
    p_municipality_id,
    trim(p_candidate_id),
    p_taxpayer_id,
    v_case_id,
    v_recipient.user_id,
    v_recipient.email,
    trim(p_subject),
    trim(p_body),
    encode(
      extensions.digest(convert_to(trim(p_body), 'UTF8'), 'sha256'),
      'hex'
    ),
    trim(p_client_request_id),
    'provider_pending',
    (select auth.uid())
  )
  returning * into v_outbox;

  return jsonb_build_object(
    'outbox_id', v_outbox.id,
    'status', v_outbox.status,
    'queued_at', v_outbox.queued_at,
    'recipient_masked',
      regexp_replace(v_outbox.recipient_email::text, '(^.).*(@.*$)', E'\\1***\\2')
  );
end;
$$;

revoke all on function public.ia_queue_homologation_notification(
  uuid, text, uuid, uuid, text, text, text
) from public, anon;
grant execute on function public.ia_queue_homologation_notification(
  uuid, text, uuid, uuid, text, text, text
) to authenticated, service_role;

create or replace function public.ia_copilot_read_context(
  p_municipality_id uuid,
  p_question text,
  p_taxpayer_id uuid default null,
  p_pathname text default '/',
  p_case_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_taxpayer jsonb := null;
  v_debts jsonb := '[]'::jsonb;
  v_divergences jsonb := '[]'::jsonb;
  v_cases jsonb := '[]'::jsonb;
  v_timeline jsonb := '[]'::jsonb;
  v_communications jsonb := '[]'::jsonb;
  v_summary jsonb := '{}'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if char_length(trim(p_question)) not between 4 and 1000 then
    raise exception 'invalid question length';
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

  if v_role is null and p_taxpayer_id is not null and exists (
    select 1
    from public.taxpayer_user_links tul
    where tul.municipality_id = p_municipality_id
      and tul.taxpayer_id = p_taxpayer_id
      and tul.user_id = (select auth.uid())
      and tul.status = 'active'
      and tul.valid_from <= now()
      and (tul.valid_until is null or tul.valid_until > now())
  ) then
    v_role := 'taxpayer';
  end if;

  if v_role is null and p_taxpayer_id is not null and exists (
    select 1
    from public.taxpayer_accountant_links tal
    join public.accountant_user_links aul
      on aul.municipality_id = tal.municipality_id
     and aul.accounting_firm_id = tal.accounting_firm_id
    where tal.municipality_id = p_municipality_id
      and tal.taxpayer_id = p_taxpayer_id
      and tal.status = 'active'
      and tal.can_access_portal
      and tal.valid_from <= now()
      and (tal.valid_until is null or tal.valid_until > now())
      and aul.user_id = (select auth.uid())
      and aul.status = 'active'
      and aul.valid_from <= now()
      and (aul.valid_until is null or aul.valid_until > now())
  ) then
    v_role := 'accountant';
  end if;

  if v_role is null then
    raise exception 'copilot access denied' using errcode = '42501';
  end if;

  if p_taxpayer_id is not null
    and not private.can_access_taxpayer(p_municipality_id, p_taxpayer_id) then
    raise exception 'taxpayer context denied' using errcode = '42501';
  end if;

  if p_case_id is not null
    and not private.can_access_case(p_municipality_id, p_case_id) then
    raise exception 'case context denied' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'taxpayer_count', count(*)::integer,
    'open_balance_total', coalesce(sum(s.open_balance_total), 0),
    'active_divergence_count', coalesce(sum(s.active_divergence_count), 0)::integer,
    'active_case_count', coalesce(sum(s.active_case_count), 0)::integer,
    'waiting_question_count', coalesce(sum(s.waiting_question_count), 0)::integer
  )
  into v_summary
  from public.vw_taxpayer_360_summary s
  where s.municipality_id = p_municipality_id;

  if p_taxpayer_id is not null then
    select jsonb_build_object(
      'taxpayer_id', s.taxpayer_id,
      'legal_name', s.legal_name,
      'trade_name', s.trade_name,
      'municipal_registration', s.municipal_registration,
      'taxpayer_type', s.taxpayer_type,
      'taxpayer_status', s.taxpayer_status,
      'open_balance_total', s.open_balance_total,
      'active_divergence_count', s.active_divergence_count,
      'active_case_count', s.active_case_count,
      'waiting_question_count', s.waiting_question_count
    )
    into v_taxpayer
    from public.vw_taxpayer_360_summary s
    where s.municipality_id = p_municipality_id
      and s.taxpayer_id = p_taxpayer_id
    limit 1;

    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.competencia desc), '[]'::jsonb)
    into v_debts
    from (
      select
        d.competencia,
        d.valor_emitido,
        d.valor_vencido,
        d.valor_pago,
        d.saldo_em_aberto,
        d.status,
        d.elegivel,
        d.regra_versao,
        d.data_base
      from public.vw_taxpayer_360_debts d
      where d.municipality_id = p_municipality_id
        and d.taxpayer_id = p_taxpayer_id
      order by d.competencia desc
      limit 60
    ) row_data;

    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.period_start desc), '[]'::jsonb)
    into v_divergences
    from (
      select
        d.divergence_id,
        d.divergence_type,
        d.period_start,
        d.period_end,
        d.difference_amount,
        d.status,
        d.rule_code,
        d.rule_name,
        d.rule_description,
        d.block_reasons
      from public.vw_taxpayer_360_divergences d
      where d.municipality_id = p_municipality_id
        and d.taxpayer_id = p_taxpayer_id
      order by d.period_start desc
      limit 50
    ) row_data;

    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.opened_at desc), '[]'::jsonb)
    into v_cases
    from (
      select
        c.case_id,
        c.case_number,
        c.status,
        c.opened_at,
        c.updated_at,
        c.current_explanation_title,
        c.current_explanation_summary,
        c.legal_basis_summary,
        c.legal_review_required,
        c.waiting_question_count
      from public.vw_taxpayer_360_cases c
      where c.municipality_id = p_municipality_id
        and c.taxpayer_id = p_taxpayer_id
      order by c.opened_at desc
      limit 50
    ) row_data;

    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.event_at desc), '[]'::jsonb)
    into v_timeline
    from (
      select
        h.case_id,
        h.event_at,
        h.item_type,
        h.title,
        h.summary,
        h.visibility
      from public.vw_taxpayer_360_timeline h
      where h.municipality_id = p_municipality_id
        and h.taxpayer_id = p_taxpayer_id
      order by h.event_at desc
      limit 100
    ) row_data;

    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.occurred_at asc), '[]'::jsonb)
    into v_communications
    from (
      select
        c.case_id,
        c.communication_id,
        c.communication_type,
        c.direction,
        c.channel_or_source,
        c.title,
        c.summary,
        c.status,
        c.visibility,
        c.delivery_mode,
        c.external_delivery_attempted,
        c.occurred_at
      from public.vw_taxpayer_360_communications c
      where c.municipality_id = p_municipality_id
        and c.taxpayer_id = p_taxpayer_id
      order by c.occurred_at asc
      limit 100
    ) row_data;
  end if;

  return jsonb_build_object(
    'verified', true,
    'municipality_id', p_municipality_id,
    'role', v_role,
    'question', trim(p_question),
    'pathname', left(coalesce(p_pathname, '/'), 500),
    'case_id', p_case_id,
    'scope_reference',
      case
        when p_taxpayer_id is not null then 'contribuinte:' || p_taxpayer_id::text
        else 'municipio:' || p_municipality_id::text
      end,
    'operational_summary', v_summary,
    'taxpayer', v_taxpayer,
    'debts', v_debts,
    'divergences', v_divergences,
    'cases', v_cases,
    'timeline', v_timeline,
    'communications', v_communications,
    'sources', jsonb_build_array(
      jsonb_build_object(
        'kind', 'database',
        'title', 'IA Fiscal - dados autorizados',
        'reference',
          case
            when p_taxpayer_id is not null then 'dossie_360'
            else 'resumo_municipal'
          end,
        'occurred_at', now()
      )
    ),
    'limitations', jsonb_build_array(
      'API transacional do CIGIS ainda nao conectada',
      'resposta informativa sem efeito fiscal',
      'nenhuma acao externa autorizada'
    ),
    'checked_at', now()
  );
end;
$$;

revoke all on function public.ia_copilot_read_context(
  uuid, text, uuid, text, uuid
) from public, anon;
grant execute on function public.ia_copilot_read_context(
  uuid, text, uuid, text, uuid
) to authenticated, service_role;

comment on function public.ia_copilot_read_context(uuid, text, uuid, text, uuid) is
  'Contexto read-only para o Copiloto. Autoriza deterministicamente municipio, contribuinte e caso antes de retornar dados; nao executa escrita nem entrega externa.';
