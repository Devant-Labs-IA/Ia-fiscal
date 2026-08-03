-- IA Fiscal
-- Versioned ISS maturity, operational accountant relationships and
-- notification preflight. External delivery remains disabled.

-- ---------------------------------------------------------------------------
-- 1. Legal source and due-date rules.
-- ---------------------------------------------------------------------------

create table if not exists public.municipality_business_calendar (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  calendar_date date not null,
  calendar_scope text not null
    check (calendar_scope in ('municipal_service', 'federal_banking')),
  is_business_day boolean not null,
  day_type text not null
    check (day_type in (
      'business_day',
      'weekend',
      'national_holiday',
      'state_holiday',
      'municipal_holiday',
      'administrative_closure'
    )),
  description text,
  legal_source_version_id uuid,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'revoked')),
  source_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (municipality_id, calendar_scope, calendar_date),
  unique (municipality_id, id),
  foreign key (municipality_id)
    references public.municipalities(id) on delete cascade,
  foreign key (municipality_id, legal_source_version_id)
    references public.legal_source_versions(municipality_id, id)
);

create table if not exists public.due_date_rule_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  code text not null,
  version integer not null check (version > 0),
  tax_code text not null,
  collection_regime text not null
    check (collection_regime in (
      'monthly_iss',
      'withheld_iss',
      'simple_national_das',
      'personal_service_assessment',
      'special_collection'
    )),
  competence_month_offset smallint not null default 1
    check (competence_month_offset between 0 and 24),
  due_day smallint
    check (due_day between 1 and 31),
  business_day_adjustment text not null
    check (business_day_adjustment in (
      'none',
      'next_business_day',
      'notice_defined',
      'special_rule_required'
    )),
  exception_policy text not null,
  valid_from date not null,
  valid_until date,
  legal_source_version_id uuid not null,
  status text not null default 'draft'
    check (status in (
      'draft',
      'active_homologation',
      'active',
      'retired',
      'revoked'
    )),
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

create index if not exists municipality_business_calendar_lookup_idx
  on public.municipality_business_calendar (
    municipality_id, calendar_scope, calendar_date, is_business_day
  );

create index if not exists due_date_rule_versions_lookup_idx
  on public.due_date_rule_versions (
    municipality_id, tax_code, collection_regime, valid_from, valid_until
  )
  where status in ('active_homologation', 'active');

alter table public.municipality_business_calendar enable row level security;
alter table public.due_date_rule_versions enable row level security;

drop policy if exists municipality_business_calendar_select
  on public.municipality_business_calendar;
create policy municipality_business_calendar_select
on public.municipality_business_calendar
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

drop policy if exists due_date_rule_versions_select
  on public.due_date_rule_versions;
create policy due_date_rule_versions_select
on public.due_date_rule_versions
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

revoke all on public.municipality_business_calendar
  from public, anon, authenticated;
revoke all on public.due_date_rule_versions
  from public, anon, authenticated;
grant select on public.municipality_business_calendar to authenticated;
grant select on public.due_date_rule_versions to authenticated;
grant all on public.municipality_business_calendar to service_role;
grant all on public.due_date_rule_versions to service_role;

drop trigger if exists municipality_business_calendar_set_updated_at
  on public.municipality_business_calendar;
create trigger municipality_business_calendar_set_updated_at
before update on public.municipality_business_calendar
for each row execute function private.set_updated_at();

drop trigger if exists municipality_business_calendar_immutable_identity
  on public.municipality_business_calendar;
create trigger municipality_business_calendar_immutable_identity
before update on public.municipality_business_calendar
for each row execute function private.prevent_tenant_or_id_change();

drop trigger if exists municipality_business_calendar_audit
  on public.municipality_business_calendar;
create trigger municipality_business_calendar_audit
after insert or update or delete on public.municipality_business_calendar
for each row execute function private.audit_row_change();

drop trigger if exists due_date_rule_versions_set_updated_at
  on public.due_date_rule_versions;
create trigger due_date_rule_versions_set_updated_at
before update on public.due_date_rule_versions
for each row execute function private.set_updated_at();

drop trigger if exists due_date_rule_versions_immutable_identity
  on public.due_date_rule_versions;
create trigger due_date_rule_versions_immutable_identity
before update on public.due_date_rule_versions
for each row execute function private.prevent_tenant_or_id_change();

drop trigger if exists due_date_rule_versions_audit
  on public.due_date_rule_versions;
create trigger due_date_rule_versions_audit
after insert or update or delete on public.due_date_rule_versions
for each row execute function private.audit_row_change();

create or replace function private.ia_next_business_day(
  p_municipality_id uuid,
  p_calendar_scope text,
  p_nominal_date date
) returns date
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_candidate date := p_nominal_date;
  v_iterations integer := 0;
  v_override boolean;
begin
  if p_nominal_date is null then
    return null;
  end if;

  loop
    v_iterations := v_iterations + 1;
    if v_iterations > 31 then
      raise exception 'business calendar resolution exceeded 31 days';
    end if;

    select c.is_business_day
      into v_override
    from public.municipality_business_calendar c
    where c.municipality_id = p_municipality_id
      and c.calendar_scope = p_calendar_scope
      and c.calendar_date = v_candidate
      and c.verification_status = 'verified';

    if v_override is true then
      return v_candidate;
    end if;

    if v_override is false
       or extract(isodow from v_candidate) in (6, 7) then
      v_candidate := v_candidate + 1;
    else
      return v_candidate;
    end if;
  end loop;
end;
$function$;

revoke all on function private.ia_next_business_day(uuid, text, date)
  from public, anon, authenticated;
grant execute on function private.ia_next_business_day(uuid, text, date)
  to service_role;

-- Register the official municipal source without manufacturing a fiscal
-- approval identity. The source is active and the extracted version remains
-- under review until a municipal fiscal/legal user signs it.
with municipality as (
  select id
  from public.municipalities
  where ibge_code = '3512407'
),
inserted as (
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
    'law',
    'municipal',
    'Município de Cordeirópolis',
    'Código Tributário do Município de Cordeirópolis',
    'Lei Complementar nº 399/2024',
    'https://cordeiropolis.sp.gov.br/wp-content/uploads/2024/12/Edicao-1645-_C.pdf',
    'ISSQN',
    'current_account_balance',
    'active'
  from municipality m
  where not exists (
    select 1
    from public.legal_sources s
    where s.municipality_id = m.id
      and s.official_identifier = 'Lei Complementar nº 399/2024'
  )
  returning id
)
select count(*) from inserted;

