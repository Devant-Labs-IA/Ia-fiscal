begin;

create table public.notification_templates (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  code text not null,
  name text not null,
  notification_type text not null check (notification_type in ('initial_inspection_alert')),
  legal_nature text not null default 'informational_alert'
    check (legal_nature = 'informational_alert'),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_templates_municipality_id_id_uq unique (municipality_id, id),
  constraint notification_templates_code_uq unique (municipality_id, code)
);

create table public.notification_template_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  template_id uuid not null,
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'approved', 'active', 'retired', 'rejected')),
  subject text not null,
  body_text text not null,
  body_html text,
  allowed_placeholders text[] not null default '{}'::text[],
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_template_versions_template_fk
    foreign key (municipality_id, template_id)
    references public.notification_templates(municipality_id, id) on delete cascade,
  constraint notification_template_versions_approval_ck check (
    status not in ('approved', 'active')
    or (approved_by is not null and approved_at is not null)
  ),
  constraint notification_template_versions_municipality_id_id_uq unique (municipality_id, id),
  constraint notification_template_versions_number_uq
    unique (municipality_id, template_id, version)
);

create unique index notification_template_versions_one_active_idx
  on public.notification_template_versions (municipality_id, template_id)
  where status = 'active';

create table public.notification_channel_settings (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  integration_id uuid,
  channel text not null default 'email' check (channel = 'email'),
  status text not null default 'disabled'
    check (status in ('disabled', 'testing', 'active', 'error')),
  sender_name text,
  sender_email extensions.citext,
  reply_to_email extensions.citext,
  initial_template_version_id uuid,
  daily_limit integer not null default 30 check (daily_limit between 1 and 100000),
  monthly_limit integer not null default 500 check (monthly_limit between 1 and 10000000),
  kill_switch boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_channel_settings_integration_fk
    foreign key (municipality_id, integration_id)
    references public.integrations(municipality_id, id) on delete set null,
  constraint notification_channel_settings_template_fk
    foreign key (municipality_id, initial_template_version_id)
    references public.notification_template_versions(municipality_id, id),
  constraint notification_channel_settings_sender_ck
    check (
      status <> 'active'
      or (
        sender_name is not null
        and sender_email is not null
        and initial_template_version_id is not null
        and kill_switch = false
      )
    ),
  constraint notification_channel_settings_municipality_id_id_uq unique (municipality_id, id),
  constraint notification_channel_settings_channel_uq unique (municipality_id, channel)
);

create table public.notification_batches (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  case_opening_batch_id uuid not null,
  status text not null default 'preparing'
    check (status in ('preparing', 'queued', 'processing', 'completed', 'partially_failed', 'failed', 'cancelled')),
  idempotency_key text not null,
  total_notifications integer not null default 0 check (total_notifications >= 0),
  sent_notifications integer not null default 0 check (sent_notifications >= 0),
  failed_notifications integer not null default 0 check (failed_notifications >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_batches_case_batch_fk
    foreign key (municipality_id, case_opening_batch_id)
    references public.case_opening_batches(municipality_id, id),
  constraint notification_batches_municipality_id_id_uq unique (municipality_id, id),
  constraint notification_batches_idempotency_uq unique (municipality_id, idempotency_key)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  notification_batch_id uuid,
  case_id uuid not null,
  template_version_id uuid not null,
  notification_type text not null check (notification_type = 'initial_inspection_alert'),
  legal_nature text not null check (legal_nature = 'informational_alert'),
  subject_snapshot text not null,
  body_text_snapshot text not null,
  body_html_snapshot text,
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'prepared'
    check (status in ('prepared', 'queued', 'processing', 'sent', 'partially_failed', 'failed', 'cancelled')),
  idempotency_key text not null,
  prepared_at timestamptz not null default now(),
  queued_at timestamptz,
  sent_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notifications_batch_fk
    foreign key (municipality_id, notification_batch_id)
    references public.notification_batches(municipality_id, id) on delete set null,
  constraint notifications_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id),
  constraint notifications_template_fk
    foreign key (municipality_id, template_version_id)
    references public.notification_template_versions(municipality_id, id),
  constraint notifications_municipality_id_id_uq unique (municipality_id, id),
  constraint notifications_case_type_uq unique (municipality_id, case_id, notification_type),
  constraint notifications_idempotency_uq unique (municipality_id, idempotency_key)
);

