-- IA Fiscal
-- Deterministic and versioned RBT12/RBT12p, Factor R and effective-rate
-- engine for the 2018-2026 Simples Nacional annex tables.

-- ---------------------------------------------------------------------------
-- 1. Federal legal sources.
-- ---------------------------------------------------------------------------

with municipality as (
  select id
  from public.municipalities
  where ibge_code = '3512407'
),
source_rows (
  source_type,
  issuing_authority,
  title,
  official_identifier,
  official_url,
  divergence_scope
) as (
  values
    (
      'law',
      'Congresso Nacional',
      'Estatuto Nacional da Microempresa e da Empresa de Pequeno Porte',
      'Lei Complementar nº 123/2006 (texto atualizado)',
      'https://www2.camara.leg.br/legin/fed/leicom/2006/leicomplementar-123-14-dezembro-2006-548099-normaatualizada-pl.html',
      'simple_national_effective_rate'
    ),
    (
      'official_guidance',
      'Receita Federal do Brasil',
      'Manual do PGDAS-D e DEFIS — versão 4 atualizada',
      'Manual PGDAS-D 2018 v4',
      'https://www8.receita.fazenda.gov.br/simplesnacional/arquivos/manual/manual_pgdas-d_2018_v4.pdf',
      'simple_national_rbt12_factor_r'
    )
)
insert into public.legal_sources (
  municipality_id,
  source_type,
  jurisdiction,
  issuing_authority,
  title,
  official_identifier,
  official_url,
  tax_scope,
  divergence_scope,
  status
)
select
  m.id,
  sr.source_type,
  'federal',
  sr.issuing_authority,
  sr.title,
  sr.official_identifier,
  sr.official_url,
  'Simples Nacional / ISSQN',
  sr.divergence_scope,
  'active'
from municipality m
cross join source_rows sr
where not exists (
  select 1
  from public.legal_sources s
  where s.municipality_id = m.id
    and s.official_identifier = sr.official_identifier
);

with source_content (
  official_identifier,
  content_text,
  valid_from,
  publication_date
) as (
  values
    (
      'Lei Complementar nº 123/2006 (texto atualizado)',
      'Art. 18: a alíquota efetiva resulta de '
      || '((RBT12 x alíquota nominal) - parcela a deduzir) / RBT12. '
      || 'O enquadramento usa a receita dos 12 meses anteriores; no início '
      || 'da atividade os valores são proporcionalizados. Os Anexos I a V '
      || 'definem faixas, alíquotas nominais, parcelas a deduzir e partilha. '
      || 'Para atividades sujeitas ao Fator R, razão igual ou superior a '
      || '0,28 usa o Anexo III; inferior a 0,28 usa o Anexo V.',
      date '2018-01-01',
      date '2006-12-14'
    ),
    (
      'Manual PGDAS-D 2018 v4',
      'RBT12p: no primeiro mês, receita do próprio período multiplicada por '
      || '12; nos 11 meses seguintes, média dos meses anteriores multiplicada '
      || 'por 12; a partir do 13º mês, 12 competências anteriores. '
      || 'Fator R no mês de abertura usa FSPA/RPA; nos meses 2 a 12 usa as '
      || 'somas desde a abertura até o mês anterior; depois usa FS12/RBT12. '
      || 'Em janeiro a março de 2018 o Fator R foi arredondado para duas '
      || 'casas; desde abril de 2018 são usadas duas casas sem arredondamento. '
      || 'Declaração e recolhimento vencem no dia 20 do mês subsequente.',
      date '2018-01-01',
      date '2025-06-17'
    )
),
resolved as (
  select
    s.municipality_id,
    s.id as source_id,
    c.content_text,
    c.valid_from,
    c.publication_date
  from public.legal_sources s
  join source_content c
    on c.official_identifier = s.official_identifier
  join public.municipalities m
    on m.id = s.municipality_id
   and m.ibge_code = '3512407'
)
insert into public.legal_source_versions (
  municipality_id,
  source_id,
  version,
  status,
  content_text,
  content_sha256,
  valid_from,
  publication_date
)
select
  r.municipality_id,
  r.source_id,
  1,
  'under_review',
  r.content_text,
  encode(extensions.digest(r.content_text, 'sha256'), 'hex'),
  r.valid_from,
  r.publication_date
from resolved r
where not exists (
  select 1
  from public.legal_source_versions v
  where v.municipality_id = r.municipality_id
    and v.source_id = r.source_id
    and v.version = 1
);

-- ---------------------------------------------------------------------------
-- 2. Versioned annex tables and calculated snapshots.
-- ---------------------------------------------------------------------------

create table if not exists public.simple_national_rate_rule_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  code text not null,
  version integer not null check (version > 0),
  valid_from date not null,
  valid_until date,
  status text not null default 'draft'
    check (status in (
      'draft',
      'active_homologation',
      'active',
      'retired',
      'revoked'
    )),
  legal_source_version_id uuid not null,
  formula_code text not null,
  rule_payload jsonb not null
    check (jsonb_typeof(rule_payload) = 'object'),
  rule_sha256 text not null
    check (rule_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (municipality_id, code, version),
  unique (municipality_id, id),
  check (valid_until is null or valid_until >= valid_from),
  foreign key (municipality_id)
    references public.municipalities(id) on delete cascade,
  foreign key (municipality_id, legal_source_version_id)
    references public.legal_source_versions(municipality_id, id)
);