with municipality as (
  select id
  from public.municipalities
  where ibge_code = '3512407'
),
source as (
  select s.municipality_id, s.id
  from public.legal_sources s
  join municipality m on m.id = s.municipality_id
  where s.official_identifier = 'Lei Complementar nº 399/2024'
  order by s.created_at
  limit 1
),
content as (
  select
    'Art. 213 §1º: optantes do Simples Nacional usam os percentuais da legislação federal. '
    || 'Art. 215: o ISS mensal é recolhido até o dia 15 do mês subsequente. '
    || 'Art. 216: trabalho pessoal e sociedades profissionais seguem o aviso de lançamento. '
    || 'Art. 217: ISS retido vence no dia 15 do mês subsequente. '
    || 'Art. 218: atividades especiais podem ter outra forma de recolhimento. '
    || 'Art. 282: vencimento não útil prorroga ao primeiro dia útil. '
    || 'Art. 286: efeitos desde 01/01/2025.' as body
),
inserted as (
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
    s.municipality_id,
    s.id,
    1,
    'under_review',
    c.body,
    encode(extensions.digest(c.body, 'sha256'), 'hex'),
    date '2025-01-01',
    date '2024-12-20'
  from source s
  cross join content c
  where not exists (
    select 1
    from public.legal_source_versions v
    where v.municipality_id = s.municipality_id
      and v.source_id = s.id
      and v.version = 1
  )
  returning id
)
select count(*) from inserted;

