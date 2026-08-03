begin;

create table public.taxpayers (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  municipal_registration text not null,
  tax_id text check (tax_id is null or tax_id ~ '^([0-9]{11}|[0-9]{14})$'),
  legal_name text not null,
  trade_name text,
  taxpayer_type text not null default 'company'
    check (taxpayer_type in ('individual', 'company', 'other')),
  status text not null default 'active'
    check (status in ('active', 'inactive', 'suspended', 'closed')),
  source_key text,
  source_metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint taxpayers_municipality_id_id_uq unique (municipality_id, id),
  constraint taxpayers_registration_uq unique (municipality_id, municipal_registration)
);

create unique index taxpayers_tax_id_uq
  on public.taxpayers (municipality_id, tax_id)
  where tax_id is not null;
create index taxpayers_name_search_idx
  on public.taxpayers using gin (
    to_tsvector(
      'portuguese',
      coalesce(legal_name, '') || ' ' || coalesce(trade_name, '') || ' ' ||
      coalesce(municipal_registration, '') || ' ' || coalesce(tax_id, '')
    )
  );

create table public.accounting_firms (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  tax_id text check (tax_id is null or tax_id ~ '^([0-9]{11}|[0-9]{14})$'),
  legal_name text not null,
  trade_name text,
  registration_code text,
  status text not null default 'active'
    check (status in ('active', 'inactive', 'suspended')),
  source_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_firms_municipality_id_id_uq unique (municipality_id, id)
);

create unique index accounting_firms_tax_id_uq
  on public.accounting_firms (municipality_id, tax_id)
  where tax_id is not null;
create index accounting_firms_name_search_idx
  on public.accounting_firms using gin (
    to_tsvector(
      'portuguese',
      coalesce(legal_name, '') || ' ' || coalesce(trade_name, '') || ' ' ||
      coalesce(tax_id, '')
    )
  );

create table public.taxpayer_user_links (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  access_role text not null
    check (access_role in ('owner', 'legal_representative', 'authorized_user', 'readonly')),
  status text not null default 'pending'
    check (status in ('pending', 'active', 'suspended', 'revoked')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  evidence_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint taxpayer_user_links_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint taxpayer_user_links_validity_ck
    check (valid_until is null or valid_until > valid_from),
  constraint taxpayer_user_links_verification_ck
    check (status <> 'active' or verified_at is not null),
  constraint taxpayer_user_links_municipality_id_id_uq unique (municipality_id, id),
  constraint taxpayer_user_links_user_uq unique (municipality_id, taxpayer_id, user_id)
);

create index taxpayer_user_links_user_active_idx
  on public.taxpayer_user_links (user_id, municipality_id, taxpayer_id)
  where status = 'active';

create table public.accountant_user_links (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  accounting_firm_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  access_role text not null
    check (access_role in ('owner', 'accountant', 'authorized_user', 'readonly')),
  status text not null default 'pending'
    check (status in ('pending', 'active', 'suspended', 'revoked')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accountant_user_links_firm_fk
    foreign key (municipality_id, accounting_firm_id)
    references public.accounting_firms(municipality_id, id) on delete cascade,
  constraint accountant_user_links_validity_ck
    check (valid_until is null or valid_until > valid_from),
  constraint accountant_user_links_verification_ck
    check (status <> 'active' or verified_at is not null),
  constraint accountant_user_links_municipality_id_id_uq unique (municipality_id, id),
  constraint accountant_user_links_user_uq unique (municipality_id, accounting_firm_id, user_id)
);

create index accountant_user_links_user_active_idx
  on public.accountant_user_links (user_id, municipality_id, accounting_firm_id)
  where status = 'active';

create table public.taxpayer_accountant_links (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  accounting_firm_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'suspended', 'revoked', 'expired')),
  valid_from timestamptz not null,
  valid_until timestamptz,
  can_receive_initial_notice boolean not null default false,
  can_access_portal boolean not null default false,
  authorization_basis text,
  evidence_reference text,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint taxpayer_accountant_links_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint taxpayer_accountant_links_firm_fk
    foreign key (municipality_id, accounting_firm_id)
    references public.accounting_firms(municipality_id, id) on delete cascade,
  constraint taxpayer_accountant_links_validity_ck
    check (valid_until is null or valid_until > valid_from),
  constraint taxpayer_accountant_links_verification_ck
    check (
      status <> 'active'
      or (verified_at is not null and nullif(trim(authorization_basis), '') is not null)
    ),
  constraint taxpayer_accountant_links_municipality_id_id_uq unique (municipality_id, id),
  constraint taxpayer_accountant_links_parties_uq
    unique (municipality_id, taxpayer_id, accounting_firm_id, valid_from)
);