create table if not exists public.simple_national_rate_bands (
  id bigint generated by default as identity primary key,
  municipality_id uuid not null,
  rule_version_id uuid not null,
  annex_code text not null
    check (annex_code in ('I', 'II', 'III', 'IV', 'V')),
  band_number smallint not null check (band_number between 1 and 6),
  rbt12_lower numeric(18,2) not null check (rbt12_lower >= 0),
  rbt12_upper numeric(18,2) not null check (rbt12_upper > 0),
  nominal_rate numeric(12,8) not null
    check (nominal_rate > 0 and nominal_rate <= 1),
  deduction_amount numeric(18,2) not null default 0
    check (deduction_amount >= 0),
  iss_distribution_rate numeric(12,8)
    check (
      iss_distribution_rate is null
      or (
        iss_distribution_rate >= 0
        and iss_distribution_rate <= 1
      )
    ),
  iss_effective_cap numeric(12,8)
    check (
      iss_effective_cap is null
      or (
        iss_effective_cap >= 0
        and iss_effective_cap <= 1
      )
    ),
  iss_fixed_effective_rate numeric(12,8)
    check (
      iss_fixed_effective_rate is null
      or (
        iss_fixed_effective_rate >= 0
        and iss_fixed_effective_rate <= 0.05
      )
    ),
  source_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  unique (municipality_id, rule_version_id, annex_code, band_number),
  unique (municipality_id, id),
  check (rbt12_upper >= rbt12_lower),
  foreign key (municipality_id, rule_version_id)
    references public.simple_national_rate_rule_versions(municipality_id, id)
    on delete cascade
);

create table if not exists public.simple_national_effective_rate_calculations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  calculation_snapshot_id uuid not null,
  declaration_id uuid,
  annex_item_id uuid,
  source_line_key text not null,
  taxpayer_id uuid not null,
  competence_month date not null,
  rule_version_id uuid not null,
  rate_band_id bigint,
  declared_annex_code text
    check (
      declared_annex_code is null
      or declared_annex_code in ('I', 'II', 'III', 'IV', 'V')
    ),
  expected_annex_code text
    check (
      expected_annex_code is null
      or expected_annex_code in ('I', 'II', 'III', 'IV', 'V')
    ),
  activity_code text,
  revenue_type text,
  line_tax_base numeric(18,2),
  factor_r_applicable boolean,
  factor_r numeric(20,12),
  rbt12_basis numeric(18,2) check (rbt12_basis is null or rbt12_basis > 0),
  rbt12_mode text
    check (rbt12_mode in (
      'rolling_12_months',
      'startup_first_month',
      'startup_average_prior_months'
    ) or rbt12_mode is null),
  nominal_rate numeric(20,12),
  deduction_amount numeric(18,2),
  effective_rate numeric(30,20)
    check (
      effective_rate is null
      or (effective_rate >= 0 and effective_rate <= 1)
    ),
  iss_effective_rate numeric(30,20)
    check (
      iss_effective_rate is null
      or (
        iss_effective_rate >= 0
        and iss_effective_rate <= 0.05
      )
    ),
  status text not null
    check (status in ('calculated', 'blocked', 'superseded')),
  block_reasons jsonb not null default '[]'::jsonb
    check (jsonb_typeof(block_reasons) = 'array'),
  evidence_snapshot jsonb not null
    check (jsonb_typeof(evidence_snapshot) = 'object'),
  snapshot_sha256 text not null
    check (snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  result_key text not null,
  is_test boolean not null default false,
  calculated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (
    municipality_id,
    result_key
  ),
  unique (municipality_id, id),
  check (
    status <> 'calculated'
    or (
      declaration_id is not null
      and annex_item_id is not null
      and rate_band_id is not null
      and expected_annex_code is not null
      and rbt12_basis is not null
      and nominal_rate is not null
      and deduction_amount is not null
      and effective_rate is not null
      and jsonb_array_length(block_reasons) = 0
    )
  ),
  check (
    status <> 'blocked'
    or jsonb_array_length(block_reasons) > 0
  ),
  foreign key (municipality_id, calculation_snapshot_id)
    references public.simple_national_calculation_snapshots(municipality_id, id)
    on delete cascade,
  foreign key (municipality_id, declaration_id)
    references public.pgdasd_declarations(municipality_id, id),
  foreign key (municipality_id, annex_item_id)
    references public.pgdasd_annex_items(municipality_id, id),
  foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id)
    on delete cascade,
  foreign key (municipality_id, rule_version_id)
    references public.simple_national_rate_rule_versions(municipality_id, id),
  foreign key (municipality_id, rate_band_id)
    references public.simple_national_rate_bands(municipality_id, id)
);

create index if not exists simple_national_rate_rules_lookup_idx
  on public.simple_national_rate_rule_versions (
    municipality_id, valid_from, valid_until, status
  );

create index if not exists simple_national_rate_bands_lookup_idx
  on public.simple_national_rate_bands (
    municipality_id, rule_version_id, annex_code, rbt12_lower, rbt12_upper
  );

create index if not exists simple_national_effective_rates_search_idx
  on public.simple_national_effective_rate_calculations (
    municipality_id, competence_month, status, expected_annex_code, taxpayer_id
  );

alter table public.simple_national_rate_rule_versions enable row level security;
alter table public.simple_national_rate_bands enable row level security;
alter table public.simple_national_effective_rate_calculations
  enable row level security;

drop policy if exists simple_national_rate_rule_versions_select
  on public.simple_national_rate_rule_versions;
create policy simple_national_rate_rule_versions_select
on public.simple_national_rate_rule_versions
for select
to authenticated
using (
  (select private.can_manage_municipality(municipality_id))
  or (select private.has_municipality_role(
    municipality_id,
    array[
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer',
      'operations_analyst'
    ]::text[]
  ))
);

drop policy if exists simple_national_rate_bands_select
  on public.simple_national_rate_bands;
create policy simple_national_rate_bands_select
on public.simple_national_rate_bands
for select
to authenticated
using (
  (select private.can_manage_municipality(municipality_id))
  or (select private.has_municipality_role(
    municipality_id,
    array[
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer',
      'operations_analyst'
    ]::text[]
  ))
);

drop policy if exists simple_national_effective_rate_calculations_select
  on public.simple_national_effective_rate_calculations;
create policy simple_national_effective_rate_calculations_select
on public.simple_national_effective_rate_calculations
for select
to authenticated
using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));
drop policy if exists simple_national_effective_rate_calculations_select
  on public.simple_national_effective_rate_calculations;
create policy simple_national_effective_rate_calculations_select
on public.simple_national_effective_rate_calculations
for select
to authenticated
using (
  (select private.can_manage_municipality(municipality_id))
  or (select private.can_access_taxpayer(municipality_id, taxpayer_id))
);

revoke all on public.simple_national_rate_rule_versions
  from public, anon, authenticated;
revoke all on public.simple_national_rate_bands
  from public, anon, authenticated;