-- Calendar and federal collection sources used by the maturity resolver.
with municipality as (
  select id
  from public.municipalities
  where ibge_code = '3512407'
),
source_rows (
  source_type,
  jurisdiction,
  issuing_authority,
  title,
  official_identifier,
  official_url,
  tax_scope,
  divergence_scope
) as (
  values
    (
      'decree',
      'municipal',
      'Município de Cordeirópolis',
      'Calendário de pontos facultativos e feriados de 2026',
      'Decreto nº 7.096/2025',
      'https://cordeiropolis.sp.gov.br/wp-content/uploads/2025/12/Edicao-1752-_CN.pdf',
      'Calendário fiscal municipal',
      'due_date_calendar'
    ),
    (
      'official_guidance',
      'federal',
      'Receita Federal do Brasil',
      'Manual do PGDAS-D e DEFIS 2018',
      'Manual PGDAS-D 2018 v4',
      'https://www8.receita.fazenda.gov.br/simplesnacional/arquivos/manual/manual_pgdas-d_2018_v4.pdf',
      'Simples Nacional / DAS',
      'simple_national_due_date'
    ),
    (
      'official_guidance',
      'federal',
      'Receita Federal do Brasil',
      'Agenda Tributária — 20 de abril de 2026',
      'Agenda RFB PGDAS-D 2026-04-20',
      'https://www.gov.br/receitafederal/pt-br/assuntos/agenda-tributaria/2026/abril/dia-20-04-2026',
      'Simples Nacional / DAS',
      'simple_national_due_date'
    ),
    (
      'law',
      'federal',
      'Congresso Nacional',
      'Declara feriado nacional o Dia Nacional de Zumbi e da Consciência Negra',
      'Lei nº 14.759/2023',
      'https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2023/lei/l14759.htm',
      'Calendário bancário federal',
      'simple_national_due_date'
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
  s.source_type,
  s.jurisdiction,
  s.issuing_authority,
  s.title,
  s.official_identifier,
  s.official_url,
  s.tax_scope,
  s.divergence_scope,
  'active'
from municipality m
cross join source_rows s
where not exists (
  select 1
  from public.legal_sources x
  where x.municipality_id = m.id
    and x.official_identifier = s.official_identifier
);

with source_content (
  official_identifier,
  content_text,
  valid_from,
  publication_date
) as (
  values
    (
      'Decreto nº 7.096/2025',
      'Art. 1º: pontos facultativos municipais em 16 e 17/02/2026, '
      || '20/04/2026, 05/06/2026, 10/07/2026, 28/10/2026, '
      || '24/12/2026 e 31/12/2026; em 18/02/2026 o atendimento '
      || 'municipal começa às 12h. Art. 2º: feriados municipais em '
      || '03/04/2026, 04/06/2026, 13/06/2026 e 20/11/2026.',
      date '2026-01-01',
      date '2025-12-31'
    ),
    (
      'Manual PGDAS-D 2018 v4',
      'Declaração e recolhimento do Simples Nacional vencem no dia 20 '
      || 'do mês subsequente. Sem expediente bancário no dia 20, o '
      || 'recolhimento ocorre no dia útil imediatamente posterior.',
      date '2018-01-01',
      date '2018-01-01'
    ),
    (
      'Agenda RFB PGDAS-D 2026-04-20',
      'A agenda tributária oficial confirma o PGDAS-D/DAS da '
      || 'competência março de 2026 com vencimento em 20/04/2026.',
      date '2026-04-20',
      date '2026-03-30'
    ),
    (
      'Lei nº 14.759/2023',
      'Declara feriado nacional o dia 20 de novembro, Dia Nacional de '
      || 'Zumbi e da Consciência Negra.',
      date '2023-12-22',
      date '2023-12-22'
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

-- Only verified non-business dates that can affect the 2026 backfill are
-- persisted. The federal scope stays independent from municipal closures.
with sources as (
  select
    m.id as municipality_id,
    (array_agg(v.id order by v.created_at) filter (
      where s.official_identifier = 'Decreto nº 7.096/2025'
    ))[1] as decree_version_id,
    (array_agg(v.id order by v.created_at) filter (
      where s.official_identifier = 'Agenda RFB PGDAS-D 2026-04-20'
    ))[1] as rfb_agenda_version_id,
    (array_agg(v.id order by v.created_at) filter (
      where s.official_identifier = 'Lei nº 14.759/2023'
    ))[1] as national_holiday_version_id
  from public.municipalities m
  join public.legal_sources s on s.municipality_id = m.id
  join public.legal_source_versions v
    on v.municipality_id = s.municipality_id
   and v.source_id = s.id
   and v.version = 1
  where m.ibge_code = '3512407'
  group by m.id
),
calendar_rows (
  calendar_scope,
  calendar_date,
  is_business_day,
  day_type,
  description,
  source_kind
) as (
  values
    ('municipal_service', date '2026-02-16', false,
      'administrative_closure', 'Carnaval — ponto facultativo', 'decree'),
    ('municipal_service', date '2026-02-17', false,
      'administrative_closure', 'Carnaval — ponto facultativo', 'decree'),
    ('municipal_service', date '2026-02-18', true,
      'business_day', 'Quarta-feira de Cinzas — atendimento desde 12h', 'decree'),
    ('municipal_service', date '2026-04-03', false,
      'municipal_holiday', 'Sexta-Feira da Paixão', 'decree'),
    ('municipal_service', date '2026-04-20', false,
      'administrative_closure', 'Ponto facultativo municipal', 'decree'),
    ('municipal_service', date '2026-04-21', false,
      'national_holiday', 'Tiradentes', 'decree'),
    ('municipal_service', date '2026-05-01', false,
      'national_holiday', 'Dia do Trabalho', 'decree'),
    ('municipal_service', date '2026-06-04', false,
      'municipal_holiday', 'Corpus Christi', 'decree'),
    ('municipal_service', date '2026-06-05', false,
      'administrative_closure', 'Ponto facultativo municipal', 'decree'),
    ('federal_banking', date '2026-04-20', true,
      'business_day', 'Vencimento PGDAS-D confirmado pela Agenda RFB', 'rfb'),
    ('federal_banking', date '2026-11-20', false,
      'national_holiday', 'Dia Nacional de Zumbi e da Consciência Negra', 'national')
)
insert into public.municipality_business_calendar (
  municipality_id,
  calendar_scope,
  calendar_date,
  is_business_day,
  day_type,
  description,
  legal_source_version_id,
  verification_status,
  source_snapshot
)
select
  s.municipality_id,
  c.calendar_scope,
  c.calendar_date,
  c.is_business_day,
  c.day_type,
  c.description,
  case
    when c.source_kind = 'rfb' then s.rfb_agenda_version_id
    when c.source_kind = 'national' then s.national_holiday_version_id
    else s.decree_version_id
  end,
  'verified',
  jsonb_build_object(
    'official_source', c.source_kind,
    'scope', c.calendar_scope,
    'backfill_id', 'due-preflight-20260730'
  )
from sources s
cross join calendar_rows c
on conflict (municipality_id, calendar_scope, calendar_date)
do nothing;

create or replace function private.prevent_verified_calendar_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.verification_status = 'verified' then
    raise exception 'verified business calendar rows are immutable; create a new calendar version';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

drop trigger if exists municipality_business_calendar_verified_immutable
  on public.municipality_business_calendar;
create trigger municipality_business_calendar_verified_immutable
before update or delete on public.municipality_business_calendar
for each row execute function private.prevent_verified_calendar_mutation();

with source_version as (
  select
    v.municipality_id,
    v.id as legal_source_version_id
  from public.legal_source_versions v
  join public.legal_sources s
    on s.municipality_id = v.municipality_id
   and s.id = v.source_id
  join public.municipalities m
    on m.id = v.municipality_id
  where m.ibge_code = '3512407'
    and s.official_identifier = 'Lei Complementar nº 399/2024'
    and v.version = 1
  order by v.created_at
  limit 1
),
rule as (
  select
    sv.*,
    jsonb_build_object(
      'competence_month_offset', 1,
      'due_day', 15,
      'business_day_adjustment', 'next_business_day',
      'general_articles', jsonb_build_array('215', '217', '282'),
      'exceptions', jsonb_build_array('216', '218'),
      'classification_basis',
        'user_confirmed_monthly_notes_2026-07-30',
      'holiday_calendar',
        'decree_7096_2025_verified_scope_municipal_service',
      'execution_scope', 'homologation'
    ) as payload
  from source_version sv
),
inserted as (
  insert into public.due_date_rule_versions (
    municipality_id,
    code,
    version,
    tax_code,
    collection_regime,
    competence_month_offset,
    due_day,
    business_day_adjustment,
    exception_policy,
    valid_from,
    legal_source_version_id,
    status,
    rule_payload,
    rule_sha256
  )
  select
    r.municipality_id,
    'cordeiropolis_iss_monthly_due',
    1,
    'ISS-SIGISS',
    'monthly_iss',
    1,
    15,
    'next_business_day',
    'block personal-service assessments and special collection until explicitly classified',
    date '2025-01-01',
    r.legal_source_version_id,
    'active_homologation',
    r.payload,
    encode(
      extensions.digest(
        jsonb_build_object(
          'code', 'cordeiropolis_iss_monthly_due',
          'version', 1,
          'tax_code', 'ISS-SIGISS',
          'collection_regime', 'monthly_iss',
          'competence_month_offset', 1,
          'due_day', 15,
          'business_day_adjustment', 'next_business_day',
          'exception_policy',
            'block personal-service assessments and special collection until explicitly classified',
          'valid_from', date '2025-01-01',
          'legal_source_version_id', r.legal_source_version_id,
          'payload', r.payload
        )::text,
        'sha256'
      ),
      'hex'
    )
  from rule r
  where not exists (
    select 1
    from public.due_date_rule_versions d
    where d.municipality_id = r.municipality_id
      and d.code = 'cordeiropolis_iss_monthly_due'
      and d.version = 1
  )
  returning id
)
select count(*) from inserted;

with source_version as (
  select
    v.municipality_id,
    v.id as legal_source_version_id
  from public.legal_source_versions v
  join public.legal_sources s
    on s.municipality_id = v.municipality_id
   and s.id = v.source_id
  join public.municipalities m
    on m.id = v.municipality_id
  where m.ibge_code = '3512407'
    and s.official_identifier = 'Manual PGDAS-D 2018 v4'
    and v.version = 1
  order by v.created_at
  limit 1
),
rule as (
  select
    sv.*,
    jsonb_build_object(
      'competence_month_offset', 1,
      'due_day', 20,
      'business_day_adjustment', 'next_business_day',
      'calendar_scope', 'federal_banking',
      'classification_source_field', 'source_snapshot.taxpayer_role',
      'classification_source_value', 'Simples',
      'execution_scope', 'homologation',
      'valid_through', '2026-12-31'
    ) as payload
  from source_version sv
)
insert into public.due_date_rule_versions (
  municipality_id,
  code,
  version,
  tax_code,
  collection_regime,
  competence_month_offset,
  due_day,
  business_day_adjustment,
  exception_policy,
  valid_from,
  valid_until,
  legal_source_version_id,
  status,
  rule_payload,
  rule_sha256
)
select
  r.municipality_id,
  'simple_national_das_due',
  1,
  'ISS-SIGISS',
  'simple_national_das',
  1,
  20,
  'next_business_day',
  'apply only when the source record classifies the taxpayer role as Simples',
  date '2018-01-01',
  date '2026-12-31',
  r.legal_source_version_id,
  'active_homologation',
  r.payload,
  encode(
    extensions.digest(
      jsonb_build_object(
        'code', 'simple_national_das_due',
        'version', 1,
        'tax_code', 'ISS-SIGISS',
        'collection_regime', 'simple_national_das',
        'competence_month_offset', 1,
        'due_day', 20,
        'business_day_adjustment', 'next_business_day',
        'exception_policy',
          'apply only when the source record classifies the taxpayer role as Simples',
        'valid_from', date '2018-01-01',
        'valid_until', date '2026-12-31',
        'legal_source_version_id', r.legal_source_version_id,
        'payload', r.payload
      )::text,
      'sha256'
    ),
    'hex'
  )
from rule r
where not exists (
  select 1
  from public.due_date_rule_versions d
  where d.municipality_id = r.municipality_id
    and d.code = 'simple_national_das_due'
    and d.version = 1
);

create or replace function private.prevent_active_due_rule_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.status in ('active_homologation', 'active')
     and (
       new.code,
       new.version,
       new.tax_code,
       new.collection_regime,
       new.competence_month_offset,
       new.due_day,
       new.business_day_adjustment,
       new.exception_policy,
       new.valid_from,
       new.valid_until,
       new.legal_source_version_id,
       new.rule_payload,
       new.rule_sha256
     ) is distinct from (
       old.code,
       old.version,
       old.tax_code,
       old.collection_regime,
       old.competence_month_offset,
       old.due_day,
       old.business_day_adjustment,
       old.exception_policy,
       old.valid_from,
       old.valid_until,
       old.legal_source_version_id,
       old.rule_payload,
       old.rule_sha256
     ) then
    raise exception 'active due-date rule definitions are immutable; create a new version';
  end if;
  return new;
end;
$function$;

drop trigger if exists due_date_rule_versions_active_immutable
  on public.due_date_rule_versions;
create trigger due_date_rule_versions_active_immutable
before update on public.due_date_rule_versions
for each row execute function private.prevent_active_due_rule_mutation();

create table if not exists public.current_account_maturity_classifications (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  current_account_entry_id uuid not null,
  version integer not null check (version > 0),
  maturity_class text not null
    check (maturity_class in (
      'municipal_monthly_iss',
      'simple_national_das',
      'personal_service_assessment',
      'special_collection',
      'unclassified'
    )),
  classification_status text not null
    check (classification_status in (
      'confirmed_homologation',
      'verified',
      'blocked',
      'superseded'
    )),
  classification_source text not null
    check (classification_source in (
      'source_report',
      'user_confirmation',
      'fiscal_review'
    )),
  exception_assessment jsonb not null
    check (jsonb_typeof(exception_assessment) = 'object'),
  evidence_snapshot jsonb not null
    check (jsonb_typeof(evidence_snapshot) = 'object'),
  evidence_sha256 text not null
    check (evidence_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  unique (municipality_id, current_account_entry_id, version),
  unique (municipality_id, id),
  foreign key (municipality_id, current_account_entry_id)
    references public.current_account_entries(municipality_id, id)
    on delete cascade,
  foreign key (municipality_id)
    references public.municipalities(id) on delete cascade
);

create unique index if not exists
  current_account_maturity_classifications_current_uq
on public.current_account_maturity_classifications (
  municipality_id, current_account_entry_id
)
where classification_status in ('confirmed_homologation', 'verified');

alter table public.current_account_maturity_classifications
  enable row level security;

drop policy if exists current_account_maturity_classifications_select
  on public.current_account_maturity_classifications;
create policy current_account_maturity_classifications_select
on public.current_account_maturity_classifications
for select
to authenticated
using (
  (select private.can_manage_municipality(municipality_id))
  or exists (
    select 1
    from public.current_account_entries e
    where e.municipality_id =
      current_account_maturity_classifications.municipality_id
      and e.id =
        current_account_maturity_classifications.current_account_entry_id
      and private.can_access_taxpayer(e.municipality_id, e.taxpayer_id)
  )
);

revoke all on public.current_account_maturity_classifications
  from public, anon, authenticated;
grant select on public.current_account_maturity_classifications
  to authenticated;
grant all on public.current_account_maturity_classifications
  to service_role;

drop trigger if exists current_account_maturity_classifications_audit
  on public.current_account_maturity_classifications;
create trigger current_account_maturity_classifications_audit
after insert or update or delete
on public.current_account_maturity_classifications
for each row execute function private.audit_row_change();

with classified as (
  select
    e.municipality_id,
    e.id as current_account_entry_id,
    case
      when e.source_snapshot->>'taxpayer_role' in ('Prestador', 'Tomador')
        then 'municipal_monthly_iss'
      when e.source_snapshot->>'taxpayer_role' = 'Simples'
        then 'simple_national_das'
      else 'unclassified'
    end as maturity_class,
    jsonb_build_object(
      'source_taxpayer_role', e.source_snapshot->>'taxpayer_role',
      'user_statement',
        'current service-note entries fall due in the following month',
      'municipal_exceptions_considered',
        jsonb_build_array('LC399-art216', 'LC399-art218'),
      'special_regime_indicator_found', false,
      'classification_scope', 'existing_import_batch_only',
      'backfill_id', 'due-preflight-20260730'
    ) as evidence
  from public.current_account_entries e
  join public.municipalities m on m.id = e.municipality_id
  where m.ibge_code = '3512407'
    and e.direction = 'debit'
    and e.entry_kind = 'assessment'
    and e.tax_code = 'ISS-SIGISS'
)
insert into public.current_account_maturity_classifications (
  municipality_id,
  current_account_entry_id,
  version,
  maturity_class,
  classification_status,
  classification_source,
  exception_assessment,
  evidence_snapshot,
  evidence_sha256
)
select
  c.municipality_id,
  c.current_account_entry_id,
  1,
  c.maturity_class,
  case
    when c.maturity_class = 'unclassified' then 'blocked'
    else 'confirmed_homologation'
  end,
  'user_confirmation',
  jsonb_build_object(
    'personal_service_assessment',
      case when c.maturity_class = 'unclassified'
        then 'unresolved' else 'not_indicated_in_source_and_user_confirmed_monthly' end,
    'special_collection',
      case when c.maturity_class = 'unclassified'
        then 'unresolved' else 'not_indicated_in_source_and_user_confirmed_monthly' end
  ),
  c.evidence,
  encode(extensions.digest(c.evidence::text, 'sha256'), 'hex')
from classified c
on conflict (municipality_id, current_account_entry_id, version)
do nothing;

drop trigger if exists current_account_maturity_classifications_immutable
  on public.current_account_maturity_classifications;
create trigger current_account_maturity_classifications_immutable
before update or delete on public.current_account_maturity_classifications
for each row execute function private.prevent_any_mutation();

-- ---------------------------------------------------------------------------
-- 2. Derivation metadata on current-account entries and audited backfill.
-- ---------------------------------------------------------------------------

alter table public.current_account_entries
  add column if not exists nominal_due_on date,
  add column if not exists due_date_rule_version_id uuid,
  add column if not exists due_date_status text not null default 'missing',
  add column if not exists due_date_evidence jsonb not null default '{}'::jsonb;

alter table public.current_account_entries
  drop constraint if exists current_account_entries_due_date_status_ck,
  add constraint current_account_entries_due_date_status_ck
    check (due_date_status in (
      'missing',
      'source_report',
      'calculated_calendar_pending',
      'calculated_confirmed',
      'manual_verified',
      'blocked_exception',
      'not_applicable_credit'
    )),
  drop constraint if exists current_account_entries_due_date_evidence_ck,
  add constraint current_account_entries_due_date_evidence_ck
    check (jsonb_typeof(due_date_evidence) = 'object'),
  drop constraint if exists current_account_entries_due_date_rule_fk,
  add constraint current_account_entries_due_date_rule_fk
    foreign key (municipality_id, due_date_rule_version_id)
    references public.due_date_rule_versions(municipality_id, id);

create index if not exists current_account_entries_maturity_v3_idx
  on public.current_account_entries (
    municipality_id,
    due_on,
    status,
    direction,
    taxpayer_id,
    competence_month
  );

with classified as (
  select
    e.id,
    e.municipality_id,
    e.competence_month,
    e.source_snapshot->>'taxpayer_role' as taxpayer_role,
    mc.maturity_class,
    mc.id as maturity_classification_id,
    mc.evidence_sha256 as maturity_classification_sha256,
    case
      when mc.maturity_class = 'municipal_monthly_iss'
        then 'cordeiropolis_iss_monthly_due'
      when mc.maturity_class = 'simple_national_das'
        then 'simple_national_das_due'
      else null
    end as rule_code,
    case
      when mc.maturity_class = 'municipal_monthly_iss'
        then 'municipal_service'
      when mc.maturity_class = 'simple_national_das'
        then 'federal_banking'
      else null
    end as calendar_scope
  from public.current_account_entries e
  join public.municipalities m on m.id = e.municipality_id
  left join public.current_account_maturity_classifications mc
    on mc.municipality_id = e.municipality_id
   and mc.current_account_entry_id = e.id
   and mc.classification_status in ('confirmed_homologation', 'verified')
  where m.ibge_code = '3512407'
    and e.direction = 'debit'
    and e.entry_kind = 'assessment'
    and e.tax_code = 'ISS-SIGISS'
),
resolved as (
  select
    c.*,
    r.id as rule_id,
    r.version,
    r.competence_month_offset,
    r.due_day,
    r.legal_source_version_id,
    (
      date_trunc('month', c.competence_month)
      + make_interval(months => r.competence_month_offset)
      + make_interval(days => r.due_day - 1)
    )::date as nominal_due
  from classified c
  join public.due_date_rule_versions r
    on r.municipality_id = c.municipality_id
   and r.code = c.rule_code
   and r.version = 1
   and r.status = 'active_homologation'
   and c.competence_month >= r.valid_from
   and (r.valid_until is null or c.competence_month <= r.valid_until)
)
update public.current_account_entries e
set
  nominal_due_on = r.nominal_due,
  due_on = private.ia_next_business_day(
    e.municipality_id,
    r.calendar_scope,
    r.nominal_due
  ),
  due_date_rule_version_id = r.rule_id,
  due_date_status = 'calculated_confirmed',
  due_date_evidence = jsonb_build_object(
    'rule_code', r.rule_code,
    'rule_version', r.version,
    'legal_source_version_id', r.legal_source_version_id,
    'source_taxpayer_role', r.taxpayer_role,
    'maturity_class', r.maturity_class,
    'maturity_classification_id', r.maturity_classification_id,
    'maturity_classification_sha256', r.maturity_classification_sha256,
    'calendar_scope', r.calendar_scope,
    'classification',
      case
        when r.rule_code = 'simple_national_das_due'
          then 'simple_national_pgdas_d'
        else 'municipal_monthly_iss_from_service_notes'
      end,
    'classification_basis', 'user_authorized_2026-07-30',
    'business_day_logic', 'verified_scoped_calendar_then_weekend',
    'official_calendar_sources',
      case
        when r.calendar_scope = 'municipal_service'
          then jsonb_build_array('LC 399/2024', 'Decreto 7.096/2025')
        else jsonb_build_array('Manual PGDAS-D 2018 v4', 'Agenda RFB 2026')
      end,
    'exception_guard',
      case
        when r.calendar_scope = 'municipal_service'
          then 'source role restricted to corporate Prestador/Tomador; arts 216/218 require separate rule'
        else 'source role explicitly Simples'
      end,
    'backfill_id', 'due-preflight-20260730'
  )
from resolved r
where e.municipality_id = r.municipality_id
  and e.id = r.id;

update public.current_account_entries e
set
  nominal_due_on = null,
  due_on = null,
  due_date_rule_version_id = null,
  due_date_status = 'blocked_exception',
  due_date_evidence = jsonb_build_object(
    'reason', 'unclassified_taxpayer_role_or_special_collection',
    'source_taxpayer_role', e.source_snapshot->>'taxpayer_role',
    'exception_articles', jsonb_build_array('216', '218'),
    'backfill_id', 'due-preflight-20260730'
  )
from public.municipalities m
where m.id = e.municipality_id
  and m.ibge_code = '3512407'
  and e.direction = 'debit'
  and e.entry_kind = 'assessment'
  and e.tax_code = 'ISS-SIGISS'
  and not exists (
    select 1
    from public.current_account_maturity_classifications mc
    where mc.municipality_id = e.municipality_id
      and mc.current_account_entry_id = e.id
      and mc.classification_status in (
        'confirmed_homologation', 'verified'
      )
      and mc.maturity_class in (
        'municipal_monthly_iss', 'simple_national_das'
      )
  );

update public.current_account_entries e
set
  due_date_status = 'not_applicable_credit',
  due_date_evidence = jsonb_build_object(
    'reason', 'credit_or_payment_has_no_tax_due_date',
    'backfill_id', 'due-preflight-20260730'
  )
from public.municipalities m
where m.id = e.municipality_id
  and m.ibge_code = '3512407'
  and e.direction = 'credit';

-- Maturity consumers fail closed: only explicitly confirmed dates may enter
-- ranking, divergence detection or case preparation.
create or replace view public.vw_current_account_period
with (security_invoker = true)
as
with dated_entries as (
  select
    e.*,
    (clock_timestamp() at time zone m.timezone)::date as business_date,
    exists (
      select 1
      from public.current_account_maturity_classifications mc
      where mc.municipality_id = e.municipality_id
        and mc.current_account_entry_id = e.id
        and mc.classification_status in (
          'confirmed_homologation', 'verified'
        )
        and mc.maturity_class in (
          'municipal_monthly_iss',
          'simple_national_das',
          'personal_service_assessment',
          'special_collection'
        )
    ) as maturity_classified
  from public.current_account_entries e
  join public.municipalities m on m.id = e.municipality_id
),
period_amounts as (
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
        and e.due_date_status in (
          'source_report', 'calculated_confirmed', 'manual_verified'
        )
        and e.maturity_classified
        and e.due_on <= e.business_date
    ), 0)::numeric(18,2) as valor_vencido,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and (
          e.due_on is null
          or e.due_date_status not in (
            'source_report', 'calculated_confirmed', 'manual_verified'
          )
          or not e.maturity_classified
        )
    ), 0)::numeric(18,2) as valor_sem_vencimento,
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit'
        and e.status = 'valid'
        and e.due_date_status in (
          'source_report', 'calculated_confirmed', 'manual_verified'
        )
        and e.maturity_classified
        and e.due_on > e.business_date
    ), 0)::numeric(18,2) as valor_a_vencer,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind = 'payment'
        and e.status = 'valid'
        and e.occurred_on <= e.business_date
    ), 0)::numeric(18,2) as valor_pago,
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind <> 'payment'
        and e.status = 'valid'
        and e.occurred_on <= e.business_date
    ), 0)::numeric(18,2) as outros_creditos,
    min(e.due_on) filter (
      where e.direction = 'debit'
        and e.due_date_status in (
          'source_report', 'calculated_confirmed', 'manual_verified'
        )
        and e.maturity_classified
    ) as primeiro_vencimento,
    max(e.due_on) filter (
      where e.direction = 'debit'
        and e.due_date_status in (
          'source_report', 'calculated_confirmed', 'manual_verified'
        )
        and e.maturity_classified
    ) as ultimo_vencimento,
    max(e.imported_at) as data_base,
    count(distinct e.source_system_id) as qtd_fontes
  from dated_entries e
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
    p.valor_vencido - p.valor_pago - p.outros_creditos, 0
  )::numeric(18,2) as saldo_em_aberto,
  greatest(
    p.valor_vencido - p.valor_pago - p.outros_creditos, 0
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
  'current-account-maturity-v3'::text as regra_versao,
  p.data_base,
  p.qtd_fontes,
  p.valor_vencido,
  p.valor_sem_vencimento,
  p.valor_a_vencer,
  greatest(
    p.valor_emitido - p.valor_pago - p.outros_creditos, 0
  )::numeric(18,2) as saldo_reportado,
  p.primeiro_vencimento,
  p.ultimo_vencimento
from period_amounts p
join public.taxpayers t
  on t.municipality_id = p.municipality_id
 and t.id = p.taxpayer_id;

revoke all on public.vw_current_account_period from anon, authenticated;
grant select on public.vw_current_account_period
  to authenticated, service_role;

comment on view public.vw_current_account_period is
  'Conta corrente v3: somente vencimentos com status confirmado entram em ranking, divergência ou processo.';

-- ---------------------------------------------------------------------------
-- 3. Separate relationship, verification and delivery states.
-- ---------------------------------------------------------------------------

alter table public.taxpayer_accountant_links
  add column if not exists relationship_status text not null default 'proposed',
  add column if not exists verification_status text not null default 'unverified',
  add column if not exists delivery_status text not null default 'blocked';

alter table public.taxpayer_accountant_links
  drop constraint if exists taxpayer_accountant_links_relationship_status_ck,
  add constraint taxpayer_accountant_links_relationship_status_ck
    check (relationship_status in (
      'proposed',
      'linked',
      'ended',
      'rejected'
    )),
  drop constraint if exists taxpayer_accountant_links_verification_status_ck,
  add constraint taxpayer_accountant_links_verification_status_ck
    check (verification_status in (
      'unverified',
      'verified',
      'rejected',
      'expired'
    )),
  drop constraint if exists taxpayer_accountant_links_delivery_status_ck,
  add constraint taxpayer_accountant_links_delivery_status_ck
    check (delivery_status in (
      'blocked',
      'blocked_unverified_contact',
      'eligible',
      'revoked'
    )),
  drop constraint if exists taxpayer_accountant_links_delivery_guard_ck,
  add constraint taxpayer_accountant_links_delivery_guard_ck
    check (
      delivery_status <> 'eligible'
      or (
        relationship_status = 'linked'
        and verification_status = 'verified'
        and status = 'active'
        and verified_at is not null
        and can_receive_initial_notice
      )
    );

update public.taxpayer_accountant_links l
set
  relationship_status = 'linked',
  verification_status = case
    when l.status = 'active' and l.verified_at is not null
      then 'verified'
    else 'unverified'
  end,
  delivery_status = case
    when l.status = 'active'
      and l.verified_at is not null
      and l.can_receive_initial_notice
      then 'eligible'
    else 'blocked_unverified_contact'
  end,
  validation_metadata = l.validation_metadata || jsonb_build_object(
    'relationship_promoted_at', now(),
    'relationship_promotion_basis',
      'user_authorized_linkage_2026-07-30',
    'contact_verification_preserved', true,
    'external_delivery_preserved_blocked', true
  )
from public.municipalities m
where m.id = l.municipality_id
  and m.ibge_code = '3512407'
  and l.relationship_status = 'proposed';

-- Keep the legacy status quarantined until documentary verification. The new
-- relationship_status now represents the operational link requested by the
-- user without falsely verifying the contact or enabling delivery.
create or replace view public.vw_taxpayer_responsibilities_visible
with (security_invoker = true)
as
select
  l.municipality_id,
  l.taxpayer_id,
  l.id as link_id,
  l.accounting_firm_id,
  af.legal_name as responsible_name,
  case
    when af.tax_id is null then null
    else
      left(regexp_replace(af.tax_id, '[^0-9]', '', 'g'), 2)
      || '********'
      || right(regexp_replace(af.tax_id, '[^0-9]', '', 'g'), 4)
  end as masked_document,
  case
    when pc.value is null then null
    when position('@' in pc.value) > 2
      then left(pc.value, 2) || '***@' || split_part(pc.value, '@', 2)
    else '***'
  end as masked_email,
  l.status as link_status,
  l.quarantine_reason as link_quarantine_reason,
  l.visible_in_homologation,
  l.valid_from,
  l.valid_until,
  l.verified_at as link_verified_at,
  pc.status as contact_status,
  pc.quarantine_reason as contact_quarantine_reason,
  pc.verified_at as contact_verified_at,
  (
    l.relationship_status = 'linked'
    and l.verification_status = 'verified'
    and l.delivery_status = 'eligible'
    and l.status = 'active'
    and l.verified_at is not null
    and l.valid_from <= now()
    and (l.valid_until is null or l.valid_until > now())
    and pc.status = 'verified'
    and pc.verified_at is not null
    and pc.valid_from <= now()
    and (pc.valid_until is null or pc.valid_until > now())
  ) as safe_for_delivery,
  l.relationship_status,
  l.verification_status,
  l.delivery_status
from public.taxpayer_accountant_links l
join public.accounting_firms af
  on af.municipality_id = l.municipality_id
 and af.id = l.accounting_firm_id
left join lateral (
  select c.*
  from public.party_contacts c
  where c.municipality_id = l.municipality_id
    and c.accounting_firm_id = l.accounting_firm_id
    and c.contact_type = 'email'
    and (c.status = 'verified' or c.visible_in_homologation)
  order by
    (c.status = 'verified') desc,
    c.is_primary desc,
    c.created_at desc
  limit 1
) pc on true
where l.relationship_status = 'linked'
   or l.visible_in_homologation;

revoke all on public.vw_taxpayer_responsibilities_visible
  from public, anon;
grant select on public.vw_taxpayer_responsibilities_visible
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Notification template and blocked recipient candidates.
-- ---------------------------------------------------------------------------

create table if not exists public.notification_recipient_candidates (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  proposed_for text not null
    check (proposed_for = 'initial_inspection_alert'),
  recipient_type text not null
    check (recipient_type in ('taxpayer', 'accountant')),
  contact_id uuid not null,
  taxpayer_accountant_link_id uuid,
  candidate_status text not null default 'blocked_unverified'
    check (candidate_status in (
      'blocked_unverified',
      'eligible_after_verification',
      'rejected',
      'expired'
    )),
  delivery_block_reason text,
  priority smallint not null default 100
    check (priority between 1 and 1000),
  relationship_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(relationship_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (
    municipality_id,
    taxpayer_id,
    proposed_for,
    recipient_type,
    contact_id
  ),
  unique (municipality_id, id),
  check (
    (recipient_type = 'taxpayer' and taxpayer_accountant_link_id is null)
    or
    (recipient_type = 'accountant' and taxpayer_accountant_link_id is not null)
  ),
  check (
    candidate_status <> 'eligible_after_verification'
    or nullif(trim(delivery_block_reason), '') is null
  ),
  foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  foreign key (municipality_id, contact_id)
    references public.party_contacts(municipality_id, id),
  foreign key (municipality_id, taxpayer_accountant_link_id)
    references public.taxpayer_accountant_links(municipality_id, id)
);

create index if not exists notification_recipient_candidates_search_idx
  on public.notification_recipient_candidates (
    municipality_id,
    taxpayer_id,
    candidate_status,
    recipient_type
  );

alter table public.notification_recipient_candidates enable row level security;

drop policy if exists notification_recipient_candidates_select
  on public.notification_recipient_candidates;
create policy notification_recipient_candidates_select
on public.notification_recipient_candidates
for select
to authenticated
using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));
-- Municipal administrators may inspect the preflight list even when they are
-- not assigned to each taxpayer.
drop policy if exists notification_recipient_candidates_select
  on public.notification_recipient_candidates;
