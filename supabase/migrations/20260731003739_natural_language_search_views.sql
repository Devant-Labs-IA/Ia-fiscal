create or replace view public.vw_current_account_period
with (security_invoker = true)
as
with period_amounts as (
  select
    e.municipality_id,
    e.taxpayer_id,
    e.competence_month,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
    ), 0)::numeric(18,2) as valor_emitido,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind = 'payment'
        and e.status = 'valid'
    ), 0)::numeric(18,2) as valor_pago,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind <> 'payment'
        and e.status = 'valid'
    ), 0)::numeric(18,2) as outros_creditos,
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
    p.valor_emitido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as saldo_em_aberto,
  greatest(
    p.valor_emitido - p.valor_pago - p.outros_creditos,
    0
  )::numeric(18,2) as divergencia_conta_corrente,
  case
    when p.valor_emitido - p.valor_pago - p.outros_creditos > 0
      then 'em_aberto'
    else 'pago'
  end as status,
  true as elegivel,
  'current-account-ledger-v1'::text as regra_versao,
  p.data_base,
  p.qtd_fontes
from period_amounts p
join public.taxpayers t
  on t.municipality_id = p.municipality_id
 and t.id = p.taxpayer_id;

create or replace view public.vw_responsaveis_ativos
with (security_invoker = true)
as
select
  l.municipality_id as municipio_id,
  l.taxpayer_id as contribuinte_id,
  f.id as responsavel_id,
  f.legal_name as nome,
  'accounting_firm'::text as tipo,
  case
    when f.tax_id is null then null
    else left(f.tax_id, 2)
         || repeat('*', greatest(length(f.tax_id) - 4, 0))
         || right(f.tax_id, 2)
  end as documento_mascarado,
  (
    select
      left(split_part(pc.normalized_value::text, '@', 1), 1)
      || '***@'
      || split_part(pc.normalized_value::text, '@', 2)
    from public.party_contacts pc
    where pc.municipality_id = l.municipality_id
      and pc.accounting_firm_id = l.accounting_firm_id
      and pc.contact_type = 'email'
      and pc.status = 'verified'
    order by pc.is_primary desc, pc.created_at
    limit 1
  ) as email_mascarado,
  'ativo'::text as vinculo_status,
  l.valid_from::date as vigencia_inicio,
  l.valid_until::date as vigencia_fim,
  coalesce(l.evidence_reference, 'cadastro_verificado') as fonte_vinculo
from public.taxpayer_accountant_links l
join public.accounting_firms f
  on f.municipality_id = l.municipality_id
 and f.id = l.accounting_firm_id
where l.status = 'active';

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
  r.code as rule_code
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

revoke all on table public.vw_current_account_period from anon;
revoke all on table public.vw_responsaveis_ativos from anon;
revoke all on table public.vw_fiscal_divergence_search from anon;

grant select on table public.vw_current_account_period to authenticated, service_role;
grant select on table public.vw_responsaveis_ativos to authenticated, service_role;
grant select on table public.vw_fiscal_divergence_search to authenticated, service_role;

comment on view public.vw_current_account_period is
  'One current-account row per municipality, taxpayer and competence for parameterized natural-language search.';
comment on view public.vw_responsaveis_ativos is
  'Verified active accountant relationships only; quarantined links remain visible through dedicated quarantine views.';
comment on view public.vw_fiscal_divergence_search is
  'Search projection for detected divergences with rule identity and execution mode.';

