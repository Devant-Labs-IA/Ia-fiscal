-- IA Fiscal 009
-- Restores PGDAS-D, Factor R, RBT12 and tax-base cross-checks to the MVP.
-- Adds a strictly isolated homologation execution path and visible quarantine.

alter table public.party_contacts
  add column if not exists quarantine_reason text,
  add column if not exists visible_in_homologation boolean not null default true,
  add column if not exists verification_metadata jsonb not null default '{}'::jsonb;

alter table public.party_contacts
  drop constraint if exists party_contacts_status_check,
  add constraint party_contacts_status_check
    check (status in ('unverified', 'quarantined', 'verified', 'invalid', 'revoked')),
  add constraint party_contacts_verification_metadata_ck
    check (jsonb_typeof(verification_metadata) = 'object'),
  add constraint party_contacts_quarantine_ck
    check (status <> 'quarantined' or nullif(trim(quarantine_reason), '') is not null);

alter table public.taxpayer_accountant_links
  add column if not exists quarantine_reason text,
  add column if not exists visible_in_homologation boolean not null default true,
  add column if not exists validation_metadata jsonb not null default '{}'::jsonb;

alter table public.taxpayer_accountant_links
  drop constraint if exists taxpayer_accountant_links_status_check,
  add constraint taxpayer_accountant_links_status_check
    check (status in ('pending', 'quarantined', 'active', 'suspended', 'revoked', 'expired')),
  add constraint taxpayer_accountant_links_validation_metadata_ck
    check (jsonb_typeof(validation_metadata) = 'object'),
  add constraint taxpayer_accountant_links_quarantine_ck
    check (status <> 'quarantined' or nullif(trim(quarantine_reason), '') is not null);

alter table public.divergence_rules
  drop constraint if exists divergence_rules_divergence_type_check,
  add constraint divergence_rules_divergence_type_check
    check (divergence_type in (
      'current_account_balance',
      'pgdasd_sigiss_annex',
      'pgdasd_sigiss_tax_base',
      'pgdasd_rbt12',
      'factor_r'
    ));

alter table public.divergences
  add column if not exists execution_mode text not null default 'live',
  drop constraint if exists divergences_divergence_type_check,
  add constraint divergences_divergence_type_check
    check (divergence_type in (
      'current_account_balance',
      'pgdasd_sigiss_annex',
      'pgdasd_sigiss_tax_base',
      'pgdasd_rbt12',
      'factor_r'
    )),
  add constraint divergences_execution_mode_ck
    check (execution_mode in ('live', 'homologation_test'));

alter table public.detection_runs
  add column if not exists execution_mode text not null default 'live',
  add constraint detection_runs_execution_mode_ck
    check (execution_mode in ('live', 'homologation_test'));

alter table public.case_opening_batches
  add column if not exists execution_mode text not null default 'live',
  add column if not exists approved_system_actor text,
  drop constraint if exists case_opening_batches_approval_ck,
  add constraint case_opening_batches_execution_mode_ck
    check (execution_mode in ('live', 'homologation_test')),
  add constraint case_opening_batches_approval_ck
    check (
      status not in ('approved', 'processing', 'completed')
      or (
        approved_at is not null
        and (
          approved_by is not null
          or (
            execution_mode = 'homologation_test'
            and nullif(trim(approved_system_actor), '') is not null
          )
        )
      )
    );

alter table public.fiscal_cases
  add column if not exists execution_mode text not null default 'live',
  add constraint fiscal_cases_execution_mode_ck
    check (execution_mode in ('live', 'homologation_test'));

alter table public.notifications
  add column if not exists execution_mode text not null default 'live',
  add constraint notifications_execution_mode_ck
    check (execution_mode in ('live', 'homologation_test'));

create table if not exists public.project_source_documents (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  source_kind text not null check (source_kind in (
    'canonical_memory', 'workflow', 'transcript', 'video',
    'fiscal_report', 'taxpayer_registry', 'supporting_document'
  )),
  title text not null,
  drive_file_id text not null,
  drive_url text not null,
  mime_type text not null,
  size_bytes bigint,
  modified_at timestamptz,
  classification text not null default 'restricted'
    check (classification in ('internal', 'restricted', 'highly_restricted')),
  ingestion_status text not null default 'registered'
    check (ingestion_status in (
      'registered', 'text_extracted', 'structured_imported',
      'analyzed', 'failed', 'superseded'
    )),
  scope_status text not null default 'supporting'
    check (scope_status in ('canonical', 'approved', 'supporting', 'historical', 'rejected')),
  source_sha256 text,
  extraction_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_source_documents_tenant_id_uq unique (municipality_id, id),
  constraint project_source_documents_drive_uq unique (municipality_id, drive_file_id),
  constraint project_source_documents_size_ck check (size_bytes is null or size_bytes >= 0),
  constraint project_source_documents_sha_ck
    check (source_sha256 is null or source_sha256 ~ '^[a-f0-9]{64}$'),
  constraint project_source_documents_metadata_ck
    check (jsonb_typeof(extraction_metadata) = 'object')
);

create table if not exists private.project_source_document_contents (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  document_id uuid not null,
  content_format text not null check (content_format in ('plain_text', 'markdown', 'json', 'summary')),
  extracted_text text not null,
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  extractor_version text not null,
  created_at timestamptz not null default now(),
  constraint project_source_document_contents_document_fk
    foreign key (municipality_id, document_id)
    references public.project_source_documents(municipality_id, id)
    on delete cascade,
  constraint project_source_document_contents_document_uq
    unique (municipality_id, document_id, content_format, content_sha256)
);