create policy notification_recipient_candidates_select
on public.notification_recipient_candidates
for select
to authenticated
using (
  (select private.can_manage_municipality(municipality_id))
  or (select private.can_access_taxpayer(municipality_id, taxpayer_id))
);

revoke all on public.notification_recipient_candidates
  from public, anon, authenticated;
grant select on public.notification_recipient_candidates to authenticated;
grant all on public.notification_recipient_candidates to service_role;

drop trigger if exists notification_recipient_candidates_set_updated_at
  on public.notification_recipient_candidates;
create trigger notification_recipient_candidates_set_updated_at
before update on public.notification_recipient_candidates
for each row execute function private.set_updated_at();

drop trigger if exists notification_recipient_candidates_immutable_identity
  on public.notification_recipient_candidates;
create trigger notification_recipient_candidates_immutable_identity
before update on public.notification_recipient_candidates
for each row execute function private.prevent_tenant_or_id_change();

create or replace function private.validate_notification_recipient_candidate()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_contact public.party_contacts%rowtype;
  v_link public.taxpayer_accountant_links%rowtype;
begin
  select *
    into v_contact
  from public.party_contacts c
  where c.municipality_id = new.municipality_id
    and c.id = new.contact_id;

  if not found or v_contact.contact_type <> 'email' then
    raise exception 'recipient candidate requires a tenant-matched email contact';
  end if;

  if new.recipient_type = 'taxpayer' then
    if v_contact.taxpayer_id is distinct from new.taxpayer_id
       or v_contact.accounting_firm_id is not null
       or new.taxpayer_accountant_link_id is not null then
      raise exception 'taxpayer candidate contact does not belong to taxpayer';
    end if;
  else
    select *
      into v_link
    from public.taxpayer_accountant_links l
    where l.municipality_id = new.municipality_id
      and l.id = new.taxpayer_accountant_link_id
      and l.taxpayer_id = new.taxpayer_id;

    if not found
       or v_contact.accounting_firm_id is distinct from v_link.accounting_firm_id
       or v_contact.taxpayer_id is not null then
      raise exception 'accountant candidate contact does not match the linked firm';
    end if;
  end if;

  if new.candidate_status = 'eligible_after_verification' then
    if v_contact.status <> 'verified'
       or v_contact.verified_at is null
       or v_contact.valid_from > now()
       or (v_contact.valid_until is not null and v_contact.valid_until <= now())
       or (
         new.recipient_type = 'accountant'
         and (
           v_link.relationship_status <> 'linked'
           or v_link.verification_status <> 'verified'
           or v_link.delivery_status <> 'eligible'
           or v_link.status <> 'active'
           or not v_link.can_receive_initial_notice
           or v_link.valid_from > now()
           or (v_link.valid_until is not null and v_link.valid_until <= now())
         )
       ) then
      raise exception 'candidate cannot be promoted before contact and relationship verification';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists notification_recipient_candidates_validate
  on public.notification_recipient_candidates;
