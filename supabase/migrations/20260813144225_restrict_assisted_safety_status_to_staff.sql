-- Restringe o diagnóstico operacional de comunicação aos perfis internos do município.

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

  if not private.has_municipality_role(p_municipality_id, null) then
    raise exception 'municipal staff access required' using errcode = '42501';
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

notify pgrst, 'reload schema';