create index taxpayer_accountant_links_active_taxpayer_idx
  on public.taxpayer_accountant_links (municipality_id, taxpayer_id, accounting_firm_id)
  where status = 'active';

create table public.party_contacts (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid,
  accounting_firm_id uuid,
  contact_type text not null check (contact_type in ('email', 'phone')),
  label text,
  value text not null,
  normalized_value extensions.citext not null,
  is_primary boolean not null default false,
  status text not null default 'unverified'
    check (status in ('unverified', 'verified', 'invalid', 'revoked')),
  source text not null default 'manual'
    check (source in ('manual', 'import', 'source_system', 'user_confirmed')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint party_contacts_exactly_one_party_ck check (
    (taxpayer_id is not null and accounting_firm_id is null)
    or (taxpayer_id is null and accounting_firm_id is not null)
  ),
  constraint party_contacts_email_ck check (
    contact_type <> 'email'
    or normalized_value::text ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint party_contacts_validity_ck
    check (valid_until is null or valid_until > valid_from),
  constraint party_contacts_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint party_contacts_firm_fk
    foreign key (municipality_id, accounting_firm_id)
    references public.accounting_firms(municipality_id, id) on delete cascade,
  constraint party_contacts_municipality_id_id_uq unique (municipality_id, id)
);

create unique index party_contacts_taxpayer_value_uq
  on public.party_contacts (municipality_id, taxpayer_id, contact_type, normalized_value)
  where taxpayer_id is not null;
create unique index party_contacts_firm_value_uq
  on public.party_contacts (municipality_id, accounting_firm_id, contact_type, normalized_value)
  where accounting_firm_id is not null;
create index party_contacts_verified_taxpayer_idx
  on public.party_contacts (municipality_id, taxpayer_id, contact_type, is_primary)
  where status = 'verified';
create index party_contacts_verified_firm_idx
  on public.party_contacts (municipality_id, accounting_firm_id, contact_type, is_primary)
  where status = 'verified';

create table public.source_systems (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  integration_id uuid,
  code text not null,
  name text not null,
  source_type text not null
    check (source_type in ('manual_file', 'database', 'api', 'webhook')),
  status text not null default 'inactive'
    check (status in ('inactive', 'testing', 'active', 'error', 'disabled')),
  data_contract_version text,
  non_secret_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(non_secret_config) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint source_systems_integration_fk
    foreign key (municipality_id, integration_id)
    references public.integrations(municipality_id, id) on delete set null,
  constraint source_systems_municipality_id_id_uq unique (municipality_id, id),
  constraint source_systems_code_uq unique (municipality_id, code)
);

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_system_id uuid not null,
  import_type text not null
    check (import_type in ('taxpayers', 'contacts', 'current_account', 'mixed')),
  status text not null default 'received'
    check (status in ('received', 'validating', 'validated', 'processing', 'completed', 'failed', 'cancelled')),
  source_file_name text,
  source_storage_path text,
  source_sha256 text check (source_sha256 is null or source_sha256 ~ '^[a-f0-9]{64}$'),
  idempotency_key text not null,
  row_count integer not null default 0 check (row_count >= 0),
  accepted_count integer not null default 0 check (accepted_count >= 0),
  rejected_count integer not null default 0 check (rejected_count >= 0),
  requested_by uuid references auth.users(id) on delete set null,
  received_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  error_summary jsonb not null default '{}'::jsonb
    check (jsonb_typeof(error_summary) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_batches_source_fk
    foreign key (municipality_id, source_system_id)
    references public.source_systems(municipality_id, id),
  constraint import_batches_counts_ck
    check (accepted_count + rejected_count <= row_count or row_count = 0),
  constraint import_batches_municipality_id_id_uq unique (municipality_id, id),
  constraint import_batches_idempotency_uq unique (municipality_id, idempotency_key)
);

create index import_batches_status_received_idx
  on public.import_batches (municipality_id, status, received_at desc);

create table private.import_staging_rows (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  import_batch_id uuid not null,
  row_number integer not null check (row_number > 0),
  raw_data jsonb not null check (jsonb_typeof(raw_data) = 'object'),
  normalized_data jsonb check (normalized_data is null or jsonb_typeof(normalized_data) = 'object'),
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  validation_status text not null default 'pending'
    check (validation_status in ('pending', 'valid', 'invalid', 'processed')),
  created_at timestamptz not null default now(),
  constraint import_staging_rows_batch_fk
    foreign key (municipality_id, import_batch_id)
    references public.import_batches(municipality_id, id) on delete cascade,
  constraint import_staging_rows_batch_row_uq
    unique (municipality_id, import_batch_id, row_number)
);

create index import_staging_rows_pending_idx
  on private.import_staging_rows (municipality_id, import_batch_id, id)
  where validation_status in ('pending', 'valid');

create table public.import_batch_errors (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  import_batch_id uuid not null,
  row_number integer,
  field_name text,
  error_code text not null,
  safe_message text not null,
  severity text not null default 'error'
    check (severity in ('warning', 'error', 'critical')),
  created_at timestamptz not null default now(),
  constraint import_batch_errors_batch_fk
    foreign key (municipality_id, import_batch_id)
    references public.import_batches(municipality_id, id) on delete cascade
);

create index import_batch_errors_batch_idx
  on public.import_batch_errors (municipality_id, import_batch_id, row_number, id);

create table public.current_account_entries (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  source_system_id uuid not null,
  import_batch_id uuid,
  external_record_id text not null,
  entry_kind text not null
    check (entry_kind in ('assessment', 'payment', 'credit', 'penalty', 'interest', 'adjustment', 'reversal')),
  direction text not null check (direction in ('debit', 'credit')),
  amount numeric(18,2) not null check (amount >= 0),
  competence_month date not null,
  occurred_on date not null,
  due_on date,
  status text not null default 'valid'
    check (status in ('valid', 'cancelled', 'suspended', 'contested', 'reversed')),
  tax_code text,
  document_reference text,
  payload_sha256 text check (payload_sha256 is null or payload_sha256 ~ '^[a-f0-9]{64}$'),
  source_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_snapshot) = 'object'),
  imported_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint current_account_entries_competence_ck
    check (competence_month = date_trunc('month', competence_month)::date),
  constraint current_account_entries_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint current_account_entries_source_fk
    foreign key (municipality_id, source_system_id)
    references public.source_systems(municipality_id, id),
  constraint current_account_entries_batch_fk
    foreign key (municipality_id, import_batch_id)
    references public.import_batches(municipality_id, id) on delete set null,
  constraint current_account_entries_municipality_id_id_uq unique (municipality_id, id),
  constraint current_account_entries_external_uq
    unique (municipality_id, source_system_id, external_record_id)
);

