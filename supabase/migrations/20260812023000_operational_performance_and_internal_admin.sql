-- IA Fiscal: operational performance, auditable taxpayer maintenance and
-- internal user administration for the homologation environment.
-- External notification delivery remains unchanged and disabled.

-- Keep planner statistics fresh after small and bulk municipal imports. The
-- dashboard read models are highly sensitive to missing statistics because RLS
-- checks are intentionally applied to every protected source.
alter table public.taxpayers set (
  autovacuum_analyze_scale_factor = 0.05,
  autovacuum_analyze_threshold = 25
);
alter table public.current_account_entries set (
  autovacuum_analyze_scale_factor = 0.05,
  autovacuum_analyze_threshold = 25
);
alter table public.divergences set (
  autovacuum_analyze_scale_factor = 0.05,
  autovacuum_analyze_threshold = 25
);
alter table public.fiscal_cases set (
  autovacuum_analyze_scale_factor = 0.05,
  autovacuum_analyze_threshold = 25
);
alter table public.notifications set (
  autovacuum_analyze_scale_factor = 0.05,
  autovacuum_analyze_threshold = 25
);
alter table public.notification_recipient_candidates set (
  autovacuum_analyze_scale_factor = 0.05,
  autovacuum_analyze_threshold = 25
);

-- Taxpayer maintenance is limited to AAL2 municipal administrators and
-- supervisors. There is intentionally no DELETE policy: removal in the UI is
-- an audited status transition to inactive.
drop policy if exists taxpayers_insert_admin on public.taxpayers;
create policy taxpayers_insert_admin
on public.taxpayers
for insert
to authenticated
with check (
  (select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor']::text[]
  ))
);

drop policy if exists taxpayers_update_admin on public.taxpayers;
create policy taxpayers_update_admin
on public.taxpayers
for update
to authenticated
using (
  (select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor']::text[]
  ))
)
with check (
  (select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor']::text[]
  ))
);

comment on policy taxpayers_insert_admin on public.taxpayers is
  'AAL2 municipal administrators and supervisors may create taxpayers in their municipality.';
comment on policy taxpayers_update_admin on public.taxpayers is
  'AAL2 municipal administrators and supervisors may edit or archive taxpayers in their municipality.';

grant insert, update on table public.taxpayers to authenticated;

-- Preserve the technical identifiers for audit while also exposing the
-- governed Portuguese name and explanation already stored with each rule.
create or replace view public.vw_fiscal_divergence_search
with (security_invoker = true)
as
select
  d.municipality_id,
  d.id as divergence_id,
  d.taxpayer_id,
  t.tax_id,
  t.legal_name,
  d.divergence_type,
  d.period_start,
  d.period_end,
  d.difference_amount,
  d.threshold_amount,
  d.priority_score,
  d.status,
  d.execution_mode,
  d.as_of,
  d.rule_version_id,
  d.detection_run_id,
  d.block_reasons,
  rv.version as rule_version_number,
  rv.status as rule_version_status,
  r.code as rule_code,
  exists (
    select 1
    from public.case_findings cf
    where cf.municipality_id = d.municipality_id
      and cf.divergence_id = d.id
  ) as has_case_finding,
  (
    select count(*)::integer
    from public.case_findings cf
    where cf.municipality_id = d.municipality_id
      and cf.divergence_id = d.id
  ) as case_finding_count,
  r.name as rule_name,
  r.description as rule_description
from public.divergences d
join public.taxpayers t
  on t.municipality_id = d.municipality_id
 and t.id = d.taxpayer_id
join public.divergence_rule_versions rv
  on rv.municipality_id = d.municipality_id
 and rv.id = d.rule_version_id
join public.divergence_rules r
  on r.municipality_id = rv.municipality_id
 and r.id = rv.rule_id;

comment on view public.vw_fiscal_divergence_search is
  'Busca fiscal tenant-safe com cobertura de achado e explicação governada da regra em português.';

create or replace view public.vw_taxpayer_360_divergences
with (security_invoker = true)
as
select
  d.municipality_id,
  d.divergence_id,
  d.taxpayer_id,
  d.tax_id,
  d.legal_name,
  d.divergence_type,
  d.period_start,
  d.period_end,
  d.difference_amount,
  d.threshold_amount,
  d.priority_score,
  d.status,
  d.execution_mode,
  d.as_of,
  d.rule_version_id,
  d.rule_version_number,
  d.rule_version_status,
  d.rule_code,
  d.block_reasons,
  d.has_case_finding,
  d.case_finding_count,
  d.rule_name,
  d.rule_description
from public.vw_fiscal_divergence_search d
where private.has_municipality_role(
  d.municipality_id,
  array[
    'municipal_admin',
    'supervisor',
    'fiscal_auditor',
    'legal_reviewer'
  ]::text[]
);

