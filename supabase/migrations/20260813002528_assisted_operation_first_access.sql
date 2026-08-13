-- Operação assistida: base municipal de testes, com comunicação externa bloqueada.
-- Também registra, de forma isolada por usuário, a conclusão do treinamento inicial.

create table if not exists public.user_onboarding_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  onboarding_key text not null,
  onboarding_version integer not null,
  current_step integer not null default 0,
  completed_at timestamptz,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, onboarding_key),
  constraint user_onboarding_progress_key_ck
    check (onboarding_key ~ '^[a-z0-9][a-z0-9:_-]{2,79}$'),
  constraint user_onboarding_progress_version_ck check (onboarding_version > 0),
  constraint user_onboarding_progress_step_ck check (current_step >= 0)
);

comment on table public.user_onboarding_progress is
  'Progresso do treinamento obrigatório por identidade e experiência versionada.';

alter table public.municipality_portal_settings
  add column if not exists external_delivery_locked boolean not null default true;

comment on column public.municipality_portal_settings.external_delivery_locked is
  'Trava mestra fail-closed. Enquanto true, nenhum job de comunicação externa pode receber contexto de envio.';

create or replace function private.enforce_external_delivery_master_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.job_type in ('send_initial_notice', 'send_approved_response')
     and new.status in ('pending', 'processing', 'retry')
     and coalesce((
       select ps.external_delivery_locked
       from public.municipality_portal_settings ps
       where ps.municipality_id = new.municipality_id
     ), true) then
    raise exception 'external delivery master lock is active';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_external_delivery_master_lock()
  from public, anon, authenticated, service_role;

drop trigger if exists jobs_external_delivery_master_lock on private.jobs;
create trigger jobs_external_delivery_master_lock
before insert or update of municipality_id, job_type, status on private.jobs
for each row execute function private.enforce_external_delivery_master_lock();

alter table public.user_onboarding_progress enable row level security;
alter table public.user_onboarding_progress force row level security;

drop policy if exists user_onboarding_progress_select_own
  on public.user_onboarding_progress;
create policy user_onboarding_progress_select_own
  on public.user_onboarding_progress
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists user_onboarding_progress_insert_own
  on public.user_onboarding_progress;
create policy user_onboarding_progress_insert_own
  on public.user_onboarding_progress
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists user_onboarding_progress_update_own
  on public.user_onboarding_progress;
create policy user_onboarding_progress_update_own
  on public.user_onboarding_progress
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on table public.user_onboarding_progress from public, anon, authenticated;
grant select on table public.user_onboarding_progress to authenticated;
grant insert (
  user_id,
  onboarding_key,
  onboarding_version,
  current_step,
  completed_at,
  started_at,
  updated_at
) on table public.user_onboarding_progress to authenticated;
grant update (
  user_id,
  onboarding_key,
  onboarding_version,
  current_step,
  completed_at,
  started_at,
  updated_at
) on table public.user_onboarding_progress to authenticated;

create table if not exists private.pending_staff_access_grants (
  id uuid primary key default gen_random_uuid(),
  normalized_email text not null,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  municipality_role text not null,
  grant_assisted_test_access boolean not null default false,
  authorized_by uuid references auth.users(id) on delete set null,
  reason text not null,
  expires_at timestamptz not null,
  consumed_by uuid references auth.users(id) on delete set null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint pending_staff_access_grants_email_ck
    check (
      normalized_email = lower(trim(normalized_email))
      and normalized_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    ),
  constraint pending_staff_access_grants_role_ck
    check (municipality_role in (
      'municipal_admin',
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer',
      'support_readonly'
    )),
  constraint pending_staff_access_grants_expiry_ck check (expires_at > created_at),
  unique (normalized_email, municipality_id)
);

revoke all on table private.pending_staff_access_grants
  from public, anon, authenticated, service_role;

create table if not exists private.assisted_operation_testers (
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  authorized_by uuid references auth.users(id) on delete set null,
  reason text not null,
  active boolean not null default true,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (municipality_id, user_id),
  constraint assisted_operation_testers_expiry_ck check (expires_at > created_at)
);

revoke all on table private.assisted_operation_testers
  from public, anon, authenticated, service_role;

create table if not exists private.assisted_operation_access_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  user_id uuid not null,
  authorized_by uuid,
  event_type text not null,
  expires_at timestamptz,
  reason text not null,
  recorded_at timestamptz not null default now(),
  constraint assisted_operation_access_events_type_ck
    check (event_type in ('granted', 'updated', 'revoked'))
);

comment on table private.assisted_operation_access_events is
  'Trilha imutável das capacidades temporárias de testes assistidos.';