create index current_account_entries_taxpayer_period_idx
  on public.current_account_entries (
    municipality_id, taxpayer_id, competence_month, status, direction
  );
create index current_account_entries_batch_idx
  on public.current_account_entries (municipality_id, import_batch_id)
  where import_batch_id is not null;

create table public.taxpayer_fiscal_conditions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  condition_type text not null
    check (condition_type in ('installment', 'compensation', 'suspension', 'contest', 'judicial_order', 'manual_block')),
  status text not null default 'active'
    check (status in ('active', 'resolved', 'cancelled', 'expired')),
  blocks_automation boolean not null default true,
  period_start date,
  period_end date,
  reason text,
  source_reference text,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint taxpayer_fiscal_conditions_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint taxpayer_fiscal_conditions_period_ck
    check (period_end is null or period_start is null or period_end >= period_start),
  constraint taxpayer_fiscal_conditions_effective_ck
    check (effective_until is null or effective_until > effective_from),
  constraint taxpayer_fiscal_conditions_municipality_id_id_uq unique (municipality_id, id)
);

create index taxpayer_fiscal_conditions_blocking_idx
  on public.taxpayer_fiscal_conditions (municipality_id, taxpayer_id, period_start, period_end)
  where status = 'active' and blocks_automation;

create table public.divergence_rules (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  divergence_type text not null check (divergence_type in ('current_account_balance')),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint divergence_rules_municipality_id_id_uq unique (municipality_id, id),
  constraint divergence_rules_code_uq unique (municipality_id, code)
);