create index notifications_queue_idx
  on public.notifications (municipality_id, status, prepared_at, id)
  where status in ('prepared', 'queued', 'processing');

create table public.notification_recipients (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  notification_id uuid not null,
  recipient_type text not null check (recipient_type in ('taxpayer', 'accountant')),
  contact_id uuid not null,
  taxpayer_accountant_link_id uuid,
  email_snapshot extensions.citext not null,
  relationship_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(relationship_snapshot) = 'object'),
  status text not null default 'pending'
    check (status in ('pending', 'queued', 'sent', 'delivered', 'failed', 'bounced', 'cancelled')),
  idempotency_key text not null,
  resolved_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_recipients_notification_fk
    foreign key (municipality_id, notification_id)
    references public.notifications(municipality_id, id) on delete cascade,
  constraint notification_recipients_contact_fk
    foreign key (municipality_id, contact_id)
    references public.party_contacts(municipality_id, id),
  constraint notification_recipients_accountant_link_fk
    foreign key (municipality_id, taxpayer_accountant_link_id)
    references public.taxpayer_accountant_links(municipality_id, id),
  constraint notification_recipients_accountant_ck check (
    (recipient_type = 'taxpayer' and taxpayer_accountant_link_id is null)
    or (recipient_type = 'accountant' and taxpayer_accountant_link_id is not null)
  ),
  constraint notification_recipients_municipality_id_id_uq unique (municipality_id, id),
  constraint notification_recipients_email_uq
    unique (municipality_id, notification_id, email_snapshot),
  constraint notification_recipients_idempotency_uq unique (municipality_id, idempotency_key)
);

create index notification_recipients_delivery_idx
  on public.notification_recipients (municipality_id, status, created_at, id)
  where status in ('pending', 'queued', 'failed');

create table private.delivery_attempts (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  recipient_id uuid not null,
  attempt_number integer not null check (attempt_number > 0),
  provider_code text not null,
  provider_message_id text,
  idempotency_key text not null,
  status text not null
    check (status in ('started', 'accepted', 'delivered', 'temporary_failure', 'permanent_failure', 'ambiguous')),
  response_code integer,
  safe_error_code text,
  safe_error_detail text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  next_attempt_at timestamptz,
  constraint delivery_attempts_recipient_fk
    foreign key (municipality_id, recipient_id)
    references public.notification_recipients(municipality_id, id) on delete cascade,
  constraint delivery_attempts_attempt_uq
    unique (municipality_id, recipient_id, attempt_number),
  constraint delivery_attempts_idempotency_uq
    unique (municipality_id, idempotency_key)
);

create index delivery_attempts_retry_idx
  on private.delivery_attempts (municipality_id, next_attempt_at, id)
  where status in ('temporary_failure', 'ambiguous');

create table private.email_provider_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  provider_code text not null,
  provider_event_id text not null,
  provider_message_id text,
  event_type text not null,
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  safe_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(safe_payload) = 'object'),
  occurred_at timestamptz,
  received_at timestamptz not null default now(),
  constraint email_provider_events_uq
    unique (provider_code, provider_event_id)
);

