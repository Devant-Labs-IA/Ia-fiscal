-- Effective PGDAS-D declarations, per-line annex checks and complete evidence hashes.

create table if not exists public.taxpayer_fiscal_profiles (
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  activity_started_on date,
  activity_date_source text,
  activity_date_verified boolean not null default false,
  simples_opted_from date,
  simples_opted_until date,
  source_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (municipality_id, taxpayer_id),
  constraint taxpayer_fiscal_profiles_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint taxpayer_fiscal_profiles_activity_source_ck
    check (
      activity_date_source is null
      or activity_date_source in (
        'official_registry', 'pgdasd', 'municipal_registry',
        'manual_verified', 'synthetic_test'
      )
    ),
  constraint taxpayer_fiscal_profiles_activity_verified_ck
    check (not activity_date_verified or activity_started_on is not null),
  constraint taxpayer_fiscal_profiles_simples_period_ck
    check (
      simples_opted_until is null
      or simples_opted_from is null
      or simples_opted_until >= simples_opted_from
    ),
  constraint taxpayer_fiscal_profiles_snapshot_ck
    check (jsonb_typeof(source_snapshot) = 'object')
);

create table if not exists public.simple_national_annex_line_checks (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  calculation_snapshot_id uuid not null,
  declaration_id uuid not null,
  annex_item_id uuid not null,
  taxpayer_id uuid not null,
  competence_month date not null,
  activity_code text,
  observed_annex_code text not null,
  expected_annex_code text not null,
  factor_r numeric(12,8) not null,
  mismatch boolean not null,
  calculation_snapshot_sha256 text not null
    check (calculation_snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_snapshot jsonb not null,
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint simple_national_annex_line_checks_uq
    unique (
      municipality_id,
      calculation_snapshot_id,
      annex_item_id,
      calculation_snapshot_sha256
    ),
  constraint simple_national_annex_line_checks_snapshot_fk
    foreign key (municipality_id, calculation_snapshot_id)
    references public.simple_national_calculation_snapshots(municipality_id, id)
    on delete cascade,
  constraint simple_national_annex_line_checks_declaration_fk
    foreign key (municipality_id, declaration_id)
    references public.pgdasd_declarations(municipality_id, id),
  constraint simple_national_annex_line_checks_annex_item_fk
    foreign key (municipality_id, annex_item_id)
    references public.pgdasd_annex_items(municipality_id, id),
  constraint simple_national_annex_line_checks_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id),
  constraint simple_national_annex_line_checks_competence_ck
    check (competence_month = date_trunc('month', competence_month)::date),
  constraint simple_national_annex_line_checks_annex_ck
    check (
      observed_annex_code in ('III', 'V')
      and expected_annex_code in ('III', 'V')
    ),
  constraint simple_national_annex_line_checks_factor_r_ck
    check (factor_r between 0 and 100),
  constraint simple_national_annex_line_checks_evidence_ck
    check (jsonb_typeof(evidence_snapshot) = 'object')
);

create index if not exists taxpayer_fiscal_profiles_activity_idx
  on public.taxpayer_fiscal_profiles (
    municipality_id, activity_started_on, activity_date_verified, taxpayer_id
  );

create index if not exists simple_national_annex_line_checks_search_idx
  on public.simple_national_annex_line_checks (
    municipality_id, competence_month, mismatch, taxpayer_id
  );

alter table public.taxpayer_fiscal_profiles enable row level security;
alter table public.simple_national_annex_line_checks enable row level security;

drop policy if exists taxpayer_fiscal_profiles_select
  on public.taxpayer_fiscal_profiles;
create policy taxpayer_fiscal_profiles_select
on public.taxpayer_fiscal_profiles
for select
to authenticated
using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));

drop policy if exists simple_national_annex_line_checks_select
  on public.simple_national_annex_line_checks;
create policy simple_national_annex_line_checks_select
on public.simple_national_annex_line_checks
for select
to authenticated
using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));

revoke all on public.taxpayer_fiscal_profiles
  from public, anon, authenticated;
revoke all on public.simple_national_annex_line_checks
  from public, anon, authenticated;