create trigger notification_recipient_candidates_validate
before insert or update on public.notification_recipient_candidates
for each row execute function private.validate_notification_recipient_candidate();

drop trigger if exists notification_recipient_candidates_audit
  on public.notification_recipient_candidates;
create trigger notification_recipient_candidates_audit
after insert or update or delete on public.notification_recipient_candidates
for each row execute function private.audit_row_change();

with municipality as (
  select id
  from public.municipalities
  where ibge_code = '3512407'
),
taxpayer_candidates as (
  select
    t.municipality_id,
    t.id as taxpayer_id,
    'taxpayer'::text as recipient_type,
    tc.id as contact_id,
    null::uuid as taxpayer_accountant_link_id,
    null::uuid as source_link_id,
    'not_applicable'::text as relationship_status,
    'not_applicable'::text as verification_status,
    tc.status as contact_status
  from public.taxpayers t
  join municipality m on m.id = t.municipality_id
  join lateral (
    select c.*
    from public.party_contacts c
    where c.municipality_id = t.municipality_id
      and c.taxpayer_id = t.id
      and c.contact_type = 'email'
      and c.visible_in_homologation
      and c.valid_from <= now()
      and (c.valid_until is null or c.valid_until > now())
    order by c.is_primary desc, c.created_at desc
    limit 1
  ) tc on true
  where t.status = 'active'
),
accountant_candidates as (
  select
    l.municipality_id,
    l.taxpayer_id,
    'accountant'::text as recipient_type,
    ac.id as contact_id,
    l.id as taxpayer_accountant_link_id,
    l.id as source_link_id,
    l.relationship_status,
    l.verification_status,
    ac.status as contact_status
  from public.taxpayer_accountant_links l
  join municipality m on m.id = l.municipality_id
  join lateral (
    select c.*
    from public.party_contacts c
    where c.municipality_id = l.municipality_id
      and c.accounting_firm_id = l.accounting_firm_id
      and c.contact_type = 'email'
      and c.visible_in_homologation
      and c.valid_from <= now()
      and (c.valid_until is null or c.valid_until > now())
    order by c.is_primary desc, c.created_at desc
    limit 1
  ) ac on true
  where l.relationship_status = 'linked'
    and l.valid_from <= now()
    and (l.valid_until is null or l.valid_until > now())
),
candidates as (
  select * from taxpayer_candidates
  union all
  select * from accountant_candidates
)
insert into public.notification_recipient_candidates (
  municipality_id,
  taxpayer_id,
  proposed_for,
  recipient_type,
  contact_id,
  taxpayer_accountant_link_id,
  candidate_status,
  delivery_block_reason,
  priority,
  relationship_snapshot
)
select
  c.municipality_id,
  c.taxpayer_id,
  'initial_inspection_alert',
  c.recipient_type,
  c.contact_id,
  c.taxpayer_accountant_link_id,
  'blocked_unverified',
  concat_ws(
    ';',
    case
      when c.recipient_type = 'accountant'
        and c.verification_status <> 'verified'
        then 'relationship_unverified'
    end,
    case
      when c.contact_status <> 'verified'
        then 'contact_unverified'
    end,
    'external_delivery_not_authorized'
  ),
  case when c.recipient_type = 'taxpayer' then 10 else 20 end,
  jsonb_build_object(
    'source_link_id', c.source_link_id,
    'relationship_status', c.relationship_status,
    'relationship_verification_status', c.verification_status,
    'contact_status', c.contact_status,
    'prepared_for_homologation', true,
    'external_delivery_authorized', false
  )