-- One stable, exact snapshot replaces repeated client-side downloads and
-- aggregation. Authorization is checked once, then tenant scope is explicit.
create or replace function public.ia_operational_report(
  p_municipality_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_report jsonb;
begin
  if not private.has_municipality_role(
    p_municipality_id,
    array[
      'municipal_admin',
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer'
    ]::text[]
  ) then
    raise exception using
      errcode = '42501',
      message = 'municipal operational report access denied';
  end if;

  select jsonb_build_object(
    'taxpayer_count', coalesce(summary.taxpayer_count, 0),
    'overdue_period_count', coalesce(summary.overdue_period_count, 0),
    'open_balance_total', coalesce(summary.open_balance_total, 0),
    'active_divergence_count', coalesce(summary.active_divergence_count, 0),
    'divergence_amount_total', coalesce(summary.divergence_amount_total, 0),
    'active_case_count', coalesce(summary.active_case_count, 0),
    'blocked_calculation_count', coalesce(summary.blocked_calculation_count, 0),
    'waiting_question_count', coalesce(summary.waiting_question_count, 0),
    'recipient_candidate_count', coalesce(recipients.recipient_candidate_count, 0),
    'delivery_ready_count', coalesce(recipients.delivery_ready_count, 0),
    'external_delivery_count', coalesce(recipients.external_delivery_count, 0),
    'generated_at', statement_timestamp()
  )
  into v_report
  from (
    select
      count(*)::integer as taxpayer_count,
      coalesce(sum(s.overdue_period_count), 0)::integer as overdue_period_count,
      coalesce(sum(s.open_balance_total), 0)::numeric(18,2) as open_balance_total,
      coalesce(sum(s.active_divergence_count), 0)::integer as active_divergence_count,
      coalesce(sum(s.divergence_amount_total), 0)::numeric(18,2) as divergence_amount_total,
      coalesce(sum(s.active_case_count), 0)::integer as active_case_count,
      coalesce(sum(s.blocked_calculation_count), 0)::integer as blocked_calculation_count,
      coalesce(sum(s.waiting_question_count), 0)::integer as waiting_question_count
    from public.vw_taxpayer_360_summary s
    where s.municipality_id = p_municipality_id
  ) summary
  cross join (
    select
      count(*)::integer as recipient_candidate_count,
      count(*) filter (where r.safe_for_delivery)::integer as delivery_ready_count,
      count(*) filter (where r.external_delivery_authorized)::integer as external_delivery_count
    from public.vw_notification_recipient_candidates r
    where r.municipality_id = p_municipality_id
  ) recipients;

  return v_report;
end;
$$;

revoke all on function public.ia_operational_report(uuid) from public;
revoke all on function public.ia_operational_report(uuid) from anon;
grant execute on function public.ia_operational_report(uuid) to authenticated;

comment on function public.ia_operational_report(uuid) is
  'Returns an exact internal operational snapshot for one authorized municipality. Performs no external action.';

-- Internal directory. It never sends an invitation or e-mail and it only
-- exposes users already linked to the municipality.
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

comment on function public.ia_list_municipality_users(uuid) is
  'Lists existing municipal access memberships for an AAL2 municipal administrator. Sends no communication.';

-- Add an existing authenticated account to a municipality. Account creation
-- and e-mail delivery are intentionally outside this RPC.
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
  on conflict (municipality_id, user_id)
  do update set
    role = excluded.role,
    status = 'active',
    valid_from = least(public.municipality_memberships.valid_from, excluded.valid_from),
    valid_until = null,
    activated_at = coalesce(
      public.municipality_memberships.activated_at,
      excluded.activated_at
    ),
    updated_at = clock_timestamp()
  returning id into v_membership_id;

  return v_membership_id;
end;
$$;

revoke all on function public.ia_add_existing_municipality_user(uuid, text, text) from public;
revoke all on function public.ia_add_existing_municipality_user(uuid, text, text) from anon;
grant execute on function public.ia_add_existing_municipality_user(uuid, text, text) to authenticated;

comment on function public.ia_add_existing_municipality_user(uuid, text, text) is
  'Activates municipal access for an existing Auth user. Never creates an account or sends e-mail.';

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
  'Changes role or status for one municipal membership, preserving at least one active administrator.';

-- Refresh statistics in the same deployment that introduces the controls.
analyze public.taxpayers;
analyze public.current_account_entries;
analyze public.current_account_maturity_classifications;
analyze public.divergences;
analyze public.divergence_rules;
analyze public.divergence_rule_versions;
analyze public.fiscal_cases;
analyze public.case_explanations;
analyze public.simple_national_calculation_snapshots;
analyze public.notifications;
analyze public.notification_recipient_candidates;
analyze public.fiscal_chat_inbox;