create table public.divergence_rule_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  rule_id uuid not null,
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'approved', 'active', 'retired', 'rejected')),
  implementation_key text not null,
  implementation_version text not null,
  parameters jsonb not null default '{}'::jsonb
    check (jsonb_typeof(parameters) = 'object'),
  checksum_sha256 text not null check (checksum_sha256 ~ '^[a-f0-9]{64}$'),
  effective_from timestamptz,
  effective_until timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint divergence_rule_versions_rule_fk
    foreign key (municipality_id, rule_id)
    references public.divergence_rules(municipality_id, id) on delete cascade,
  constraint divergence_rule_versions_approval_ck
    check (
      status not in ('approved', 'active')
      or (approved_by is not null and approved_at is not null)
    ),
  constraint divergence_rule_versions_effective_ck
    check (effective_until is null or effective_from is null or effective_until > effective_from),
  constraint divergence_rule_versions_municipality_id_id_uq unique (municipality_id, id),
  constraint divergence_rule_versions_number_uq unique (municipality_id, rule_id, version)
);

create unique index divergence_rule_versions_one_active_idx
  on public.divergence_rule_versions (municipality_id, rule_id)
  where status = 'active';

create table public.detection_runs (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  rule_version_id uuid not null,
  import_batch_id uuid,
  status text not null default 'queued'
    check (status in ('queued', 'running', 'completed', 'failed', 'cancelled')),
  as_of timestamptz not null,
  period_start date not null,
  period_end date not null,
  idempotency_key text not null,
  candidate_count integer not null default 0 check (candidate_count >= 0),
  divergence_count integer not null default 0 check (divergence_count >= 0),
  blocked_count integer not null default 0 check (blocked_count >= 0),
  started_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  finished_at timestamptz,
  error_code text,
  error_detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint detection_runs_rule_fk
    foreign key (municipality_id, rule_version_id)
    references public.divergence_rule_versions(municipality_id, id),
  constraint detection_runs_batch_fk
    foreign key (municipality_id, import_batch_id)
    references public.import_batches(municipality_id, id) on delete set null,
  constraint detection_runs_period_ck check (period_end >= period_start),
  constraint detection_runs_municipality_id_id_uq unique (municipality_id, id),
  constraint detection_runs_idempotency_uq unique (municipality_id, idempotency_key)
);

create index detection_runs_status_idx
  on public.detection_runs (municipality_id, status, created_at desc);

create table public.divergences (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  detection_run_id uuid not null,
  rule_version_id uuid not null,
  divergence_type text not null check (divergence_type in ('current_account_balance')),
  period_start date not null,
  period_end date not null,
  as_of timestamptz not null,
  assessed_amount numeric(18,2) not null default 0,
  paid_amount numeric(18,2) not null default 0,
  other_credits_amount numeric(18,2) not null default 0,
  difference_amount numeric(18,2) not null,
  threshold_amount numeric(18,2) not null,
  priority_score numeric(10,4) not null default 0,
  status text not null default 'detected'
    check (status in ('detected', 'pending_revalidation', 'eligible', 'blocked', 'converted', 'resolved', 'dismissed')),
  block_reasons jsonb not null default '[]'::jsonb
    check (jsonb_typeof(block_reasons) = 'array'),
  source_snapshot jsonb not null check (jsonb_typeof(source_snapshot) = 'object'),
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  last_revalidated_at timestamptz,
  resolved_at timestamptz,
  resolved_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint divergences_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id),
  constraint divergences_run_fk
    foreign key (municipality_id, detection_run_id)
    references public.detection_runs(municipality_id, id) on delete cascade,
  constraint divergences_rule_fk
    foreign key (municipality_id, rule_version_id)
    references public.divergence_rule_versions(municipality_id, id),
  constraint divergences_period_ck check (period_end >= period_start),
  constraint divergences_amount_ck check (
    assessed_amount >= 0 and paid_amount >= 0 and other_credits_amount >= 0
    and difference_amount >= 0 and threshold_amount >= 0
  ),
  constraint divergences_municipality_id_id_uq unique (municipality_id, id),
  constraint divergences_municipality_id_id_taxpayer_uq
    unique (municipality_id, id, taxpayer_id),
  constraint divergences_run_taxpayer_period_uq
    unique (
      municipality_id, detection_run_id, taxpayer_id,
      divergence_type, period_start, period_end
    )
);