revoke all on public.simple_national_effective_rate_calculations
  from public, anon, authenticated;
grant select on public.simple_national_rate_rule_versions to authenticated;
grant select on public.simple_national_rate_bands to authenticated;
grant select on public.simple_national_effective_rate_calculations
  to authenticated;
grant all on public.simple_national_rate_rule_versions to service_role;
grant all on public.simple_national_rate_bands to service_role;
grant all on public.simple_national_effective_rate_calculations
  to service_role;
grant usage, select on sequence
  public.simple_national_rate_bands_id_seq to service_role;

drop trigger if exists simple_national_rate_rules_set_updated_at
  on public.simple_national_rate_rule_versions;
create trigger simple_national_rate_rules_set_updated_at
before update on public.simple_national_rate_rule_versions
for each row execute function private.set_updated_at();

drop trigger if exists simple_national_rate_rules_immutable_identity
  on public.simple_national_rate_rule_versions;
create trigger simple_national_rate_rules_immutable_identity
before update on public.simple_national_rate_rule_versions
for each row execute function private.prevent_tenant_or_id_change();

drop trigger if exists simple_national_rate_rules_audit
  on public.simple_national_rate_rule_versions;
create trigger simple_national_rate_rules_audit
after insert or update or delete on public.simple_national_rate_rule_versions
for each row execute function private.audit_row_change();

drop trigger if exists simple_national_rate_bands_audit
  on public.simple_national_rate_bands;
create trigger simple_national_rate_bands_audit
after insert or update or delete on public.simple_national_rate_bands
for each row execute function private.audit_row_change();

drop trigger if exists simple_national_effective_rates_immutable
  on public.simple_national_effective_rate_calculations;
create trigger simple_national_effective_rates_immutable
before update or delete on public.simple_national_effective_rate_calculations
for each row execute function private.prevent_any_mutation();

drop trigger if exists simple_national_effective_rates_audit
  on public.simple_national_effective_rate_calculations;
create trigger simple_national_effective_rates_audit
after insert or update or delete
on public.simple_national_effective_rate_calculations
for each row execute function private.audit_row_change();

with federal_version as (
  select
    v.municipality_id,
    v.id as legal_source_version_id
  from public.legal_source_versions v
  join public.legal_sources s
    on s.municipality_id = v.municipality_id
   and s.id = v.source_id
  join public.municipalities m
    on m.id = v.municipality_id
   and m.ibge_code = '3512407'
  where s.official_identifier =
    'Lei Complementar nº 123/2006 (texto atualizado)'
    and v.version = 1
  order by v.created_at
  limit 1
),
payload as (
  select
    fv.*,
    jsonb_build_object(
      'formula',
        '((rbt12 * nominal_rate) - deduction_amount) / rbt12',
      'rate_unit', 'fraction',
      'rbt12_general', '12_months_before_competence',
      'rbt12_startup_first_month', 'current_revenue_times_12',
      'rbt12_startup_months_2_to_12',
        'average_prior_calendar_months_times_12',
      'factor_r_startup_first_month', 'current_payroll/current_revenue',
      'factor_r_startup_months_2_to_12',
        'payroll_since_start/revenue_since_start_before_competence',
      'factor_r_precision_2018_q1', 'round_2_decimals',
      'factor_r_precision_from_2018_04',
        'truncate_2_decimals_without_rounding',
      'factor_r_threshold', 0.28,
      'factor_r_annex_ge_threshold', 'III',
      'factor_r_annex_lt_threshold', 'V',
      'iss_effective_cap', 0.05,
      'maximum_rbt12', 4800000,
      'iss_sublimit_reference', 3600000,
      'valid_through', '2026-12-31',
      'state_specific_rule_required_for_current_cases', false,
      'execution_scope', 'homologation'
    ) as body
  from federal_version fv
)
insert into public.simple_national_rate_rule_versions (
  municipality_id,
  code,
  version,
  valid_from,
  valid_until,
  status,
  legal_source_version_id,
  formula_code,
  rule_payload,
  rule_sha256
)
select
  p.municipality_id,
  'lc123_annex_effective_rates',
  1,
  date '2018-01-01',
  date '2026-12-31',
  'active_homologation',
  p.legal_source_version_id,
  'effective-rate-v2-line-level',
  p.body,
  encode(
    extensions.digest(
      jsonb_build_object(
        'code', 'lc123_annex_effective_rates',
        'version', 1,
        'valid_from', date '2018-01-01',
        'valid_until', date '2026-12-31',
        'legal_source_version_id', p.legal_source_version_id,
        'formula_code', 'effective-rate-v2-line-level',
        'payload', p.body
      )::text,
      'sha256'
    ),
    'hex'
  )
from payload p
where not exists (
  select 1
  from public.simple_national_rate_rule_versions r
  where r.municipality_id = p.municipality_id
    and r.code = 'lc123_annex_effective_rates'
    and r.version = 1
);

