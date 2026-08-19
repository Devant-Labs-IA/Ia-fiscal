-- Serialize municipal access changes and keep taxpayer writes constrained to
-- the fields used by the internal homologation workflow.

revoke insert, update, delete on table public.taxpayers from authenticated;

grant insert (
  municipality_id,
  municipal_registration,
  tax_id,
  legal_name,
  trade_name,
  taxpayer_type,
  status,
  source_metadata
) on public.taxpayers to authenticated;

grant update (
  municipal_registration,
  tax_id,
  legal_name,
  trade_name,
  taxpayer_type,
  status,
  updated_at
) on public.taxpayers to authenticated;

create or replace function public.ia_add_existing_municipality_user(
  p_municipality_id uuid,
  p_email text,
  p_role text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_membership_id uuid;
  v_target public.municipality_memberships%rowtype;
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if not private.has_municipality_role(
    p_municipality_id,
    array['municipal_admin']::text[]
  ) then
    raise exception using errcode = '42501', message = 'municipal user administration denied';
  end if;
  if v_email = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception using errcode = '22023', message = 'invalid user email';
  end if;
  if p_role not in (
    'municipal_admin', 'supervisor', 'fiscal_auditor',
    'legal_reviewer', 'support_readonly'
  ) then
    raise exception using errcode = '22023', message = 'invalid municipal role';
  end if;

  -- All mutations for one municipality take the same row lock. The second
  -- authorization check prevents a caller who was demoted while waiting from
  -- continuing with a stale authorization decision.
  perform 1
  from public.municipalities m
  where m.id = p_municipality_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'municipality not found';
  end if;
  if not private.has_municipality_role(
    p_municipality_id,
    array['municipal_admin']::text[]
  ) then
    raise exception using errcode = '42501', message = 'municipal user administration denied';
  end if;

  select u.id
  into v_user_id
  from auth.users u
  where lower(u.email) = v_email
  order by u.created_at
  limit 1;

  if v_user_id is null then
    raise exception using
      errcode = 'P0002',
      message = 'authenticated user account not found';
  end if;

  select mm.*
  into v_target
  from public.municipality_memberships mm
  where mm.municipality_id = p_municipality_id
    and mm.user_id = v_user_id
  for update;

  if found then
    if v_target.user_id = auth.uid()
       and p_role <> 'municipal_admin' then
      raise exception using
        errcode = '42501',
        message = 'an administrator cannot remove their own active administrative access';
    end if;

    if v_target.role = 'municipal_admin'
       and v_target.status = 'active'
       and p_role <> 'municipal_admin'
       and not exists (
         select 1
         from public.municipality_memberships other
         where other.municipality_id = p_municipality_id
           and other.id <> v_target.id
           and other.role = 'municipal_admin'
           and other.status = 'active'
           and other.valid_from <= clock_timestamp()
           and (other.valid_until is null or other.valid_until > clock_timestamp())
       ) then
      raise exception using
        errcode = '23514',
        message = 'the municipality must retain an active administrator';
    end if;

    update public.municipality_memberships mm
    set role = p_role,
        status = 'active',
        valid_from = least(mm.valid_from, clock_timestamp()),
        valid_until = null,
        activated_at = coalesce(mm.activated_at, clock_timestamp()),
        updated_at = clock_timestamp()
    where mm.municipality_id = p_municipality_id
      and mm.id = v_target.id
    returning mm.id into v_membership_id;
  else
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
      p_municipality_id,
      v_user_id,
      p_role,
      'active',
      clock_timestamp(),
      null,
      auth.uid(),
      clock_timestamp()
    )
    returning id into v_membership_id;
  end if;

  return v_membership_id;
end;
$$;

revoke all on function public.ia_add_existing_municipality_user(uuid, text, text) from public;
revoke all on function public.ia_add_existing_municipality_user(uuid, text, text) from anon;
grant execute on function public.ia_add_existing_municipality_user(uuid, text, text) to authenticated;

comment on function public.ia_add_existing_municipality_user(uuid, text, text) is
  'Adds or reactivates an existing Auth user under a per-municipality lock, without sending e-mail.';

create or replace function public.ia_update_municipality_membership(
  p_municipality_id uuid,
  p_membership_id uuid,
  p_role text,
  p_status text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.municipality_memberships%rowtype;
begin
  if not private.has_municipality_role(
    p_municipality_id,
    array['municipal_admin']::text[]
  ) then
    raise exception using errcode = '42501', message = 'municipal user administration denied';
  end if;
  if p_role not in (
    'municipal_admin', 'supervisor', 'fiscal_auditor',
    'legal_reviewer', 'support_readonly'
  ) then
    raise exception using errcode = '22023', message = 'invalid municipal role';
  end if;
  if p_status not in ('active', 'suspended', 'revoked') then
    raise exception using errcode = '22023', message = 'invalid membership status';
  end if;

  perform 1
  from public.municipalities m
  where m.id = p_municipality_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'municipality not found';
  end if;
  if not private.has_municipality_role(
    p_municipality_id,
    array['municipal_admin']::text[]
  ) then
    raise exception using errcode = '42501', message = 'municipal user administration denied';
  end if;

  select mm.*
  into strict v_target
  from public.municipality_memberships mm
  where mm.municipality_id = p_municipality_id
    and mm.id = p_membership_id
  for update;

  if v_target.user_id = auth.uid()
     and (p_role <> 'municipal_admin' or p_status <> 'active') then
    raise exception using
      errcode = '42501',
      message = 'an administrator cannot remove their own active administrative access';
  end if;

  if v_target.role = 'municipal_admin'
     and v_target.status = 'active'
     and (p_role <> 'municipal_admin' or p_status <> 'active')
     and not exists (
       select 1
       from public.municipality_memberships other
       where other.municipality_id = p_municipality_id
         and other.id <> p_membership_id
         and other.role = 'municipal_admin'
         and other.status = 'active'
         and other.valid_from <= clock_timestamp()
         and (other.valid_until is null or other.valid_until > clock_timestamp())
     ) then
    raise exception using
      errcode = '23514',
      message = 'the municipality must retain an active administrator';
  end if;

  update public.municipality_memberships mm
  set role = p_role,
      status = p_status,
      activated_at = case
        when p_status = 'active' then coalesce(mm.activated_at, clock_timestamp())
        else mm.activated_at
      end,
      valid_until = case
        when p_status = 'active' then null
        else clock_timestamp()
      end,
      updated_at = clock_timestamp()
  where mm.municipality_id = p_municipality_id
    and mm.id = p_membership_id;

  return p_membership_id;
end;
$$;

revoke all on function public.ia_update_municipality_membership(uuid, uuid, text, text) from public;
revoke all on function public.ia_update_municipality_membership(uuid, uuid, text, text) from anon;
grant execute on function public.ia_update_municipality_membership(uuid, uuid, text, text) to authenticated;

comment on function public.ia_update_municipality_membership(uuid, uuid, text, text) is
  'Changes one membership under a per-municipality lock and preserves an active administrator.';