grant select on public.taxpayer_fiscal_profiles to authenticated;
grant select on public.simple_national_annex_line_checks to authenticated;
grant all on public.taxpayer_fiscal_profiles to service_role;
grant all on public.simple_national_annex_line_checks to service_role;
grant usage, select on sequence
  public.simple_national_annex_line_checks_id_seq to service_role;

drop trigger if exists taxpayer_fiscal_profiles_set_updated_at
  on public.taxpayer_fiscal_profiles;
create trigger taxpayer_fiscal_profiles_set_updated_at
before update on public.taxpayer_fiscal_profiles
for each row execute function private.set_updated_at();

drop trigger if exists taxpayer_fiscal_profiles_immutable_identity
  on public.taxpayer_fiscal_profiles;
create trigger taxpayer_fiscal_profiles_immutable_identity
before update on public.taxpayer_fiscal_profiles
for each row execute function private.prevent_tenant_or_id_change();

drop trigger if exists taxpayer_fiscal_profiles_audit
  on public.taxpayer_fiscal_profiles;
create trigger taxpayer_fiscal_profiles_audit
after insert or update or delete on public.taxpayer_fiscal_profiles
for each row execute function private.audit_row_change();

drop trigger if exists simple_national_annex_line_checks_audit
  on public.simple_national_annex_line_checks;
create trigger simple_national_annex_line_checks_audit
after insert or update or delete on public.simple_national_annex_line_checks
for each row execute function private.audit_row_change();

