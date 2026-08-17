-- Pre-authorize the co-builder account for the IA Fiscal application only.
-- Access becomes effective only after the exact e-mail is confirmed and the
-- session reaches AAL2. This migration grants no GitHub, Vercel or Supabase
-- dashboard permissions.

alter table private.pending_staff_access_grants
  add column if not exists permanent_access boolean not null default false;

comment on column private.pending_staff_access_grants.permanent_access is
  'When true, the consumed municipality membership has no valid_until. expires_at remains the deadline to claim the pending grant.';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'private.pending_staff_access_grants'::regclass
      and conname = 'pending_staff_access_grants_consumption_ck'
  ) then
    alter table private.pending_staff_access_grants
      add constraint pending_staff_access_grants_consumption_ck
      check ((consumed_at is null) = (consumed_by is null));
  end if;
end;
$$;

create table private.pending_platform_administrator_grants (
  id uuid primary key default gen_random_uuid(),
  normalized_email text not null unique,
  authorized_by uuid references auth.users(id) on delete set null,
  reason text not null,
  expires_at timestamptz not null,
  consumed_by uuid references auth.users(id) on delete set null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),

  constraint pending_platform_admin_email_ck check (
    normalized_email = lower(trim(normalized_email))
    and normalized_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ),
  constraint pending_platform_admin_expiry_ck check (expires_at > created_at),
  constraint pending_platform_admin_consumption_ck
    check ((consumed_at is null) = (consumed_by is null))
);

comment on table private.pending_platform_administrator_grants is
  'Trigger-only pre-authorizations for an internal IA Fiscal platform administrator. Not exposed through the API.';

alter table private.pending_platform_administrator_grants enable row level security;
alter table private.pending_platform_administrator_grants force row level security;

revoke all on private.pending_platform_administrator_grants
  from public, anon, authenticated, service_role;

create table private.platform_administrator_access_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  actor_user_id uuid,
  granted_by uuid,
  event_type text not null,
  active boolean not null,
  revoked_at timestamptz,
  reason text not null,
  database_role text not null,
  recorded_at timestamptz not null default now(),

  constraint platform_admin_access_events_type_ck
    check (event_type in ('granted', 'restored', 'updated', 'revoked', 'deleted'))
);

comment on table private.platform_administrator_access_events is
  'Immutable, private audit trail for IA Fiscal platform administrator grants, restorations and revocations.';

alter table private.platform_administrator_access_events enable row level security;
alter table private.platform_administrator_access_events force row level security;

revoke all on private.platform_administrator_access_events
  from public, anon, authenticated, service_role;

