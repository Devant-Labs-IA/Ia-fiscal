-- PostgreSQL preserves varchar domains in RETURN QUERY. Cast directory text
-- values explicitly so the public RPC matches its stable text contract.
create or replace function public.ia_list_municipality_users(
  p_municipality_id uuid
)
returns table (
  membership_id uuid,
  user_id uuid,
  full_name text,
  email text,
  role text,
  status text,
  valid_from timestamptz,
  valid_until timestamptz,
  last_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_municipality_role(
    p_municipality_id,
    array['municipal_admin']::text[]
  ) then
    raise exception using
      errcode = '42501',
      message = 'municipal user directory access denied';
  end if;

  return query
  select
    mm.id,
    mm.user_id,
    coalesce(nullif(trim(p.full_name), ''), 'Usuário sem nome')::text,
    coalesce(p.email, u.email, '')::text,
    mm.role::text,
    mm.status::text,
    mm.valid_from,
    mm.valid_until,
    p.last_seen_at
  from public.municipality_memberships mm
  left join public.profiles p on p.user_id = mm.user_id
  left join auth.users u on u.id = mm.user_id
  where mm.municipality_id = p_municipality_id
  order by
    (mm.status = 'active') desc,
    coalesce(nullif(trim(p.full_name), ''), p.email, u.email, mm.user_id::text);
end;
$$;

revoke all on function public.ia_list_municipality_users(uuid) from public;
revoke all on function public.ia_list_municipality_users(uuid) from anon;
grant execute on function public.ia_list_municipality_users(uuid) to authenticated;
