-- Padronização oficial da integração SIGIS ↔ IA Fiscal.
-- Mantém um alias temporário para instalações que tenham aplicado a nomenclatura anterior.

create or replace function public.ia_sigis_resolve_access(
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

  if v_role is null and exists (
    select 1
    from public.taxpayer_accountant_links tal
    join public.accountant_user_links aul
      on aul.municipality_id = tal.municipality_id
     and aul.accounting_firm_id = tal.accounting_firm_id
    where tal.municipality_id = p_municipality_id
      and tal.taxpayer_id = v_taxpayer.id
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
    raise exception 'SIGIS context access denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'authorized', true,
    'municipality_id', p_municipality_id,
    'taxpayer_id', v_taxpayer.id,
    'tax_id', regexp_replace(v_taxpayer.tax_id, '\D', '', 'g'),
    'role', v_role,
    'source', 'sigis_authorization_boundary',
    'checked_at', now()
  );
end;
$$;

revoke all on function public.ia_sigis_resolve_access(uuid, uuid, text)
  from public, anon;
grant execute on function public.ia_sigis_resolve_access(uuid, uuid, text)
  to authenticated, service_role;

comment on function public.ia_sigis_resolve_access(uuid, uuid, text) is
  'Resolve deterministicamente município, usuário e contribuinte antes de qualquer chamada ao SIGIS. Não consulta o SIGIS e não amplia permissões.';

-- Alias temporário para clientes implantados com a nomenclatura anterior.
create or replace function public.ia_cigis_resolve_access(
  p_municipality_id uuid,
  p_taxpayer_id uuid default null,
  p_tax_id text default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.ia_sigis_resolve_access(
    p_municipality_id,
    p_taxpayer_id,
    p_tax_id
  );
$$;

revoke all on function public.ia_cigis_resolve_access(uuid, uuid, text)
  from public, anon;
grant execute on function public.ia_cigis_resolve_access(uuid, uuid, text)
  to authenticated, service_role;

comment on function public.ia_cigis_resolve_access(uuid, uuid, text) is
  'Alias técnico temporário. Novas integrações devem usar public.ia_sigis_resolve_access.';
