-- Homologation-only access simplification.
-- Keep authentication, tenant membership and role-based authorization in place,
-- but stop requiring the JWT to be elevated from AAL1 to AAL2.
create or replace function private.is_aal2()
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.is_service_role()
      or (
        coalesce(auth.jwt() ->> 'role', '') = 'authenticated'
        and (select auth.uid()) is not null
      );
$$;

comment on function private.is_aal2() is
  'Homologation override: accepts authenticated AAL1 or AAL2 sessions. Production must restore the explicit aal2 claim requirement.';