create table if not exists public.pgdasd_declarations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  source_system_id uuid not null,
  import_batch_id uuid,
  external_record_id text not null,
  competence_month date not null,
  receipt_number text,
  declaration_status text not null default 'original'
    check (declaration_status in ('original', 'rectified', 'cancelled')),
  accounting_regime text not null default 'accrual'
    check (accounting_regime in ('cash', 'accrual')),
  total_revenue_declared numeric(18,2) not null default 0 check (total_revenue_declared >= 0),
  total_tax_base_declared numeric(18,2) not null default 0 check (total_tax_base_declared >= 0),
  iss_tax_base_declared numeric(18,2) not null default 0 check (iss_tax_base_declared >= 0),
  iss_due_declared numeric(18,2) not null default 0 check (iss_due_declared >= 0),
  rbt12_declared numeric(18,2) check (rbt12_declared is null or rbt12_declared >= 0),
  fs12_declared numeric(18,2) check (fs12_declared is null or fs12_declared >= 0),
  factor_r_declared numeric(12,8) check (
    factor_r_declared is null or factor_r_declared between 0 and 100
  ),
  transmitted_at timestamptz,
  data_origin text not null default 'official_import'
    check (data_origin in ('official_import', 'manual', 'synthetic_test')),
  is_test boolean not null default false,
  source_snapshot jsonb not null default '{}'::jsonb,
  payload_sha256 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pgdasd_declarations_tenant_id_uq unique (municipality_id, id),
  constraint pgdasd_declarations_external_uq
    unique (municipality_id, source_system_id, external_record_id),
  constraint pgdasd_declarations_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint pgdasd_declarations_source_fk
    foreign key (municipality_id, source_system_id)
    references public.source_systems(municipality_id, id),
  constraint pgdasd_declarations_batch_fk
    foreign key (municipality_id, import_batch_id)
    references public.import_batches(municipality_id, id) on delete set null,
  constraint pgdasd_declarations_competence_ck
    check (competence_month = date_trunc('month', competence_month)::date),
  constraint pgdasd_declarations_snapshot_ck
    check (jsonb_typeof(source_snapshot) = 'object'),
  constraint pgdasd_declarations_sha_ck
    check (payload_sha256 is null or payload_sha256 ~ '^[a-f0-9]{64}$'),
  constraint pgdasd_declarations_test_origin_ck
    check (not is_test or data_origin = 'synthetic_test')
);

create table if not exists public.pgdasd_annex_items (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  declaration_id uuid not null,
  taxpayer_id uuid not null,
  external_line_id text not null,
  annex_code text not null check (annex_code in ('I', 'II', 'III', 'IV', 'V')),
  activity_code text,
  revenue_type text,
  gross_revenue numeric(18,2) not null default 0 check (gross_revenue >= 0),
  tax_base numeric(18,2) not null default 0 check (tax_base >= 0),
  effective_rate numeric(12,8) check (effective_rate is null or effective_rate between 0 and 100),
  iss_rate numeric(12,8) check (iss_rate is null or iss_rate between 0 and 100),
  iss_amount numeric(18,2) not null default 0 check (iss_amount >= 0),
  factor_r_applicable boolean not null default false,
  source_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint pgdasd_annex_items_tenant_id_uq unique (municipality_id, id),
  constraint pgdasd_annex_items_line_uq
    unique (municipality_id, declaration_id, external_line_id),
  constraint pgdasd_annex_items_declaration_fk
    foreign key (municipality_id, declaration_id)
    references public.pgdasd_declarations(municipality_id, id) on delete cascade,
  constraint pgdasd_annex_items_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint pgdasd_annex_items_snapshot_ck
    check (jsonb_typeof(source_snapshot) = 'object')
);

create table if not exists public.sigiss_tax_base_periods (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  source_system_id uuid not null,
  import_batch_id uuid,
  external_record_id text not null,
  competence_month date not null,
  taxpayer_role text not null check (taxpayer_role in ('tomador', 'prestador', 'simples')),
  services_revenue numeric(18,2) not null default 0 check (services_revenue >= 0),
  iss_tax_base numeric(18,2) not null default 0 check (iss_tax_base >= 0),
  iss_due numeric(18,2) not null default 0 check (iss_due >= 0),
  retained_iss numeric(18,2) not null default 0 check (retained_iss >= 0),
  declared_annex_code text check (declared_annex_code is null or declared_annex_code in ('I','II','III','IV','V')),
  service_code_summary jsonb not null default '[]'::jsonb,
  data_origin text not null default 'official_import'
    check (data_origin in ('official_import', 'manual', 'synthetic_test')),
  is_test boolean not null default false,
  source_snapshot jsonb not null default '{}'::jsonb,
  payload_sha256 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sigiss_tax_base_periods_tenant_id_uq unique (municipality_id, id),
  constraint sigiss_tax_base_periods_external_uq
    unique (municipality_id, source_system_id, external_record_id),
  constraint sigiss_tax_base_periods_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint sigiss_tax_base_periods_source_fk
    foreign key (municipality_id, source_system_id)
    references public.source_systems(municipality_id, id),
  constraint sigiss_tax_base_periods_batch_fk
    foreign key (municipality_id, import_batch_id)
    references public.import_batches(municipality_id, id) on delete set null,
  constraint sigiss_tax_base_periods_competence_ck
    check (competence_month = date_trunc('month', competence_month)::date),
  constraint sigiss_tax_base_periods_codes_ck
    check (jsonb_typeof(service_code_summary) = 'array'),
  constraint sigiss_tax_base_periods_snapshot_ck
    check (jsonb_typeof(source_snapshot) = 'object'),
  constraint sigiss_tax_base_periods_sha_ck
    check (payload_sha256 is null or payload_sha256 ~ '^[a-f0-9]{64}$'),
  constraint sigiss_tax_base_periods_test_origin_ck
    check (not is_test or data_origin = 'synthetic_test')
);

create table if not exists public.factor_r_payroll_periods (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  source_system_id uuid not null,
  import_batch_id uuid,
  external_record_id text not null,
  competence_month date not null,
  employee_remuneration numeric(18,2) not null default 0 check (employee_remuneration >= 0),
  pro_labore numeric(18,2) not null default 0 check (pro_labore >= 0),
  individual_contributors numeric(18,2) not null default 0 check (individual_contributors >= 0),
  thirteenth_salary numeric(18,2) not null default 0 check (thirteenth_salary >= 0),
  employer_social_security numeric(18,2) not null default 0 check (employer_social_security >= 0),
  fgts numeric(18,2) not null default 0 check (fgts >= 0),
  other_eligible_payroll numeric(18,2) not null default 0 check (other_eligible_payroll >= 0),
  fs_month numeric(18,2) generated always as (
    employee_remuneration + pro_labore + individual_contributors +
    thirteenth_salary + employer_social_security + fgts + other_eligible_payroll
  ) stored,
  data_origin text not null default 'official_import'
    check (data_origin in ('official_import', 'manual', 'synthetic_test')),
  is_test boolean not null default false,
  source_snapshot jsonb not null default '{}'::jsonb,
  payload_sha256 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint factor_r_payroll_periods_tenant_id_uq unique (municipality_id, id),
  constraint factor_r_payroll_periods_external_uq
    unique (municipality_id, source_system_id, external_record_id),
  constraint factor_r_payroll_periods_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint factor_r_payroll_periods_source_fk
    foreign key (municipality_id, source_system_id)
    references public.source_systems(municipality_id, id),
  constraint factor_r_payroll_periods_batch_fk
    foreign key (municipality_id, import_batch_id)
    references public.import_batches(municipality_id, id) on delete set null,
  constraint factor_r_payroll_periods_competence_ck
    check (competence_month = date_trunc('month', competence_month)::date),
  constraint factor_r_payroll_periods_snapshot_ck
    check (jsonb_typeof(source_snapshot) = 'object'),
  constraint factor_r_payroll_periods_sha_ck
    check (payload_sha256 is null or payload_sha256 ~ '^[a-f0-9]{64}$'),
  constraint factor_r_payroll_periods_test_origin_ck
    check (not is_test or data_origin = 'synthetic_test')
);