with rule as (
  select r.municipality_id, r.id
  from public.simple_national_rate_rule_versions r
  join public.municipalities m on m.id = r.municipality_id
  where m.ibge_code = '3512407'
    and r.code = 'lc123_annex_effective_rates'
    and r.version = 1
),
bands (
  annex_code,
  band_number,
  rbt12_lower,
  rbt12_upper,
  nominal_rate,
  deduction_amount,
  iss_distribution_rate
) as (
  values
    ('I',   1,       0.00,  180000.00, 0.0400,      0.00, null),
    ('I',   2,  180000.01,  360000.00, 0.0730,   5940.00, null),
    ('I',   3,  360000.01,  720000.00, 0.0950,  13860.00, null),
    ('I',   4,  720000.01, 1800000.00, 0.1070,  22500.00, null),
    ('I',   5, 1800000.01, 3600000.00, 0.1430,  87300.00, null),
    ('I',   6, 3600000.01, 4800000.00, 0.1900, 378000.00, null),
    ('II',  1,       0.00,  180000.00, 0.0450,      0.00, null),
    ('II',  2,  180000.01,  360000.00, 0.0780,   5940.00, null),
    ('II',  3,  360000.01,  720000.00, 0.1000,  13860.00, null),
    ('II',  4,  720000.01, 1800000.00, 0.1120,  22500.00, null),
    ('II',  5, 1800000.01, 3600000.00, 0.1470,  85500.00, null),
    ('II',  6, 3600000.01, 4800000.00, 0.3000, 720000.00, null),
    ('III', 1,       0.00,  180000.00, 0.0600,      0.00, 0.3350),
    ('III', 2,  180000.01,  360000.00, 0.1120,   9360.00, 0.3200),
    ('III', 3,  360000.01,  720000.00, 0.1350,  17640.00, 0.3250),
    ('III', 4,  720000.01, 1800000.00, 0.1600,  35640.00, 0.3250),
    ('III', 5, 1800000.01, 3600000.00, 0.2100, 125640.00, 0.3350),
    ('III', 6, 3600000.01, 4800000.00, 0.3300, 648000.00, null),
    ('IV',  1,       0.00,  180000.00, 0.0450,      0.00, 0.4450),
    ('IV',  2,  180000.01,  360000.00, 0.0900,   8100.00, 0.4000),
    ('IV',  3,  360000.01,  720000.00, 0.1020,  12420.00, 0.4000),
    ('IV',  4,  720000.01, 1800000.00, 0.1400,  39780.00, 0.4000),
    ('IV',  5, 1800000.01, 3600000.00, 0.2200, 183780.00, 0.4000),
    ('IV',  6, 3600000.01, 4800000.00, 0.3300, 828000.00, null),
    ('V',   1,       0.00,  180000.00, 0.1550,      0.00, 0.1400),
    ('V',   2,  180000.01,  360000.00, 0.1800,   4500.00, 0.1700),
    ('V',   3,  360000.01,  720000.00, 0.1950,   9900.00, 0.1900),
    ('V',   4,  720000.01, 1800000.00, 0.2050,  17100.00, 0.2100),
    ('V',   5, 1800000.01, 3600000.00, 0.2300,  62100.00, 0.2350),
    ('V',   6, 3600000.01, 4800000.00, 0.3050, 540000.00, null)
)
insert into public.simple_national_rate_bands (
  municipality_id,
  rule_version_id,
  annex_code,
  band_number,
  rbt12_lower,
  rbt12_upper,
  nominal_rate,
  deduction_amount,
  iss_distribution_rate,
  iss_effective_cap,
  iss_fixed_effective_rate,
  source_snapshot
)
select
  r.municipality_id,
  r.id,
  b.annex_code,
  b.band_number,
  b.rbt12_lower,
  b.rbt12_upper,
  b.nominal_rate,
  b.deduction_amount,
  b.iss_distribution_rate,
  case
    when b.iss_distribution_rate is not null then 0.05
    else null
  end,
  case
    when b.annex_code in ('III', 'IV', 'V')
      and b.band_number = 6 then 0.05
    else null
  end,
  jsonb_build_object(
    'legal_table', 'LC 123/2006 annex ' || b.annex_code,
    'band', b.band_number,
    'rate_unit', 'fraction',
    'valid_from', '2018-01-01',
    'valid_until', '2026-12-31'
  )
from rule r
cross join bands b
on conflict (
  municipality_id,
  rule_version_id,
  annex_code,
  band_number
) do nothing;

do $band_validation$
declare
  v_count integer;
begin
  select count(*)::integer
    into v_count
  from public.simple_national_rate_bands b
  join public.simple_national_rate_rule_versions r
    on r.municipality_id = b.municipality_id
   and r.id = b.rule_version_id
  join public.municipalities m on m.id = b.municipality_id
  where m.ibge_code = '3512407'
    and r.code = 'lc123_annex_effective_rates'
    and r.version = 1;

  if v_count <> 30 then
    raise exception 'expected 30 Simples Nacional rate bands, found %', v_count;
  end if;
end
$band_validation$;

create or replace function private.prevent_active_simple_rate_rule_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.status in ('active_homologation', 'active')
     and new is distinct from old then
    raise exception 'active Simples rate rule is immutable; create a new version';
  end if;
  return new;
end;
$function$;

drop trigger if exists simple_national_rate_rules_active_immutable
  on public.simple_national_rate_rule_versions;
create trigger simple_national_rate_rules_active_immutable
before update on public.simple_national_rate_rule_versions
for each row execute function private.prevent_active_simple_rate_rule_mutation();

drop trigger if exists simple_national_rate_bands_immutable
  on public.simple_national_rate_bands;
create trigger simple_national_rate_bands_immutable
before update or delete on public.simple_national_rate_bands
for each row execute function private.prevent_any_mutation();

-- ---------------------------------------------------------------------------
-- 3. Pure calculation functions.
-- ---------------------------------------------------------------------------

create or replace function private.calculate_rbt12_basis(
  p_activity_started_on date,
  p_competence_month date,
  p_current_revenue numeric,
  p_prior_revenue_sum numeric,
  p_prior_months_with_data integer
) returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_competence date := date_trunc('month', p_competence_month)::date;
  v_start date := date_trunc('month', p_activity_started_on)::date;
  v_months_active integer;
  v_expected_prior integer;
  v_value numeric(18,2);
  v_mode text;