create table public.case_threads (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  case_id uuid not null,
  status text not null default 'open' check (status in ('open', 'locked', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint case_threads_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint case_threads_municipality_id_id_uq unique (municipality_id, id),
  constraint case_threads_id_case_uq unique (municipality_id, id, case_id),
  constraint case_threads_case_uq unique (municipality_id, case_id)
);

create table public.case_messages (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  thread_id uuid not null,
  case_id uuid not null,
  parent_message_id uuid,
  sender_type text not null
    check (sender_type in ('taxpayer', 'accountant', 'fiscal', 'system')),
  author_user_id uuid references auth.users(id) on delete set null,
  source_type text not null default 'human'
    check (source_type in ('human', 'approved_ai_draft', 'system')),
  visibility text not null default 'participants'
    check (visibility in ('participants', 'staff')),
  body text not null check (char_length(trim(body)) between 1 and 20000),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'draft'
    check (status in ('draft', 'published', 'withdrawn')),
  client_request_id text,
  published_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint case_messages_thread_fk
    foreign key (municipality_id, thread_id)
    references public.case_threads(municipality_id, id) on delete cascade,
  constraint case_messages_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint case_messages_parent_fk
    foreign key (municipality_id, parent_message_id)
    references public.case_messages(municipality_id, id),
  constraint case_messages_publish_ck check (
    (status = 'published' and published_at is not null)
    or status <> 'published'
  ),
  constraint case_messages_author_ck check (
    (sender_type = 'system')
    or author_user_id is not null
  ),
  constraint case_messages_thread_case_fk
    foreign key (municipality_id, thread_id, case_id)
    references public.case_threads(municipality_id, id, case_id),
  constraint case_messages_municipality_id_id_uq unique (municipality_id, id),
  constraint case_messages_id_case_uq unique (municipality_id, id, case_id)
);

create unique index case_messages_client_request_uq
  on public.case_messages (municipality_id, case_id, client_request_id)
  where client_request_id is not null;
create index case_messages_timeline_idx
  on public.case_messages (municipality_id, case_id, created_at, id);

create table public.case_questions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  case_id uuid not null,
  message_id uuid not null,
  status text not null default 'submitted'
    check (status in ('submitted', 'queued_for_ai', 'researching', 'awaiting_fiscal', 'answered', 'needs_manual_answer', 'closed')),
  assigned_membership_id uuid,
  submitted_at timestamptz not null default now(),
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint case_questions_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint case_questions_message_fk
    foreign key (municipality_id, message_id)
    references public.case_messages(municipality_id, id),
  constraint case_questions_message_case_fk
    foreign key (municipality_id, message_id, case_id)
    references public.case_messages(municipality_id, id, case_id),
  constraint case_questions_assignment_fk
    foreign key (municipality_id, assigned_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint case_questions_municipality_id_id_uq unique (municipality_id, id),
  constraint case_questions_id_case_uq unique (municipality_id, id, case_id),
  constraint case_questions_message_uq unique (municipality_id, message_id)
);

create index case_questions_work_queue_idx
  on public.case_questions (municipality_id, status, submitted_at, id)
  where status in ('submitted', 'queued_for_ai', 'researching', 'awaiting_fiscal');

create table private.message_access_snapshots (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  message_id uuid not null,
  user_id uuid not null references auth.users(id) on delete restrict,
  access_basis text not null
    check (access_basis in ('taxpayer_link', 'accountant_link', 'staff_membership')),
  access_reference_id uuid not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  created_at timestamptz not null default now(),
  constraint message_access_snapshots_message_fk
    foreign key (municipality_id, message_id)
    references public.case_messages(municipality_id, id) on delete cascade
);

create index message_access_snapshots_message_idx
  on private.message_access_snapshots (municipality_id, message_id, user_id);

create table public.legal_sources (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  source_type text not null
    check (source_type in ('law', 'decree', 'regulation', 'instruction', 'official_guidance', 'court_decision')),
  jurisdiction text not null,
  issuing_authority text not null,
  title text not null,
  official_identifier text,
  official_url text,
  tax_scope text not null default 'ISSQN',
  divergence_scope text not null default 'current_account_balance',
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_sources_municipality_id_id_uq unique (municipality_id, id)
);

create unique index legal_sources_identifier_uq
  on public.legal_sources (municipality_id, issuing_authority, official_identifier)
  where official_identifier is not null;

create table public.legal_source_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_id uuid not null,
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'under_review', 'approved', 'published', 'revoked', 'retired')),
  content_text text not null,
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  valid_from date,
  valid_until date,
  publication_date date,
  supersedes_version_id uuid,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  published_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_source_versions_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id) on delete cascade,
  constraint legal_source_versions_supersedes_fk
    foreign key (municipality_id, supersedes_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint legal_source_versions_validity_ck
    check (valid_until is null or valid_from is null or valid_until >= valid_from),
  constraint legal_source_versions_approval_ck check (
    status not in ('approved', 'published')
    or (approved_by is not null and approved_at is not null)
  ),
  constraint legal_source_versions_publication_ck check (
    status <> 'published' or published_at is not null
  ),
  constraint legal_source_versions_municipality_id_id_uq unique (municipality_id, id),
  constraint legal_source_versions_number_uq unique (municipality_id, source_id, version)
);

