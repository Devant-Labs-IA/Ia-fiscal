-- IA Fiscal: taxpayer 360 dossier — deterministic operational next-action queue.
-- Priority is workflow-oriented, not a legal risk classification.

create or replace view public.vw_taxpayer_360_next_actions
with (security_invoker = true)
as
select
  fi.municipality_id,
  fi.taxpayer_id,
  fi.case_id,
  'chat_question'::text as source_type,
  fi.question_id as source_id,
  'respond_taxpayer_question'::text as action_code,
  'Responder questionamento do contribuinte'::text as action_label,
  'urgent'::text as operational_priority,
  10::integer as priority_rank,
  coalesce(fi.routing_reason, 'Questionamento aguardando atendimento fiscal') as reason,
  fi.sla_due_at as due_at,
  fi.created_at
from public.fiscal_chat_inbox fi
where fi.status in ('waiting', 'claimed')
  and private.can_view_case_staff(fi.municipality_id, fi.case_id)

union all

select
  c.municipality_id,
  c.taxpayer_id,
  c.case_id,
  'fiscal_case'::text as source_type,
  c.case_id as source_id,
  'continue_fiscal_review'::text as action_code,
  'Dar continuidade à análise fiscal'::text as action_label,
  'high'::text as operational_priority,
  20::integer as priority_rank,
  'Processo está aguardando ação do fiscal'::text as reason,
  null::timestamptz as due_at,
  coalesce(c.updated_at, c.opened_at) as created_at
from public.vw_taxpayer_360_cases c
where c.status = 'awaiting_fiscal'

union all

select
  n.municipality_id,
  n.taxpayer_id,
  n.case_id,
  'notification'::text as source_type,
  n.communication_id as source_id,
  'review_prepared_notification'::text as action_code,
  'Revisar notificação preparada'::text as action_label,
  'high'::text as operational_priority,
  30::integer as priority_rank,
  case
    when n.external_delivery_attempted then 'Notificação preparada com tentativa externa registrada'
    else 'Notificação preparada; envio externo permanece bloqueado'
  end as reason,
  null::timestamptz as due_at,
  n.created_at
from public.vw_taxpayer_360_communications n
where n.communication_type = 'notification'
  and n.status in ('draft', 'prepared', 'review_pending')

union all

select
  c.municipality_id,
  c.taxpayer_id,
  null::uuid as case_id,
  'calculation'::text as source_type,
  null::uuid as source_id,
  'complete_calculation_inputs'::text as action_code,
  'Completar dados para cálculo'::text as action_label,
  'medium'::text as operational_priority,
  40::integer as priority_rank,
  format('%s cálculo(s) bloqueado(s) por dados insuficientes', count(*)) as reason,
  null::timestamptz as due_at,
  max(c.calculated_at) as created_at
from public.vw_taxpayer_360_calculations c
where c.status = 'blocked'
group by c.municipality_id, c.taxpayer_id

union all

select
  d.municipality_id,
  d.taxpayer_id,
  null::uuid as case_id,
  'divergence'::text as source_type,
  null::uuid as source_id,
  'revalidate_divergences'::text as action_code,
  'Revalidar divergências pendentes'::text as action_label,
  'medium'::text as operational_priority,
  50::integer as priority_rank,
  format('%s divergência(s) aguardando revalidação', count(*)) as reason,
  null::timestamptz as due_at,
  max(d.as_of) as created_at
from public.vw_taxpayer_360_divergences d
where d.status = 'pending_revalidation'
group by d.municipality_id, d.taxpayer_id

union all

select
  d.municipality_id,
  d.taxpayer_id,
  null::uuid as case_id,
  'current_account'::text as source_type,
  null::uuid as source_id,
  'analyze_overdue_balance'::text as action_code,
  'Analisar saldo municipal em aberto'::text as action_label,
  'attention'::text as operational_priority,
  60::integer as priority_rank,
  format('%s competência(s) com saldo em aberto', count(*)) as reason,
  null::timestamptz as due_at,
  max(d.data_base) as created_at
from public.vw_taxpayer_360_debts d
where d.status = 'em_aberto'
  and d.saldo_em_aberto > 0
group by d.municipality_id, d.taxpayer_id;