begin
  if p_activity_started_on is null then
    if coalesce(p_prior_months_with_data, 0) = 12 then
      return jsonb_build_object(
        'status', 'calculated',
        'mode', 'rolling_12_months',
        'months_active', null,
        'expected_prior_months', 12,
        'covered_prior_months', 12,
        'rbt12_basis', round(coalesce(p_prior_revenue_sum, 0), 2)
      );
    end if;
    return jsonb_build_object(
      'status', 'blocked',
      'reason', 'missing_verified_activity_start'
    );
  end if;

  if v_start > v_competence then
    return jsonb_build_object(
      'status', 'blocked',
      'reason', 'activity_start_after_competence'
    );
  end if;

  v_months_active :=
    (
      extract(year from age(v_competence, v_start))::integer * 12
      + extract(month from age(v_competence, v_start))::integer
      + 1
    );

  if v_months_active = 1 then
    if p_current_revenue is null then
      return jsonb_build_object(
        'status', 'blocked',
        'reason', 'missing_current_revenue_for_first_month',
        'months_active', v_months_active
      );
    end if;
    v_value := round(greatest(p_current_revenue, 0) * 12, 2);
    v_mode := 'startup_first_month';
    v_expected_prior := 0;
  elsif v_months_active between 2 and 12 then
    v_expected_prior := v_months_active - 1;
    if coalesce(p_prior_months_with_data, 0) <> v_expected_prior then
      return jsonb_build_object(
        'status', 'blocked',
        'reason', 'incomplete_startup_revenue_history',
        'months_active', v_months_active,
        'expected_prior_months', v_expected_prior,
        'covered_prior_months', coalesce(p_prior_months_with_data, 0)
      );
    end if;
    v_value := round(
      (
        coalesce(p_prior_revenue_sum, 0)
        / v_expected_prior::numeric
      ) * 12,
      2
    );
    v_mode := 'startup_average_prior_months';
  else
    v_expected_prior := 12;
    if coalesce(p_prior_months_with_data, 0) <> 12 then
      return jsonb_build_object(
        'status', 'blocked',
        'reason', 'incomplete_rolling_12_month_history',
        'months_active', v_months_active,
        'expected_prior_months', 12,
        'covered_prior_months', coalesce(p_prior_months_with_data, 0)
      );
    end if;
    v_value := round(coalesce(p_prior_revenue_sum, 0), 2);
    v_mode := 'rolling_12_months';
  end if;

  return jsonb_build_object(
    'status', 'calculated',
    'mode', v_mode,
    'months_active', v_months_active,
    'expected_prior_months', v_expected_prior,
    'covered_prior_months', coalesce(p_prior_months_with_data, 0),
    'rbt12_basis', v_value
  );
end;
$function$;

create or replace function private.calculate_factor_r_pgdas(
  p_competence_month date,
  p_fs_basis numeric,
  p_revenue_basis numeric
) returns numeric
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_raw numeric;
begin
  v_raw := case
    when coalesce(p_fs_basis, 0) = 0
     and coalesce(p_revenue_basis, 0) = 0
      then 0.01::numeric
    when coalesce(p_fs_basis, 0) > 0
     and coalesce(p_revenue_basis, 0) = 0
      then 0.28::numeric
    when coalesce(p_fs_basis, 0) = 0
     and coalesce(p_revenue_basis, 0) > 0
      then 0.01::numeric
    else p_fs_basis / p_revenue_basis
  end;

  if date_trunc('month', p_competence_month)::date
       between date '2018-01-01' and date '2018-03-01' then
    return round(v_raw, 2);
  end if;

  return trunc(v_raw, 2);
end;
$function$;

create or replace function private.calculate_startup_factor_r(
  p_activity_started_on date,
  p_competence_month date,
  p_current_fs numeric,
  p_current_revenue numeric,
  p_prior_fs_sum numeric,
  p_prior_revenue_sum numeric,
  p_prior_revenue_months integer,
  p_prior_payroll_months integer
) returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_competence date := date_trunc('month', p_competence_month)::date;
  v_start date := date_trunc('month', p_activity_started_on)::date;
  v_months_active integer;
  v_expected_prior integer;
  v_factor numeric;
  v_mode text;
begin
  if p_activity_started_on is null then
    if coalesce(p_prior_revenue_months, 0) = 12
       and coalesce(p_prior_payroll_months, 0) = 12 then
      v_factor := private.calculate_factor_r_pgdas(
        v_competence,
        coalesce(p_prior_fs_sum, 0),
        coalesce(p_prior_revenue_sum, 0)
      );
      return jsonb_build_object(
        'status', 'calculated',
        'mode', 'rolling_12_months',
        'months_active', null,
        'factor_r', v_factor,
        'expected_annex_code', case
          when v_factor >= 0.28 then 'III'
          else 'V'
        end,
        'precision', case
          when v_competence between date '2018-01-01' and date '2018-03-01'
            then 'round_2_decimals'
          else 'truncate_2_decimals_without_rounding'
        end
      );
    end if;
    return jsonb_build_object(
      'status', 'blocked',
      'reason', 'missing_verified_activity_start'
    );
  end if;

  if v_start > v_competence then
    return jsonb_build_object(
      'status', 'blocked',
      'reason', 'activity_start_after_competence'
    );
  end if;

  v_months_active :=
    (
      extract(year from age(v_competence, v_start))::integer * 12
      + extract(month from age(v_competence, v_start))::integer
      + 1
    );

  if v_months_active = 1 then
    if p_current_fs is null or p_current_revenue is null then
      return jsonb_build_object(
        'status', 'blocked',
        'reason', 'missing_current_period_inputs_for_first_month'
      );
    end if;
    v_factor := private.calculate_factor_r_pgdas(
      v_competence,
      p_current_fs,
      p_current_revenue
    );
    v_mode := 'startup_first_month';
    v_expected_prior := 0;
  else
    v_expected_prior := least(v_months_active - 1, 12);
    if coalesce(p_prior_revenue_months, 0) <> v_expected_prior
       or coalesce(p_prior_payroll_months, 0) <> v_expected_prior then
      return jsonb_build_object(
        'status', 'blocked',
        'reason', 'incomplete_factor_r_history',
        'months_active', v_months_active,
        'expected_prior_months', v_expected_prior,
        'covered_revenue_months', coalesce(p_prior_revenue_months, 0),
        'covered_payroll_months', coalesce(p_prior_payroll_months, 0)
      );
    end if;
    v_factor := private.calculate_factor_r_pgdas(
      v_competence,
      coalesce(p_prior_fs_sum, 0),
      coalesce(p_prior_revenue_sum, 0)
    );
    v_mode := case
      when v_months_active <= 12 then 'startup_since_opening'
      else 'rolling_12_months'
    end;
  end if;

  return jsonb_build_object(
    'status', 'calculated',
    'mode', v_mode,
    'months_active', v_months_active,
    'factor_r', v_factor,
    'expected_annex_code', case
      when v_factor >= 0.28 then 'III'
      else 'V'
    end,
    'precision', case
      when v_competence between date '2018-01-01' and date '2018-03-01'
        then 'round_2_decimals'
      else 'truncate_2_decimals_without_rounding'
    end
  );
end;
$function$;