from candidates c
on conflict (
  municipality_id,
  taxpayer_id,
  proposed_for,
  recipient_type,
  contact_id
) do update
set
  taxpayer_accountant_link_id =
    excluded.taxpayer_accountant_link_id,
  candidate_status = 'blocked_unverified',
  delivery_block_reason = excluded.delivery_block_reason,
  priority = excluded.priority,
  relationship_snapshot = excluded.relationship_snapshot
where public.notification_recipient_candidates.candidate_status =
  'blocked_unverified';

-- Any superseded candidate remains auditable but cannot be selected.
with current_candidates as (
  select
    t.municipality_id,
    t.id as taxpayer_id,
    tc.id as contact_id
  from public.taxpayers t
  join public.municipalities m
    on m.id = t.municipality_id
   and m.ibge_code = '3512407'
  join lateral (
    select c.id
    from public.party_contacts c
    where c.municipality_id = t.municipality_id
      and c.taxpayer_id = t.id
      and c.contact_type = 'email'
      and c.visible_in_homologation
      and c.valid_from <= now()
      and (c.valid_until is null or c.valid_until > now())
    order by c.is_primary desc, c.created_at desc
    limit 1
  ) tc on true
),
current_accountant_candidates as (
  select
    l.municipality_id,
    l.taxpayer_id,
    ac.id as contact_id
  from public.taxpayer_accountant_links l
  join public.municipalities m
    on m.id = l.municipality_id
   and m.ibge_code = '3512407'
  join lateral (
    select c.id
    from public.party_contacts c
    where c.municipality_id = l.municipality_id
      and c.accounting_firm_id = l.accounting_firm_id
      and c.contact_type = 'email'
      and c.visible_in_homologation
      and c.valid_from <= now()
      and (c.valid_until is null or c.valid_until > now())
    order by c.is_primary desc, c.created_at desc
    limit 1
  ) ac on true
  where l.relationship_status = 'linked'
    and l.valid_from <= now()
    and (l.valid_until is null or l.valid_until > now())
)
update public.notification_recipient_candidates c
set
  candidate_status = 'expired',
  delivery_block_reason = 'superseded_contact_or_relationship',
  relationship_snapshot = c.relationship_snapshot || jsonb_build_object(
    'expired_at', now(),
    'expiration_reason', 'superseded_contact_or_relationship'
  )
