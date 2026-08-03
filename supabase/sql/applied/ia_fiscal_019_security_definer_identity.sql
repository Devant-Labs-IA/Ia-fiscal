-- IA Fiscal
-- Security hotfix: never infer the caller from current_user inside
-- SECURITY DEFINER functions. In that context current_user is the function
-- owner, not the authenticated caller.

create or replace function private.is_service_role()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role';
$$;

create or replace function private.is_aal2()
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.is_service_role()
      or (
        coalesce(auth.jwt() ->> 'role', '') = 'authenticated'
        and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
      );
$$;

revoke all on function private.is_service_role() from public, anon, authenticated;
revoke all on function private.is_aal2() from public, anon, authenticated;
grant execute on function private.is_service_role() to service_role;
grant execute on function private.is_aal2() to service_role;

-- Authenticated RPCs call these helpers from their privileged function body.
-- Granting direct EXECUTE is unnecessary and would widen the public surface.