create or replace function private.calculate_simple_effective_rate(
  p_rbt12 numeric,
  p_nominal_rate numeric,
  p_deduction_amount numeric
) returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when p_rbt12 is null or p_rbt12 <= 0 then null
    when p_nominal_rate is null or p_deduction_amount is null then null
    else (
      (p_rbt12 * p_nominal_rate) - p_deduction_amount
    ) / p_rbt12
  end;
$$;

revoke all on function private.calculate_rbt12_basis(
  date, date, numeric, numeric, integer
) from public, anon, authenticated;
revoke all on function private.calculate_factor_r_pgdas(date, numeric, numeric)
  from public, anon, authenticated;
revoke all on function private.calculate_startup_factor_r(
  date, date, numeric, numeric, numeric, numeric, integer, integer
) from public, anon, authenticated;
revoke all on function private.calculate_simple_effective_rate(
  numeric, numeric, numeric
) from public, anon, authenticated;
grant execute on function private.calculate_rbt12_basis(
  date, date, numeric, numeric, integer
) to service_role;
grant execute on function private.calculate_factor_r_pgdas(date, numeric, numeric)
  to service_role;
grant execute on function private.calculate_startup_factor_r(
  date, date, numeric, numeric, numeric, numeric, integer, integer
) to service_role;
grant execute on function private.calculate_simple_effective_rate(
  numeric, numeric, numeric
) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Rebuild and read contracts.
-- ---------------------------------------------------------------------------