revoke all on table private.assisted_operation_access_events
  from public, anon, authenticated, service_role;

create or replace function private.audit_assisted_operation_tester_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.assisted_operation_testers%rowtype;
  v_event_type text;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  v_event_type := case
    when tg_op = 'INSERT' then 'granted'
    when tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.active and not new.active) then 'revoked'
    else 'updated'
  end;

  insert into private.assisted_operation_access_events (
    municipality_id,
    user_id,
    authorized_by,
    event_type,
    expires_at,
    reason
  ) values (
    v_row.municipality_id,
    v_row.user_id,
    v_row.authorized_by,
    v_event_type,
    v_row.expires_at,
    left(v_row.reason, 500)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.audit_assisted_operation_tester_change()
  from public, anon, authenticated, service_role;

drop trigger if exists assisted_operation_testers_audit
  on private.assisted_operation_testers;
create trigger assisted_operation_testers_audit
after insert or update or delete on private.assisted_operation_testers
for each row execute function private.audit_assisted_operation_tester_change();

create or replace function private.has_assisted_operation_test_access(
  p_municipality_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and private.is_aal2()
     and private.current_municipality_membership_id(
       p_municipality_id,
       array['supervisor']::text[]
     ) is not null
     and exists (
       select 1
       from private.assisted_operation_testers aot
       where aot.municipality_id = p_municipality_id
         and aot.user_id = (select auth.uid())
         and aot.active
         and aot.expires_at > now()
     );
$$;

revoke all on function private.has_assisted_operation_test_access(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.ia_has_assisted_operation_test_access(
  p_municipality_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_assisted_operation_test_access(p_municipality_id);
$$;

revoke all on function public.ia_has_assisted_operation_test_access(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_has_assisted_operation_test_access(uuid) to authenticated;

-- Preserva a segregação: a capacidade temporária nunca substitui municipal_admin.
-- O vínculo real de Luís continua supervisor e expira junto com a concessão.

alter function public.ia_get_notification_job_context(bigint)
  rename to ia_get_notification_job_context_without_master_lock;

revoke all on function public.ia_get_notification_job_context_without_master_lock(bigint)
  from public, anon, authenticated, service_role;

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
  v_locked boolean;
  v_external_email_enabled boolean;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'send_initial_notice';

  select ps.external_delivery_locked, ps.external_email_enabled
    into v_locked, v_external_email_enabled
  from public.municipality_portal_settings ps
  where ps.municipality_id = v_job.municipality_id;

  if coalesce(v_locked, true) or not coalesce(v_external_email_enabled, false) then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'assisted_external_delivery_locked',
      'recipient_id', v_job.aggregate_id
    );
  end if;

  return public.ia_get_notification_job_context_without_master_lock(p_job_id);
end;
$$;

revoke all on function public.ia_get_notification_job_context(bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_notification_job_context(bigint) to service_role;

create or replace function public.ia_get_assisted_operation_safety_status(
  p_municipality_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings_present boolean := false;
  v_locked boolean := true;
  v_external_email_enabled boolean := false;
  v_open_channel boolean := false;
  v_automatic_notice boolean := false;
  v_pending_jobs bigint := 0;
begin
  if (select auth.uid()) is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;

  if not (
    private.has_municipality_role(p_municipality_id, null)
    or exists (
      select 1
      from public.taxpayer_user_links tul
      where tul.municipality_id = p_municipality_id
        and tul.user_id = (select auth.uid())
        and tul.status = 'active'
        and tul.verified_at is not null
        and tul.valid_from <= now()
        and (tul.valid_until is null or tul.valid_until > now())
    )
    or exists (
      select 1
      from public.accountant_user_links aul
      where aul.municipality_id = p_municipality_id
        and aul.user_id = (select auth.uid())
        and aul.status = 'active'
        and aul.verified_at is not null
        and aul.valid_from <= now()
        and (aul.valid_until is null or aul.valid_until > now())
    )
  ) then
    raise exception 'municipality access denied' using errcode = '42501';
  end if;

  select true, ps.external_delivery_locked, ps.external_email_enabled
    into v_settings_present, v_locked, v_external_email_enabled
  from public.municipality_portal_settings ps
  where ps.municipality_id = p_municipality_id;

  select exists (
    select 1
    from public.notification_channel_settings cs
    where cs.municipality_id = p_municipality_id
      and cs.channel = 'email'
      and cs.status = 'active'
      and not cs.kill_switch
  ) into v_open_channel;

  select exists (
    select 1
    from public.municipality_policy_versions pv
    where pv.municipality_id = p_municipality_id
      and pv.status = 'active'
      and (pv.auto_initial_notice_enabled or pv.accountant_notice_enabled)
  ) into v_automatic_notice;

  select count(*)
    into v_pending_jobs
  from private.jobs j
  where j.municipality_id = p_municipality_id
    and j.job_type in ('send_initial_notice', 'send_approved_response')
    and j.status in ('pending', 'processing', 'retry');

  return jsonb_build_object(
    'verified', v_settings_present,
    'external_delivery_blocked',
      v_settings_present
      and coalesce(v_locked, true)
      and not coalesce(v_external_email_enabled, false)
      and not v_open_channel
      and not v_automatic_notice,
    'master_lock', coalesce(v_locked, true),
    'external_email_enabled', coalesce(v_external_email_enabled, false),
    'open_email_channel', v_open_channel,
    'automatic_notice_enabled', v_automatic_notice,
    'pending_external_jobs', v_pending_jobs,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.ia_get_assisted_operation_safety_status(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_assisted_operation_safety_status(uuid)
  to authenticated;

create or replace function private.consume_pending_staff_access_grants(
  p_user_id uuid,
  p_email text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant private.pending_staff_access_grants%rowtype;
begin
  if not exists (
    select 1
    from auth.users u
    where u.id = p_user_id
      and lower(trim(coalesce(u.email, ''))) = lower(trim(coalesce(p_email, '')))
      and u.email_confirmed_at is not null
      and u.confirmation_sent_at is not null
      and u.email_confirmed_at >= u.confirmation_sent_at
  ) then
    return;
  end if;

  for v_grant in
    select pg.*
    from private.pending_staff_access_grants pg
    where pg.normalized_email = lower(trim(coalesce(p_email, '')))
      and pg.consumed_at is null
      and pg.expires_at > now()
    for update
  loop
    insert into public.municipality_memberships (
      municipality_id,
      user_id,
      role,
      status,
      valid_from,
      valid_until,
      invited_by,
      activated_at
    ) values (
      v_grant.municipality_id,
      p_user_id,
      v_grant.municipality_role,
      'active',
      now(),
      v_grant.expires_at,
      v_grant.authorized_by,
      now()
    )
    on conflict (municipality_id, user_id) do update
      set status = 'active',
          valid_from = least(public.municipality_memberships.valid_from, now()),
          valid_until = case
            when public.municipality_memberships.valid_until is null then null
            else greatest(public.municipality_memberships.valid_until, excluded.valid_until)
          end,
          invited_by = excluded.invited_by,
          activated_at = coalesce(public.municipality_memberships.activated_at, now()),
          updated_at = now()
      where public.municipality_memberships.role = excluded.role;

    -- Um grant pendente nunca troca nem rebaixa um papel já existente.
    -- Nesse caso ele permanece pendente para resolução administrativa explícita.
    if not exists (
      select 1
      from public.municipality_memberships mm
      where mm.municipality_id = v_grant.municipality_id
        and mm.user_id = p_user_id
        and mm.role = v_grant.municipality_role
    ) then
      continue;
    end if;

    if v_grant.grant_assisted_test_access then
      insert into private.assisted_operation_testers (
        municipality_id,
        user_id,
        authorized_by,
        reason,
        active,
        expires_at
      ) values (
        v_grant.municipality_id,
        p_user_id,
        v_grant.authorized_by,
        v_grant.reason,
        true,
        v_grant.expires_at
      )
      on conflict (municipality_id, user_id) do update
        set authorized_by = excluded.authorized_by,
            reason = excluded.reason,
            active = true,
            expires_at = excluded.expires_at,
            updated_at = now();
    end if;

    update private.pending_staff_access_grants
       set consumed_by = p_user_id,
           consumed_at = now()
     where id = v_grant.id;
  end loop;

  return;
end;
$$;

revoke all on function private.consume_pending_staff_access_grants(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, email, full_name)
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '')
  )
  on conflict (user_id) do nothing;

  if new.email_confirmed_at is not null then
    perform private.consume_pending_staff_access_grants(new.id, new.email);
  end if;
  return new;
end;
$$;

revoke all on function private.handle_auth_user_created()
  from public, anon, authenticated, service_role;

create or replace function private.handle_auth_user_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set email = new.email,
         updated_at = clock_timestamp()
   where user_id = new.id;

  if new.email_confirmed_at is not null then
    perform private.consume_pending_staff_access_grants(new.id, new.email);
  end if;
  return new;
end;
$$;

revoke all on function private.handle_auth_user_updated()
  from public, anon, authenticated, service_role;

drop trigger if exists ia_fiscal_auth_user_updated on auth.users;
create trigger ia_fiscal_auth_user_updated
after update of email, email_confirmed_at on auth.users
for each row execute function private.handle_auth_user_updated();

