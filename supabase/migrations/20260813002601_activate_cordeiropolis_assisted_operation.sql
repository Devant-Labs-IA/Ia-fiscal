-- Ativa somente Cordeirópolis para trabalho interno assistido.
-- A fundação fail-closed precisa estar instalada antes desta promoção.

do $$
declare
  v_municipality_id uuid;
  v_authorized_by uuid;
begin
  select m.id
    into strict v_municipality_id
  from public.municipalities m
  where m.ibge_code = '3512407';

  select u.id
    into strict v_authorized_by
  from auth.users u
  where lower(u.email) = 'diego@devantsolucoes.com.br';

  if not exists (
    select 1
    from public.municipality_portal_settings ps
    where ps.municipality_id = v_municipality_id
  ) then
    raise exception 'portal safety settings are missing';
  end if;

  -- Defesa em profundidade: todas as chaves de entrega ficam fechadas antes da promoção.
  update public.municipality_portal_settings
     set external_email_enabled = false,
         external_delivery_locked = true,
         sandbox_response_publication_enabled = false,
         updated_at = now()
   where municipality_id = v_municipality_id;

  update public.notification_channel_settings
     set status = 'disabled',
         kill_switch = true,
         updated_at = now()
   where municipality_id = v_municipality_id;

  update public.municipality_policy_versions
     set auto_initial_notice_enabled = false,
         accountant_notice_enabled = false,
         updated_at = now()
   where municipality_id = v_municipality_id;

  update private.jobs
     set status = 'cancelled',
         locked_at = null,
         locked_by = null,
         lease_expires_at = null,
         completed_at = coalesce(completed_at, now()),
         updated_at = now(),
         last_error_code = 'assisted_external_delivery_locked',
         last_error_detail = 'Cancelado antes da entrada em operação assistida.'
   where municipality_id = v_municipality_id
     and job_type in ('send_initial_notice', 'send_approved_response')
     and status in ('pending', 'processing', 'retry');

  if exists (
    select 1
    from public.municipality_portal_settings ps
    where ps.municipality_id = v_municipality_id
      and (ps.external_email_enabled or not ps.external_delivery_locked)
  ) or exists (
    select 1
    from public.notification_channel_settings cs
    where cs.municipality_id = v_municipality_id
      and (cs.status <> 'disabled' or not cs.kill_switch)
  ) or exists (
    select 1
    from public.municipality_policy_versions pv
    where pv.municipality_id = v_municipality_id
      and (pv.auto_initial_notice_enabled or pv.accountant_notice_enabled)
  ) then
    raise exception 'external delivery controls are not fail-closed';
  end if;

  if exists (
    select 1
    from private.jobs j
    where j.municipality_id = v_municipality_id
      and j.job_type in ('send_initial_notice', 'send_approved_response')
      and j.status in ('pending', 'processing', 'retry')
  ) then
    raise exception 'external delivery jobs remain pending';
  end if;

  update public.municipalities
     set status = 'active',
         updated_at = now()
   where id = v_municipality_id
     and status in ('setup', 'homologation', 'active');

  if not found then
    raise exception 'municipality cannot enter assisted operation from its current state';
  end if;

  insert into private.pending_staff_access_grants (
    normalized_email,
    municipality_id,
    municipality_role,
    grant_assisted_test_access,
    authorized_by,
    reason,
    expires_at
  ) values (
    'luisnarcizo@uol.com.br',
    v_municipality_id,
    'supervisor',
    true,
    v_authorized_by,
    'Acesso operacional de testes autorizado por Diego, limitado a Cordeirópolis e sem comunicação externa.',
    now() + interval '90 days'
  )
  on conflict (normalized_email, municipality_id) do update
    set municipality_role = excluded.municipality_role,
        grant_assisted_test_access = true,
        authorized_by = excluded.authorized_by,
        reason = excluded.reason,
        expires_at = excluded.expires_at,
        consumed_by = null,
        consumed_at = null;

  -- Também cobre o caso de a identidade já ter sido criada e confirmada
  -- entre a instalação da fundação e esta ativação individual.
  perform private.consume_pending_staff_access_grants(u.id, u.email)
  from auth.users u
  where lower(trim(coalesce(u.email, ''))) = 'luisnarcizo@uol.com.br';
end;
$$;