create or replace function public.ia_rebuild_simple_national_effective_rates(
  p_municipality_id uuid,
  p_period_start date,
  p_period_end date,
  p_is_test boolean default true
) returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if not (
    private.is_service_role()
    or (
      private.is_aal2()
      and private.has_municipality_role(
        p_municipality_id,
        array['supervisor']::text[]
      )
    )
  ) then
    raise exception 'supervisor with aal2 required';
  end if;

  if p_period_end < p_period_start then
    raise exception 'invalid period';
  end if;

  if p_is_test and not exists (
    select 1
    from public.municipality_policy_versions pv
    where pv.municipality_id = p_municipality_id
      and coalesce(
        (pv.operational_config ->> 'test_mode')::boolean,
        false
      )
  ) then
    raise exception 'homologation test mode is not enabled';
  end if;

  -- Refresh the canonical v2 declaration snapshot first. That pipeline
  -- resolves the effective declaration, RBT12/RBT12p, FS12 and Factor R;
  -- this function then applies the annex band per declaration line.
  perform public.ia_rebuild_simple_national_snapshots(
    p_municipality_id,
    p_period_start,
    p_period_end,
    p_is_test
  );

  with declarations as (
    select distinct on (d.taxpayer_id, d.competence_month)
      d.id,
      d.municipality_id,
      d.taxpayer_id,
      d.competence_month,
      d.declaration_status,
      d.transmitted_at,
      d.payload_sha256,
      d.total_revenue_declared,
      d.is_test
    from public.pgdasd_declarations d
    where d.municipality_id = p_municipality_id
      and d.competence_month between
        date_trunc('month', p_period_start)::date
        and date_trunc('month', p_period_end)::date
      and d.is_test = p_is_test
      and d.declaration_status <> 'cancelled'
    order by
      d.taxpayer_id,
      d.competence_month,
      (d.declaration_status = 'rectified') desc,
      d.transmitted_at desc nulls last,
      d.created_at desc,
      d.id desc
  ),
  source_rows as (
    select
      s.municipality_id,
      s.id as calculation_snapshot_id,
      d.id as declaration_id,
      ai.id as annex_item_id,
      s.taxpayer_id,
      s.competence_month,
      r.id as rule_version_id,
      ai.annex_code as declared_annex_code,
      coalesce(ai.external_line_id, 'snapshot-block') as source_line_key,
      case
        when ai.id is null then null
        when ai.factor_r_applicable
          then factor_result.value->>'expected_annex_code'
        else ai.annex_code
      end as expected_annex_code,
      ai.activity_code,
      ai.revenue_type,
      ai.tax_base as line_tax_base,
      ai.factor_r_applicable,
      nullif(factor_result.value->>'factor_r', '')::numeric as factor_r,
      nullif(rbt12_result.value->>'rbt12_basis', '')::numeric
        as rbt12_basis,
      rbt12_result.value->>'mode' as rbt12_mode,
      s.snapshot_sha256 as calculation_snapshot_sha256,
      r.rule_sha256,
      (
        case
          when rbt12_result.value->>'status' = 'blocked'
            then jsonb_build_array(jsonb_build_object(
              'code', rbt12_result.value->>'reason',
              'stage', 'rbt12'
            ))
          else '[]'::jsonb
        end
        ||
        case
          when coalesce(ai.factor_r_applicable, false)
            and factor_result.value->>'status' = 'blocked'
            then jsonb_build_array(jsonb_build_object(
              'code', factor_result.value->>'reason',
              'stage', 'factor_r'
            ))
          else '[]'::jsonb
        end
      ) as snapshot_block_reasons,
      case
        when rbt12_result.value->>'status' <> 'calculated'
          then 'blocked'
        when coalesce(ai.factor_r_applicable, false)
          and factor_result.value->>'status' <> 'calculated'
          then 'blocked'
        else 'calculated'
      end as snapshot_status,
      jsonb_build_object(
        'upstream_snapshot', s.evidence_snapshot,
        'rbt12_result', rbt12_result.value,
        'factor_r_result', factor_result.value,
        'current_revenue', d.total_revenue_declared,
        'current_fs', current_payroll.current_fs,
        'history_revenue_months',
          coalesce(
            (s.evidence_snapshot->'quality'->>'history_month_count')::integer,
            0
          ),
        'history_payroll_months',
          coalesce(payroll_history.history_month_count, 0)
      ) as source_evidence,
      s.is_test,
      d.payload_sha256 as declaration_payload_sha256
    from declarations d
    join public.simple_national_calculation_snapshots s
      on s.municipality_id = d.municipality_id
     and s.taxpayer_id = d.taxpayer_id
     and s.competence_month = d.competence_month
     and s.is_test = d.is_test
     and s.calculation_version =
       'simple-national-v2-effective-declaration'
    join public.simple_national_rate_rule_versions r
      on r.municipality_id = s.municipality_id
     and r.code = 'lc123_annex_effective_rates'
     and r.status = case
       when p_is_test then 'active_homologation'
       else 'active'
     end
     and s.competence_month >= r.valid_from
     and (
       r.valid_until is null
       or s.competence_month <= r.valid_until
     )
    left join public.taxpayer_fiscal_profiles fp
      on fp.municipality_id = s.municipality_id
     and fp.taxpayer_id = s.taxpayer_id
    left join public.pgdasd_annex_items ai
      on ai.municipality_id = d.municipality_id
     and ai.declaration_id = d.id
     and ai.taxpayer_id = d.taxpayer_id
    left join lateral (
      select
        sum(p.fs_month)::numeric as current_fs
      from public.factor_r_payroll_periods p
      where p.municipality_id = d.municipality_id
        and p.taxpayer_id = d.taxpayer_id
        and p.competence_month = d.competence_month
        and p.is_test = d.is_test
    ) current_payroll on true
    left join lateral (
      select
        count(distinct p.competence_month)::integer
          as history_month_count
      from public.factor_r_payroll_periods p
      where p.municipality_id = d.municipality_id
        and p.taxpayer_id = d.taxpayer_id
        and p.is_test = d.is_test
        and p.competence_month
          >= (d.competence_month - interval '12 months')::date
        and p.competence_month < d.competence_month
    ) payroll_history on true
    cross join lateral (
      select private.calculate_rbt12_basis(
        case
          when fp.activity_date_verified then fp.activity_started_on
          else null
        end,
        d.competence_month,
        d.total_revenue_declared,
        s.calculated_rbt12,
        coalesce(
          (s.evidence_snapshot->'quality'->>'history_month_count')::integer,
          0
        )
      ) as value
    ) rbt12_result
    cross join lateral (
      select private.calculate_startup_factor_r(
        case
          when fp.activity_date_verified then fp.activity_started_on
          else null
        end,
        d.competence_month,
        current_payroll.current_fs,
        d.total_revenue_declared,
        s.calculated_fs12,
        s.calculated_rbt12,
        coalesce(
          (s.evidence_snapshot->'quality'->>'history_month_count')::integer,
          0
        ),
        coalesce(
          payroll_history.history_month_count,
          0
        )
      ) as value
    ) factor_result
  ),
  with_bands as (
    select
      p.*,
      b.id as rate_band_id,
      b.band_number,
      b.nominal_rate,
      b.deduction_amount,
      b.iss_distribution_rate,
      b.iss_effective_cap,
      b.iss_fixed_effective_rate,
      case
        when p.snapshot_status <> 'calculated'
          then p.snapshot_block_reasons
        else '[]'::jsonb
      end
      || case
        when p.annex_item_id is null
          then jsonb_build_array(jsonb_build_object(
            'code', 'missing_effective_declaration_annex_item'
          ))
        else '[]'::jsonb
      end
      || case
        when p.snapshot_status = 'calculated'
          and coalesce(p.rbt12_basis, 0) <= 0
          then jsonb_build_array(jsonb_build_object(
            'code', 'missing_or_zero_rbt12_basis'
          ))
        else '[]'::jsonb
      end
      || case
        when p.annex_item_id is not null
          and p.expected_annex_code is null
          then jsonb_build_array(jsonb_build_object(
            'code', 'missing_expected_annex'
          ))
        else '[]'::jsonb
      end
      || case
        when p.snapshot_status = 'calculated'
          and p.rbt12_basis > 4800000
          then jsonb_build_array(jsonb_build_object(
            'code', 'rbt12_above_simple_national_limit',
            'maximum', 4800000
          ))
        else '[]'::jsonb
      end
      || case
        when p.snapshot_status = 'calculated'
          and p.rbt12_basis > 0
          and p.rbt12_basis <= 4800000
          and p.expected_annex_code is not null
          and b.id is null
          then jsonb_build_array(jsonb_build_object(
            'code', 'rate_band_not_found'
          ))
        else '[]'::jsonb
      end as block_reasons
    from source_rows p
    left join public.simple_national_rate_bands b
      on b.municipality_id = p.municipality_id
     and b.rule_version_id = p.rule_version_id
     and b.annex_code = p.expected_annex_code
     and p.rbt12_basis between b.rbt12_lower and b.rbt12_upper
  ),
  calculated as (
    select
      p.*,
      private.calculate_simple_effective_rate(
        p.rbt12_basis,
        p.nominal_rate,
        p.deduction_amount
      ) as effective_rate
    from with_bands p
  ),
  payload as (
    select
      p.*,
      case
        when p.iss_fixed_effective_rate is not null
          then p.iss_fixed_effective_rate
        when p.iss_distribution_rate is null
          or p.effective_rate is null then null
        else least(
          p.effective_rate * p.iss_distribution_rate,
          coalesce(p.iss_effective_cap, 0.05)
        )
      end as iss_effective_rate,
      jsonb_build_object(
        'calculation_version', 'effective-rate-v2-line-level',
        'calculation_snapshot_id', p.calculation_snapshot_id,
        'calculation_snapshot_sha256',
          p.calculation_snapshot_sha256,
        'declaration_id', p.declaration_id,
        'declaration_payload_sha256', p.declaration_payload_sha256,
        'annex_item_id', p.annex_item_id,
        'source_line_key', p.source_line_key,
        'rule_version_id', p.rule_version_id,
        'rule_sha256', p.rule_sha256,
        'competence_month', p.competence_month,
        'declared_annex_code', p.declared_annex_code,
        'expected_annex_code', p.expected_annex_code,
        'activity_code', p.activity_code,
        'revenue_type', p.revenue_type,
        'line_tax_base', p.line_tax_base,
        'factor_r_applicable', p.factor_r_applicable,
        'factor_r', p.factor_r,
        'rbt12_basis', p.rbt12_basis,
        'rbt12_mode', p.rbt12_mode,
        'band_number', p.band_number,
        'nominal_rate', p.nominal_rate,
        'deduction_amount', p.deduction_amount,
        'effective_rate_formula',
          '((rbt12 * nominal_rate) - deduction_amount) / rbt12',
        'effective_rate', p.effective_rate,
        'iss_distribution_rate', p.iss_distribution_rate,
        'iss_effective_cap', p.iss_effective_cap,
        'iss_fixed_effective_rate', p.iss_fixed_effective_rate,
        'block_reasons', p.block_reasons,
        'source_snapshot_evidence', p.source_evidence,
        'is_test', p.is_test
      ) as evidence
    from calculated p
  ),
  keyed as (
    select
      p.*,
      -- The idempotency key covers the complete deterministic result, not
      -- only the upstream snapshot. This is essential for the first month of
      -- activity, where current-period payroll is imported outside the
      -- rolling snapshot and can legitimately change a blocked result into a
      -- calculated one.
      encode(extensions.digest(p.evidence::text, 'sha256'), 'hex')
        as result_key,
      encode(extensions.digest(p.evidence::text, 'sha256'), 'hex')
        as result_sha256
    from payload p
  ),
  inserted as (
    insert into public.simple_national_effective_rate_calculations (
      municipality_id,
      calculation_snapshot_id,
      declaration_id,
      annex_item_id,
      source_line_key,
      taxpayer_id,
      competence_month,
      rule_version_id,
      rate_band_id,
      declared_annex_code,
      expected_annex_code,
      activity_code,
      revenue_type,
      line_tax_base,
      factor_r_applicable,
      factor_r,
      rbt12_basis,
      rbt12_mode,
      nominal_rate,
      deduction_amount,
      effective_rate,
      iss_effective_rate,
      status,
      block_reasons,
      evidence_snapshot,
      snapshot_sha256,
      result_key,
      is_test,
      calculated_at
    )
    select
      p.municipality_id,
      p.calculation_snapshot_id,
      p.declaration_id,
      p.annex_item_id,
      p.source_line_key,
      p.taxpayer_id,
      p.competence_month,
      p.rule_version_id,
      p.rate_band_id,
      p.declared_annex_code,
      p.expected_annex_code,
      p.activity_code,
      p.revenue_type,
      p.line_tax_base,
      p.factor_r_applicable,
      p.factor_r,
      case
        when jsonb_array_length(p.block_reasons) = 0
          then p.rbt12_basis
        else null
      end,
      p.rbt12_mode,
      p.nominal_rate,
      p.deduction_amount,
      p.effective_rate,
      p.iss_effective_rate,
      case
        when jsonb_array_length(p.block_reasons) = 0
          then 'calculated'
        else 'blocked'
      end,
      p.block_reasons,
      p.evidence,
      p.result_sha256,
      p.result_key,
      p.is_test,
      clock_timestamp()
    from keyed p
    on conflict (municipality_id, result_key) do nothing
    returning id
  )
  select count(*)::integer into v_count
  from inserted;

  return v_count;