create index divergences_work_queue_idx
  on public.divergences (
    municipality_id, status, priority_score desc, difference_amount desc, id
  )
  where status in ('detected', 'pending_revalidation', 'eligible');
create index divergences_taxpayer_idx
  on public.divergences (municipality_id, taxpayer_id, created_at desc);

create table public.divergence_items (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  divergence_id uuid not null,
  current_account_entry_id uuid not null,
  entry_kind text not null,
  direction text not null check (direction in ('debit', 'credit')),
  amount_snapshot numeric(18,2) not null check (amount_snapshot >= 0),
  competence_month date not null,
  source_sha256 text check (source_sha256 is null or source_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint divergence_items_divergence_fk
    foreign key (municipality_id, divergence_id)
    references public.divergences(municipality_id, id) on delete cascade,
  constraint divergence_items_entry_fk
    foreign key (municipality_id, current_account_entry_id)
    references public.current_account_entries(municipality_id, id),
  constraint divergence_items_entry_uq
    unique (municipality_id, divergence_id, current_account_entry_id)
);

create index divergence_items_entry_idx
  on public.divergence_items (municipality_id, current_account_entry_id);

create table public.divergence_revalidations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  divergence_id uuid not null,
  revalidation_number integer not null check (revalidation_number > 0),
  assessed_amount numeric(18,2) not null,
  paid_amount numeric(18,2) not null,
  other_credits_amount numeric(18,2) not null,
  difference_amount numeric(18,2) not null,
  eligible boolean not null,
  block_reasons jsonb not null default '[]'::jsonb
    check (jsonb_typeof(block_reasons) = 'array'),
  source_snapshot jsonb not null check (jsonb_typeof(source_snapshot) = 'object'),
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  performed_by uuid references auth.users(id) on delete set null,
  performed_at timestamptz not null default now(),
  constraint divergence_revalidations_divergence_fk
    foreign key (municipality_id, divergence_id)
    references public.divergences(municipality_id, id) on delete cascade,
  constraint divergence_revalidations_amount_ck check (
    assessed_amount >= 0 and paid_amount >= 0 and other_credits_amount >= 0
    and difference_amount >= 0
  ),
  constraint divergence_revalidations_number_uq
    unique (municipality_id, divergence_id, revalidation_number),
  constraint divergence_revalidations_municipality_id_id_uq unique (municipality_id, id)
);

create index divergence_revalidations_latest_idx
  on public.divergence_revalidations (municipality_id, divergence_id, revalidation_number desc);

create table private.municipality_case_counters (
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  year integer not null check (year between 2000 and 9999),
  last_value bigint not null default 0 check (last_value >= 0),
  primary key (municipality_id, year)
);

create table public.case_opening_batches (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  detection_run_id uuid not null,
  policy_version_id uuid not null,
  status text not null default 'draft'
    check (status in ('draft', 'submitted', 'approved', 'processing', 'completed', 'rejected', 'cancelled')),
  requested_count integer not null default 0 check (requested_count >= 0),
  approved_count integer not null default 0 check (approved_count >= 0),
  opened_count integer not null default 0 check (opened_count >= 0),
  blocked_count integer not null default 0 check (blocked_count >= 0),
  idempotency_key text not null,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  approval_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint case_opening_batches_run_fk
    foreign key (municipality_id, detection_run_id)
    references public.detection_runs(municipality_id, id),
  constraint case_opening_batches_policy_fk
    foreign key (municipality_id, policy_version_id)
    references public.municipality_policy_versions(municipality_id, id),
  constraint case_opening_batches_approval_ck
    check (
      status not in ('approved', 'processing', 'completed')
      or (approved_by is not null and approved_at is not null)
    ),
  constraint case_opening_batches_municipality_id_id_uq unique (municipality_id, id),
  constraint case_opening_batches_idempotency_uq unique (municipality_id, idempotency_key)
);

