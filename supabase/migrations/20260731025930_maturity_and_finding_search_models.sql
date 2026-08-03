-- ---------------------------------------------------------------------------
-- 6. Search/read models: due evidence and finding coverage are explicit.
-- ---------------------------------------------------------------------------

create or replace view public.vw_current_account_period
with (security_invoker = true)
as
with period_amounts as (
  select
    e.municipality_id,
    e.taxpayer_id,
    e.competence_month,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit' and e.status = 'valid'
    ), 0)::numeric(18,2) as valor_emitido,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and e.due_on is not null
        and e.due_on <= current_date
    ), 0)::numeric(18,2) as valor_vencido,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and e.due_on is null
    ), 0)::numeric(18,2) as valor_sem_vencimento,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and e.due_on > current_date
    ), 0)::numeric(18,2) as valor_a_vencer,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind = 'payment'
        and e.status = 'valid'
        and e.occurred_on <= current_date
    ), 0)::numeric(18,2) as valor_pago,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind <> 'payment'
        and e.status = 'valid'
        and e.occurred_on <= current_date
    ), 0)::numeric(18,2) as outros_creditos,
    min(e.due_on) filter (where e.direction = 'debit') as primeiro_vencimento,
    max(e.due_on) filter (where e.direction = 'debit') as ultimo_vencimento,
    max(e.imported_at) as data_base,
    count(distinct e.source_system_id) as qtd_fontes
  from public.current_account_entries e
  group by e.municipality_id, e.taxpayer_id, e.competence_month
)
select
  p.municipality_id as municipio_id,
  p.taxpayer_id as contribuinte_id,
  t.tax_id,
  t.legal_name as razao_social,
  p.competence_month as competencia,
  p.valor_emitido,
  p.valor_pago,
  greatest(
    p.valor_vencido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as saldo_em_aberto,
  greatest(
    p.valor_vencido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as divergencia_conta_corrente,
  case
    when p.valor_sem_vencimento > 0 then 'dados_incompletos'
    when greatest(
      p.valor_vencido - p.valor_pago - p.outros_creditos, 0
    ) > 0 then 'em_aberto'
    when p.valor_a_vencer > 0 then 'a_vencer'
    else 'pago'
  end as status,
  (
    p.valor_sem_vencimento = 0
    and greatest(
      p.valor_vencido - p.valor_pago - p.outros_creditos, 0
    ) > 0
  ) as elegivel,
  'current-account-maturity-v2'::text as regra_versao,
  p.data_base,
  p.qtd_fontes,
  p.valor_vencido,
  p.valor_sem_vencimento,
  p.valor_a_vencer,
  greatest(
    p.valor_emitido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as saldo_reportado,
  p.primeiro_vencimento,
  p.ultimo_vencimento
from period_amounts p
join public.taxpayers t
  on t.municipality_id = p.municipality_id
 and t.id = p.taxpayer_id;

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
    select count(*)
    from public.case_findings cf
    where cf.municipality_id = d.municipality_id
      and cf.divergence_id = d.id
  )::integer as case_finding_count
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

revoke all on public.vw_current_account_period from anon, authenticated;
revoke all on public.vw_fiscal_divergence_search from anon, authenticated;
grant select on public.vw_current_account_period to authenticated, service_role;
grant select on public.vw_fiscal_divergence_search to authenticated, service_role;

comment on view public.vw_current_account_period is
  'Conta corrente com vencimento comprovado. Linhas sem due_on permanecem visíveis, mas inelegíveis.';
comment on view public.vw_fiscal_divergence_search is
  'Busca fiscal tenant-safe com cobertura explícita de achado imutável por processo.';