create table public.legal_sections (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_version_id uuid not null,
  section_key text not null,
  heading text,
  ordinal integer not null check (ordinal > 0),
  content_text text not null,
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint legal_sections_version_fk
    foreign key (municipality_id, source_version_id)
    references public.legal_source_versions(municipality_id, id) on delete cascade,
  constraint legal_sections_municipality_id_id_uq unique (municipality_id, id),
  constraint legal_sections_key_uq unique (municipality_id, source_version_id, section_key)
);

create index legal_sections_source_idx
  on public.legal_sections (municipality_id, source_version_id, ordinal);

create table public.knowledge_releases (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  name text not null,
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'under_review', 'approved', 'published', 'retired', 'revoked')),
  tax_scope text not null default 'ISSQN',
  divergence_scope text not null default 'current_account_balance',
  effective_from timestamptz,
  effective_until timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  published_at timestamptz,
  release_sha256 text check (release_sha256 is null or release_sha256 ~ '^[a-f0-9]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint knowledge_releases_approval_ck check (
    status not in ('approved', 'published')
    or (approved_by is not null and approved_at is not null)
  ),
  constraint knowledge_releases_publication_ck check (
    status <> 'published' or (published_at is not null and release_sha256 is not null)
  ),
  constraint knowledge_releases_effective_ck
    check (effective_until is null or effective_from is null or effective_until > effective_from),
  constraint knowledge_releases_municipality_id_id_uq unique (municipality_id, id),
  constraint knowledge_releases_version_uq unique (municipality_id, name, version)
);

create unique index knowledge_releases_one_published_scope_idx
  on public.knowledge_releases (municipality_id, tax_scope, divergence_scope)
  where status = 'published';

create table public.knowledge_release_items (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  release_id uuid not null,
  source_version_id uuid not null,
  created_at timestamptz not null default now(),
  constraint knowledge_release_items_release_fk
    foreign key (municipality_id, release_id)
    references public.knowledge_releases(municipality_id, id) on delete cascade,
  constraint knowledge_release_items_version_fk
    foreign key (municipality_id, source_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint knowledge_release_items_municipality_id_id_uq unique (municipality_id, id),
  constraint knowledge_release_items_version_uq
    unique (municipality_id, release_id, source_version_id)
);

create table public.rule_legal_basis (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  rule_version_id uuid not null,
  knowledge_release_id uuid not null,
  legal_section_id uuid,
  basis_type text not null default 'primary'
    check (basis_type in ('primary', 'supporting', 'procedure')),
  created_at timestamptz not null default now(),
  constraint rule_legal_basis_rule_fk
    foreign key (municipality_id, rule_version_id)
    references public.divergence_rule_versions(municipality_id, id) on delete cascade,
  constraint rule_legal_basis_release_fk
    foreign key (municipality_id, knowledge_release_id)
    references public.knowledge_releases(municipality_id, id),
  constraint rule_legal_basis_section_fk
    foreign key (municipality_id, legal_section_id)
    references public.legal_sections(municipality_id, id),
  constraint rule_legal_basis_municipality_id_id_uq unique (municipality_id, id)
);

create table private.legal_chunks (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  legal_section_id uuid not null,
  chunk_index integer not null check (chunk_index >= 0),
  content_text text not null,
  token_count integer check (token_count is null or token_count > 0),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  search_vector tsvector generated always as (
    to_tsvector('portuguese', coalesce(content_text, ''))
  ) stored,
  created_at timestamptz not null default now(),
  constraint legal_chunks_section_fk
    foreign key (municipality_id, legal_section_id)
    references public.legal_sections(municipality_id, id) on delete cascade,
  constraint legal_chunks_section_index_uq
    unique (municipality_id, legal_section_id, chunk_index),
  constraint legal_chunks_municipality_id_id_uq unique (municipality_id, id)
);

create index legal_chunks_search_idx
  on private.legal_chunks using gin (search_vector);
create index legal_chunks_section_idx
  on private.legal_chunks (municipality_id, legal_section_id, chunk_index);

create table private.legal_embeddings (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  legal_chunk_id uuid not null,
  provider_code text not null,
  model text not null,
  dimensions integer not null check (dimensions between 1 and 16000),
  embedding extensions.vector not null,
  source_sha256 text not null check (source_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint legal_embeddings_chunk_fk
    foreign key (municipality_id, legal_chunk_id)
    references private.legal_chunks(municipality_id, id) on delete cascade,
  constraint legal_embeddings_model_uq
    unique (municipality_id, legal_chunk_id, provider_code, model)
);

create table public.ai_prompt_templates (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  code text not null,
  name text not null,
  purpose text not null check (purpose = 'fiscal_response_draft'),
  status text not null default 'draft' check (status in ('draft', 'active', 'retired')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_prompt_templates_municipality_id_id_uq unique (municipality_id, id),
  constraint ai_prompt_templates_code_uq unique (municipality_id, code)
);

create table public.ai_prompt_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  prompt_template_id uuid not null,
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'approved', 'active', 'retired', 'rejected')),
  system_prompt text not null,
  output_schema jsonb not null check (jsonb_typeof(output_schema) = 'object'),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_prompt_versions_template_fk
    foreign key (municipality_id, prompt_template_id)
    references public.ai_prompt_templates(municipality_id, id) on delete cascade,
  constraint ai_prompt_versions_approval_ck check (
    status not in ('approved', 'active')
    or (approved_by is not null and approved_at is not null)
  ),
  constraint ai_prompt_versions_municipality_id_id_uq unique (municipality_id, id),
  constraint ai_prompt_versions_number_uq
    unique (municipality_id, prompt_template_id, version)
);