create table if not exists public.simple_national_calculation_snapshots (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  competence_month date not null,
  calculation_version text not null,
  declared_rbt12 numeric(18,2),
  calculated_rbt12 numeric(18,2) not null check (calculated_rbt12 >= 0),
  declared_fs12 numeric(18,2),
  calculated_fs12 numeric(18,2) not null check (calculated_fs12 >= 0),
  declared_factor_r numeric(12,8),
  calculated_factor_r numeric(12,8) not null check (calculated_factor_r between 0 and 100),
  declared_annex_code text,
  expected_annex_code text,
  pgdasd_tax_base numeric(18,2) not null default 0 check (pgdasd_tax_base >= 0),
  sigiss_tax_base numeric(18,2) not null default 0 check (sigiss_tax_base >= 0),
  rbt12_difference numeric(18,2) not null default 0 check (rbt12_difference >= 0),
  factor_r_difference numeric(12,8) not null default 0 check (factor_r_difference >= 0),
  tax_base_difference numeric(18,2) not null default 0 check (tax_base_difference >= 0),
  annex_mismatch boolean not null default false,
  factor_r_applicable boolean not null default false,
  status text not null default 'calculated'
    check (status in ('calculated', 'incomplete', 'blocked', 'superseded')),
  block_reasons jsonb not null default '[]'::jsonb,
  evidence_snapshot jsonb not null,
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  is_test boolean not null default false,
  calculated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint simple_national_snapshots_tenant_id_uq unique (municipality_id, id),
  constraint simple_national_snapshots_period_uq
    unique (municipality_id, taxpayer_id, competence_month, calculation_version, is_test),
  constraint simple_national_snapshots_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint simple_national_snapshots_competence_ck
    check (competence_month = date_trunc('month', competence_month)::date),
  constraint simple_national_snapshots_annex_ck
    check (
      (declared_annex_code is null or declared_annex_code in ('I','II','III','IV','V'))
      and
      (expected_annex_code is null or expected_annex_code in ('I','II','III','IV','V'))
    ),
  constraint simple_national_snapshots_blocks_ck
    check (jsonb_typeof(block_reasons) = 'array'),
  constraint simple_national_snapshots_evidence_ck
    check (jsonb_typeof(evidence_snapshot) = 'object')
);

create table if not exists public.simple_national_divergence_items (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  divergence_id uuid not null,
  calculation_snapshot_id uuid not null,
  metric_code text not null check (metric_code in (
    'annex', 'tax_base', 'rbt12', 'factor_r'
  )),
  expected_value text,
  observed_value text,
  numeric_difference numeric(18,8) not null default 0 check (numeric_difference >= 0),
  evidence_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint simple_national_divergence_items_divergence_fk
    foreign key (municipality_id, divergence_id)
    references public.divergences(municipality_id, id) on delete cascade,
  constraint simple_national_divergence_items_snapshot_fk
    foreign key (municipality_id, calculation_snapshot_id)
    references public.simple_national_calculation_snapshots(municipality_id, id),
  constraint simple_national_divergence_items_uq
    unique (municipality_id, divergence_id, calculation_snapshot_id, metric_code),
  constraint simple_national_divergence_items_evidence_ck
    check (jsonb_typeof(evidence_snapshot) = 'object')
);

create table if not exists private.sandbox_message_outbox (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  case_id uuid not null,
  notification_id uuid not null,
  contact_id uuid not null,
  original_recipient_email extensions.citext not null,
  sandbox_recipient_email extensions.citext not null,
  subject text not null,
  body_text text not null,
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'captured'
    check (status in ('captured', 'inspected', 'failed', 'discarded')),
  provider_code text not null default 'sandbox',
  captured_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint sandbox_message_outbox_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint sandbox_message_outbox_notification_fk
    foreign key (municipality_id, notification_id)
    references public.notifications(municipality_id, id) on delete cascade,
  constraint sandbox_message_outbox_contact_fk
    foreign key (municipality_id, contact_id)
    references public.party_contacts(municipality_id, id),
  constraint sandbox_message_outbox_notification_uq
    unique (municipality_id, notification_id, contact_id),
  constraint sandbox_message_outbox_metadata_ck
    check (jsonb_typeof(metadata) = 'object')
);

create index if not exists project_source_documents_status_idx
  on public.project_source_documents (municipality_id, ingestion_status, source_kind, modified_at desc);
create index if not exists pgdasd_declarations_period_idx
  on public.pgdasd_declarations (municipality_id, taxpayer_id, competence_month, is_test);
create index if not exists pgdasd_annex_items_declaration_idx
  on public.pgdasd_annex_items (municipality_id, declaration_id, annex_code);
create index if not exists sigiss_tax_base_periods_period_idx
  on public.sigiss_tax_base_periods (municipality_id, taxpayer_id, competence_month, is_test);
create index if not exists factor_r_payroll_periods_period_idx
  on public.factor_r_payroll_periods (municipality_id, taxpayer_id, competence_month, is_test);
create index if not exists simple_national_snapshots_search_idx
  on public.simple_national_calculation_snapshots (
    municipality_id, competence_month, status, is_test, taxpayer_id
  );
create index if not exists simple_national_divergence_items_divergence_idx
  on public.simple_national_divergence_items (municipality_id, divergence_id);
create index if not exists sandbox_message_outbox_status_idx
  on private.sandbox_message_outbox (municipality_id, status, captured_at desc);

alter table public.project_source_documents enable row level security;
alter table public.pgdasd_declarations enable row level security;
alter table public.pgdasd_annex_items enable row level security;
alter table public.sigiss_tax_base_periods enable row level security;
alter table public.factor_r_payroll_periods enable row level security;
alter table public.simple_national_calculation_snapshots enable row level security;
alter table public.simple_national_divergence_items enable row level security;
alter table private.project_source_document_contents enable row level security;
alter table private.sandbox_message_outbox enable row level security;

create policy project_source_documents_select
  on public.project_source_documents for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor','fiscal_auditor','legal_reviewer']::text[]
    ))
  );

create policy pgdasd_declarations_select
  on public.pgdasd_declarations for select to authenticated
  using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));

