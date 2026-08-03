-- IA Fiscal: taxpayer 360 dossier — controlled staff read access and core views.
-- Scope: read only. No write, review, approval, delivery or closure permission is expanded.

create or replace function private.can_view_case_staff(
  p_municipality_id uuid,
  p_case_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.fiscal_cases fc
    where fc.municipality_id = p_municipality_id
      and fc.id = p_case_id
      and (
        private.has_municipality_role(
          p_municipality_id,
          array['municipal_admin', 'supervisor', 'legal_reviewer']::text[]
        )
        or (
          private.has_municipality_role(
            p_municipality_id,
            array['fiscal_auditor']::text[]
          )
          and (
            fc.confidentiality = 'internal'
            or exists (
              select 1
              from public.case_assignments ca
              join public.municipality_memberships mm
                on mm.municipality_id = ca.municipality_id
               and mm.id = ca.membership_id
              where ca.municipality_id = fc.municipality_id
                and ca.case_id = fc.id
                and ca.status = 'active'
                and mm.user_id = (select auth.uid())
                and mm.status = 'active'
                and mm.valid_from <= now()
                and (mm.valid_until is null or mm.valid_until > now())
            )
          )
        )
      )
  );
$$;

revoke all on function private.can_view_case_staff(uuid, uuid) from public, anon;
grant execute on function private.can_view_case_staff(uuid, uuid)
  to authenticated, service_role;

comment on function private.can_view_case_staff(uuid, uuid) is
  'Read-only staff visibility: fiscal auditors see internal cases in their municipality; restricted/fiscal_secret cases require active assignment. Does not grant review or write authority.';