from public.municipalities m
where m.id = c.municipality_id
  and m.ibge_code = '3512407'
  and c.candidate_status = 'blocked_unverified'
  and (
    (
      c.recipient_type = 'taxpayer'
      and not exists (
        select 1
        from current_candidates x
        where x.municipality_id = c.municipality_id
          and x.taxpayer_id = c.taxpayer_id
          and x.contact_id = c.contact_id
      )
    )
    or
    (
      c.recipient_type = 'accountant'
      and not exists (
        select 1
        from current_accountant_candidates x
        where x.municipality_id = c.municipality_id
          and x.taxpayer_id = c.taxpayer_id
          and x.contact_id = c.contact_id
      )
    )
  );

create or replace view public.vw_notification_recipient_candidates
with (security_invoker = true)
as
select
  c.municipality_id,
  c.taxpayer_id,
  c.id as candidate_id,
  c.proposed_for,
  c.recipient_type,
  c.contact_id,
  c.taxpayer_accountant_link_id,
  case
    when position('@' in pc.normalized_value::text) > 1
      then left(split_part(pc.normalized_value::text, '@', 1), 2)
        || '***@'
        || split_part(pc.normalized_value::text, '@', 2)
    else '***'
  end as masked_email,
  c.candidate_status,
  c.delivery_block_reason,
  c.priority,
  (
    c.candidate_status = 'eligible_after_verification'
    and pc.status = 'verified'
    and pc.verified_at is not null
    and pc.valid_from <= now()
    and (pc.valid_until is null or pc.valid_until > now())
    and t.status = 'active'
    and (
      (
        c.recipient_type = 'taxpayer'
        and pc.taxpayer_id = c.taxpayer_id
        and pc.accounting_firm_id is null
      )
      or (
        c.recipient_type = 'accountant'
        and l.taxpayer_id = c.taxpayer_id
        and pc.accounting_firm_id = l.accounting_firm_id
        and pc.taxpayer_id is null
        and l.relationship_status = 'linked'
        and l.verification_status = 'verified'
        and l.delivery_status = 'eligible'
        and l.status = 'active'
        and l.can_receive_initial_notice
        and l.valid_from <= now()
        and (l.valid_until is null or l.valid_until > now())
      )
    )
  ) as ready_pending_external_authorization,
  false as safe_for_delivery,
  false as external_delivery_authorized,
  c.created_at,
  c.updated_at