create policy pgdasd_annex_items_select
  on public.pgdasd_annex_items for select to authenticated
  using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));

create policy sigiss_tax_base_periods_select
  on public.sigiss_tax_base_periods for select to authenticated
  using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));

create policy factor_r_payroll_periods_select
  on public.factor_r_payroll_periods for select to authenticated
  using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));

create policy simple_national_snapshots_select
  on public.simple_national_calculation_snapshots for select to authenticated
  using ((select private.can_access_taxpayer(municipality_id, taxpayer_id)));

create policy simple_national_divergence_items_select
  on public.simple_national_divergence_items for select to authenticated
  using ((select private.can_access_divergence(municipality_id, divergence_id)));

revoke all on table public.project_source_documents from anon, authenticated;
revoke all on table public.pgdasd_declarations from anon, authenticated;
revoke all on table public.pgdasd_annex_items from anon, authenticated;
revoke all on table public.sigiss_tax_base_periods from anon, authenticated;
revoke all on table public.factor_r_payroll_periods from anon, authenticated;
revoke all on table public.simple_national_calculation_snapshots from anon, authenticated;
revoke all on table public.simple_national_divergence_items from anon, authenticated;

grant select on table public.project_source_documents to authenticated;
grant select on table public.pgdasd_declarations to authenticated;
grant select on table public.pgdasd_annex_items to authenticated;
grant select on table public.sigiss_tax_base_periods to authenticated;
grant select on table public.factor_r_payroll_periods to authenticated;
grant select on table public.simple_national_calculation_snapshots to authenticated;
grant select on table public.simple_national_divergence_items to authenticated;

grant all on table public.project_source_documents to service_role;
grant all on table public.pgdasd_declarations to service_role;
grant all on table public.pgdasd_annex_items to service_role;
grant all on table public.sigiss_tax_base_periods to service_role;
grant all on table public.factor_r_payroll_periods to service_role;
grant all on table public.simple_national_calculation_snapshots to service_role;
grant all on table public.simple_national_divergence_items to service_role;
grant all on table private.project_source_document_contents to service_role;
grant all on table private.sandbox_message_outbox to service_role;
grant usage, select on all sequences in schema private to service_role;

create trigger project_source_documents_set_updated_at
  before update on public.project_source_documents
  for each row execute function private.set_updated_at();
create trigger project_source_documents_immutable_identity
  before update on public.project_source_documents
  for each row execute function private.prevent_tenant_or_id_change();
create trigger project_source_documents_audit
  after insert or update or delete on public.project_source_documents
  for each row execute function private.audit_row_change();

create trigger pgdasd_declarations_set_updated_at
  before update on public.pgdasd_declarations
  for each row execute function private.set_updated_at();
create trigger pgdasd_declarations_immutable_identity
  before update on public.pgdasd_declarations
  for each row execute function private.prevent_tenant_or_id_change();
create trigger pgdasd_declarations_audit
  after insert or update or delete on public.pgdasd_declarations
  for each row execute function private.audit_row_change();

create trigger pgdasd_annex_items_immutable_identity
  before update on public.pgdasd_annex_items
  for each row execute function private.prevent_tenant_or_id_change();
create trigger pgdasd_annex_items_audit
  after insert or update or delete on public.pgdasd_annex_items
  for each row execute function private.audit_row_change();

create trigger sigiss_tax_base_periods_set_updated_at
  before update on public.sigiss_tax_base_periods
  for each row execute function private.set_updated_at();
create trigger sigiss_tax_base_periods_immutable_identity
  before update on public.sigiss_tax_base_periods
  for each row execute function private.prevent_tenant_or_id_change();
create trigger sigiss_tax_base_periods_audit
  after insert or update or delete on public.sigiss_tax_base_periods
  for each row execute function private.audit_row_change();

create trigger factor_r_payroll_periods_set_updated_at
  before update on public.factor_r_payroll_periods
  for each row execute function private.set_updated_at();
create trigger factor_r_payroll_periods_immutable_identity
  before update on public.factor_r_payroll_periods
  for each row execute function private.prevent_tenant_or_id_change();
create trigger factor_r_payroll_periods_audit
  after insert or update or delete on public.factor_r_payroll_periods
  for each row execute function private.audit_row_change();

create trigger simple_national_snapshots_set_updated_at
  before update on public.simple_national_calculation_snapshots
  for each row execute function private.set_updated_at();
create trigger simple_national_snapshots_immutable_identity
  before update on public.simple_national_calculation_snapshots
  for each row execute function private.prevent_tenant_or_id_change();
create trigger simple_national_snapshots_audit
  after insert or update or delete on public.simple_national_calculation_snapshots
  for each row execute function private.audit_row_change();

create trigger simple_national_divergence_items_audit
  after insert or update or delete on public.simple_national_divergence_items
  for each row execute function private.audit_row_change();

create or replace function private.calculate_factor_r(
  p_fs12 numeric,
  p_rbt12 numeric
) returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(p_fs12, 0) = 0 and coalesce(p_rbt12, 0) = 0 then 0.01::numeric
    when coalesce(p_fs12, 0) > 0 and coalesce(p_rbt12, 0) = 0 then 0.28::numeric
    when coalesce(p_fs12, 0) = 0 and coalesce(p_rbt12, 0) > 0 then 0.01::numeric
    else round(p_fs12 / nullif(p_rbt12, 0), 8)
  end;
$$;

create or replace function private.expected_factor_r_annex(
  p_factor_r numeric,
  p_factor_r_applicable boolean
) returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when not coalesce(p_factor_r_applicable, false) then null
    when p_factor_r >= 0.28 then 'III'
    else 'V'
  end;
$$;

revoke all on function private.calculate_factor_r(numeric, numeric) from public;
revoke all on function private.expected_factor_r_annex(numeric, boolean) from public;