create index case_opening_batches_status_idx
  on public.case_opening_batches (municipality_id, status, created_at desc);

create table public.case_opening_batch_items (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  batch_id uuid not null,
  divergence_id uuid not null,
  assigned_membership_id uuid,
  status text not null default 'selected'
    check (status in ('selected', 'excluded', 'approved', 'revalidating', 'blocked', 'opened', 'failed')),
  selection_rank integer check (selection_rank is null or selection_rank > 0),
  exclusion_reason text,
  last_error_code text,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint case_opening_batch_items_batch_fk
    foreign key (municipality_id, batch_id)
    references public.case_opening_batches(municipality_id, id) on delete cascade,
  constraint case_opening_batch_items_divergence_fk
    foreign key (municipality_id, divergence_id)
    references public.divergences(municipality_id, id),
  constraint case_opening_batch_items_assignment_fk
    foreign key (municipality_id, assigned_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint case_opening_batch_items_municipality_id_id_uq unique (municipality_id, id),
  constraint case_opening_batch_items_id_divergence_uq
    unique (municipality_id, id, divergence_id),
  constraint case_opening_batch_items_divergence_uq
    unique (municipality_id, batch_id, divergence_id)
);

create index case_opening_batch_items_work_idx
  on public.case_opening_batch_items (municipality_id, batch_id, status, selection_rank, id)
  where status in ('approved', 'revalidating');

create table public.fiscal_cases (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  taxpayer_id uuid not null,
  divergence_id uuid not null,
  batch_item_id uuid not null,
  case_number text not null,
  status text not null default 'opened'
    check (status in (
      'opened',
      'initial_notice_pending',
      'initial_notice_sent',
      'awaiting_access',
      'awaiting_taxpayer',
      'awaiting_fiscal',
      'under_review',
      'resolved',
      'closed',
      'cancelled'
    )),
  confidentiality text not null default 'fiscal_secret'
    check (confidentiality in ('internal', 'restricted', 'fiscal_secret')),
  opened_at timestamptz not null default now(),
  opened_by uuid references auth.users(id) on delete set null,
  first_accessed_at timestamptz,
  closed_at timestamptz,
  closure_reason text,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fiscal_cases_divergence_taxpayer_fk
    foreign key (municipality_id, divergence_id, taxpayer_id)
    references public.divergences(municipality_id, id, taxpayer_id),
  constraint fiscal_cases_batch_item_divergence_fk
    foreign key (municipality_id, batch_item_id, divergence_id)
    references public.case_opening_batch_items(municipality_id, id, divergence_id),
  constraint fiscal_cases_municipality_id_id_uq unique (municipality_id, id),
  constraint fiscal_cases_number_uq unique (municipality_id, case_number),
  constraint fiscal_cases_divergence_uq unique (municipality_id, divergence_id)
);

create index fiscal_cases_status_idx
  on public.fiscal_cases (municipality_id, status, opened_at desc, id);
create index fiscal_cases_taxpayer_idx
  on public.fiscal_cases (municipality_id, taxpayer_id, opened_at desc);

create table public.case_findings (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  case_id uuid not null,
  divergence_id uuid not null,
  rule_version_id uuid not null,
  revalidation_id uuid not null,
  assessed_amount numeric(18,2) not null check (assessed_amount >= 0),
  paid_amount numeric(18,2) not null check (paid_amount >= 0),
  other_credits_amount numeric(18,2) not null check (other_credits_amount >= 0),
  difference_amount numeric(18,2) not null check (difference_amount >= 0),
  period_start date not null,
  period_end date not null,
  finding_snapshot jsonb not null check (jsonb_typeof(finding_snapshot) = 'object'),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint case_findings_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint case_findings_divergence_fk
    foreign key (municipality_id, divergence_id)
    references public.divergences(municipality_id, id),
  constraint case_findings_rule_fk
    foreign key (municipality_id, rule_version_id)
    references public.divergence_rule_versions(municipality_id, id),
  constraint case_findings_revalidation_fk
    foreign key (municipality_id, revalidation_id)
    references public.divergence_revalidations(municipality_id, id),
  constraint case_findings_period_ck check (period_end >= period_start),
  constraint case_findings_municipality_id_id_uq unique (municipality_id, id),
  constraint case_findings_case_uq unique (municipality_id, case_id)
);

create index case_findings_divergence_idx
  on public.case_findings (municipality_id, divergence_id);

create table public.case_assignments (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  case_id uuid not null,
  membership_id uuid not null,
  assignment_role text not null
    check (assignment_role in ('responsible_fiscal', 'reviewer', 'supervisor', 'collaborator')),
  status text not null default 'active'
    check (status in ('active', 'completed', 'revoked')),
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint case_assignments_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint case_assignments_membership_fk
    foreign key (municipality_id, membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint case_assignments_municipality_id_id_uq unique (municipality_id, id)
);

create unique index case_assignments_active_role_uq
  on public.case_assignments (municipality_id, case_id, membership_id, assignment_role)
  where status = 'active';
create index case_assignments_member_active_idx
  on public.case_assignments (municipality_id, membership_id, case_id)
  where status = 'active';

create table public.case_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  case_id uuid not null,
  event_type text not null,
  visibility text not null default 'staff'
    check (visibility in ('staff', 'participants')),
  actor_type text not null
    check (actor_type in ('system', 'staff', 'taxpayer', 'accountant', 'service')),
  actor_user_id uuid references auth.users(id) on delete set null,
  correlation_id uuid not null default gen_random_uuid(),
  event_data jsonb not null default '{}'::jsonb
    check (jsonb_typeof(event_data) = 'object'),
  occurred_at timestamptz not null default now(),
  constraint case_events_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade
);

create index case_events_timeline_idx
  on public.case_events (municipality_id, case_id, occurred_at, id);

create trigger taxpayers_set_updated_at
  before update on public.taxpayers
  for each row execute function private.set_updated_at();
create trigger accounting_firms_set_updated_at
  before update on public.accounting_firms
  for each row execute function private.set_updated_at();
create trigger taxpayer_user_links_set_updated_at
  before update on public.taxpayer_user_links
  for each row execute function private.set_updated_at();
create trigger accountant_user_links_set_updated_at
  before update on public.accountant_user_links
  for each row execute function private.set_updated_at();
create trigger taxpayer_accountant_links_set_updated_at
  before update on public.taxpayer_accountant_links
  for each row execute function private.set_updated_at();
create trigger party_contacts_set_updated_at
  before update on public.party_contacts
  for each row execute function private.set_updated_at();
create trigger source_systems_set_updated_at
  before update on public.source_systems
  for each row execute function private.set_updated_at();
create trigger import_batches_set_updated_at
  before update on public.import_batches
  for each row execute function private.set_updated_at();
create trigger current_account_entries_set_updated_at
  before update on public.current_account_entries
  for each row execute function private.set_updated_at();
create trigger taxpayer_fiscal_conditions_set_updated_at
  before update on public.taxpayer_fiscal_conditions
  for each row execute function private.set_updated_at();
create trigger divergence_rules_set_updated_at
  before update on public.divergence_rules
  for each row execute function private.set_updated_at();
create trigger divergence_rule_versions_set_updated_at
  before update on public.divergence_rule_versions
  for each row execute function private.set_updated_at();
create trigger detection_runs_set_updated_at
  before update on public.detection_runs
  for each row execute function private.set_updated_at();
create trigger divergences_set_updated_at
  before update on public.divergences
  for each row execute function private.set_updated_at();
create trigger case_opening_batches_set_updated_at
  before update on public.case_opening_batches
  for each row execute function private.set_updated_at();
create trigger case_opening_batch_items_set_updated_at
  before update on public.case_opening_batch_items
  for each row execute function private.set_updated_at();
create trigger fiscal_cases_set_updated_at
  before update on public.fiscal_cases
  for each row execute function private.set_updated_at();
create trigger case_assignments_set_updated_at
  before update on public.case_assignments
  for each row execute function private.set_updated_at();

commit;