from public.notification_recipient_candidates c
join public.party_contacts pc
  on pc.municipality_id = c.municipality_id
 and pc.id = c.contact_id
join public.taxpayers t
  on t.municipality_id = c.municipality_id
 and t.id = c.taxpayer_id
left join public.taxpayer_accountant_links l
  on l.municipality_id = c.municipality_id
 and l.id = c.taxpayer_accountant_link_id
 and l.taxpayer_id = c.taxpayer_id;

revoke all on public.vw_notification_recipient_candidates
  from public, anon;
grant select on public.vw_notification_recipient_candidates
  to authenticated, service_role;

with template as (
  select t.municipality_id, t.id
  from public.notification_templates t
  join public.municipalities m on m.id = t.municipality_id
  where m.ibge_code = '3512407'
    and t.code = 'initial_inspection_alert_sandbox'
  order by t.created_at
  limit 1
),
content as (
  select
    'Aviso inicial para conferência fiscal — {{municipality_name}}'
      as subject,
    'Prezado contribuinte ou representante,' || E'\n\n'
    || 'Em verificação de rotina, foram identificados registros que precisam '
    || 'de conferência no ambiente autenticado de {{municipality_name}}. '
    || 'Este aviso tem natureza exclusivamente informativa: não constitui '
    || 'notificação fiscal formal, lançamento definitivo, acusação de infração '
    || 'ou conclusão de fraude.' || E'\n\n'
    || 'Consulte a composição no ambiente autenticado. Caso já exista '
    || 'pagamento, parcelamento, compensação, suspensão ou contestação, '
    || 'apresente os comprovantes pelo canal oficial do Município.' || E'\n\n'
    || 'Por segurança, valores, documentos fiscais e dados pessoais não são '
    || 'detalhados neste e-mail. O envio somente poderá ocorrer após validação '
    || 'do destinatário e autorização expressa do fluxo de comunicação.'
      as body_text
),
inserted as (
  insert into public.notification_template_versions (
    municipality_id,
    template_id,
    version,
    status,
    subject,
    body_text,
    body_html,
    allowed_placeholders,
    content_sha256
  )
  select
    t.municipality_id,
    t.id,
    2,
    'draft',
    c.subject,
    c.body_text,
    null,
    array['municipality_name']::text[],
    encode(
      extensions.digest(
        c.subject || E'\n' || c.body_text
        || E'\nmunicipality_name',
        'sha256'
      ),
      'hex'
    )
  from template t
  cross join content c
  where not exists (
    select 1
    from public.notification_template_versions v
    where v.municipality_id = t.municipality_id
      and v.template_id = t.id
      and v.version = 2
  )
  returning id
)
select count(*) from inserted;

-- No notification_recipients rows are created here. Candidates are references
-- only, all blocked, and cannot enter the delivery queue.