end;
$function$;

revoke all on function public.ia_rebuild_simple_national_effective_rates(
  uuid, date, date, boolean
) from public, anon;
grant execute on function public.ia_rebuild_simple_national_effective_rates(
  uuid, date, date, boolean
) to authenticated, service_role;

create or replace view public.vw_simple_national_effective_rates
with (security_invoker = true)
as
with effective_declarations as (
  select distinct on (
    d.municipality_id,
    d.taxpayer_id,
    d.competence_month,
    d.is_test
  )
    d.id,
    d.municipality_id,
    d.taxpayer_id,
    d.competence_month,
    d.is_test
  from public.pgdasd_declarations d
  where d.declaration_status <> 'cancelled'
  order by
    d.municipality_id,
    d.taxpayer_id,
    d.competence_month,
    d.is_test,
    (d.declaration_status = 'rectified') desc,
    d.transmitted_at desc nulls last,
    d.created_at desc,
    d.id desc
),
current_manifest as (
  select
    d.municipality_id,
    d.taxpayer_id,
    d.competence_month,
    d.is_test,
    d.id as declaration_id,
    coalesce(ai.external_line_id, 'snapshot-block') as source_line_key
  from effective_declarations d
  left join public.pgdasd_annex_items ai
    on ai.municipality_id = d.municipality_id
   and ai.declaration_id = d.id
   and ai.taxpayer_id = d.taxpayer_id
),
ranked as (
  select
    c.*,
    row_number() over (
      partition by
        c.municipality_id,
        c.taxpayer_id,
        c.competence_month,
        c.source_line_key,
        c.is_test
      order by c.calculated_at desc, c.created_at desc, c.id desc
    ) as revision_rank
  from public.simple_national_effective_rate_calculations c
  join current_manifest m
    on m.municipality_id = c.municipality_id
   and m.taxpayer_id = c.taxpayer_id
   and m.competence_month = c.competence_month
   and m.is_test = c.is_test
   and m.declaration_id = c.declaration_id
   and m.source_line_key = c.source_line_key
)
select
  c.municipality_id as municipio_id,
  c.taxpayer_id as contribuinte_id,
  c.competence_month as competencia,
  c.calculation_snapshot_id,
  c.declaration_id,
  c.annex_item_id,
  c.activity_code as atividade,
  c.revenue_type as tipo_receita,
  c.line_tax_base as base_linha,
  c.declared_annex_code as anexo_declarado,
  c.expected_annex_code as anexo_esperado,
  c.factor_r_applicable as fator_r_aplicavel,
  c.factor_r as fator_r,
  c.rbt12_basis as rbt12,
  c.rbt12_mode,
  b.band_number as faixa,
  c.nominal_rate as aliquota_nominal,
  c.deduction_amount as parcela_deduzir,
  c.effective_rate as aliquota_efetiva,
  c.iss_effective_rate as aliquota_efetiva_iss,
  c.status,
  c.block_reasons,
  c.snapshot_sha256,
  c.result_key,
  c.is_test,
  c.calculated_at,
  true as is_current
from ranked c
left join public.simple_national_rate_bands b
  on b.municipality_id = c.municipality_id
 and b.id = c.rate_band_id
where c.revision_rank = 1;

revoke all on public.vw_simple_national_effective_rates
  from public, anon;
grant select on public.vw_simple_national_effective_rates
  to authenticated, service_role;