create or replace function public.ia_rebuild_simple_national_snapshots(
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
      and coalesce((pv.operational_config ->> 'test_mode')::boolean, false)
  ) then
    raise exception 'homologation test mode is not enabled';
  end if;

  with declarations as (
    select distinct on (d.taxpayer_id, d.competence_month)
      d.id,
      d.taxpayer_id,
      d.competence_month,
      d.rbt12_declared,
      d.fs12_declared,
      d.factor_r_declared,
      d.iss_tax_base_declared,
      d.is_test,
      d.payload_sha256,
      d.declaration_status,
      d.transmitted_at
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
  calculated as (
    select
      d.*,
      fp.activity_started_on,
      fp.activity_date_verified,
      coalesce(hist.calculated_rbt12, 0)::numeric(18,2)
        as calculated_rbt12,
      coalesce(hist.history_month_count, 0)::integer
        as history_month_count,
      coalesce(hist.history_inputs, '[]'::jsonb)
        as rbt12_inputs,
      coalesce(payroll.calculated_fs12, 0)::numeric(18,2)
        as calculated_fs12,
      coalesce(payroll.payroll_inputs, '[]'::jsonb)
        as payroll_inputs,
      coalesce(sigiss.sigiss_tax_base, 0)::numeric(18,2)
        as sigiss_tax_base,
      coalesce(sigiss.sigiss_inputs, '[]'::jsonb)
        as sigiss_inputs,
      coalesce(annex.factor_r_applicable, false)
        as factor_r_applicable,
      coalesce(annex.applicable_annex_count, 0)::integer
        as applicable_annex_count,
      case
        when coalesce(annex.applicable_annex_count, 0) = 1
          then annex.single_declared_annex_code
      end as declared_annex_code,
      coalesce(annex.annex_inputs, '[]'::jsonb)
        as annex_inputs
    from declarations d
    left join public.taxpayer_fiscal_profiles fp
      on fp.municipality_id = p_municipality_id
     and fp.taxpayer_id = d.taxpayer_id
    left join lateral (
      select
        sum(e.total_revenue_declared) as calculated_rbt12,
        count(*) as history_month_count,
        jsonb_agg(
          jsonb_build_object(
            'declaration_id', e.id,
            'competence_month', e.competence_month,
            'declaration_status', e.declaration_status,
            'transmitted_at', e.transmitted_at,
            'total_revenue_declared', e.total_revenue_declared,
            'payload_sha256', coalesce(
              e.payload_sha256,
              encode(
                extensions.digest(
                  jsonb_build_object(
                    'id', e.id,
                    'competence_month', e.competence_month,
                    'status', e.declaration_status,
                    'revenue', e.total_revenue_declared
                  )::text,
                  'sha256'
                ),
                'hex'
              )
            )
          )
          order by e.competence_month
        ) as history_inputs
      from (
        select distinct on (pr.competence_month)
          pr.id,
          pr.competence_month,
          pr.declaration_status,
          pr.transmitted_at,
          pr.total_revenue_declared,
          pr.payload_sha256,
          pr.created_at
        from public.pgdasd_declarations pr
        where pr.municipality_id = p_municipality_id
          and pr.taxpayer_id = d.taxpayer_id
          and pr.is_test = p_is_test
          and pr.declaration_status <> 'cancelled'
          and pr.competence_month
            >= (d.competence_month - interval '12 months')::date
          and pr.competence_month < d.competence_month
        order by
          pr.competence_month,
          (pr.declaration_status = 'rectified') desc,
          pr.transmitted_at desc nulls last,
          pr.created_at desc,
          pr.id desc
      ) e
    ) hist on true
    left join lateral (
      select
        sum(p.fs_month) as calculated_fs12,
        jsonb_agg(
          jsonb_build_object(
            'payroll_period_id', p.id,
            'competence_month', p.competence_month,
            'fs_month', p.fs_month,
            'payload_sha256', coalesce(
              p.payload_sha256,
              encode(
                extensions.digest(
                  jsonb_build_object(
                    'id', p.id,
                    'competence_month', p.competence_month,
                    'fs_month', p.fs_month
                  )::text,
                  'sha256'
                ),
                'hex'
              )
            )
          )
          order by p.competence_month, p.id
        ) as payroll_inputs
      from public.factor_r_payroll_periods p
      where p.municipality_id = p_municipality_id
        and p.taxpayer_id = d.taxpayer_id
        and p.is_test = p_is_test
        and p.competence_month
          >= (d.competence_month - interval '12 months')::date
        and p.competence_month < d.competence_month
    ) payroll on true
    left join lateral (
      select
        sum(s.iss_tax_base) as sigiss_tax_base,
        jsonb_agg(
          jsonb_build_object(
            'sigiss_period_id', s.id,
            'iss_tax_base', s.iss_tax_base,
            'payload_sha256', coalesce(
              s.payload_sha256,
              encode(
                extensions.digest(
                  jsonb_build_object(
                    'id', s.id,
                    'competence_month', s.competence_month,
                    'iss_tax_base', s.iss_tax_base
                  )::text,
                  'sha256'
                ),
                'hex'
              )
            )
          )
          order by s.id
        ) as sigiss_inputs
      from public.sigiss_tax_base_periods s
      where s.municipality_id = p_municipality_id
        and s.taxpayer_id = d.taxpayer_id
        and s.is_test = p_is_test
        and s.competence_month = d.competence_month
    ) sigiss on true
    left join lateral (
      select
        bool_or(ai.factor_r_applicable) as factor_r_applicable,
        count(distinct ai.annex_code)
          filter (where ai.factor_r_applicable) as applicable_annex_count,
        min(ai.annex_code)
          filter (where ai.factor_r_applicable) as single_declared_annex_code,
        jsonb_agg(
          jsonb_build_object(
            'annex_item_id', ai.id,
            'external_line_id', ai.external_line_id,
            'activity_code', ai.activity_code,
            'annex_code', ai.annex_code,
            'factor_r_applicable', ai.factor_r_applicable,
            'tax_base', ai.tax_base,
            'source_sha256', encode(
              extensions.digest(ai.source_snapshot::text, 'sha256'),
              'hex'
            )
          )
          order by ai.external_line_id, ai.id
        ) as annex_inputs
      from public.pgdasd_annex_items ai
      where ai.municipality_id = p_municipality_id
        and ai.declaration_id = d.id
    ) annex on true
  ),
  prepared as (
    select
      c.*,
      private.calculate_factor_r(
        c.calculated_fs12,
        c.calculated_rbt12
      ) as calculated_factor_r
    from calculated c
  ),
  payload as (
    select
      p.*,
      private.expected_factor_r_annex(
        p.calculated_factor_r,
        p.factor_r_applicable
      ) as expected_annex_code,
      jsonb_strip_nulls(
        jsonb_build_object(
          'calculation_version',
            'simple-national-v2-effective-declaration',
          'implementation', jsonb_build_object(
            'rbt12', 'effective_pgdasd_declaration_per_competence_v2',
            'factor_r', 'fs12_divided_by_rbt12_v1',
            'annex', 'factor_r_per_activity_line_v2',
            'tax_base', 'pgdasd_vs_sigiss_v1'
          ),
          'pgdasd_declaration_id', p.id,
          'declaration_status', p.declaration_status,
          'transmitted_at', p.transmitted_at,
          'competence_month', p.competence_month,
          'window', jsonb_build_object(
            'start', (p.competence_month - interval '12 months')::date,
            'end_exclusive', p.competence_month
          ),
          'activity', jsonb_build_object(
            'started_on', p.activity_started_on,
            'verified', p.activity_date_verified
          ),
          'inputs', jsonb_build_object(
            'target_declaration_sha256', p.payload_sha256,
            'rbt12_declarations', p.rbt12_inputs,
            'payroll_periods', p.payroll_inputs,
            'sigiss_periods', p.sigiss_inputs,
            'annex_items', p.annex_inputs
          ),
          'outputs', jsonb_build_object(
            'declared_rbt12', p.rbt12_declared,
            'calculated_rbt12', p.calculated_rbt12,
            'declared_fs12', p.fs12_declared,
            'calculated_fs12', p.calculated_fs12,
            'declared_factor_r', p.factor_r_declared,
            'calculated_factor_r', p.calculated_factor_r,
            'declared_annex_code', p.declared_annex_code,
            'expected_annex_code',
              private.expected_factor_r_annex(
                p.calculated_factor_r,
                p.factor_r_applicable
              ),
            'pgdasd_tax_base', p.iss_tax_base_declared,
            'sigiss_tax_base', p.sigiss_tax_base
          ),
          'quality', jsonb_build_object(
            'history_month_count', p.history_month_count,
            'applicable_annex_count', p.applicable_annex_count,
            'is_test', p.is_test
          )
        )
      ) as evidence
    from prepared p
  ),
  upserted as (
    insert into public.simple_national_calculation_snapshots (
      municipality_id,
      taxpayer_id,
      competence_month,
      calculation_version,
      declared_rbt12,
      calculated_rbt12,
      declared_fs12,
      calculated_fs12,
      declared_factor_r,
      calculated_factor_r,
      declared_annex_code,
      expected_annex_code,
      pgdasd_tax_base,
      sigiss_tax_base,
      rbt12_difference,
      factor_r_difference,
      tax_base_difference,
      annex_mismatch,
      factor_r_applicable,
      status,
      block_reasons,
      evidence_snapshot,
      snapshot_sha256,
      is_test,
      calculated_at
    )
    select
      p_municipality_id,
      p.taxpayer_id,
      p.competence_month,
      'simple-national-v2-effective-declaration',
      p.rbt12_declared,
      p.calculated_rbt12,
      p.fs12_declared,
      p.calculated_fs12,
      p.factor_r_declared,
      p.calculated_factor_r,
      p.declared_annex_code,
      p.expected_annex_code,
      p.iss_tax_base_declared,
      p.sigiss_tax_base,
      abs(
        coalesce(p.rbt12_declared, p.calculated_rbt12)
        - p.calculated_rbt12
      ),
      abs(
        coalesce(p.factor_r_declared, p.calculated_factor_r)
        - p.calculated_factor_r
      ),
      abs(p.iss_tax_base_declared - p.sigiss_tax_base),
      exists (
        select 1
        from public.pgdasd_annex_items ai
        where ai.municipality_id = p_municipality_id
          and ai.declaration_id = p.id
          and ai.factor_r_applicable
          and ai.annex_code <> p.expected_annex_code
      ),
      p.factor_r_applicable,
      case
        when p.history_month_count < 12 then 'blocked'
        when p.rbt12_declared is null then 'incomplete'
        else 'calculated'
      end,
      (
        case
          when p.rbt12_declared is null
            then jsonb_build_array(
              jsonb_build_object('code', 'missing_declared_rbt12')
            )
          else '[]'::jsonb
        end
        ||
        case
          when p.history_month_count >= 12 then '[]'::jsonb
          when p.activity_started_on is null
            then jsonb_build_array(
              jsonb_build_object(
                'code', 'insufficient_history_missing_activity_start',
                'history_month_count', p.history_month_count
              )
            )
          when p.activity_started_on
            > (p.competence_month - interval '12 months')::date
            then jsonb_build_array(
              jsonb_build_object(
                'code', 'startup_annualization_rule_not_homologated',
                'activity_started_on', p.activity_started_on
              )
            )
          else jsonb_build_array(
            jsonb_build_object(
              'code', 'incomplete_rbt12_history',
              'history_month_count', p.history_month_count
            )
          )
        end
      ),
      p.evidence,
      encode(
        extensions.digest(p.evidence::text, 'sha256'),
        'hex'
      ),
      p_is_test,
      now()
    from payload p
    on conflict (
      municipality_id,
      taxpayer_id,
      competence_month,
      calculation_version,
      is_test
    ) do update
      set declared_rbt12 = excluded.declared_rbt12,
          calculated_rbt12 = excluded.calculated_rbt12,
          declared_fs12 = excluded.declared_fs12,
          calculated_fs12 = excluded.calculated_fs12,
          declared_factor_r = excluded.declared_factor_r,
          calculated_factor_r = excluded.calculated_factor_r,
          declared_annex_code = excluded.declared_annex_code,
          expected_annex_code = excluded.expected_annex_code,
          pgdasd_tax_base = excluded.pgdasd_tax_base,
          sigiss_tax_base = excluded.sigiss_tax_base,
          rbt12_difference = excluded.rbt12_difference,
          factor_r_difference = excluded.factor_r_difference,
          tax_base_difference = excluded.tax_base_difference,
          annex_mismatch = excluded.annex_mismatch,
          factor_r_applicable = excluded.factor_r_applicable,
          status = excluded.status,
          block_reasons = excluded.block_reasons,
          evidence_snapshot = excluded.evidence_snapshot,
          snapshot_sha256 = excluded.snapshot_sha256,
          calculated_at = excluded.calculated_at
    returning id, taxpayer_id, competence_month
  )
  select count(*)::integer
  into v_count
  from upserted;

  with declarations as (
    select distinct on (d.taxpayer_id, d.competence_month)
      d.id,
      d.taxpayer_id,
      d.competence_month
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
  lines as (
    select
      s.id as calculation_snapshot_id,
      d.id as declaration_id,
      ai.id as annex_item_id,
      d.taxpayer_id,
      d.competence_month,
      ai.activity_code,
      ai.annex_code as observed_annex_code,
      s.expected_annex_code,
      s.calculated_factor_r,
      jsonb_build_object(
        'calculation_snapshot_id', s.id,
        'calculation_snapshot_sha256', s.snapshot_sha256,
        'declaration_id', d.id,
        'annex_item_id', ai.id,
        'activity_code', ai.activity_code,
        'observed_annex_code', ai.annex_code,
        'expected_annex_code', s.expected_annex_code,
        'calculated_factor_r', s.calculated_factor_r,
        'factor_r_applicable', ai.factor_r_applicable,
        'line_source_sha256', encode(
          extensions.digest(ai.source_snapshot::text, 'sha256'),
          'hex'
        )
      ) as evidence
    from declarations d
    join public.simple_national_calculation_snapshots s
      on s.municipality_id = p_municipality_id
     and s.taxpayer_id = d.taxpayer_id
     and s.competence_month = d.competence_month
     and s.calculation_version =
       'simple-national-v2-effective-declaration'
     and s.is_test = p_is_test
    join public.pgdasd_annex_items ai
      on ai.municipality_id = p_municipality_id
     and ai.declaration_id = d.id
     and ai.factor_r_applicable
    where s.expected_annex_code is not null
  )
  insert into public.simple_national_annex_line_checks (
    municipality_id,
    calculation_snapshot_id,
    declaration_id,
    annex_item_id,
    taxpayer_id,
    competence_month,
    activity_code,
    observed_annex_code,
    expected_annex_code,
    factor_r,
    mismatch,
    calculation_snapshot_sha256,
    evidence_snapshot,
    snapshot_sha256
  )
  select
    p_municipality_id,
    l.calculation_snapshot_id,
    l.declaration_id,
    l.annex_item_id,
    l.taxpayer_id,
    l.competence_month,
    l.activity_code,
    l.observed_annex_code,
    l.expected_annex_code,
    l.calculated_factor_r,
    l.observed_annex_code <> l.expected_annex_code,
    l.evidence ->> 'calculation_snapshot_sha256',
    l.evidence,
    encode(
      extensions.digest(l.evidence::text, 'sha256'),
      'hex'
    )
  from lines l
  on conflict (
    municipality_id,
    calculation_snapshot_id,
    annex_item_id,
    calculation_snapshot_sha256
  ) do nothing;

  return v_count;
end;
$function$;

revoke all on function public.ia_rebuild_simple_national_snapshots(
  uuid, date, date, boolean
) from public, anon, authenticated;
grant execute on function public.ia_rebuild_simple_national_snapshots(
  uuid, date, date, boolean
) to service_role;

-- Detection is pinned to the corrected calculation contract. Old snapshots
-- and their audit evidence remain queryable but cannot create new findings.
do $block$
declare
  v_signature regprocedure :=
    'public.ia_run_simple_national_detection(uuid,uuid,timestamp with time zone,text,uuid,boolean)'::regprocedure;
  v_definition text;
  v_old text :=
    'and s.is_test = p_test_mode';
  v_new text :=
    'and s.is_test = p_test_mode' || chr(10) ||
    '      and s.calculation_version = ' ||
    quote_literal('simple-national-v2-effective-declaration');
begin
  select pg_get_functiondef(v_signature) into strict v_definition;

  if position(
    'simple-national-v2-effective-declaration'
    in v_definition
  ) > 0 then
    return;
  end if;

  if position(v_old in v_definition) = 0 then
    raise exception
      'simple national detection contract changed; migration aborted';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$block$;

revoke all on function public.ia_run_simple_national_detection(
  uuid, uuid, timestamptz, text, uuid, boolean
) from public, anon, authenticated;
grant execute on function public.ia_run_simple_national_detection(
  uuid, uuid, timestamptz, text, uuid, boolean
) to service_role;

-- New draft rule versions preserve history while aligning the implementation
-- contract. Formula approval and activation remain explicit human gates.
insert into public.divergence_rule_versions (
  municipality_id,
  rule_id,
  version,
  status,
  implementation_key,
  implementation_version,
  parameters,
  checksum_sha256,
  created_by
)
select
  rv.municipality_id,
  rv.rule_id,
  rv.version + 1,
  'draft',
  'current_account_generated_vs_paid_v1',
  '1.1.0',
  rv.parameters || jsonb_build_object(
    'formula_approved', false,
    'requires_due_on', true,
    'maturity_policy', 'due_on_lte_as_of',
    'supersedes_version_id', rv.id
  ),
  encode(
    extensions.digest(
      jsonb_build_object(
        'rule_id', rv.rule_id,
        'version', rv.version + 1,
        'implementation_key',
          'current_account_generated_vs_paid_v1',
        'implementation_version', '1.1.0',
        'parameters', rv.parameters || jsonb_build_object(
          'formula_approved', false,
          'requires_due_on', true,
          'maturity_policy', 'due_on_lte_as_of',
          'supersedes_version_id', rv.id
        )
      )::text,
      'sha256'
    ),
    'hex'
  ),
  null
from public.divergence_rule_versions rv
join public.divergence_rules r
  on r.municipality_id = rv.municipality_id
 and r.id = rv.rule_id
where r.divergence_type = 'current_account_balance'
  and rv.implementation_key = 'current_account_balance_v1'
  and not exists (
    select 1
    from public.divergence_rule_versions v2
    where v2.municipality_id = rv.municipality_id
      and v2.rule_id = rv.rule_id
      and v2.implementation_key =
        'current_account_generated_vs_paid_v1'
  );

comment on table public.taxpayer_fiscal_profiles is
  'Versioned fiscal inputs that cannot be inferred safely from declarations, including verified activity start.';

comment on table public.simple_national_annex_line_checks is
  'Per-activity Annex III/V decisions; mixed activities are never collapsed with min(annex_code).';