create or replace function public.ia_rebuild_simple_national_snapshots(
  p_municipality_id uuid,
  p_period_start date,
  p_period_end date,
  p_is_test boolean default true
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
      d.is_test
    from public.pgdasd_declarations d
    where d.municipality_id = p_municipality_id
      and d.competence_month between date_trunc('month', p_period_start)::date
                                 and date_trunc('month', p_period_end)::date
      and d.is_test = p_is_test
      and d.declaration_status <> 'cancelled'
    order by d.taxpayer_id, d.competence_month,
             (d.declaration_status = 'rectified') desc,
             d.transmitted_at desc nulls last,
             d.created_at desc
  ),
  calculated as (
    select
      d.*,
      coalesce((
        select sum(pr.total_revenue_declared)
        from public.pgdasd_declarations pr
        where pr.municipality_id = p_municipality_id
          and pr.taxpayer_id = d.taxpayer_id
          and pr.is_test = p_is_test
          and pr.declaration_status <> 'cancelled'
          and pr.competence_month >= (d.competence_month - interval '12 months')::date
          and pr.competence_month < d.competence_month
      ), 0)::numeric(18,2) as calculated_rbt12,
      coalesce((
        select sum(fp.fs_month)
        from public.factor_r_payroll_periods fp
        where fp.municipality_id = p_municipality_id
          and fp.taxpayer_id = d.taxpayer_id
          and fp.is_test = p_is_test
          and fp.competence_month >= (d.competence_month - interval '12 months')::date
          and fp.competence_month < d.competence_month
      ), 0)::numeric(18,2) as calculated_fs12,
      coalesce((
        select sum(sp.iss_tax_base)
        from public.sigiss_tax_base_periods sp
        where sp.municipality_id = p_municipality_id
          and sp.taxpayer_id = d.taxpayer_id
          and sp.is_test = p_is_test
          and sp.competence_month = d.competence_month
      ), 0)::numeric(18,2) as sigiss_tax_base,
      (
        select min(ai.annex_code)
        from public.pgdasd_annex_items ai
        where ai.municipality_id = p_municipality_id
          and ai.declaration_id = d.id
          and ai.factor_r_applicable
      ) as declared_annex_code,
      coalesce((
        select bool_or(ai.factor_r_applicable)
        from public.pgdasd_annex_items ai
        where ai.municipality_id = p_municipality_id
          and ai.declaration_id = d.id
      ), false) as factor_r_applicable
    from declarations d
  ),
  prepared as (
    select
      c.*,
      private.calculate_factor_r(c.calculated_fs12, c.calculated_rbt12) as calculated_factor_r
    from calculated c
  ),
  payload as (
    select
      p.*,
      private.expected_factor_r_annex(
        p.calculated_factor_r,
        p.factor_r_applicable
      ) as expected_annex_code,
      jsonb_build_object(
        'pgdasd_declaration_id', p.id,
        'competence_month', p.competence_month,
        'calculation_version', 'simple-national-v1-homologation',
        'window', jsonb_build_object(
          'start', (p.competence_month - interval '12 months')::date,
          'end_exclusive', p.competence_month
        ),
        'is_test', p.is_test
      ) as evidence
    from prepared p
  )
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
    'simple-national-v1-homologation',
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
    abs(coalesce(p.rbt12_declared, p.calculated_rbt12) - p.calculated_rbt12),
    abs(coalesce(p.factor_r_declared, p.calculated_factor_r) - p.calculated_factor_r),
    abs(p.iss_tax_base_declared - p.sigiss_tax_base),
    (
      p.factor_r_applicable
      and p.declared_annex_code is not null
      and p.expected_annex_code is not null
      and p.declared_annex_code <> p.expected_annex_code
    ),
    p.factor_r_applicable,
    case
      when p.rbt12_declared is null then 'incomplete'
      else 'calculated'
    end,
    case
      when p.rbt12_declared is null
        then jsonb_build_array(jsonb_build_object('code', 'missing_declared_rbt12'))
      else '[]'::jsonb
    end,
    p.evidence,
    encode(extensions.digest(p.evidence::text, 'sha256'), 'hex'),
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
        calculated_at = excluded.calculated_at;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.ia_run_simple_national_detection(
  p_municipality_id uuid,
  p_rule_version_id uuid,
  p_as_of timestamptz,
  p_idempotency_key text,
  p_import_batch_id uuid default null,
  p_test_mode boolean default true
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.divergence_rule_versions%rowtype;
  v_rule_type text;
  v_run_id uuid;
  v_threshold numeric;
  v_period_start date;
  v_period_end date;
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

  select rv.*
    into strict v_rule
  from public.divergence_rule_versions rv
  join public.divergence_rules r
    on r.municipality_id = rv.municipality_id
   and r.id = rv.rule_id
  where rv.municipality_id = p_municipality_id
    and rv.id = p_rule_version_id
  for share;

  select r.divergence_type
    into strict v_rule_type
  from public.divergence_rules r
  where r.municipality_id = p_municipality_id
    and r.id = v_rule.rule_id;

  if v_rule_type not in (
    'pgdasd_sigiss_annex',
    'pgdasd_sigiss_tax_base',
    'pgdasd_rbt12',
    'factor_r'
  ) then
    raise exception 'unsupported simple national divergence type';
  end if;

  if p_test_mode then
    if not private.is_service_role() then
      raise exception 'service role required for homologation test';
    end if;
    if coalesce((v_rule.parameters ->> 'test_mode')::boolean, false) is not true then
      raise exception 'rule is not enabled for homologation tests';
    end if;
  else
    if v_rule.status <> 'active'
       or coalesce((v_rule.parameters ->> 'formula_approved')::boolean, false) is not true then
      raise exception 'approved active rule required';
    end if;
  end if;

  v_threshold := coalesce((v_rule.parameters ->> 'threshold')::numeric, 0);
  v_period_end := date_trunc('month', p_as_of)::date;
  v_period_start := (
    select coalesce(min(s.competence_month), v_period_end)
    from public.simple_national_calculation_snapshots s
    where s.municipality_id = p_municipality_id
      and s.competence_month <= v_period_end
      and s.is_test = p_test_mode
  );

  insert into public.detection_runs (
    municipality_id,
    rule_version_id,
    import_batch_id,
    status,
    as_of,
    period_start,
    period_end,
    idempotency_key,
    execution_mode,
    started_by,
    started_at
  ) values (
    p_municipality_id,
    p_rule_version_id,
    p_import_batch_id,
    'running',
    p_as_of,
    v_period_start,
    v_period_end,
    p_idempotency_key,
    case when p_test_mode then 'homologation_test' else 'live' end,
    auth.uid(),
    now()
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_run_id;

  if exists (
    select 1 from public.divergences d
    where d.municipality_id = p_municipality_id
      and d.detection_run_id = v_run_id
  ) then
    return v_run_id;
  end if;

  with candidates as (
    select
      s.*,
      case v_rule_type
        when 'pgdasd_sigiss_annex' then case when s.annex_mismatch then 1::numeric else 0::numeric end
        when 'pgdasd_sigiss_tax_base' then s.tax_base_difference
        when 'pgdasd_rbt12' then s.rbt12_difference
        when 'factor_r' then s.factor_r_difference
      end as metric_difference,
      case v_rule_type
        when 'pgdasd_sigiss_annex' then s.declared_annex_code
        when 'pgdasd_sigiss_tax_base' then s.pgdasd_tax_base::text
        when 'pgdasd_rbt12' then s.declared_rbt12::text
        when 'factor_r' then s.declared_factor_r::text
      end as observed_value,
      case v_rule_type
        when 'pgdasd_sigiss_annex' then s.expected_annex_code
        when 'pgdasd_sigiss_tax_base' then s.sigiss_tax_base::text
        when 'pgdasd_rbt12' then s.calculated_rbt12::text
        when 'factor_r' then s.calculated_factor_r::text
      end as expected_value
    from public.simple_national_calculation_snapshots s
    where s.municipality_id = p_municipality_id
      and s.competence_month between v_period_start and v_period_end
      and s.is_test = p_test_mode
      and s.status <> 'superseded'
  ),
  selected as (
    select *
    from candidates
    where metric_difference > v_threshold
  ),
  prepared as (
    select
      s.*,
      jsonb_build_object(
        'calculation_snapshot_id', s.id,
        'metric_code', case v_rule_type
          when 'pgdasd_sigiss_annex' then 'annex'
          when 'pgdasd_sigiss_tax_base' then 'tax_base'
          when 'pgdasd_rbt12' then 'rbt12'
          when 'factor_r' then 'factor_r'
        end,
        'observed_value', s.observed_value,
        'expected_value', s.expected_value,
        'difference', s.metric_difference,
        'rule_version_id', v_rule.id,
        'execution_mode', case when p_test_mode then 'homologation_test' else 'live' end
      ) as snapshot
    from selected s
  )
  insert into public.divergences (
    municipality_id,
    taxpayer_id,
    detection_run_id,
    rule_version_id,
    divergence_type,
    period_start,
    period_end,
    as_of,
    assessed_amount,
    paid_amount,
    other_credits_amount,
    difference_amount,
    threshold_amount,
    priority_score,
    status,
    block_reasons,
    source_snapshot,
    snapshot_sha256,
    execution_mode
  )
  select
    p_municipality_id,
    p.taxpayer_id,
    v_run_id,
    v_rule.id,
    v_rule_type,
    p.competence_month,
    p.competence_month,
    p_as_of,
    0,
    0,
    0,
    p.metric_difference,
    v_threshold,
    p.metric_difference,
    case when p.status = 'blocked' then 'blocked' else 'pending_revalidation' end,
    p.block_reasons,
    p.snapshot,
    encode(extensions.digest(p.snapshot::text, 'sha256'), 'hex'),
    case when p_test_mode then 'homologation_test' else 'live' end
  from prepared p;

  insert into public.simple_national_divergence_items (
    municipality_id,
    divergence_id,
    calculation_snapshot_id,
    metric_code,
    expected_value,
    observed_value,
    numeric_difference,
    evidence_snapshot
  )
  select
    d.municipality_id,
    d.id,
    s.id,
    case d.divergence_type
      when 'pgdasd_sigiss_annex' then 'annex'
      when 'pgdasd_sigiss_tax_base' then 'tax_base'
      when 'pgdasd_rbt12' then 'rbt12'
      when 'factor_r' then 'factor_r'
    end,
    d.source_snapshot ->> 'expected_value',
    d.source_snapshot ->> 'observed_value',
    d.difference_amount,
    s.evidence_snapshot
  from public.divergences d
  join public.simple_national_calculation_snapshots s
    on s.municipality_id = d.municipality_id
   and s.id = (d.source_snapshot ->> 'calculation_snapshot_id')::uuid
  where d.municipality_id = p_municipality_id
    and d.detection_run_id = v_run_id;

  update public.detection_runs dr
     set status = 'completed',
         candidate_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
         ),
         divergence_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
             and d.status = 'pending_revalidation'
         ),
         blocked_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
             and d.status = 'blocked'
         ),
         finished_at = now()
   where dr.municipality_id = p_municipality_id
     and dr.id = v_run_id;

  return v_run_id;