create unique index ai_prompt_versions_one_active_idx
  on public.ai_prompt_versions (municipality_id, prompt_template_id)
  where status = 'active';

create table private.ai_runs (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  case_id uuid not null,
  question_id uuid not null,
  prompt_version_id uuid not null,
  knowledge_release_id uuid,
  provider_code text not null,
  model text not null,
  status text not null default 'started'
    check (status in ('started', 'completed', 'failed', 'blocked_no_sources', 'blocked_configuration')),
  request_sha256 text not null check (request_sha256 ~ '^[a-f0-9]{64}$'),
  response_sha256 text check (response_sha256 is null or response_sha256 ~ '^[a-f0-9]{64}$'),
  provider_response_id text,
  input_tokens integer check (input_tokens is null or input_tokens >= 0),
  output_tokens integer check (output_tokens is null or output_tokens >= 0),
  estimated_cost numeric(18,8) check (estimated_cost is null or estimated_cost >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  safe_error_code text,
  safe_error_detail text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint ai_runs_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint ai_runs_question_case_fk
    foreign key (municipality_id, question_id, case_id)
    references public.case_questions(municipality_id, id, case_id) on delete cascade,
  constraint ai_runs_prompt_fk
    foreign key (municipality_id, prompt_version_id)
    references public.ai_prompt_versions(municipality_id, id),
  constraint ai_runs_release_fk
    foreign key (municipality_id, knowledge_release_id)
    references public.knowledge_releases(municipality_id, id),
  constraint ai_runs_municipality_id_id_uq unique (municipality_id, id),
  constraint ai_runs_id_case_question_uq unique (municipality_id, id, case_id, question_id)
);

create index ai_runs_question_idx
  on private.ai_runs (municipality_id, question_id, started_at desc);

create table private.ai_run_sources (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  ai_run_id uuid not null,
  legal_chunk_id uuid not null,
  rank integer not null check (rank > 0),
  score numeric(12,8),
  citation_snapshot jsonb not null check (jsonb_typeof(citation_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  constraint ai_run_sources_run_fk
    foreign key (municipality_id, ai_run_id)
    references private.ai_runs(municipality_id, id) on delete cascade,
  constraint ai_run_sources_chunk_fk
    foreign key (municipality_id, legal_chunk_id)
    references private.legal_chunks(municipality_id, id),
  constraint ai_run_sources_rank_uq unique (municipality_id, ai_run_id, rank),
  constraint ai_run_sources_chunk_uq unique (municipality_id, ai_run_id, legal_chunk_id)
);

create table public.ai_drafts (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  case_id uuid not null,
  question_id uuid not null,
  ai_run_id uuid not null,
  status text not null default 'awaiting_fiscal_review'
    check (status in ('awaiting_fiscal_review', 'revision_requested', 'approved', 'rejected', 'published', 'needs_manual_answer')),
  current_revision_number integer not null default 1 check (current_revision_number > 0),
  requires_human_attention boolean not null default true,
  limitation_summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_drafts_run_case_question_fk
    foreign key (municipality_id, ai_run_id, case_id, question_id)
    references private.ai_runs(municipality_id, id, case_id, question_id),
  constraint ai_drafts_municipality_id_id_uq unique (municipality_id, id),
  constraint ai_drafts_run_uq unique (municipality_id, ai_run_id)
);

create index ai_drafts_review_queue_idx
  on public.ai_drafts (municipality_id, status, created_at, id)
  where status in ('awaiting_fiscal_review', 'revision_requested', 'needs_manual_answer');

create table public.ai_draft_revisions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  draft_id uuid not null,
  revision_number integer not null check (revision_number > 0),
  revision_type text not null check (revision_type in ('ai_generated', 'fiscal_edited')),
  body text not null check (char_length(trim(body)) between 1 and 20000),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ai_draft_revisions_draft_fk
    foreign key (municipality_id, draft_id)
    references public.ai_drafts(municipality_id, id) on delete cascade,
  constraint ai_draft_revisions_municipality_id_id_uq unique (municipality_id, id),
  constraint ai_draft_revisions_number_uq unique (municipality_id, draft_id, revision_number)
);

create table public.ai_draft_citations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  draft_revision_id uuid not null,
  legal_section_id uuid not null,
  source_version_id uuid not null,
  citation_label text not null,
  quoted_excerpt text not null check (char_length(quoted_excerpt) <= 2000),
  source_sha256 text not null check (source_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint ai_draft_citations_revision_fk
    foreign key (municipality_id, draft_revision_id)
    references public.ai_draft_revisions(municipality_id, id) on delete cascade,
  constraint ai_draft_citations_section_fk
    foreign key (municipality_id, legal_section_id)
    references public.legal_sections(municipality_id, id),
  constraint ai_draft_citations_version_fk
    foreign key (municipality_id, source_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint ai_draft_citations_municipality_id_id_uq unique (municipality_id, id),
  constraint ai_draft_citations_section_uq
    unique (municipality_id, draft_revision_id, legal_section_id)
);

create table public.draft_reviews (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  draft_id uuid not null,
  draft_revision_id uuid not null,
  decision text not null check (decision in ('approved', 'rejected', 'revision_requested')),
  reviewer_membership_id uuid not null,
  notes text,
  approved_content_sha256 text,
  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint draft_reviews_draft_fk
    foreign key (municipality_id, draft_id)
    references public.ai_drafts(municipality_id, id) on delete cascade,
  constraint draft_reviews_revision_fk
    foreign key (municipality_id, draft_revision_id)
    references public.ai_draft_revisions(municipality_id, id),
  constraint draft_reviews_membership_fk
    foreign key (municipality_id, reviewer_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint draft_reviews_approval_hash_ck check (
    (decision = 'approved' and approved_content_sha256 ~ '^[a-f0-9]{64}$')
    or (decision <> 'approved' and approved_content_sha256 is null)
  ),
  constraint draft_reviews_municipality_id_id_uq unique (municipality_id, id)
);

create unique index draft_reviews_one_approval_idx
  on public.draft_reviews (municipality_id, draft_id)
  where decision = 'approved';

alter table public.case_messages
  add column source_draft_revision_id uuid,
  add constraint case_messages_source_revision_fk
    foreign key (municipality_id, source_draft_revision_id)
    references public.ai_draft_revisions(municipality_id, id),
  add constraint case_messages_ai_source_ck check (
    (source_type = 'approved_ai_draft' and source_draft_revision_id is not null)
    or (source_type <> 'approved_ai_draft' and source_draft_revision_id is null)
  );

create table public.case_documents (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  case_id uuid not null,
  uploaded_by uuid references auth.users(id) on delete set null,
  storage_bucket text not null,
  storage_path text not null,
  original_file_name text not null,
  media_type text not null,
  size_bytes bigint not null check (size_bytes between 1 and 52428800),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'quarantined'
    check (status in ('quarantined', 'available', 'rejected', 'archived')),
  malware_scan_status text not null default 'pending'
    check (malware_scan_status in ('pending', 'clean', 'infected', 'failed', 'not_configured')),
  created_at timestamptz not null default now(),
  constraint case_documents_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint case_documents_municipality_id_id_uq unique (municipality_id, id),
  constraint case_documents_storage_uq unique (storage_bucket, storage_path)
);

create index case_documents_case_idx
  on public.case_documents (municipality_id, case_id, created_at desc);

create table public.retention_policies (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  data_category text not null,
  retention_days integer not null check (retention_days > 0),
  legal_basis text not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'active', 'retired')),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint retention_policies_approval_ck check (
    status not in ('approved', 'active')
    or (approved_by is not null and approved_at is not null)
  ),
  constraint retention_policies_municipality_id_id_uq unique (municipality_id, id),
  constraint retention_policies_category_uq unique (municipality_id, data_category, status)
);

create table public.legal_holds (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  case_id uuid,
  scope_type text not null check (scope_type in ('case', 'municipality')),
  reason text not null,
  status text not null default 'active' check (status in ('active', 'released')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  released_by uuid references auth.users(id) on delete set null,
  released_at timestamptz,
  constraint legal_holds_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id),
  constraint legal_holds_scope_ck check (
    (scope_type = 'case' and case_id is not null)
    or (scope_type = 'municipality' and case_id is null)
  ),
  constraint legal_holds_release_ck check (
    status <> 'released'
    or (released_by is not null and released_at is not null)
  ),
  constraint legal_holds_municipality_id_id_uq unique (municipality_id, id)
);

create table public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  requester_user_id uuid references auth.users(id) on delete set null,
  request_type text not null
    check (request_type in ('access', 'correction', 'restriction', 'information', 'other')),
  status text not null default 'received'
    check (status in ('received', 'validating', 'in_progress', 'completed', 'denied', 'cancelled')),
  description text not null,
  decision_basis text,
  received_at timestamptz not null default now(),
  due_at timestamptz,
  completed_at timestamptz,
  assigned_membership_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint privacy_requests_assignment_fk
    foreign key (municipality_id, assigned_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint privacy_requests_municipality_id_id_uq unique (municipality_id, id)
);

create trigger notification_templates_set_updated_at
  before update on public.notification_templates
  for each row execute function private.set_updated_at();
create trigger notification_template_versions_set_updated_at
  before update on public.notification_template_versions
  for each row execute function private.set_updated_at();
create trigger notification_channel_settings_set_updated_at
  before update on public.notification_channel_settings
  for each row execute function private.set_updated_at();
create trigger notification_batches_set_updated_at
  before update on public.notification_batches
  for each row execute function private.set_updated_at();
create trigger notifications_set_updated_at
  before update on public.notifications
  for each row execute function private.set_updated_at();
create trigger notification_recipients_set_updated_at
  before update on public.notification_recipients
  for each row execute function private.set_updated_at();
create trigger case_threads_set_updated_at
  before update on public.case_threads
  for each row execute function private.set_updated_at();
create trigger case_messages_set_updated_at
  before update on public.case_messages
  for each row execute function private.set_updated_at();
create trigger case_questions_set_updated_at
  before update on public.case_questions
  for each row execute function private.set_updated_at();
create trigger legal_sources_set_updated_at
  before update on public.legal_sources
  for each row execute function private.set_updated_at();
create trigger legal_source_versions_set_updated_at
  before update on public.legal_source_versions
  for each row execute function private.set_updated_at();
create trigger knowledge_releases_set_updated_at
  before update on public.knowledge_releases
  for each row execute function private.set_updated_at();
create trigger ai_prompt_templates_set_updated_at
  before update on public.ai_prompt_templates
  for each row execute function private.set_updated_at();
create trigger ai_prompt_versions_set_updated_at
  before update on public.ai_prompt_versions
  for each row execute function private.set_updated_at();
create trigger ai_drafts_set_updated_at
  before update on public.ai_drafts
  for each row execute function private.set_updated_at();
create trigger retention_policies_set_updated_at
  before update on public.retention_policies
  for each row execute function private.set_updated_at();
create trigger privacy_requests_set_updated_at
  before update on public.privacy_requests
  for each row execute function private.set_updated_at();

commit;