create or replace function private.can_access_case(
  p_municipality_id uuid,
  p_case_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_view_case_staff(p_municipality_id, p_case_id)
      or exists (
        select 1
        from public.fiscal_cases fc
        join public.taxpayer_user_links tul
          on tul.municipality_id = fc.municipality_id
         and tul.taxpayer_id = fc.taxpayer_id
        where fc.municipality_id = p_municipality_id
          and fc.id = p_case_id
          and tul.user_id = (select auth.uid())
          and tul.status = 'active'
          and tul.valid_from <= now()
          and (tul.valid_until is null or tul.valid_until > now())
      )
      or exists (
        select 1
        from public.fiscal_cases fc
        join public.taxpayer_accountant_links tal
          on tal.municipality_id = fc.municipality_id
         and tal.taxpayer_id = fc.taxpayer_id
        join public.accountant_user_links aul
          on aul.municipality_id = tal.municipality_id
         and aul.accounting_firm_id = tal.accounting_firm_id
        where fc.municipality_id = p_municipality_id
          and fc.id = p_case_id
          and tal.status = 'active'
          and tal.can_access_portal
          and tal.valid_from <= now()
          and (tal.valid_until is null or tal.valid_until > now())
          and aul.user_id = (select auth.uid())
          and aul.status = 'active'
          and aul.valid_from <= now()
          and (aul.valid_until is null or aul.valid_until > now())
      );
$$;

create or replace function private.can_access_divergence(
  p_municipality_id uuid,
  p_divergence_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_municipality_role(
           p_municipality_id,
           array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
         )
      or exists (
        select 1
        from public.fiscal_cases fc
        where fc.municipality_id = p_municipality_id
          and fc.divergence_id = p_divergence_id
          and private.can_access_case(fc.municipality_id, fc.id)
      );
$$;

drop policy if exists current_account_entries_select_supervisor
  on public.current_account_entries;
drop policy if exists current_account_entries_select_staff
  on public.current_account_entries;
create policy current_account_entries_select_staff
on public.current_account_entries
for select
to authenticated
using (
  (select private.has_municipality_role(
    current_account_entries.municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  ))
);

drop policy if exists notifications_select on public.notifications;
create policy notifications_select
on public.notifications
for select
to authenticated
using (
  (select private.can_view_case_staff(notifications.municipality_id, notifications.case_id))
);

drop policy if exists notification_recipients_select
  on public.notification_recipients;
create policy notification_recipients_select
on public.notification_recipients
for select
to authenticated
using (
  exists (
    select 1
    from public.notifications n
    where n.municipality_id = notification_recipients.municipality_id
      and n.id = notification_recipients.notification_id
      and private.can_view_case_staff(n.municipality_id, n.case_id)
  )
);

drop policy if exists case_events_select on public.case_events;
create policy case_events_select
on public.case_events
for select
to authenticated
using (
  (select private.can_access_case(case_events.municipality_id, case_events.case_id))
  and (
    case_events.visibility = 'participants'
    or (select private.can_view_case_staff(case_events.municipality_id, case_events.case_id))
  )
);

drop policy if exists case_documents_select on public.case_documents;
create policy case_documents_select
on public.case_documents
for select
to authenticated
using (
  (select private.can_access_case(case_documents.municipality_id, case_documents.case_id))
  and (
    case_documents.status = 'available'
    or (select private.can_view_case_staff(case_documents.municipality_id, case_documents.case_id))
  )
);

drop policy if exists case_messages_select on public.case_messages;
create policy case_messages_select
on public.case_messages
for select
to authenticated
using (
  (select private.can_access_case(case_messages.municipality_id, case_messages.case_id))
  and (
    (case_messages.status = 'published' and case_messages.visibility = 'participants')
    or (select private.can_view_case_staff(case_messages.municipality_id, case_messages.case_id))
  )
);

create or replace view public.vw_taxpayer_360_debts
with (security_invoker = true)
as
select
  p.municipio_id as municipality_id,
  p.contribuinte_id as taxpayer_id,
  p.competencia,
  p.valor_emitido,
  p.valor_vencido,
  p.valor_pago,
  greatest(p.valor_vencido - p.valor_pago - p.saldo_em_aberto, 0::numeric)::numeric(18,2)
    as applied_credits_derived,
  p.saldo_em_aberto,
  p.divergencia_conta_corrente,
  p.valor_sem_vencimento,
  p.valor_a_vencer,
  p.saldo_reportado,
  p.primeiro_vencimento,
  p.ultimo_vencimento,
  p.status,
  p.elegivel,
  p.regra_versao,
  p.data_base,
  p.qtd_fontes
from public.vw_current_account_period p
where private.has_municipality_role(
  p.municipio_id,
  array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
);

comment on column public.vw_taxpayer_360_debts.applied_credits_derived is
  'Observable residual derived from overdue amount, payments and open balance. It is not a source-system field and must be labelled as derived in the UI.';

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
  d.case_finding_count
from public.vw_fiscal_divergence_search d
where private.has_municipality_role(
  d.municipality_id,
  array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
);

create or replace view public.vw_taxpayer_360_cases
with (security_invoker = true)
as
select
  fc.municipality_id,
  fc.taxpayer_id,
  fc.id as case_id,
  fc.case_number,
  fc.divergence_id,
  fc.status,
  fc.confidentiality,
  fc.execution_mode,
  fc.opened_at,
  fc.first_accessed_at,
  fc.closed_at,
  fc.closure_reason,
  fc.version,
  fc.updated_at,
  ce.title as current_explanation_title,
  ce.summary as current_explanation_summary,
  ce.legal_basis_summary,
  ce.legal_review_required,
  coalesce(a.active_assignment_count, 0)::integer as active_assignment_count,
  a.active_assignment_roles,
  coalesce(q.waiting_question_count, 0)::integer as waiting_question_count
from public.fiscal_cases fc
left join lateral (
  select
    e.title,
    e.summary,
    e.legal_basis_summary,
    e.legal_review_required
  from public.case_explanations e
  where e.municipality_id = fc.municipality_id
    and e.case_id = fc.id
    and e.is_current
  order by e.explanation_version desc
  limit 1
) ce on true
left join lateral (
  select
    count(*)::integer as active_assignment_count,
    array_agg(ca.assignment_role order by ca.assigned_at) as active_assignment_roles
  from public.case_assignments ca
  where ca.municipality_id = fc.municipality_id
    and ca.case_id = fc.id
    and ca.status = 'active'
) a on true
left join lateral (
  select count(*)::integer as waiting_question_count
  from public.case_questions cq
  where cq.municipality_id = fc.municipality_id
    and cq.case_id = fc.id
    and cq.status in ('waiting', 'claimed')
) q on true
where private.can_view_case_staff(fc.municipality_id, fc.id);

create or replace view public.vw_taxpayer_360_calculations
with (security_invoker = true)
as
select
  s.municipality_id,
  s.taxpayer_id,
  s.calculation_snapshot_id,
  s.competence_month,
  s.declared_rbt12,
  s.calculated_rbt12,
  s.rbt12_difference,
  s.declared_fs12,
  s.calculated_fs12,
  s.declared_factor_r,
  s.calculated_factor_r,
  s.factor_r_difference,
  s.declared_annex_code,
  s.expected_annex_code,
  s.annex_mismatch,
  s.pgdasd_tax_base,
  s.sigiss_tax_base,
  s.tax_base_difference,
  s.status,
  s.is_test,
  s.calculation_version,
  s.calculated_at
from public.vw_simple_national_cross_checks s
where private.has_municipality_role(
  s.municipality_id,
  array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
);

create or replace view public.vw_taxpayer_360_summary_base
with (security_invoker = true)
as
with debt_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as debt_period_count,
    count(*) filter (where status = 'em_aberto')::integer as overdue_period_count,
    count(*) filter (where status = 'dados_incompletos')::integer as incomplete_debt_period_count,
    coalesce(sum(saldo_em_aberto), 0)::numeric(18,2) as open_balance_total,
    min(primeiro_vencimento) filter (where saldo_em_aberto > 0) as oldest_open_due_on,
    max(data_base) as last_account_import_at
  from public.vw_taxpayer_360_debts
  group by municipality_id, taxpayer_id
), divergence_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as divergence_count,
    count(*) filter (
      where status not in ('converted', 'resolved', 'dismissed', 'cancelled')
    )::integer as active_divergence_count,
    count(*) filter (where jsonb_array_length(coalesce(block_reasons, '[]'::jsonb)) > 0)::integer
      as blocked_divergence_count,
    coalesce(sum(difference_amount) filter (
      where status not in ('resolved', 'dismissed', 'cancelled')
    ), 0)::numeric(18,2) as divergence_amount_total,
    max(priority_score) as highest_priority_score
  from public.vw_taxpayer_360_divergences
  group by municipality_id, taxpayer_id
), case_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as case_count,
    count(*) filter (
      where status not in ('resolved', 'closed', 'cancelled')
    )::integer as active_case_count,
    count(*) filter (where status = 'awaiting_fiscal')::integer as awaiting_fiscal_case_count,
    max(coalesce(updated_at, opened_at)) as latest_case_activity_at
  from public.vw_taxpayer_360_cases
  group by municipality_id, taxpayer_id
), calculation_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as calculation_count,
    count(*) filter (where status = 'blocked')::integer as blocked_calculation_count,
    max(calculated_at) as latest_calculation_at
  from public.vw_taxpayer_360_calculations
  group by municipality_id, taxpayer_id
)
select
  t.municipality_id,
  t.id as taxpayer_id,
  t.municipal_registration,
  t.tax_id,
  t.legal_name,
  t.trade_name,
  t.taxpayer_type,
  t.status as taxpayer_status,
  t.source_key,
  t.updated_at as taxpayer_updated_at,
  coalesce(dr.debt_period_count, 0) as debt_period_count,
  coalesce(dr.overdue_period_count, 0) as overdue_period_count,
  coalesce(dr.incomplete_debt_period_count, 0) as incomplete_debt_period_count,
  coalesce(dr.open_balance_total, 0)::numeric(18,2) as open_balance_total,
  dr.oldest_open_due_on,
  dr.last_account_import_at,
  coalesce(vr.divergence_count, 0) as divergence_count,
  coalesce(vr.active_divergence_count, 0) as active_divergence_count,
  coalesce(vr.blocked_divergence_count, 0) as blocked_divergence_count,
  coalesce(vr.divergence_amount_total, 0)::numeric(18,2) as divergence_amount_total,
  vr.highest_priority_score,
  coalesce(cr.case_count, 0) as case_count,
  coalesce(cr.active_case_count, 0) as active_case_count,
  coalesce(cr.awaiting_fiscal_case_count, 0) as awaiting_fiscal_case_count,
  cr.latest_case_activity_at,
  coalesce(sr.calculation_count, 0) as calculation_count,
  coalesce(sr.blocked_calculation_count, 0) as blocked_calculation_count,
  sr.latest_calculation_at,
  case
    when coalesce(cr.awaiting_fiscal_case_count, 0) > 0 then 'high'
    when coalesce(sr.blocked_calculation_count, 0) > 0
      or coalesce(vr.active_divergence_count, 0) > 0 then 'medium'
    when coalesce(dr.open_balance_total, 0) > 0 then 'attention'
    else 'normal'
  end as operational_attention_level
from public.taxpayers t
left join debt_rollup dr
  on dr.municipality_id = t.municipality_id and dr.taxpayer_id = t.id
left join divergence_rollup vr
  on vr.municipality_id = t.municipality_id and vr.taxpayer_id = t.id
left join case_rollup cr
  on cr.municipality_id = t.municipality_id and cr.taxpayer_id = t.id
left join calculation_rollup sr
  on sr.municipality_id = t.municipality_id and sr.taxpayer_id = t.id
where private.has_municipality_role(
  t.municipality_id,
  array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
);

revoke all on
  public.vw_taxpayer_360_debts,
  public.vw_taxpayer_360_divergences,
  public.vw_taxpayer_360_cases,
  public.vw_taxpayer_360_calculations,
  public.vw_taxpayer_360_summary_base
from public, anon;

grant select on
  public.vw_taxpayer_360_debts,
  public.vw_taxpayer_360_divergences,
  public.vw_taxpayer_360_cases,
  public.vw_taxpayer_360_calculations,
  public.vw_taxpayer_360_summary_base
to authenticated, service_role;