create or replace function private.audit_platform_administrator_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.platform_administrators%rowtype;
  v_event_type text;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;

  v_event_type := case
    when tg_op = 'INSERT' then 'granted'
    when tg_op = 'DELETE' then 'deleted'
    when old.active and not new.active then 'revoked'
    when new.revoked_at is not null and old.revoked_at is null then 'revoked'
    when not old.active and new.active then 'restored'
    when old.revoked_at is not null and new.revoked_at is null then 'restored'
    else 'updated'
  end;

  insert into private.platform_administrator_access_events (
    user_id,
    actor_user_id,
    granted_by,
    event_type,
    active,
    revoked_at,
    reason,
    database_role
  ) values (
    v_row.user_id,
    auth.uid(),
    v_row.granted_by,
    v_event_type,
    v_row.active,
    v_row.revoked_at,
    left(v_row.reason, 500),
    current_user
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

revoke all on function private.audit_platform_administrator_change()
  from public, anon, authenticated, service_role;

create or replace function private.reject_platform_admin_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception using
    errcode = '42501',
    message = 'platform administrator access events are append-only';
end;
$$;

revoke all on function private.reject_platform_admin_event_mutation()
  from public, anon, authenticated, service_role;

create trigger platform_administrator_access_events_immutable
before update or delete on private.platform_administrator_access_events
for each row
execute function private.reject_platform_admin_event_mutation();

create trigger platform_administrators_audit
after insert or update or delete on public.platform_administrators
for each row
execute function private.audit_platform_administrator_change();

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
  v_email text := lower(trim(coalesce(p_email, '')));
  v_grant private.pending_staff_access_grants%rowtype;
  v_platform_grant private.pending_platform_administrator_grants%rowtype;
  v_valid_until timestamptz;
begin
  if not exists (
    select 1
    from auth.users u
    where u.id = p_user_id
      and lower(trim(coalesce(u.email, ''))) = v_email
      and u.email_confirmed_at is not null
      and not coalesce(u.is_anonymous, false)
      and u.deleted_at is null
  ) then
    return;
  end if;

  for v_grant in
    select pending_grant.*
    from private.pending_staff_access_grants pending_grant
    where pending_grant.normalized_email = v_email
      and pending_grant.consumed_at is null
      and pending_grant.expires_at > now()
    order by pending_grant.municipality_id
    for update
  loop
    v_valid_until := case
      when v_grant.permanent_access then null
      else v_grant.expires_at
    end;

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
      v_valid_until,
      v_grant.authorized_by,
      now()
    )
    on conflict (municipality_id, user_id) do update
      set status = 'active',
          valid_from = least(
            public.municipality_memberships.valid_from,
            excluded.valid_from
          ),
          valid_until = case
            when excluded.valid_until is null then null
            when public.municipality_memberships.valid_until is null then null
            else greatest(
              public.municipality_memberships.valid_until,
              excluded.valid_until
            )
          end,
          invited_by = excluded.invited_by,
          activated_at = coalesce(
            public.municipality_memberships.activated_at,
            now()
          ),
          updated_at = now()
      where public.municipality_memberships.role = excluded.role;

    -- A pending grant never changes or downgrades a different existing role.
    -- In that case it stays pending for an explicit administrative resolution.
    if not exists (
      select 1
      from public.municipality_memberships membership
      where membership.municipality_id = v_grant.municipality_id
        and membership.user_id = p_user_id
        and membership.role = v_grant.municipality_role
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

  for v_platform_grant in
    select pending_grant.*
    from private.pending_platform_administrator_grants pending_grant
    where pending_grant.normalized_email = v_email
      and pending_grant.consumed_at is null
      and pending_grant.expires_at > now()
    for update
  loop
    insert into public.platform_administrators (
      user_id,
      granted_by,
      reason,
      active,
      created_at,
      revoked_at
    ) values (
      p_user_id,
      v_platform_grant.authorized_by,
      v_platform_grant.reason,
      true,
      now(),
      null
    )
    on conflict (user_id) do update
      set granted_by = excluded.granted_by,
          reason = excluded.reason,
          active = true,
          revoked_at = null;

    update private.pending_platform_administrator_grants
       set consumed_by = p_user_id,
           consumed_at = now()
     where id = v_platform_grant.id;
  end loop;
end;
$$;

revoke all on function private.consume_pending_staff_access_grants(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.is_platform_administrator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and private.is_aal2()
     and exists (
       select 1
       from public.platform_administrators administrator
       where administrator.user_id = (select auth.uid())
         and administrator.active
         and administrator.revoked_at is null
     );
$$;

revoke all on function private.is_platform_administrator()
  from public, anon;
grant execute on function private.is_platform_administrator()
  to authenticated, service_role;

create or replace function private.can_access_municipality(
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
     and (
       private.is_platform_administrator()
       or exists (
         select 1
         from public.municipality_memberships membership
         where membership.municipality_id = p_municipality_id
           and membership.user_id = (select auth.uid())
           and membership.status = 'active'
           and membership.valid_from <= now()
           and (membership.valid_until is null or membership.valid_until > now())
       )
       or exists (
         select 1
         from public.taxpayer_user_links taxpayer_link
         where taxpayer_link.municipality_id = p_municipality_id
           and taxpayer_link.user_id = (select auth.uid())
           and taxpayer_link.status = 'active'
           and taxpayer_link.valid_from <= now()
           and (taxpayer_link.valid_until is null or taxpayer_link.valid_until > now())
       )
       or exists (
         select 1
         from public.accountant_user_links accountant_link
         where accountant_link.municipality_id = p_municipality_id
           and accountant_link.user_id = (select auth.uid())
           and accountant_link.status = 'active'
           and accountant_link.valid_from <= now()
           and (accountant_link.valid_until is null or accountant_link.valid_until > now())
       )
     );
$$;

revoke all on function private.can_access_municipality(uuid)
  from public, anon;
grant execute on function private.can_access_municipality(uuid)
  to authenticated, service_role;

drop policy if exists memberships_select
  on public.municipality_memberships;

create policy memberships_select
on public.municipality_memberships
for select
to authenticated
using (
  private.is_aal2()
  and (
    user_id = (select auth.uid())
    or private.can_manage_municipality(municipality_id)
    or private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    )
  )
);

drop policy if exists platform_administrators_select_self
  on public.platform_administrators;

create policy platform_administrators_select_self
on public.platform_administrators
for select
to authenticated
using (
  private.is_aal2()
  and user_id = (select auth.uid())
);

drop policy if exists fiscal_search_golden_cases_select
  on public.fiscal_search_golden_cases;

create policy fiscal_search_golden_cases_select
on public.fiscal_search_golden_cases
for select
to authenticated
using (
  private.is_aal2()
  and (
    private.is_platform_administrator()
    or exists (
      select 1
      from public.municipality_memberships membership
      where membership.user_id = (select auth.uid())
        and membership.status = 'active'
        and membership.role = any (
          array[
            'municipal_admin',
            'supervisor',
            'fiscal_auditor'
          ]::text[]
        )
        and membership.valid_from <= now()
        and (membership.valid_until is null or membership.valid_until > now())
    )
  )
);

drop policy if exists worker_health_select_staff
  on public.worker_health;

create policy worker_health_select_staff
on public.worker_health
for select
to authenticated
using (
  private.is_aal2()
  and (
    private.is_platform_administrator()
    or exists (
      select 1
      from public.municipality_memberships membership
      where membership.user_id = (select auth.uid())
        and membership.status = 'active'
        and membership.role = any (
          array['municipal_admin', 'supervisor']::text[]
        )
        and membership.valid_from <= now()
        and (membership.valid_until is null or membership.valid_until > now())
    )
  )
);

do $$
begin
  if not exists (
    select 1
    from auth.users
    where lower(trim(email)) = 'diego@devantsolucoes.com.br'
      and email_confirmed_at is not null
      and deleted_at is null
  ) then
    raise exception 'confirmed Diego account not found for authorization';
  end if;

  if (
    select count(*)
    from public.municipalities
    where slug in ('cordeiropolis-sp', 'araras-sp')
  ) <> 2 then
    raise exception 'Cordeiropolis and Araras must exist before granting access';
  end if;
end;
$$;

with authorizer as (
  select id
  from auth.users
  where lower(trim(email)) = 'diego@devantsolucoes.com.br'
    and email_confirmed_at is not null
    and deleted_at is null
  order by created_at
  limit 1
)
insert into private.pending_staff_access_grants (
  normalized_email,
  municipality_id,
  municipality_role,
  grant_assisted_test_access,
  permanent_access,
  authorized_by,
  reason,
  expires_at
)
select
  'luisnarcizo@uol.com.br',
  municipality.id,
  'municipal_admin',
  false,
  true,
  authorizer.id,
  'Acesso permanente ao aplicativo IA Fiscal autorizado por Diego em 17/08/2026; administrador municipal; MFA/AAL2 obrigatorio; sem acesso assistido e sem acesso a infraestrutura.',
  now() + interval '1 year'
from public.municipalities municipality
cross join authorizer
where municipality.slug in ('cordeiropolis-sp', 'araras-sp')
on conflict (normalized_email, municipality_id) do update
set municipality_role = 'municipal_admin',
    grant_assisted_test_access = false,
    permanent_access = true,
    authorized_by = excluded.authorized_by,
    reason = excluded.reason,
    expires_at = greatest(
      private.pending_staff_access_grants.expires_at,
      excluded.expires_at
    ),
    consumed_by = null,
    consumed_at = null;

with authorizer as (
  select id
  from auth.users
  where lower(trim(email)) = 'diego@devantsolucoes.com.br'
    and email_confirmed_at is not null
    and deleted_at is null
  order by created_at
  limit 1
)
insert into private.pending_platform_administrator_grants (
  normalized_email,
  authorized_by,
  reason,
  expires_at
)
select
  'luisnarcizo@uol.com.br',
  authorizer.id,
  'Administrador global permanente do aplicativo IA Fiscal, equivalente ao acesso interno de Diego; MFA/AAL2 obrigatorio; sem permissao de GitHub, Vercel ou painel Supabase.',
  now() + interval '1 year'
from authorizer
on conflict (normalized_email) do update
set authorized_by = excluded.authorized_by,
    reason = excluded.reason,
    expires_at = greatest(
      private.pending_platform_administrator_grants.expires_at,
      excluded.expires_at
    ),
    consumed_by = null,
    consumed_at = null;

-- Handle the race where the target registers and confirms while this migration
-- is being deployed. In the normal current state this loop processes no rows.
do $$
declare
  v_user record;
begin
  for v_user in
    select id, email
    from auth.users
    where lower(trim(email)) = 'luisnarcizo@uol.com.br'
      and email_confirmed_at is not null
      and not coalesce(is_anonymous, false)
      and deleted_at is null
  loop
    perform private.consume_pending_staff_access_grants(
      v_user.id,
      v_user.email
    );
  end loop;
end;
$$;