create or replace view public.vw_taxpayer_360_primary_action
with (security_invoker = true)
as
select distinct on (a.municipality_id, a.taxpayer_id)
  a.municipality_id,
  a.taxpayer_id,
  a.case_id,
  a.source_type,
  a.source_id,
  a.action_code,
  a.action_label,
  a.operational_priority,
  a.priority_rank,
  a.reason,
  a.due_at,
  a.created_at
from public.vw_taxpayer_360_next_actions a
order by
  a.municipality_id,
  a.taxpayer_id,
  a.priority_rank,
  a.due_at nulls last,
  a.created_at desc nulls last;

create or replace view public.vw_taxpayer_360_summary
with (security_invoker = true)
as
with contact_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as contact_count,
    count(*) filter (
      where status = 'verified'
        and verified_at is not null
        and valid_from <= now()
        and (valid_until is null or valid_until > now())
    )::integer as verified_contact_count
  from public.vw_taxpayer_360_contacts
  group by municipality_id, taxpayer_id
), responsible_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as responsible_count,
    count(*) filter (where safe_for_delivery)::integer as delivery_ready_responsible_count
  from public.vw_taxpayer_360_responsibles
  group by municipality_id, taxpayer_id
), communication_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as communication_count,
    max(occurred_at) as latest_communication_at
  from public.vw_taxpayer_360_communications
  group by municipality_id, taxpayer_id
), document_rollup as (
  select
    municipality_id,
    taxpayer_id,
    count(*)::integer as document_count,
    max(created_at) as latest_document_at
  from public.vw_taxpayer_360_documents
  group by municipality_id, taxpayer_id
), chat_rollup as (
  select
    fi.municipality_id,
    fi.taxpayer_id,
    count(*) filter (where fi.status in ('waiting', 'claimed'))::integer
      as waiting_question_count,
    min(fi.sla_due_at) filter (where fi.status in ('waiting', 'claimed'))
      as next_chat_sla_due_at
  from public.fiscal_chat_inbox fi
  where private.can_view_case_staff(fi.municipality_id, fi.case_id)
  group by fi.municipality_id, fi.taxpayer_id
)
select
  b.*,
  coalesce(ct.contact_count, 0) as contact_count,
  coalesce(ct.verified_contact_count, 0) as verified_contact_count,
  coalesce(rr.responsible_count, 0) as responsible_count,
  coalesce(rr.delivery_ready_responsible_count, 0) as delivery_ready_responsible_count,
  coalesce(cm.communication_count, 0) as communication_count,
  cm.latest_communication_at,
  coalesce(dc.document_count, 0) as document_count,
  dc.latest_document_at,
  coalesce(ch.waiting_question_count, 0) as waiting_question_count,
  ch.next_chat_sla_due_at,
  pa.case_id as primary_action_case_id,
  pa.source_type as primary_action_source_type,
  pa.source_id as primary_action_source_id,
  pa.action_code as primary_action_code,
  pa.action_label as primary_action_label,
  pa.operational_priority as primary_action_priority,
  pa.reason as primary_action_reason,
  pa.due_at as primary_action_due_at
from public.vw_taxpayer_360_summary_base b
left join contact_rollup ct
  on ct.municipality_id = b.municipality_id and ct.taxpayer_id = b.taxpayer_id
left join responsible_rollup rr
  on rr.municipality_id = b.municipality_id and rr.taxpayer_id = b.taxpayer_id
left join communication_rollup cm
  on cm.municipality_id = b.municipality_id and cm.taxpayer_id = b.taxpayer_id
left join document_rollup dc
  on dc.municipality_id = b.municipality_id and dc.taxpayer_id = b.taxpayer_id
left join chat_rollup ch
  on ch.municipality_id = b.municipality_id and ch.taxpayer_id = b.taxpayer_id
left join public.vw_taxpayer_360_primary_action pa
  on pa.municipality_id = b.municipality_id and pa.taxpayer_id = b.taxpayer_id;

revoke all on
  public.vw_taxpayer_360_next_actions,
  public.vw_taxpayer_360_primary_action,
  public.vw_taxpayer_360_summary
from public, anon;

grant select on
  public.vw_taxpayer_360_next_actions,
  public.vw_taxpayer_360_primary_action,
  public.vw_taxpayer_360_summary
to authenticated, service_role;

comment on view public.vw_taxpayer_360_next_actions is
  'Deterministic operational queue. priority_rank is workflow ordering and must not be presented as legal risk or tax assessment priority.';
