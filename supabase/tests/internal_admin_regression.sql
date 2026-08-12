-- Transactional regression for internal municipal administration and the
-- taxpayer-maintenance column boundary. Every synthetic fixture is rolled back.

begin;

do $test$
declare
  v_denied boolean;
  v_role text;
  v_status text;
  x_municipality constant uuid := '00000000-0000-4000-8000-000000000880';
  u_admin_a constant uuid := '00000000-0000-4000-8000-000000000881';
  u_admin_b constant uuid := '00000000-0000-4000-8000-000000000882';
  m_admin_a constant uuid := '00000000-0000-4000-8000-000000000891';
  m_admin_b constant uuid := '00000000-0000-4000-8000-000000000892';
begin
  insert into public.municipalities (id, slug, name, state_code)
  values (x_municipality, 'regression-admin-lock', 'Regressão Administração', 'SP');

  insert into auth.users (
    id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values
    (u_admin_a, 'authenticated', 'authenticated', 'admin-a@regression.invalid', '{}', '{}', now(), now()),
    (u_admin_b, 'authenticated', 'authenticated', 'admin-b@regression.invalid', '{}', '{}', now(), now());

  insert into public.municipality_memberships (
    id, municipality_id, user_id, role, status, valid_from, valid_until, activated_at
  ) values
    (m_admin_a, x_municipality, u_admin_a, 'municipal_admin', 'active', now() - interval '1 day', null, now()),
    (m_admin_b, x_municipality, u_admin_b, 'municipal_admin', 'active', now() - interval '1 day', null, now());

  perform set_config('request.jwt.claim.sub', u_admin_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_admin_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );

  v_denied := false;
  begin
    perform public.ia_add_existing_municipality_user(
      x_municipality, 'admin-a@regression.invalid', 'supervisor'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'self demotion through add-existing was accepted';
  end if;

  select role, status into strict v_role, v_status
  from public.municipality_memberships
  where id = m_admin_a;
  if v_role <> 'municipal_admin' or v_status <> 'active' then
    raise exception 'self demotion changed the caller membership';
  end if;

  perform public.ia_add_existing_municipality_user(
    x_municipality, 'admin-b@regression.invalid', 'fiscal_auditor'
  );

  perform set_config('request.jwt.claim.sub', u_admin_b::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_admin_b, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );

  v_denied := false;
  begin
    perform public.ia_update_municipality_membership(
      x_municipality, m_admin_a, 'supervisor', 'active'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'demoted administrator retained stale administration access';
  end if;

  if has_column_privilege('authenticated', 'public.taxpayers', 'municipality_id', 'UPDATE') then
    raise exception 'authenticated may update taxpayer municipality_id';
  end if;
  if not has_column_privilege('authenticated', 'public.taxpayers', 'legal_name', 'UPDATE') then
    raise exception 'authenticated lost allowed taxpayer legal_name update';
  end if;
  if has_column_privilege('authenticated', 'public.taxpayers', 'source_key', 'INSERT') then
    raise exception 'authenticated may insert taxpayer source_key';
  end if;
  if has_table_privilege('authenticated', 'public.taxpayers', 'DELETE') then
    raise exception 'authenticated may delete taxpayers';
  end if;

  if pg_get_functiondef(
       'public.ia_add_existing_municipality_user(uuid,text,text)'::regprocedure
     ) not like '%from public.municipalities m%for update%'
     or pg_get_functiondef(
       'public.ia_update_municipality_membership(uuid,uuid,text,text)'::regprocedure
     ) not like '%from public.municipalities m%for update%' then
    raise exception 'municipal administration functions lack the shared row lock';
  end if;
end
$test$;

rollback;