end;
$$;

create or replace function public.ia_run_homologation_current_account_detection(
  p_municipality_id uuid,
  p_rule_version_id uuid,
  p_as_of timestamptz,
  p_idempotency_key text,
  p_import_batch_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.divergence_rule_versions%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_run_id uuid;
  v_period_start date;
  v_period_end date;
  v_threshold numeric(18,2);
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select rv.* into strict v_rule
  from public.divergence_rule_versions rv
  join public.divergence_rules r
    on r.municipality_id = rv.municipality_id
   and r.id = rv.rule_id
   and r.divergence_type = 'current_account_balance'
  where rv.municipality_id = p_municipality_id
    and rv.id = p_rule_version_id
    and coalesce((rv.parameters ->> 'test_mode')::boolean, false)
  for share;

  select pv.* into strict v_policy
  from public.municipality_policy_versions pv
  where pv.municipality_id = p_municipality_id
    and coalesce((pv.operational_config ->> 'test_mode')::boolean, false)
  order by pv.version desc
  limit 1;

  v_period_end := date_trunc('month', p_as_of)::date;
  v_period_start := (
    date_trunc('month', p_as_of)
    - make_interval(months => greatest(v_policy.lookback_months, 1) - 1)
  )::date;
  v_threshold := coalesce(
    (v_rule.parameters ->> 'threshold')::numeric,
    v_policy.minimum_divergence_amount
  );

  insert into public.detection_runs (
    municipality_id,
    rule_version_id,
    import_batch_id,
    status,
    as_of,
    period_start,
    period_end,
    idempotency_key,
    execution_mode,
    started_at
  ) values (
    p_municipality_id,
    p_rule_version_id,
    p_import_batch_id,
    'running',
    p_as_of,
    v_period_start,
    v_period_end,
    p_idempotency_key,
    'homologation_test',
    now()
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_run_id;

  if exists (
    select 1 from public.divergences d
    where d.municipality_id = p_municipality_id
      and d.detection_run_id = v_run_id
  ) then
    return v_run_id;
  end if;

  with amounts as (
    select
      e.taxpayer_id,
      coalesce(sum(e.amount) filter (
        where e.direction = 'debit' and e.status = 'valid'
      ), 0)::numeric(18,2) as assessed_amount,
      coalesce(sum(e.amount) filter (
        where e.direction = 'credit'
          and e.entry_kind = 'payment'
          and e.status = 'valid'
      ), 0)::numeric(18,2) as paid_amount,
      coalesce(sum(e.amount) filter (
        where e.direction = 'credit'
          and e.entry_kind <> 'payment'
          and e.status = 'valid'
      ), 0)::numeric(18,2) as other_credits_amount
    from public.current_account_entries e
    where e.municipality_id = p_municipality_id
      and e.competence_month between v_period_start and v_period_end
    group by e.taxpayer_id
  ),
  prepared as (
    select
      a.*,
      greatest(a.assessed_amount - a.paid_amount - a.other_credits_amount, 0)::numeric(18,2)
        as difference_amount,
      jsonb_build_object(
        'rule_version_id', v_rule.id,
        'period_start', v_period_start,
        'period_end', v_period_end,
        'execution_mode', 'homologation_test'
      ) as snapshot
    from amounts a
  )
  insert into public.divergences (
    municipality_id,
    taxpayer_id,
    detection_run_id,
    rule_version_id,
    divergence_type,
    period_start,
    period_end,
    as_of,
    assessed_amount,
    paid_amount,
    other_credits_amount,
    difference_amount,
    threshold_amount,
    priority_score,
    status,
    block_reasons,
    source_snapshot,
    snapshot_sha256,
    execution_mode
  )
  select
    p_municipality_id,
    p.taxpayer_id,
    v_run_id,
    v_rule.id,
    'current_account_balance',
    v_period_start,
    v_period_end,
    p_as_of,
    p.assessed_amount,
    p.paid_amount,
    p.other_credits_amount,
    p.difference_amount,
    v_threshold,
    p.difference_amount,
    'pending_revalidation',
    '[]'::jsonb,
    p.snapshot,
    encode(extensions.digest(p.snapshot::text, 'sha256'), 'hex'),
    'homologation_test'
  from prepared p
  where p.difference_amount >= v_threshold
  order by p.difference_amount desc
  limit v_policy.top_debtors_limit;

  insert into public.divergence_items (
    municipality_id,
    divergence_id,
    current_account_entry_id,
    entry_kind,
    direction,
    amount_snapshot,
    competence_month,
    source_sha256
  )
  select
    d.municipality_id,
    d.id,
    e.id,
    e.entry_kind,
    e.direction,
    e.amount,
    e.competence_month,
    e.payload_sha256
  from public.divergences d
  join public.current_account_entries e
    on e.municipality_id = d.municipality_id
   and e.taxpayer_id = d.taxpayer_id
   and e.competence_month between d.period_start and d.period_end
   and e.status = 'valid'
  where d.municipality_id = p_municipality_id
    and d.detection_run_id = v_run_id
  on conflict do nothing;

  update public.detection_runs dr
     set status = 'completed',
         candidate_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
         ),
         divergence_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
             and d.status = 'pending_revalidation'
         ),
         blocked_count = 0,
         finished_at = now()
   where dr.municipality_id = p_municipality_id
     and dr.id = v_run_id;

  return v_run_id;
end;
$$;

create or replace function public.ia_execute_homologation_case_test(
  p_divergence_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_divergence public.divergences%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_template public.notification_template_versions%rowtype;
  v_contact public.party_contacts%rowtype;
  v_batch_id uuid;
  v_batch_item_id uuid;
  v_case_id uuid;
  v_case_number text;
  v_notification_batch_id uuid;
  v_notification_id uuid;
  v_recipient_id uuid;
  v_sandbox_email extensions.citext;
  v_subject text;
  v_body text;
  v_hash text;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select d.* into strict v_divergence
  from public.divergences d
  where d.id = p_divergence_id
    and d.execution_mode = 'homologation_test'
    and d.status in ('pending_revalidation', 'eligible')
  for update;

  select pv.* into strict v_policy
  from public.municipality_policy_versions pv
  where pv.municipality_id = v_divergence.municipality_id
    and coalesce((pv.operational_config ->> 'test_mode')::boolean, false)
  order by pv.version desc
  limit 1;

  select tv.* into strict v_template
  from public.notification_template_versions tv
  join public.notification_templates t
    on t.municipality_id = tv.municipality_id
   and t.id = tv.template_id
   and t.code = 'initial_inspection_alert_sandbox'
  where tv.municipality_id = v_divergence.municipality_id
  order by tv.version desc
  limit 1;

  select pc.* into strict v_contact
  from public.party_contacts pc
  where pc.municipality_id = v_divergence.municipality_id
    and pc.taxpayer_id = v_divergence.taxpayer_id
    and pc.contact_type = 'email'
    and pc.status in ('quarantined', 'unverified')
    and pc.visible_in_homologation
  order by pc.is_primary desc, pc.created_at
  limit 1;

  insert into public.case_opening_batches (
    municipality_id,
    detection_run_id,
    policy_version_id,
    status,
    requested_count,
    approved_count,
    opened_count,
    blocked_count,
    idempotency_key,
    submitted_at,
    approved_at,
    approval_notes,
    execution_mode,
    approved_system_actor
  ) values (
    v_divergence.municipality_id,
    v_divergence.detection_run_id,
    v_policy.id,
    'completed',
    1,
    1,
    1,
    0,
    'homologation-case-test:' || v_divergence.id::text,
    now(),
    now(),
    'Execução automática isolada em sandbox; nenhum e-mail externo foi enviado.',
    'homologation_test',
    'ia-fiscal-sandbox'
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_batch_id;

  insert into public.case_opening_batch_items (
    municipality_id,
    batch_id,
    divergence_id,
    status,
    selection_rank,
    processed_at
  ) values (
    v_divergence.municipality_id,
    v_batch_id,
    v_divergence.id,
    'opened',
    1,
    now()
  )
  on conflict (municipality_id, batch_id, divergence_id)
  do update set status = 'opened', processed_at = now()
  returning id into v_batch_item_id;

  select fc.id into v_case_id
  from public.fiscal_cases fc
  where fc.municipality_id = v_divergence.municipality_id
    and fc.divergence_id = v_divergence.id;

  if v_case_id is null then
    v_case_number := private.next_case_number(v_divergence.municipality_id);
    insert into public.fiscal_cases (
      municipality_id,
      taxpayer_id,
      divergence_id,
      batch_item_id,
      case_number,
      status,
      execution_mode
    ) values (
      v_divergence.municipality_id,
      v_divergence.taxpayer_id,
      v_divergence.id,
      v_batch_item_id,
      v_case_number,
      'initial_notice_sent',
      'homologation_test'
    )
    returning id into v_case_id;

    insert into public.case_threads (municipality_id, case_id)
    values (v_divergence.municipality_id, v_case_id);

    insert into public.case_events (
      municipality_id,
      case_id,
      event_type,
      visibility,
      actor_type,
      event_data
    ) values (
      v_divergence.municipality_id,
      v_case_id,
      'homologation_inspection_case_opened',
      'staff',
      'service',
      jsonb_build_object(
        'divergence_id', v_divergence.id,
        'execution_mode', 'homologation_test',
        'external_delivery', false
      )
    );
  end if;

  v_subject := v_template.subject;
  v_body := v_template.body_text;
  v_hash := encode(
    extensions.digest(v_subject || E'\n' || v_body, 'sha256'),
    'hex'
  );
  v_sandbox_email := (
    'sandbox+' ||
    substring(encode(extensions.digest(lower(v_contact.normalized_value::text), 'sha256'), 'hex') from 1 for 16) ||
    '@example.invalid'
  )::extensions.citext;

  insert into public.notification_batches (
    municipality_id,
    case_opening_batch_id,
    status,
    idempotency_key,
    total_notifications,
    sent_notifications,
    failed_notifications
  ) values (
    v_divergence.municipality_id,
    v_batch_id,
    'completed',
    'homologation-notification-batch:' || v_batch_id::text,
    1,
    1,
    0
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_notification_batch_id;

  insert into public.notifications (
    municipality_id,
    notification_batch_id,
    case_id,
    template_version_id,
    notification_type,
    legal_nature,
    subject_snapshot,
    body_text_snapshot,
    content_sha256,
    status,
    idempotency_key,
    sent_at,
    execution_mode
  ) values (
    v_divergence.municipality_id,
    v_notification_batch_id,
    v_case_id,
    v_template.id,
    'initial_inspection_alert',
    'informational_alert',
    v_subject,
    v_body,
    v_hash,
    'sent',
    'homologation-notification:' || v_case_id::text,
    now(),
    'homologation_test'
  )
  on conflict (municipality_id, case_id, notification_type)
  do update
    set notification_batch_id = excluded.notification_batch_id,
        template_version_id = excluded.template_version_id,
        subject_snapshot = excluded.subject_snapshot,
        body_text_snapshot = excluded.body_text_snapshot,
        content_sha256 = excluded.content_sha256,
        status = 'sent',
        sent_at = now(),
        execution_mode = 'homologation_test'
  returning id into v_notification_id;

  insert into public.notification_recipients (
    municipality_id,
    notification_id,
    recipient_type,
    contact_id,
    email_snapshot,
    relationship_snapshot,
    status,
    idempotency_key,
    sent_at,
    delivered_at
  ) values (
    v_divergence.municipality_id,
    v_notification_id,
    'taxpayer',
    v_contact.id,
    v_sandbox_email,
    jsonb_build_object(
      'sandbox', true,
      'external_delivery', false,
      'original_contact_status', v_contact.status,
      'quarantine_reason', v_contact.quarantine_reason
    ),
    'sent',
    'homologation-recipient:' || v_notification_id::text || ':' || v_contact.id::text,
    now(),
    now()
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_recipient_id;

  insert into private.sandbox_message_outbox (
    municipality_id,
    case_id,
    notification_id,
    contact_id,
    original_recipient_email,
    sandbox_recipient_email,
    subject,
    body_text,
    content_sha256,
    status,
    metadata
  ) values (
    v_divergence.municipality_id,
    v_case_id,
    v_notification_id,
    v_contact.id,
    v_contact.normalized_value,
    v_sandbox_email,
    v_subject,
    v_body,
    v_hash,
    'captured',
    jsonb_build_object(
      'recipient_id', v_recipient_id,
      'external_delivery', false,
      'execution_mode', 'homologation_test'
    )
  )
  on conflict (municipality_id, notification_id, contact_id)
  do update set captured_at = now(), status = 'captured';

  update public.divergences
     set status = 'converted'
   where municipality_id = v_divergence.municipality_id
     and id = v_divergence.id;

  return jsonb_build_object(
    'case_id', v_case_id,
    'notification_id', v_notification_id,
    'recipient_id', v_recipient_id,
    'sandbox_recipient', v_sandbox_email,
    'external_delivery', false,
    'status', 'captured'
  );
end;
$$;

revoke all on function public.ia_rebuild_simple_national_snapshots(uuid, date, date, boolean) from public;
revoke all on function public.ia_run_simple_national_detection(uuid, uuid, timestamptz, text, uuid, boolean) from public;
revoke all on function public.ia_run_homologation_current_account_detection(uuid, uuid, timestamptz, text, uuid) from public;
revoke all on function public.ia_execute_homologation_case_test(uuid) from public;

grant execute on function public.ia_rebuild_simple_national_snapshots(uuid, date, date, boolean) to authenticated, service_role;
grant execute on function public.ia_run_simple_national_detection(uuid, uuid, timestamptz, text, uuid, boolean) to authenticated, service_role;
grant execute on function public.ia_run_homologation_current_account_detection(uuid, uuid, timestamptz, text, uuid) to service_role;
grant execute on function public.ia_execute_homologation_case_test(uuid) to service_role;

create or replace view public.vw_simple_national_cross_checks
with (security_invoker = true)
as
select
  s.municipality_id,
  s.id as calculation_snapshot_id,
  s.taxpayer_id,
  t.tax_id,
  t.legal_name,
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
from public.simple_national_calculation_snapshots s
join public.taxpayers t
  on t.municipality_id = s.municipality_id
 and t.id = s.taxpayer_id;

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
  d.block_reasons
from public.divergences d
join public.taxpayers t
  on t.municipality_id = d.municipality_id
 and t.id = d.taxpayer_id;

create or replace view public.vw_quarantined_contacts
with (security_invoker = true)
as
select
  pc.municipality_id,
  pc.id as contact_id,
  pc.taxpayer_id,
  pc.accounting_firm_id,
  pc.contact_type,
  pc.value,
  pc.normalized_value,
  pc.status,
  pc.quarantine_reason,
  pc.visible_in_homologation,
  pc.source,
  pc.created_at
from public.party_contacts pc
where pc.status in ('quarantined', 'unverified');

revoke all on table public.vw_simple_national_cross_checks from anon;
revoke all on table public.vw_fiscal_divergence_search from anon;
revoke all on table public.vw_quarantined_contacts from anon;
grant select on table public.vw_simple_national_cross_checks to authenticated, service_role;
grant select on table public.vw_fiscal_divergence_search to authenticated, service_role;
grant select on table public.vw_quarantined_contacts to authenticated, service_role;

comment on table public.pgdasd_declarations is
  'PGDAS-D declarations by taxpayer and competence. Synthetic rows are explicitly marked.';
comment on table public.factor_r_payroll_periods is
  'Monthly eligible payroll inputs used to calculate FS12 and Factor R.';
comment on table public.simple_national_calculation_snapshots is
  'Deterministic and auditable RBT12, FS12, Factor R, annex and tax-base calculation snapshot.';
comment on table private.sandbox_message_outbox is
  'Homologation-only delivery sink. Captures a complete message without external delivery.';

