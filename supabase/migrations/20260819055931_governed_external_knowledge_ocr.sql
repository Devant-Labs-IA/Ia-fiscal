-- Segundo Cerebro Fiscal: governed external OCR worker.
--
-- This migration deliberately does not activate the worker.  Claims remain
-- fail-closed until both the Phase-2 runtime gate and the dedicated OCR
-- runtime gate have been attested.  OCR may only create an `under_review`
-- candidate from an immutable official artifact; it can never approve or
-- publish legal content.

begin;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'legal-ocr-artifacts',
  'legal-ocr-artifacts',
  false,
  5242880,
  array['application/json']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table private.legal_ocr_runtime_gates (
  id uuid primary key default gen_random_uuid(),
  project_ref text not null
    check (project_ref = 'qvgenxcrdrqyiyozxtdt'),
  edge_contract text not null
    check (edge_contract = 'ia-fiscal-knowledge-ocr/v1'),
  workflow_contract text not null
    check (workflow_contract = 'ia-fiscal-knowledge-ocr-workflow/v1'),
  policy_version text not null
    check (policy_version = 'ia-fiscal-knowledge-ocr-policy/v1'),
  toolchain_lock_sha256 text not null
    check (
      toolchain_lock_sha256 =
        '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60'
    ),
  max_pages integer not null check (max_pages = 120),
  max_total_characters integer not null check (max_total_characters = 8000000),
  github_audience text not null
    check (github_audience = 'ia-fiscal-knowledge-ocr-qvgenxcrdrqyiyozxtdt'),
  github_repository text not null
    check (github_repository = 'AlmoreContabilidade/Ia-fiscal'),
  github_repository_id text not null check (github_repository_id = '1320619695'),
  github_repository_owner_id text not null
    check (github_repository_owner_id = '296187202'),
  github_ref text not null
    check (github_ref = 'refs/heads/main'),
  github_workflow_ref text not null
    check (
      github_workflow_ref =
        'AlmoreContabilidade/Ia-fiscal/.github/workflows/knowledge-ocr.yml@refs/heads/main'
    ),
  edge_deployment_id uuid not null,
  edge_bundle_sha256 text not null
    check (edge_bundle_sha256 ~ '^[a-f0-9]{64}$'),
  workflow_commit_sha text not null
    check (workflow_commit_sha ~ '^[a-f0-9]{40}$'),
  smoke_evidence_sha256 text not null
    check (smoke_evidence_sha256 ~ '^[a-f0-9]{64}$'),
  smoke_evidence_locator text not null
    check (char_length(trim(smoke_evidence_locator)) between 1 and 500),
  valid_from timestamptz not null default now(),
  valid_until timestamptz not null,
  created_at timestamptz not null default now(),
  constraint legal_ocr_runtime_gates_validity_ck check (
    valid_until > valid_from
    and valid_until <= valid_from + interval '7 days'
  ),
  constraint legal_ocr_runtime_gates_project_id_uq unique (project_ref, id),
  constraint legal_ocr_runtime_gates_evidence_uq unique (
    project_ref,
    edge_bundle_sha256,
    workflow_commit_sha,
    smoke_evidence_sha256
  )
);

create table private.legal_ocr_runtime_gate_events (
  id bigint generated always as identity primary key,
  project_ref text not null,
  runtime_gate_id uuid not null,
  event_type text not null
    check (event_type in ('attested', 'selected', 'revoked')),
  safe_reason text
    check (safe_reason is null or char_length(trim(safe_reason)) between 10 and 500),
  event_at timestamptz not null default now(),
  constraint legal_ocr_runtime_gate_events_gate_fk
    foreign key (project_ref, runtime_gate_id)
    references private.legal_ocr_runtime_gates(project_ref, id)
);

create unique index legal_ocr_runtime_gate_one_revocation_idx
  on private.legal_ocr_runtime_gate_events (runtime_gate_id)
  where event_type = 'revoked';

create table private.legal_ocr_runtime_current_gates (
  project_ref text primary key
    check (project_ref = 'qvgenxcrdrqyiyozxtdt'),
  runtime_gate_id uuid not null unique,
  selected_at timestamptz not null default now(),
  constraint legal_ocr_runtime_current_gate_fk
    foreign key (project_ref, runtime_gate_id)
    references private.legal_ocr_runtime_gates(project_ref, id)
);

create table private.legal_ocr_jobs (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_id uuid not null,
  source_artifact_id uuid not null,
  change_set_id uuid not null,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'completed', 'dead_letter')),
  priority smallint not null default 100 check (priority between 1 and 1000),
  attempt smallint not null default 0 check (attempt between 0 and 10),
  max_attempts smallint not null default 5 check (max_attempts between 1 and 10),
  available_at timestamptz not null default now(),
  lease_token_sha256 text
    check (lease_token_sha256 is null or lease_token_sha256 ~ '^[a-f0-9]{64}$'),
  lease_started_at timestamptz,
  lease_expires_at timestamptz,
  completed_at timestamptz,
  safe_error_code text
    check (
      safe_error_code is null
      or safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
    ),
  safe_error_detail text
    check (safe_error_detail is null or char_length(safe_error_detail) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_ocr_jobs_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_ocr_jobs_artifact_fk
    foreign key (municipality_id, source_artifact_id)
    references private.legal_source_artifacts(municipality_id, id),
  constraint legal_ocr_jobs_change_set_fk
    foreign key (municipality_id, change_set_id)
    references private.legal_source_change_sets(municipality_id, id),
  constraint legal_ocr_jobs_municipality_id_id_uq unique (municipality_id, id),
  constraint legal_ocr_jobs_artifact_uq unique (municipality_id, source_artifact_id),
  constraint legal_ocr_jobs_change_set_uq unique (municipality_id, change_set_id),
  constraint legal_ocr_jobs_state_ck check (
    (
      status = 'processing'
      and lease_token_sha256 is not null
      and lease_started_at is not null
      and lease_expires_at > lease_started_at
      and completed_at is null
    )
    or (
      status = 'completed'
      and lease_token_sha256 is null
      and lease_started_at is null
      and lease_expires_at is null
      and completed_at is not null
      and safe_error_code is null
      and safe_error_detail is null
    )
    or (
      status in ('queued', 'dead_letter')
      and lease_token_sha256 is null
      and lease_started_at is null
      and lease_expires_at is null
      and completed_at is null
    )
  )
);

create index legal_ocr_jobs_claim_idx
  on private.legal_ocr_jobs (available_at, priority, created_at, id)
  where status = 'queued';

create index legal_ocr_jobs_lease_expiry_idx
  on private.legal_ocr_jobs (lease_expires_at, id)
  where status = 'processing';

create table private.legal_ocr_oidc_requests (
  id uuid primary key default gen_random_uuid(),
  jti_sha256 text not null unique check (jti_sha256 ~ '^[a-f0-9]{64}$'),
  request_action text not null
    check (request_action in ('claim', 'heartbeat', 'upload_part', 'complete', 'fail')),
  audience text not null
    check (audience = 'ia-fiscal-knowledge-ocr-qvgenxcrdrqyiyozxtdt'),
  repository text not null
    check (repository = 'AlmoreContabilidade/Ia-fiscal'),
  repository_id text not null check (repository_id = '1320619695'),
  repository_owner text not null check (repository_owner = 'AlmoreContabilidade'),
  repository_owner_id text not null check (repository_owner_id = '296187202'),
  git_ref text not null check (git_ref = 'refs/heads/main'),
  environment text not null check (environment = 'knowledge-ocr'),
  workflow_ref text not null
    check (
      workflow_ref =
        'AlmoreContabilidade/Ia-fiscal/.github/workflows/knowledge-ocr.yml@refs/heads/main'
    ),
  workflow_sha text not null check (workflow_sha ~ '^[a-f0-9]{40}$'),
  subject_sha256 text not null
    check (
      subject_sha256 =
        '6458d6e7ba5d2430f62ac326d74561853af077abeddc00eb96763a08b78fd005'
    ),
  runner_environment text not null check (runner_environment = 'github-hosted'),
  run_id bigint not null check (run_id > 0),
  run_attempt integer not null check (run_attempt between 1 and 1000),
  token_expires_at timestamptz not null,
  consumed_at timestamptz not null default now(),
  constraint legal_ocr_oidc_requests_freshness_ck check (
    token_expires_at > consumed_at - interval '30 seconds'
    and token_expires_at <= consumed_at + interval '10 minutes'
  )
);

create table private.legal_ocr_job_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  job_id uuid not null,
  event_type text not null
    check (
      event_type in (
        'queued',
        'claimed',
        'heartbeat',
        'retried',
        'completed',
        'completion_replayed',
        'failed',
        'dead_lettered',
        'cancelled'
      )
    ),
  attempt smallint not null check (attempt between 0 and 10),
  oidc_request_id uuid,
  safe_error_code text
    check (
      safe_error_code is null
      or safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
    ),
  safe_error_detail text
    check (safe_error_detail is null or char_length(safe_error_detail) <= 1000),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  event_at timestamptz not null default now(),
  constraint legal_ocr_job_events_job_fk
    foreign key (municipality_id, job_id)
    references private.legal_ocr_jobs(municipality_id, id),
  constraint legal_ocr_job_events_oidc_fk
    foreign key (oidc_request_id)
    references private.legal_ocr_oidc_requests(id)
);

create index legal_ocr_job_events_job_idx
  on private.legal_ocr_job_events (municipality_id, job_id, event_at, id);

create table private.legal_ocr_job_pages (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  job_id uuid not null,
  attempt smallint not null check (attempt between 1 and 10),
  page_number integer not null check (page_number between 1 and 120),
  content_text text not null check (char_length(content_text) <= 1000000),
  text_sha256 text not null check (text_sha256 ~ '^[a-f0-9]{64}$'),
  storage_bucket text not null check (storage_bucket = 'legal-ocr-artifacts'),
  storage_path text not null
    check (storage_path !~ '(^|/)\.\.(/|$)' and storage_path !~ '^/'),
  artifact_sha256 text not null check (artifact_sha256 ~ '^[a-f0-9]{64}$'),
  artifact_byte_size bigint not null check (artifact_byte_size between 2 and 5242880),
  confidence numeric(6,5) check (confidence is null or confidence between 0 and 1),
  confidence_samples integer not null check (confidence_samples between 0 and 100000000),
  character_count integer not null check (character_count between 0 and 1000000),
  utf8_bytes integer not null check (utf8_bytes between 0 and 5242880),
  word_count integer not null check (word_count between 0 and 1000000),
  created_at timestamptz not null default now(),
  constraint legal_ocr_job_pages_job_fk
    foreign key (municipality_id, job_id)
    references private.legal_ocr_jobs(municipality_id, id),
  constraint legal_ocr_job_pages_number_uq unique (municipality_id, job_id, page_number),
  constraint legal_ocr_job_pages_storage_uq unique (storage_bucket, storage_path)
);

create table private.legal_ocr_results (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  job_id uuid not null,
  source_artifact_id uuid not null,
  change_set_id uuid not null,
  candidate_version_id uuid not null,
  attempt smallint not null check (attempt between 1 and 10),
  completion_lease_token_sha256 text not null
    check (completion_lease_token_sha256 ~ '^[a-f0-9]{64}$'),
  engine_name text not null check (engine_name ~ '^[a-z0-9][a-z0-9_.-]{1,79}$'),
  engine_version text not null check (engine_version ~ '^[A-Za-z0-9][A-Za-z0-9_.+-]{0,79}$'),
  manifest_bucket text not null check (manifest_bucket = 'legal-ocr-artifacts'),
  manifest_path text not null
    check (manifest_path !~ '(^|/)\.\.(/|$)' and manifest_path !~ '^/'),
  manifest_sha256 text not null check (manifest_sha256 ~ '^[a-f0-9]{64}$'),
  manifest_byte_size bigint not null check (manifest_byte_size between 2 and 5242880),
  completion_evidence_sha256 text not null
    check (completion_evidence_sha256 ~ '^[a-f0-9]{64}$'),
  page_evidence_sha256 text not null check (page_evidence_sha256 ~ '^[a-f0-9]{64}$'),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  page_count integer not null check (page_count between 1 and 120),
  character_count integer not null check (character_count between 80 and 8000000),
  page_coverage_bps integer not null check (page_coverage_bps between 9000 and 10000),
  mean_confidence_milli integer not null
    check (mean_confidence_milli between 550 and 1000),
  policy_version text not null
    check (policy_version = 'ia-fiscal-knowledge-ocr-policy/v1'),
  toolchain_lock_sha256 text not null
    check (
      toolchain_lock_sha256 =
        '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60'
    ),
  toolchain_evidence jsonb not null check (jsonb_typeof(toolchain_evidence) = 'object'),
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint legal_ocr_results_job_fk
    foreign key (municipality_id, job_id)
    references private.legal_ocr_jobs(municipality_id, id),
  constraint legal_ocr_results_artifact_fk
    foreign key (municipality_id, source_artifact_id)
    references private.legal_source_artifacts(municipality_id, id),
  constraint legal_ocr_results_change_set_fk
    foreign key (municipality_id, change_set_id)
    references private.legal_source_change_sets(municipality_id, id),
  constraint legal_ocr_results_version_fk
    foreign key (municipality_id, candidate_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint legal_ocr_results_job_uq unique (municipality_id, job_id),
  constraint legal_ocr_results_artifact_uq unique (municipality_id, source_artifact_id),
  constraint legal_ocr_results_version_uq unique (municipality_id, candidate_version_id),
  constraint legal_ocr_results_manifest_uq unique (manifest_bucket, manifest_path)
);

alter table private.legal_ocr_runtime_gates enable row level security;
alter table private.legal_ocr_runtime_gate_events enable row level security;
alter table private.legal_ocr_runtime_current_gates enable row level security;
alter table private.legal_ocr_jobs enable row level security;
alter table private.legal_ocr_oidc_requests enable row level security;
alter table private.legal_ocr_job_events enable row level security;
alter table private.legal_ocr_job_pages enable row level security;
alter table private.legal_ocr_results enable row level security;

revoke all on private.legal_ocr_runtime_gates from public, anon, authenticated, service_role;
revoke all on private.legal_ocr_runtime_gate_events from public, anon, authenticated, service_role;
revoke all on private.legal_ocr_runtime_current_gates from public, anon, authenticated, service_role;
revoke all on private.legal_ocr_jobs from public, anon, authenticated, service_role;
revoke all on private.legal_ocr_oidc_requests from public, anon, authenticated, service_role;
revoke all on private.legal_ocr_job_events from public, anon, authenticated, service_role;
revoke all on private.legal_ocr_job_pages from public, anon, authenticated, service_role;
revoke all on private.legal_ocr_results from public, anon, authenticated, service_role;

create trigger legal_ocr_runtime_gates_append_only
before update or delete on private.legal_ocr_runtime_gates
for each row execute function private.prevent_any_mutation();

create trigger legal_ocr_runtime_gate_events_append_only
before update or delete on private.legal_ocr_runtime_gate_events
for each row execute function private.prevent_any_mutation();

create trigger legal_ocr_oidc_requests_append_only
before update or delete on private.legal_ocr_oidc_requests
for each row execute function private.prevent_any_mutation();

create trigger legal_ocr_job_events_append_only
before update or delete on private.legal_ocr_job_events
for each row execute function private.prevent_any_mutation();

create trigger legal_ocr_job_pages_append_only
before update or delete on private.legal_ocr_job_pages
for each row execute function private.prevent_any_mutation();

create trigger legal_ocr_results_append_only
before update or delete on private.legal_ocr_results
for each row execute function private.prevent_any_mutation();

create or replace function private.prevent_legal_ocr_evidence_truncate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'governed legal OCR evidence cannot be truncated';
end;
$$;

create trigger legal_ocr_runtime_gates_no_truncate
before truncate on private.legal_ocr_runtime_gates
for each statement execute function private.prevent_legal_ocr_evidence_truncate();
create trigger legal_ocr_runtime_gate_events_no_truncate
before truncate on private.legal_ocr_runtime_gate_events
for each statement execute function private.prevent_legal_ocr_evidence_truncate();
create trigger legal_ocr_oidc_requests_no_truncate
before truncate on private.legal_ocr_oidc_requests
for each statement execute function private.prevent_legal_ocr_evidence_truncate();
create trigger legal_ocr_job_events_no_truncate
before truncate on private.legal_ocr_job_events
for each statement execute function private.prevent_legal_ocr_evidence_truncate();
create trigger legal_ocr_job_pages_no_truncate
before truncate on private.legal_ocr_job_pages
for each statement execute function private.prevent_legal_ocr_evidence_truncate();
create trigger legal_ocr_results_no_truncate
before truncate on private.legal_ocr_results
for each statement execute function private.prevent_legal_ocr_evidence_truncate();

create or replace function private.current_legal_ocr_runtime_gate_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select current_gate.runtime_gate_id
  from private.legal_ocr_runtime_current_gates current_gate
  join private.legal_ocr_runtime_gates gate
    on gate.project_ref = current_gate.project_ref
   and gate.id = current_gate.runtime_gate_id
  where current_gate.project_ref = 'qvgenxcrdrqyiyozxtdt'
    and gate.valid_from <= now()
    and gate.valid_until > now()
    and not exists (
      select 1
      from private.legal_ocr_runtime_gate_events event
      where event.runtime_gate_id = gate.id
        and event.event_type = 'revoked'
    );
$$;

create or replace function private.lock_current_legal_ocr_runtime_gate_id()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_runtime_gate_id uuid;
begin
  select current_gate.runtime_gate_id into v_runtime_gate_id
  from private.legal_ocr_runtime_current_gates current_gate
  join private.legal_ocr_runtime_gates gate
    on gate.project_ref = current_gate.project_ref
   and gate.id = current_gate.runtime_gate_id
  where current_gate.project_ref = 'qvgenxcrdrqyiyozxtdt'
    and current_gate.runtime_gate_id = private.current_legal_ocr_runtime_gate_id()
  for key share of current_gate, gate;

  return v_runtime_gate_id;
end;
$$;

create or replace function private.consume_legal_ocr_oidc_request(
  p_expected_action text,
  p_context jsonb,
  p_runtime_gate_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid;
  v_run_id bigint;
  v_run_attempt integer;
  v_expires_at timestamptz;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_context is null or jsonb_typeof(p_context) <> 'object' then
    raise exception using errcode = '42501', message = 'invalid OCR OIDC context';
  end if;
  if p_expected_action not in ('claim', 'heartbeat', 'upload_part', 'complete', 'fail')
     or p_context ->> 'action' <> p_expected_action
     or p_context ->> 'audience' <>
          'ia-fiscal-knowledge-ocr-qvgenxcrdrqyiyozxtdt'
     or p_context ->> 'repository' <> 'AlmoreContabilidade/Ia-fiscal'
     or p_context ->> 'repository_owner' <> 'AlmoreContabilidade'
     or p_context ->> 'repository_id' <> '1320619695'
     or p_context ->> 'repository_owner_id' <> '296187202'
     or p_context ->> 'runner_environment' <> 'github-hosted'
     or p_context ->> 'ref' <> 'refs/heads/main'
     or p_context ->> 'environment' <> 'knowledge-ocr'
     or p_context ->> 'workflow_ref' <>
          'AlmoreContabilidade/Ia-fiscal/.github/workflows/knowledge-ocr.yml@refs/heads/main'
     or coalesce(p_context ->> 'jti_sha256', '') !~ '^[a-f0-9]{64}$'
     or p_context ->> 'subject_sha256' <>
          '6458d6e7ba5d2430f62ac326d74561853af077abeddc00eb96763a08b78fd005'
     or coalesce(p_context ->> 'workflow_sha', '') !~ '^[a-f0-9]{40}$' then
    raise exception using errcode = '42501', message = 'OCR OIDC allowlist rejected';
  end if;

  if not exists (
    select 1
    from private.legal_ocr_runtime_gates gate
    where gate.id = p_runtime_gate_id
      and gate.project_ref = 'qvgenxcrdrqyiyozxtdt'
      and gate.workflow_commit_sha = p_context ->> 'workflow_sha'
      and gate.github_audience = p_context ->> 'audience'
      and gate.github_repository = p_context ->> 'repository'
      and gate.github_repository_id = p_context ->> 'repository_id'
      and gate.github_repository_owner_id = p_context ->> 'repository_owner_id'
      and gate.github_ref = p_context ->> 'ref'
      and gate.github_workflow_ref = p_context ->> 'workflow_ref'
      and gate.policy_version = 'ia-fiscal-knowledge-ocr-policy/v1'
      and gate.toolchain_lock_sha256 =
        '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60'
      and gate.max_pages = 120
      and gate.max_total_characters = 8000000
  ) then
    raise exception using
      errcode = '55000',
      message = 'OCR workflow SHA is not attested by the current runtime gate';
  end if;

  begin
    v_run_id := (p_context ->> 'run_id')::bigint;
    v_run_attempt := (p_context ->> 'run_attempt')::integer;
    v_expires_at := (p_context ->> 'expires_at')::timestamptz;
  exception when others then
    raise exception using errcode = '42501', message = 'invalid OCR OIDC context';
  end;
  if v_run_id <= 0
     or v_run_attempt not between 1 and 1000
     or v_expires_at <= now() - interval '30 seconds'
     or v_expires_at > now() + interval '10 minutes' then
    raise exception using errcode = '42501', message = 'expired OCR OIDC context';
  end if;

  begin
    insert into private.legal_ocr_oidc_requests (
      jti_sha256,
      request_action,
      audience,
      repository,
      repository_id,
      repository_owner,
      repository_owner_id,
      git_ref,
      environment,
      workflow_ref,
      workflow_sha,
      subject_sha256,
      runner_environment,
      run_id,
      run_attempt,
      token_expires_at
    ) values (
      p_context ->> 'jti_sha256',
      p_expected_action,
      p_context ->> 'audience',
      p_context ->> 'repository',
      p_context ->> 'repository_id',
      p_context ->> 'repository_owner',
      p_context ->> 'repository_owner_id',
      p_context ->> 'ref',
      p_context ->> 'environment',
      p_context ->> 'workflow_ref',
      p_context ->> 'workflow_sha',
      p_context ->> 'subject_sha256',
      p_context ->> 'runner_environment',
      v_run_id,
      v_run_attempt,
      v_expires_at
    ) returning id into v_request_id;
  exception when unique_violation then
    raise exception using errcode = '42501', message = 'OCR OIDC token replay detected';
  end;

  return v_request_id;
end;
$$;

create or replace function private.guard_legal_ocr_job()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'legal OCR jobs cannot be deleted';
  end if;
  if old.id is distinct from new.id
     or old.municipality_id is distinct from new.municipality_id
     or old.source_id is distinct from new.source_id
     or old.source_artifact_id is distinct from new.source_artifact_id
     or old.change_set_id is distinct from new.change_set_id
     or old.priority is distinct from new.priority
     or old.max_attempts is distinct from new.max_attempts
     or old.created_at is distinct from new.created_at then
    raise exception 'legal OCR job identity is immutable';
  end if;
  if old.status in ('completed', 'dead_letter') then
    raise exception 'terminal legal OCR jobs are immutable';
  end if;
  if new.attempt < old.attempt or new.attempt > old.attempt + 1 then
    raise exception 'invalid legal OCR attempt transition';
  end if;
  if old.status = 'queued'
     and not (
       (new.status = 'processing' and new.attempt = old.attempt + 1)
       or (
         new.status = 'dead_letter'
         and new.attempt = old.attempt
         and new.safe_error_code = 'ocr_change_set_closed'
       )
     ) then
    raise exception 'queued legal OCR job can only be claimed or cancelled';
  end if;
  if old.status = 'processing'
     and new.status not in ('processing', 'queued', 'completed', 'dead_letter') then
    raise exception 'invalid legal OCR processing transition';
  end if;
  return new;
end;
$$;

create trigger legal_ocr_jobs_guard
before update or delete on private.legal_ocr_jobs
for each row execute function private.guard_legal_ocr_job();

-- The raw official file remains immutable.  Only the extraction projection may
-- advance once, from pending to completed, and only after an append-only OCR
-- result already proves the exact text, manifest and candidate version.
drop trigger legal_source_artifacts_append_only on private.legal_source_artifacts;

create or replace function private.guard_legal_source_artifact_ocr_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_result private.legal_ocr_results%rowtype;
begin
  if tg_op = 'DELETE' then
    raise exception 'legal source artifacts cannot be deleted';
  end if;
  if (to_jsonb(old) - 'extraction_status' - 'extracted_text_sha256' - 'metadata')
       is distinct from
     (to_jsonb(new) - 'extraction_status' - 'extracted_text_sha256' - 'metadata') then
    raise exception 'raw legal source artifact evidence is immutable';
  end if;
  if old.extraction_status <> 'requires_extraction'
     or old.extracted_text_sha256 is not null
     or new.extraction_status <> 'completed'
     or new.extracted_text_sha256 is null then
    raise exception 'invalid legal source artifact extraction transition';
  end if;
  if (old.metadata
        - 'ocr_result_id'
        - 'ocr_engine'
        - 'ocr_engine_version'
        - 'ocr_manifest_sha256'
        - 'ocr_policy_version'
        - 'ocr_toolchain_lock_sha256'
        - 'ocr_page_coverage_bps'
        - 'ocr_mean_confidence_milli'
        - 'extraction_complete'
        - 'content_truncated'
        - 'extracted_char_count'
        - 'extraction_method')
       is distinct from
     (new.metadata
        - 'ocr_result_id'
        - 'ocr_engine'
        - 'ocr_engine_version'
        - 'ocr_manifest_sha256'
        - 'ocr_policy_version'
        - 'ocr_toolchain_lock_sha256'
        - 'ocr_page_coverage_bps'
        - 'ocr_mean_confidence_milli'
        - 'extraction_complete'
        - 'content_truncated'
        - 'extracted_char_count'
        - 'extraction_method') then
    raise exception 'unrelated legal source artifact metadata is immutable';
  end if;
  begin
    select result.* into strict v_result
    from private.legal_ocr_results result
    where result.id = (new.metadata ->> 'ocr_result_id')::uuid
      and result.municipality_id = old.municipality_id
      and result.source_artifact_id = old.id;
  exception when others then
    raise exception 'append-only OCR result is required before extraction completion';
  end;
  if v_result.content_sha256 <> new.extracted_text_sha256
     or new.metadata ->> 'ocr_engine' <> v_result.engine_name
     or new.metadata ->> 'ocr_engine_version' <> v_result.engine_version
     or new.metadata ->> 'ocr_manifest_sha256' <> v_result.manifest_sha256
     or new.metadata ->> 'ocr_policy_version' <> v_result.policy_version
     or new.metadata ->> 'ocr_toolchain_lock_sha256' <>
          v_result.toolchain_lock_sha256
     or new.metadata ->> 'ocr_page_coverage_bps' <>
          v_result.page_coverage_bps::text
     or new.metadata ->> 'ocr_mean_confidence_milli' <>
          v_result.mean_confidence_milli::text
     or new.metadata ->> 'extraction_complete' <> 'true'
     or new.metadata ->> 'content_truncated' <> 'false'
     or new.metadata ->> 'extraction_method' <> 'external_ocr'
     or new.metadata ->> 'extracted_char_count' <> v_result.character_count::text then
    raise exception 'legal source artifact OCR evidence does not match result';
  end if;
  return new;
end;
$$;

create trigger legal_source_artifacts_ocr_guard
before update or delete on private.legal_source_artifacts
for each row execute function private.guard_legal_source_artifact_ocr_transition();

-- Preserve the original immutable change-set evidence while allowing exactly
-- one null-to-candidate link created by a completed OCR result in the same
-- transaction.
create or replace function private.guard_legal_source_change_set()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'legal source change sets cannot be deleted';
  end if;
  if old.candidate_version_id is distinct from new.candidate_version_id then
    if old.candidate_version_id is not null
       or new.candidate_version_id is null
       or not exists (
         select 1
         from private.legal_ocr_results result
         join public.legal_source_versions version
           on version.municipality_id = result.municipality_id
          and version.id = result.candidate_version_id
         where result.municipality_id = old.municipality_id
           and result.change_set_id = old.id
           and result.source_artifact_id = old.to_artifact_id
           and result.candidate_version_id = new.candidate_version_id
           and version.source_id = old.source_id
           and version.status = 'under_review'
           and version.content_sha256 = result.content_sha256
       ) then
      raise exception 'legal source change candidate identity is immutable';
    end if;
  end if;
  if (to_jsonb(old)
        - 'status'
        - 'reviewer_membership_id'
        - 'reviewed_at'
        - 'review_notes'
        - 'updated_at'
        - 'candidate_version_id')
     is distinct from
     (to_jsonb(new)
        - 'status'
        - 'reviewer_membership_id'
        - 'reviewed_at'
        - 'review_notes'
        - 'updated_at'
        - 'candidate_version_id') then
    raise exception 'detected legal change evidence is immutable';
  end if;
  return new;
end;
$$;

create or replace function private.guard_legal_ocr_storage_object()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.bucket_id = 'legal-ocr-artifacts'
     or (tg_op = 'UPDATE' and new.bucket_id = 'legal-ocr-artifacts') then
    raise exception 'legal OCR storage artifacts are immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger legal_ocr_storage_objects_guard
before update or delete on storage.objects
for each row execute function private.guard_legal_ocr_storage_object();

create or replace function private.guard_legal_ocr_storage_bucket()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.id = 'legal-ocr-artifacts'
     or (tg_op = 'UPDATE' and new.id = 'legal-ocr-artifacts') then
    raise exception 'legal OCR storage bucket is immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger legal_ocr_storage_bucket_guard
before update or delete on storage.buckets
for each row execute function private.guard_legal_ocr_storage_bucket();

create trigger legal_ocr_storage_buckets_no_truncate
before truncate on storage.buckets
for each statement execute function private.prevent_legal_ocr_evidence_truncate();

create or replace function private.guard_legal_ocr_storage_truncate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from storage.objects object
    where object.bucket_id = 'legal-ocr-artifacts'
  ) then
    raise exception 'cannot truncate storage containing legal OCR artifacts';
  end if;
  return null;
end;
$$;

create trigger legal_ocr_storage_objects_truncate_guard
before truncate on storage.objects
for each statement execute function private.guard_legal_ocr_storage_truncate();

create or replace function public.ia_fiscal_attest_knowledge_ocr_runtime_ready(
  p_project_ref text,
  p_edge_deployment_id uuid,
  p_edge_bundle_sha256 text,
  p_workflow_commit_sha text,
  p_policy_version text,
  p_toolchain_lock_sha256 text,
  p_max_pages integer,
  p_max_total_characters integer,
  p_smoke_evidence_sha256 text,
  p_smoke_evidence_locator text,
  p_valid_until timestamptz,
  p_confirmation text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gate_id uuid;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_confirmation <> 'ATESTAR RUNTIME OCR SEGUNDO CEREBRO' then
    raise exception 'explicit OCR runtime attestation confirmation required';
  end if;
  if p_project_ref <> 'qvgenxcrdrqyiyozxtdt'
     or p_edge_deployment_id is null
     or coalesce(p_edge_bundle_sha256, '') !~ '^[a-f0-9]{64}$'
     or coalesce(p_workflow_commit_sha, '') !~ '^[a-f0-9]{40}$'
     or p_policy_version <> 'ia-fiscal-knowledge-ocr-policy/v1'
     or p_toolchain_lock_sha256 <>
          '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60'
     or p_max_pages <> 120
     or p_max_total_characters <> 8000000
     or coalesce(p_smoke_evidence_sha256, '') !~ '^[a-f0-9]{64}$'
     or char_length(trim(coalesce(p_smoke_evidence_locator, ''))) not between 1 and 500
     or p_valid_until < now() + interval '15 minutes'
     or p_valid_until > now() + interval '7 days' then
    raise exception 'invalid OCR runtime attestation evidence';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('ia-fiscal-knowledge-ocr-runtime-gate', 0)
  );

  insert into private.legal_ocr_runtime_gates (
    project_ref,
    edge_contract,
    workflow_contract,
    policy_version,
    toolchain_lock_sha256,
    max_pages,
    max_total_characters,
    github_audience,
    github_repository,
    github_repository_id,
    github_repository_owner_id,
    github_ref,
    github_workflow_ref,
    edge_deployment_id,
    edge_bundle_sha256,
    workflow_commit_sha,
    smoke_evidence_sha256,
    smoke_evidence_locator,
    valid_until
  ) values (
    p_project_ref,
    'ia-fiscal-knowledge-ocr/v1',
    'ia-fiscal-knowledge-ocr-workflow/v1',
    p_policy_version,
    p_toolchain_lock_sha256,
    p_max_pages,
    p_max_total_characters,
    'ia-fiscal-knowledge-ocr-qvgenxcrdrqyiyozxtdt',
    'AlmoreContabilidade/Ia-fiscal',
    '1320619695',
    '296187202',
    'refs/heads/main',
    'AlmoreContabilidade/Ia-fiscal/.github/workflows/knowledge-ocr.yml@refs/heads/main',
    p_edge_deployment_id,
    p_edge_bundle_sha256,
    p_workflow_commit_sha,
    p_smoke_evidence_sha256,
    trim(p_smoke_evidence_locator),
    p_valid_until
  ) returning id into v_gate_id;

  insert into private.legal_ocr_runtime_gate_events (
    project_ref,
    runtime_gate_id,
    event_type
  ) values (p_project_ref, v_gate_id, 'attested');

  insert into private.legal_ocr_runtime_current_gates (
    project_ref,
    runtime_gate_id
  ) values (p_project_ref, v_gate_id)
  on conflict (project_ref) do update set
    runtime_gate_id = excluded.runtime_gate_id,
    selected_at = now();

  insert into private.legal_ocr_runtime_gate_events (
    project_ref,
    runtime_gate_id,
    event_type
  ) values (p_project_ref, v_gate_id, 'selected');

  return v_gate_id;
end;
$$;

create or replace function public.ia_fiscal_revoke_knowledge_ocr_runtime_gate(
  p_runtime_gate_id uuid,
  p_reason text,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gate private.legal_ocr_runtime_gates%rowtype;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_confirmation <> 'REVOGAR RUNTIME OCR SEGUNDO CEREBRO' then
    raise exception 'explicit OCR runtime revocation confirmation required';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 10 and 500 then
    raise exception 'OCR runtime revocation reason must contain 10 to 500 characters';
  end if;

  select gate.* into strict v_gate
  from private.legal_ocr_runtime_gates gate
  where gate.id = p_runtime_gate_id
  for key share;

  insert into private.legal_ocr_runtime_gate_events (
    project_ref,
    runtime_gate_id,
    event_type,
    safe_reason
  ) values (
    v_gate.project_ref,
    v_gate.id,
    'revoked',
    trim(p_reason)
  );

  delete from private.legal_ocr_runtime_current_gates current_gate
  where current_gate.project_ref = v_gate.project_ref
    and current_gate.runtime_gate_id = v_gate.id;
end;
$$;

create or replace function private.enqueue_legal_ocr_job()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id uuid;
  v_priority smallint;
begin
  if new.status not in ('detected', 'changes_requested')
     or new.candidate_version_id is not null
     or new.to_artifact_id is null
     or new.change_type = 'legacy_import' then
    return new;
  end if;

  select endpoint.priority into v_priority
  from private.legal_source_artifacts artifact
  join private.legal_source_endpoints endpoint
    on endpoint.municipality_id = artifact.municipality_id
   and endpoint.id = artifact.endpoint_id
  where artifact.municipality_id = new.municipality_id
    and artifact.id = new.to_artifact_id
    and artifact.source_id = new.source_id
    and artifact.extraction_status = 'requires_extraction'
    and artifact.mime_type = 'application/pdf'
    and artifact.metadata ->> 'extraction_blocker' in (
      'source_pdf_extraction_failed', 'source_pdf_text_missing'
    )
    and case
      when artifact.metadata ->> 'extraction_page_count' ~ '^[0-9]+$'
        then (artifact.metadata ->> 'extraction_page_count')::integer between 1 and 120
      else false
    end
    and endpoint.content_mode = 'legal_body'
    and endpoint.citable_body
    and endpoint.status = 'active';

  if v_priority is null then
    return new;
  end if;

  insert into private.legal_ocr_jobs (
    municipality_id,
    source_id,
    source_artifact_id,
    change_set_id,
    priority
  ) values (
    new.municipality_id,
    new.source_id,
    new.to_artifact_id,
    new.id,
    v_priority
  )
  on conflict (municipality_id, source_artifact_id) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    insert into private.legal_ocr_job_events (
      municipality_id,
      job_id,
      event_type,
      attempt,
      metadata
    ) values (
      new.municipality_id,
      v_job_id,
      'queued',
      0,
      jsonb_build_object('source', 'official_artifact_capture')
    );
  end if;
  return new;
end;
$$;

create trigger legal_source_change_sets_enqueue_ocr
after insert on private.legal_source_change_sets
for each row execute function private.enqueue_legal_ocr_job();

create or replace function private.cancel_legal_ocr_job_for_change_set()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cancelled private.legal_ocr_jobs%rowtype;
begin
  if old.status in ('detected', 'changes_requested')
     and new.status not in ('detected', 'changes_requested') then
    update private.legal_ocr_jobs job
    set status = 'dead_letter',
        lease_token_sha256 = null,
        lease_started_at = null,
        lease_expires_at = null,
        safe_error_code = 'ocr_change_set_closed',
        safe_error_detail = 'A revisão ou substituição fechou o conjunto de mudanças.',
        updated_at = now()
    where job.municipality_id = new.municipality_id
      and job.change_set_id = new.id
      and job.status in ('queued', 'processing')
    returning job.* into v_cancelled;

    if v_cancelled.id is not null then
      insert into private.legal_ocr_job_events (
        municipality_id,
        job_id,
        event_type,
        attempt,
        safe_error_code,
        safe_error_detail
      ) values (
        v_cancelled.municipality_id,
        v_cancelled.id,
        'cancelled',
        v_cancelled.attempt,
        'ocr_change_set_closed',
        'A revisão ou substituição fechou o conjunto de mudanças.'
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger legal_source_change_sets_cancel_ocr
after update of status on private.legal_source_change_sets
for each row execute function private.cancel_legal_ocr_job_for_change_set();

-- Queue artifacts captured before this migration without rewriting any raw
-- artifact or change evidence.
with queued as (
  insert into private.legal_ocr_jobs (
    municipality_id,
    source_id,
    source_artifact_id,
    change_set_id,
    priority
  )
  select
    change_set.municipality_id,
    change_set.source_id,
    artifact.id,
    change_set.id,
    endpoint.priority
  from private.legal_source_change_sets change_set
  join private.legal_source_artifacts artifact
    on artifact.municipality_id = change_set.municipality_id
   and artifact.id = change_set.to_artifact_id
  join private.legal_source_endpoints endpoint
    on endpoint.municipality_id = artifact.municipality_id
   and endpoint.id = artifact.endpoint_id
  where change_set.status in ('detected', 'changes_requested')
    and change_set.candidate_version_id is null
    and change_set.change_type <> 'legacy_import'
    and artifact.extraction_status = 'requires_extraction'
    and artifact.mime_type = 'application/pdf'
    and artifact.metadata ->> 'extraction_blocker' in (
      'source_pdf_extraction_failed', 'source_pdf_text_missing'
    )
    and case
      when artifact.metadata ->> 'extraction_page_count' ~ '^[0-9]+$'
        then (artifact.metadata ->> 'extraction_page_count')::integer between 1 and 120
      else false
    end
    and endpoint.status = 'active'
    and endpoint.content_mode = 'legal_body'
    and endpoint.citable_body
  on conflict (municipality_id, source_artifact_id) do nothing
  returning municipality_id, id, attempt
)
insert into private.legal_ocr_job_events (
  municipality_id,
  job_id,
  event_type,
  attempt,
  metadata
)
select
  queued.municipality_id,
  queued.id,
  'queued',
  queued.attempt,
  jsonb_build_object('source', 'migration_backfill')
from queued;

create or replace function public.ia_fiscal_claim_knowledge_ocr_job(
  p_oidc_context jsonb,
  p_lease_seconds integer default 600
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_main_runtime_gate_id uuid;
  v_ocr_runtime_gate_id uuid;
  v_oidc_request_id uuid;
  v_lease_token text;
  v_lease_sha256 text;
  v_claimed private.legal_ocr_jobs%rowtype;
  v_artifact private.legal_source_artifacts%rowtype;
  v_source_title text;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_lease_seconds not between 120 and 900 then
    raise exception 'OCR lease must be between 120 and 900 seconds';
  end if;

  v_main_runtime_gate_id := private.lock_current_knowledge_runtime_gate_id();
  v_ocr_runtime_gate_id := private.lock_current_legal_ocr_runtime_gate_id();
  if v_main_runtime_gate_id is null or v_ocr_runtime_gate_id is null then
    raise exception using errcode = '55000', message = 'OCR runtime is not verified';
  end if;
  v_oidc_request_id := private.consume_legal_ocr_oidc_request(
    'claim',
    p_oidc_context,
    v_ocr_runtime_gate_id
  );

  -- Recover expired leases before claiming.  Retry timing is deterministic and
  -- bounded; the append-only event retains the failed attempt.
  with stale as (
    update private.legal_ocr_jobs job
    set status = case when job.attempt >= job.max_attempts
          then 'dead_letter' else 'queued' end,
        available_at = case when job.attempt >= job.max_attempts
          then job.available_at
          else now() + make_interval(
            mins => least(240, power(2, greatest(job.attempt, 1))::integer)
          )
        end,
        lease_token_sha256 = null,
        lease_started_at = null,
        lease_expires_at = null,
        safe_error_code = 'ocr_lease_expired',
        safe_error_detail = 'A concessão de processamento expirou sem conclusão.',
        updated_at = now()
    where job.status = 'processing'
      and job.lease_expires_at <= now()
    returning job.*
  )
  insert into private.legal_ocr_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    safe_error_code,
    safe_error_detail
  )
  select
    stale.municipality_id,
    stale.id,
    case when stale.status = 'dead_letter' then 'dead_lettered' else 'retried' end,
    stale.attempt,
    stale.safe_error_code,
    stale.safe_error_detail
  from stale;

  v_lease_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_lease_sha256 := encode(extensions.digest(v_lease_token, 'sha256'), 'hex');

  with candidate as materialized (
    select job.id
    from private.legal_ocr_jobs job
    join private.knowledge_automation_settings setting
      on setting.municipality_id = job.municipality_id
     and setting.enabled
    join private.legal_source_change_sets change_set
      on change_set.municipality_id = job.municipality_id
     and change_set.id = job.change_set_id
     and change_set.status in ('detected', 'changes_requested')
     and change_set.candidate_version_id is null
    join private.legal_source_artifacts artifact
      on artifact.municipality_id = job.municipality_id
     and artifact.id = job.source_artifact_id
     and artifact.extraction_status = 'requires_extraction'
     and artifact.mime_type = 'application/pdf'
     and artifact.metadata ->> 'extraction_blocker' in (
       'source_pdf_extraction_failed', 'source_pdf_text_missing'
     )
     and case
       when artifact.metadata ->> 'extraction_page_count' ~ '^[0-9]+$'
         then (artifact.metadata ->> 'extraction_page_count')::integer between 1 and 120
       else false
     end
    join private.legal_source_endpoints endpoint
      on endpoint.municipality_id = artifact.municipality_id
     and endpoint.id = artifact.endpoint_id
     and endpoint.status = 'active'
     and endpoint.content_mode = 'legal_body'
     and endpoint.citable_body
    join storage.objects object
      on object.bucket_id = artifact.storage_bucket
     and object.name = artifact.storage_path
     and object.metadata ->> 'size' ~ '^[0-9]+$'
     and (object.metadata ->> 'size')::numeric = artifact.byte_size::numeric
     and lower(split_part(coalesce(object.metadata ->> 'mimetype', ''), ';', 1))
       = 'application/pdf'
    where job.status = 'queued'
      and job.available_at <= now()
    order by job.priority, job.available_at, job.created_at, job.id
    for update of job skip locked
    limit 1
  )
  update private.legal_ocr_jobs job
  set status = 'processing',
      attempt = job.attempt + 1,
      lease_token_sha256 = v_lease_sha256,
      lease_started_at = now(),
      lease_expires_at = now() + make_interval(secs => p_lease_seconds),
      safe_error_code = null,
      safe_error_detail = null,
      updated_at = now()
  from candidate
  where job.id = candidate.id
  returning job.* into v_claimed;

  if v_claimed.id is null then
    return jsonb_build_object(
      'contract_version', 'ia-fiscal-knowledge-ocr/v1',
      'status', 'empty'
    );
  end if;

  select artifact.* into strict v_artifact
  from private.legal_source_artifacts artifact
  where artifact.municipality_id = v_claimed.municipality_id
    and artifact.id = v_claimed.source_artifact_id;

  select source.title into strict v_source_title
  from public.legal_sources source
  where source.municipality_id = v_claimed.municipality_id
    and source.id = v_claimed.source_id;

  insert into private.legal_ocr_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    oidc_request_id,
    metadata
  ) values (
    v_claimed.municipality_id,
    v_claimed.id,
    'claimed',
    v_claimed.attempt,
    v_oidc_request_id,
    jsonb_build_object(
      'main_runtime_gate_id', v_main_runtime_gate_id,
      'ocr_runtime_gate_id', v_ocr_runtime_gate_id,
      'workflow_sha', p_oidc_context ->> 'workflow_sha',
      'run_id', p_oidc_context ->> 'run_id',
      'run_attempt', p_oidc_context ->> 'run_attempt'
    )
  );

  return jsonb_build_object(
    'contract_version', 'ia-fiscal-knowledge-ocr/v1',
    'status', 'claimed',
    'job', jsonb_build_object(
      'id', v_claimed.id,
      'attempt', v_claimed.attempt,
      'max_attempts', v_claimed.max_attempts,
      'lease_token', v_lease_token,
      'lease_expires_at', v_claimed.lease_expires_at
    ),
    'source', jsonb_build_object(
      'title', v_source_title,
      'storage_bucket', v_artifact.storage_bucket,
      'storage_path', v_artifact.storage_path,
      'sha256', v_artifact.content_sha256,
      'byte_size', v_artifact.byte_size,
      'mime_type', v_artifact.mime_type
    ),
    'limits', jsonb_build_object(
      'max_pages', 120,
      'max_page_characters', 1000000,
      'max_total_characters', 8000000,
      'max_part_bytes', 5242880,
      'source_url_ttl_seconds', 180
    )
  );
end;
$$;

create or replace function public.ia_fiscal_heartbeat_knowledge_ocr_job(
  p_job_id uuid,
  p_lease_token text,
  p_oidc_context jsonb,
  p_usage text default 'heartbeat',
  p_extend_seconds integer default 600
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_main_runtime_gate_id uuid;
  v_ocr_runtime_gate_id uuid;
  v_oidc_request_id uuid;
  v_job private.legal_ocr_jobs%rowtype;
  v_new_expiry timestamptz;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_usage not in ('heartbeat', 'upload_part')
     or p_extend_seconds not between 120 and 900
     or coalesce(p_lease_token, '') !~ '^[a-f0-9]{64}$' then
    raise exception 'invalid OCR heartbeat contract';
  end if;
  v_main_runtime_gate_id := private.lock_current_knowledge_runtime_gate_id();
  v_ocr_runtime_gate_id := private.lock_current_legal_ocr_runtime_gate_id();
  if v_main_runtime_gate_id is null or v_ocr_runtime_gate_id is null then
    raise exception using errcode = '55000', message = 'OCR runtime is not verified';
  end if;
  v_oidc_request_id := private.consume_legal_ocr_oidc_request(
    p_usage,
    p_oidc_context,
    v_ocr_runtime_gate_id
  );

  select job.* into strict v_job
  from private.legal_ocr_jobs job
  where job.id = p_job_id
  for update;
  if v_job.status <> 'processing'
     or v_job.lease_expires_at <= now()
     or v_job.lease_token_sha256 <>
       encode(extensions.digest(p_lease_token, 'sha256'), 'hex') then
    raise exception using errcode = '42501', message = 'invalid or expired OCR lease';
  end if;

  v_new_expiry := least(
    now() + make_interval(secs => p_extend_seconds),
    v_job.lease_started_at + interval '2 hours'
  );
  if v_new_expiry <= now() then
    raise exception using errcode = '55000', message = 'OCR lease lifetime exhausted';
  end if;

  update private.legal_ocr_jobs job
  set lease_expires_at = v_new_expiry,
      updated_at = now()
  where job.id = v_job.id;

  insert into private.legal_ocr_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    oidc_request_id,
    metadata
  ) values (
    v_job.municipality_id,
    v_job.id,
    'heartbeat',
    v_job.attempt,
    v_oidc_request_id,
    jsonb_build_object(
      'usage', p_usage,
      'lease_expires_at', v_new_expiry,
      'workflow_sha', p_oidc_context ->> 'workflow_sha'
    )
  );

  return jsonb_build_object(
    'contract_version', 'ia-fiscal-knowledge-ocr/v1',
    'status', 'processing',
    'job_id', v_job.id,
    'attempt', v_job.attempt,
    'lease_expires_at', v_new_expiry
  );
end;
$$;

create or replace function public.ia_fiscal_fail_knowledge_ocr_job(
  p_job_id uuid,
  p_lease_token text,
  p_oidc_context jsonb,
  p_error_code text,
  p_error_detail text,
  p_retryable boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_main_runtime_gate_id uuid;
  v_ocr_runtime_gate_id uuid;
  v_oidc_request_id uuid;
  v_job private.legal_ocr_jobs%rowtype;
  v_replay_event private.legal_ocr_job_events%rowtype;
  v_error_code text := lower(trim(coalesce(p_error_code, '')));
  v_error_detail text := nullif(left(trim(coalesce(p_error_detail, '')), 1000), '');
  v_lease_sha256 text;
  v_retry boolean;
  v_status text;
  v_available_at timestamptz;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if coalesce(p_lease_token, '') !~ '^[a-f0-9]{64}$'
     or v_error_code !~ '^[a-z0-9][a-z0-9_.:-]{1,119}$' then
    raise exception 'invalid OCR failure contract';
  end if;
  v_main_runtime_gate_id := private.lock_current_knowledge_runtime_gate_id();
  v_ocr_runtime_gate_id := private.lock_current_legal_ocr_runtime_gate_id();
  if v_main_runtime_gate_id is null or v_ocr_runtime_gate_id is null then
    raise exception using errcode = '55000', message = 'OCR runtime is not verified';
  end if;
  v_oidc_request_id := private.consume_legal_ocr_oidc_request(
    'fail',
    p_oidc_context,
    v_ocr_runtime_gate_id
  );

  select job.* into strict v_job
  from private.legal_ocr_jobs job
  where job.id = p_job_id
  for update;
  v_lease_sha256 := encode(extensions.digest(p_lease_token, 'sha256'), 'hex');
  if v_job.status <> 'processing'
     or v_job.lease_expires_at <= now()
     or v_job.lease_token_sha256 <> v_lease_sha256 then
    -- A response may be lost after the failure transition commits. A fresh
    -- OIDC/JTI may replay the exact failure, but cannot mutate the queue again
    -- or append a duplicate job event.
    select event.* into v_replay_event
    from private.legal_ocr_job_events event
    where event.municipality_id = v_job.municipality_id
      and event.job_id = v_job.id
      and event.event_type in ('retried', 'dead_lettered')
      and event.safe_error_code = v_error_code
      and event.safe_error_detail is not distinct from v_error_detail
      and event.metadata ->> 'failure_lease_token_sha256' = v_lease_sha256
      and event.metadata ->> 'retryable' = coalesce(p_retryable, false)::text
      and event.metadata ->> 'result_status' in ('queued', 'dead_letter')
    order by event.event_at desc, event.id desc
    limit 1;

    if v_replay_event.id is not null then
      return jsonb_build_object(
        'contract_version', 'ia-fiscal-knowledge-ocr/v1',
        'status', v_replay_event.metadata ->> 'result_status',
        'job_id', v_job.id,
        'attempt', v_replay_event.attempt,
        'available_at', v_replay_event.metadata -> 'next_available_at',
        'safe_error_code', v_error_code,
        'replayed', true
      );
    end if;
    raise exception using errcode = '42501', message = 'invalid or expired OCR lease';
  end if;

  v_retry := coalesce(p_retryable, false) and v_job.attempt < v_job.max_attempts;
  v_status := case when v_retry then 'queued' else 'dead_letter' end;
  v_available_at := case when v_retry then
    now() + make_interval(
      mins => least(240, power(2, greatest(v_job.attempt, 1))::integer)
    )
    else v_job.available_at
  end;

  update private.legal_ocr_jobs job
  set status = v_status,
      available_at = v_available_at,
      lease_token_sha256 = null,
      lease_started_at = null,
      lease_expires_at = null,
      safe_error_code = v_error_code,
      safe_error_detail = v_error_detail,
      updated_at = now()
  where job.id = v_job.id;

  insert into private.legal_ocr_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    oidc_request_id,
    safe_error_code,
    safe_error_detail,
    metadata
  ) values (
    v_job.municipality_id,
    v_job.id,
    case when v_retry then 'retried' else 'dead_lettered' end,
    v_job.attempt,
    v_oidc_request_id,
    v_error_code,
    v_error_detail,
    jsonb_build_object(
      'retryable', coalesce(p_retryable, false),
      'next_available_at', case when v_retry then v_available_at end,
      'result_status', v_status,
      'failure_lease_token_sha256', v_lease_sha256,
      'workflow_sha', p_oidc_context ->> 'workflow_sha'
    )
  );

  return jsonb_build_object(
    'contract_version', 'ia-fiscal-knowledge-ocr/v1',
    'status', v_status,
    'job_id', v_job.id,
    'attempt', v_job.attempt,
    'available_at', case when v_retry then v_available_at end,
    'safe_error_code', v_error_code
  );
end;
$$;

create or replace function public.ia_fiscal_finalize_knowledge_ocr_job(
  p_job_id uuid,
  p_lease_token text,
  p_oidc_context jsonb,
  p_engine_name text,
  p_engine_version text,
  p_manifest_path text,
  p_manifest_sha256 text,
  p_manifest_byte_size bigint,
  p_expected_content_sha256 text,
  p_manifest_evidence jsonb,
  p_pages jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_main_runtime_gate_id uuid;
  v_ocr_runtime_gate_id uuid;
  v_oidc_request_id uuid;
  v_job private.legal_ocr_jobs%rowtype;
  v_artifact private.legal_source_artifacts%rowtype;
  v_change_set private.legal_source_change_sets%rowtype;
  v_existing_result private.legal_ocr_results%rowtype;
  v_page jsonb;
  v_page_number integer;
  v_expected_page_number integer := 0;
  v_content_text text;
  v_text_sha256 text;
  v_storage_path text;
  v_artifact_sha256 text;
  v_artifact_byte_size bigint;
  v_confidence_milli integer;
  v_confidence_samples integer;
  v_character_count integer;
  v_utf8_bytes integer;
  v_word_count integer;
  v_total_characters bigint := 0;
  v_total_utf8_bytes bigint := 0;
  v_total_words bigint := 0;
  v_pages_with_text integer := 0;
  v_confidence_page_samples integer := 0;
  v_confidence_sum bigint := 0;
  v_minimum_confidence_milli integer := 1000;
  v_page_coverage_bps integer;
  v_mean_confidence_milli integer;
  v_manifest_page_count integer;
  v_manifest_pages_with_text integer;
  v_manifest_page_coverage_bps integer;
  v_manifest_mean_confidence_milli integer;
  v_manifest_minimum_confidence_milli integer;
  v_manifest_confidence_page_samples integer;
  v_manifest_total_characters bigint;
  v_manifest_total_utf8_bytes bigint;
  v_manifest_total_words bigint;
  v_page_count integer;
  v_candidate_version_number integer;
  v_candidate_version_id uuid;
  v_previous_version_id uuid;
  v_content_sha256 text;
  v_page_evidence_sha256 text;
  v_result_id uuid;
  v_sections jsonb;
  v_stage jsonb;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if coalesce(p_lease_token, '') !~ '^[a-f0-9]{64}$'
     or lower(trim(coalesce(p_engine_name, ''))) !~
          '^[a-z0-9][a-z0-9_.-]{1,79}$'
     or trim(coalesce(p_engine_version, '')) !~
          '^[A-Za-z0-9][A-Za-z0-9_.+-]{0,79}$'
     or coalesce(p_manifest_sha256, '') !~ '^[a-f0-9]{64}$'
     or coalesce(p_expected_content_sha256, '') !~ '^[a-f0-9]{64}$'
     or p_manifest_byte_size not between 2 and 5242880
     or p_manifest_evidence is null
     or jsonb_typeof(p_manifest_evidence) <> 'object'
     or p_pages is null
     or jsonb_typeof(p_pages) <> 'array'
     or jsonb_array_length(p_pages) not between 1 and 120 then
    raise exception 'invalid OCR finalization contract';
  end if;

  v_main_runtime_gate_id := private.lock_current_knowledge_runtime_gate_id();
  v_ocr_runtime_gate_id := private.lock_current_legal_ocr_runtime_gate_id();
  if v_main_runtime_gate_id is null or v_ocr_runtime_gate_id is null then
    raise exception using errcode = '55000', message = 'OCR runtime is not verified';
  end if;
  v_oidc_request_id := private.consume_legal_ocr_oidc_request(
    'complete',
    p_oidc_context,
    v_ocr_runtime_gate_id
  );

  select job.* into strict v_job
  from private.legal_ocr_jobs job
  where job.id = p_job_id
  for update;
  if v_job.status = 'completed' then
    select result.* into strict v_existing_result
    from private.legal_ocr_results result
    where result.municipality_id = v_job.municipality_id
      and result.job_id = v_job.id;
    if v_existing_result.attempt <> v_job.attempt
       or v_existing_result.completion_lease_token_sha256 <>
            encode(extensions.digest(p_lease_token, 'sha256'), 'hex')
       or v_existing_result.engine_name <> lower(trim(p_engine_name))
       or v_existing_result.engine_version <> trim(p_engine_version)
       or v_existing_result.manifest_path <> p_manifest_path
       or v_existing_result.manifest_sha256 <> p_manifest_sha256
       or v_existing_result.manifest_byte_size <> p_manifest_byte_size
       or v_existing_result.completion_evidence_sha256 <>
            encode(
              extensions.digest(
                p_manifest_evidence::text || ':' || p_pages::text,
                'sha256'
              ),
              'hex'
            )
       or v_existing_result.content_sha256 <> p_expected_content_sha256
       or v_existing_result.page_count <> jsonb_array_length(p_pages) then
      raise exception using
        errcode = '22000',
        message = 'completed OCR result does not match replay evidence';
    end if;

    insert into private.legal_ocr_job_events (
      municipality_id,
      job_id,
      event_type,
      attempt,
      oidc_request_id,
      metadata
    ) values (
      v_job.municipality_id,
      v_job.id,
      'completion_replayed',
      v_job.attempt,
      v_oidc_request_id,
      jsonb_build_object(
        'ocr_result_id', v_existing_result.id,
        'manifest_sha256', v_existing_result.manifest_sha256,
        'workflow_sha', p_oidc_context ->> 'workflow_sha'
      )
    );

    return jsonb_build_object(
      'contract_version', 'ia-fiscal-knowledge-ocr/v1',
      'status', 'already_completed',
      'job_id', v_job.id,
      'ocr_result_id', v_existing_result.id,
      'artifact_id', v_existing_result.source_artifact_id,
      'change_set_id', v_existing_result.change_set_id,
      'candidate_version_id', v_existing_result.candidate_version_id,
      'content_sha256', v_existing_result.content_sha256,
      'page_count', v_existing_result.page_count,
      'character_count', v_existing_result.character_count,
      'publication_status', 'not_published'
    );
  end if;
  if v_job.status <> 'processing'
     or v_job.lease_expires_at <= now()
     or v_job.lease_token_sha256 <>
       encode(extensions.digest(p_lease_token, 'sha256'), 'hex') then
    raise exception using errcode = '42501', message = 'invalid or expired OCR lease';
  end if;

  select artifact.* into strict v_artifact
  from private.legal_source_artifacts artifact
  where artifact.municipality_id = v_job.municipality_id
    and artifact.id = v_job.source_artifact_id
  for update;
  if v_artifact.source_id <> v_job.source_id
     or v_artifact.extraction_status <> 'requires_extraction'
     or v_artifact.extracted_text_sha256 is not null
     or v_artifact.mime_type <> 'application/pdf'
     or v_artifact.metadata ->> 'extraction_blocker' not in (
       'source_pdf_extraction_failed', 'source_pdf_text_missing'
     )
     or not (case
       when v_artifact.metadata ->> 'extraction_page_count' ~ '^[0-9]+$'
         then (v_artifact.metadata ->> 'extraction_page_count')::integer between 1 and 120
       else false
     end)
     or not exists (
       select 1
       from storage.objects source_object
       where source_object.bucket_id = v_artifact.storage_bucket
         and source_object.name = v_artifact.storage_path
         and source_object.metadata ->> 'size' ~ '^[0-9]+$'
         and (source_object.metadata ->> 'size')::numeric = v_artifact.byte_size::numeric
         and lower(
           split_part(coalesce(source_object.metadata ->> 'mimetype', ''), ';', 1)
         ) = 'application/pdf'
     ) then
    raise exception 'official source artifact is not pending governed OCR';
  end if;

  begin
    v_manifest_page_count := (p_manifest_evidence ->> 'page_count')::integer;
    v_manifest_pages_with_text :=
      (p_manifest_evidence ->> 'pages_with_text')::integer;
    v_manifest_page_coverage_bps :=
      (p_manifest_evidence ->> 'page_coverage_bps')::integer;
    v_manifest_mean_confidence_milli :=
      (p_manifest_evidence ->> 'mean_confidence_milli')::integer;
    v_manifest_minimum_confidence_milli :=
      (p_manifest_evidence ->> 'minimum_confidence_milli')::integer;
    v_manifest_confidence_page_samples :=
      (p_manifest_evidence ->> 'confidence_page_samples')::integer;
    v_manifest_total_characters :=
      (p_manifest_evidence ->> 'total_characters')::bigint;
    v_manifest_total_utf8_bytes :=
      (p_manifest_evidence ->> 'total_utf8_bytes')::bigint;
    v_manifest_total_words := (p_manifest_evidence ->> 'total_words')::bigint;
  exception when others then
    raise exception 'OCR manifest quality evidence is invalid';
  end;
  if p_manifest_evidence ->> 'policy_version' <>
       'ia-fiscal-knowledge-ocr-policy/v1'
     or p_manifest_evidence ->> 'toolchain_lock_sha256' <>
       '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60'
     or p_manifest_evidence ->> 'source_sha256' <> v_artifact.content_sha256
     or (p_manifest_evidence ->> 'source_byte_size')::bigint <> v_artifact.byte_size
     or v_manifest_page_count <>
       (v_artifact.metadata ->> 'extraction_page_count')::integer
     or coalesce(p_manifest_evidence ->> 'normalized_sha256', '') !~ '^[a-f0-9]{64}$'
     or (p_manifest_evidence ->> 'normalized_byte_size')::bigint not between 1 and 536870912
     or p_manifest_evidence ->> 'language' <> 'por'
     or (p_manifest_evidence ->> 'dpi')::integer <> 300
     or lower(trim(p_engine_name)) <> 'tesseract'
     or trim(p_engine_version) <> '5.3.4'
     or jsonb_typeof(p_manifest_evidence -> 'toolchain') <> 'object'
     or p_manifest_evidence #>> '{toolchain,bubblewrap,canonical_version}' <> '0.9.0'
     or p_manifest_evidence #>> '{toolchain,qpdf,canonical_version}' <> '11.9.0'
     or p_manifest_evidence #>> '{toolchain,pdfinfo,canonical_version}' <> '24.02.0'
     or p_manifest_evidence #>> '{toolchain,pdftoppm,canonical_version}' <> '24.02.0'
     or p_manifest_evidence #>> '{toolchain,tesseract,canonical_version}' <> '5.3.4'
     or p_manifest_evidence #>> '{toolchain,unrtf,canonical_version}' <> '0.21.10'
     or p_manifest_evidence #>> '{toolchain,python,canonical_version}' <> '3.12.11'
     or p_manifest_evidence #>> '{toolchain,packages,bubblewrap}' <> '0.9.0-1ubuntu0.1'
     or p_manifest_evidence #>> '{toolchain,packages,qpdf}' <> '11.9.0-1.1ubuntu0.1'
     or p_manifest_evidence #>> '{toolchain,packages,poppler-utils}' <>
       '24.02.0-1ubuntu9.9'
     or p_manifest_evidence #>> '{toolchain,packages,tesseract-ocr}' <>
       '5.3.4-1build5'
     or p_manifest_evidence #>> '{toolchain,packages,tesseract-ocr-por}' <>
       '1:4.1.0-2'
     or p_manifest_evidence #>> '{toolchain,packages,unrtf}' <> '0.21.10-clean-1'
     or coalesce(
       p_manifest_evidence #>> '{toolchain,bubblewrap,binary_sha256}', ''
     ) !~ '^[a-f0-9]{64}$'
     or coalesce(p_manifest_evidence #>> '{toolchain,qpdf,binary_sha256}', '')
       !~ '^[a-f0-9]{64}$'
     or coalesce(p_manifest_evidence #>> '{toolchain,pdfinfo,binary_sha256}', '')
       !~ '^[a-f0-9]{64}$'
     or coalesce(p_manifest_evidence #>> '{toolchain,pdftoppm,binary_sha256}', '')
       !~ '^[a-f0-9]{64}$'
     or coalesce(p_manifest_evidence #>> '{toolchain,tesseract,binary_sha256}', '')
       !~ '^[a-f0-9]{64}$'
     or coalesce(p_manifest_evidence #>> '{toolchain,unrtf,binary_sha256}', '')
       !~ '^[a-f0-9]{64}$'
     or coalesce(p_manifest_evidence #>> '{toolchain,python,binary_sha256}', '')
       !~ '^[a-f0-9]{64}$'
     or coalesce(
       p_manifest_evidence #>> '{toolchain,tesseract_por,traineddata_sha256}', ''
     ) !~ '^[a-f0-9]{64}$' then
    raise exception 'OCR manifest root-of-trust evidence mismatch';
  end if;

  select change_set.* into strict v_change_set
  from private.legal_source_change_sets change_set
  where change_set.municipality_id = v_job.municipality_id
    and change_set.id = v_job.change_set_id
  for update;
  if v_change_set.source_id <> v_job.source_id
     or v_change_set.to_artifact_id <> v_artifact.id
     or v_change_set.status not in ('detected', 'changes_requested')
     or v_change_set.candidate_version_id is not null
     or v_change_set.change_type = 'legacy_import' then
    raise exception 'OCR change set is no longer open for extraction';
  end if;

  if p_manifest_path <>
       format(
         'jobs/%s/attempt-%s/manifest-%s.json',
         v_job.id,
         v_job.attempt,
         p_manifest_sha256
       )
     or not exists (
       select 1
       from storage.objects object
       where object.bucket_id = 'legal-ocr-artifacts'
         and object.name = p_manifest_path
         and object.metadata ->> 'size' ~ '^[0-9]+$'
         and (object.metadata ->> 'size')::numeric = p_manifest_byte_size::numeric
         and lower(split_part(coalesce(object.metadata ->> 'mimetype', ''), ';', 1))
           = 'application/json'
     ) then
    raise exception 'immutable OCR manifest artifact is missing';
  end if;

  for v_page in
    select value from jsonb_array_elements(p_pages)
  loop
    v_expected_page_number := v_expected_page_number + 1;
    if jsonb_typeof(v_page) <> 'object' then
      raise exception 'every OCR page must be an object';
    end if;
    begin
      v_page_number := (v_page ->> 'page_number')::integer;
      v_artifact_byte_size := (v_page ->> 'artifact_byte_size')::bigint;
      v_confidence_milli := nullif(v_page ->> 'confidence_milli', '')::integer;
      v_confidence_samples := (v_page ->> 'confidence_samples')::integer;
      v_character_count := (v_page ->> 'character_count')::integer;
      v_utf8_bytes := (v_page ->> 'utf8_bytes')::integer;
      v_word_count := (v_page ->> 'word_count')::integer;
    exception when others then
      raise exception 'OCR page numeric evidence is invalid';
    end;
    v_content_text := coalesce(v_page ->> 'content_text', '');
    v_text_sha256 := coalesce(v_page ->> 'text_sha256', '');
    v_storage_path := coalesce(v_page ->> 'storage_path', '');
    v_artifact_sha256 := coalesce(v_page ->> 'artifact_sha256', '');

    if v_page_number <> v_expected_page_number
       or char_length(v_content_text) > 1000000
       or v_character_count <> char_length(v_content_text)
       or v_utf8_bytes <> octet_length(v_content_text)
       or v_word_count <> (case
            when trim(v_content_text) = '' then 0
            else cardinality(regexp_split_to_array(trim(v_content_text), E'\\s+'))
          end)
       or v_confidence_samples not between 0 and 100000000
       or v_text_sha256 !~ '^[a-f0-9]{64}$'
       or v_text_sha256 <>
            encode(extensions.digest(v_content_text, 'sha256'), 'hex')
       or v_artifact_sha256 !~ '^[a-f0-9]{64}$'
       or v_artifact_byte_size not between 2 and 5242880
       or (
         v_confidence_milli is not null
         and v_confidence_milli not between 0 and 1000
       )
       or (
         char_length(v_content_text) > 0
         and (v_confidence_milli is null or v_confidence_samples = 0)
       )
       or (
         char_length(v_content_text) = 0
         and (v_confidence_milli is not null or v_confidence_samples <> 0)
       )
       or v_storage_path <>
            format(
              'jobs/%s/attempt-%s/page-%s-%s.json',
              v_job.id,
              v_job.attempt,
              lpad(v_page_number::text, 4, '0'),
              v_artifact_sha256
            ) then
      raise exception 'OCR page evidence failed deterministic validation';
    end if;
    if not exists (
      select 1
      from storage.objects object
      where object.bucket_id = 'legal-ocr-artifacts'
        and object.name = v_storage_path
        and object.metadata ->> 'size' ~ '^[0-9]+$'
        and (object.metadata ->> 'size')::numeric = v_artifact_byte_size::numeric
        and lower(split_part(coalesce(object.metadata ->> 'mimetype', ''), ';', 1))
          = 'application/json'
    ) then
      raise exception 'immutable OCR page artifact is missing';
    end if;

    v_total_characters := v_total_characters + char_length(v_content_text);
    v_total_utf8_bytes := v_total_utf8_bytes + v_utf8_bytes;
    v_total_words := v_total_words + v_word_count;
    if char_length(v_content_text) > 0 then
      v_pages_with_text := v_pages_with_text + 1;
      v_confidence_page_samples := v_confidence_page_samples + 1;
      v_confidence_sum := v_confidence_sum + v_confidence_milli;
      v_minimum_confidence_milli :=
        least(v_minimum_confidence_milli, v_confidence_milli);
    end if;
    if v_total_characters > 8000000 then
      raise exception 'OCR text exceeds the governed character limit';
    end if;

    insert into private.legal_ocr_job_pages (
      municipality_id,
      job_id,
      attempt,
      page_number,
      content_text,
      text_sha256,
      storage_bucket,
      storage_path,
      artifact_sha256,
      artifact_byte_size,
      confidence,
      confidence_samples,
      character_count,
      utf8_bytes,
      word_count
    ) values (
      v_job.municipality_id,
      v_job.id,
      v_job.attempt,
      v_page_number,
      v_content_text,
      v_text_sha256,
      'legal-ocr-artifacts',
      v_storage_path,
      v_artifact_sha256,
      v_artifact_byte_size,
      case when v_confidence_milli is null then null
        else v_confidence_milli::numeric / 1000 end,
      v_confidence_samples,
      v_character_count,
      v_utf8_bytes,
      v_word_count
    );
  end loop;

  v_page_count := jsonb_array_length(p_pages);
  v_page_coverage_bps :=
    round(v_pages_with_text::numeric * 10000 / v_page_count)::integer;
  if v_confidence_page_samples = 0 then
    raise exception 'OCR quality gate rejected coverage or confidence';
  end if;
  v_mean_confidence_milli :=
    round(v_confidence_sum::numeric / v_confidence_page_samples)::integer;
  if v_page_coverage_bps < 9000
     or v_confidence_page_samples <> v_pages_with_text
     or v_mean_confidence_milli < 550 then
    raise exception 'OCR quality gate rejected coverage or confidence';
  end if;

  if v_manifest_page_count <> v_page_count
     or v_manifest_pages_with_text <> v_pages_with_text
     or abs(v_manifest_page_coverage_bps - v_page_coverage_bps) > 1
     or abs(v_manifest_mean_confidence_milli - v_mean_confidence_milli) > 1
     or v_manifest_minimum_confidence_milli <> v_minimum_confidence_milli
     or v_manifest_confidence_page_samples <> v_confidence_page_samples
     or v_manifest_total_characters <> v_total_characters
     or v_manifest_total_utf8_bytes <> v_total_utf8_bytes
     or v_manifest_total_words <> v_total_words then
    raise exception 'OCR manifest metrics do not match server-derived evidence';
  end if;

  select
    count(*)::integer,
    string_agg(page.content_text, E'\n\f\n' order by page.page_number),
    encode(
      extensions.digest(
        string_agg(
          page.page_number::text || ':' || page.text_sha256 || ':' ||
          page.artifact_sha256 || ':' || page.artifact_byte_size::text,
          E'\n' order by page.page_number
        ),
        'sha256'
      ),
      'hex'
    )
  into v_page_count, v_content_text, v_page_evidence_sha256
  from private.legal_ocr_job_pages page
  where page.municipality_id = v_job.municipality_id
    and page.job_id = v_job.id
    and page.attempt = v_job.attempt;

  if v_page_count <> jsonb_array_length(p_pages)
     or char_length(v_content_text) not between 80 and 8000000 then
    raise exception 'OCR page set is incomplete or empty';
  end if;
  v_content_sha256 := encode(extensions.digest(v_content_text, 'sha256'), 'hex');
  if v_content_sha256 <> p_expected_content_sha256 then
    raise exception 'OCR consolidated content hash mismatch';
  end if;

  -- Serialize version numbering and prevent two artifacts for the same source
  -- from being finalized concurrently with the same predecessor.
  perform 1
  from public.legal_sources source
  where source.municipality_id = v_job.municipality_id
    and source.id = v_job.source_id
  for update;

  select version.id into v_previous_version_id
  from public.legal_source_versions version
  where version.municipality_id = v_job.municipality_id
    and version.source_id = v_job.source_id
  order by version.version desc, version.id desc
  limit 1;

  select coalesce(max(version.version), 0) + 1
    into v_candidate_version_number
  from public.legal_source_versions version
  where version.municipality_id = v_job.municipality_id
    and version.source_id = v_job.source_id;

  insert into public.legal_source_versions (
    municipality_id,
    source_id,
    version,
    status,
    content_text,
    content_sha256,
    supersedes_version_id
  ) values (
    v_job.municipality_id,
    v_job.source_id,
    v_candidate_version_number,
    'under_review',
    v_content_text,
    v_content_sha256,
    v_previous_version_id
  ) returning id into v_candidate_version_id;

  insert into private.legal_source_artifact_versions (
    municipality_id,
    artifact_id,
    source_version_id
  ) values (
    v_job.municipality_id,
    v_artifact.id,
    v_candidate_version_id
  );

  insert into private.legal_ocr_results (
    municipality_id,
    job_id,
    source_artifact_id,
    change_set_id,
    candidate_version_id,
    attempt,
    completion_lease_token_sha256,
    engine_name,
    engine_version,
    manifest_bucket,
    manifest_path,
    manifest_sha256,
    manifest_byte_size,
    completion_evidence_sha256,
    page_evidence_sha256,
    content_sha256,
    page_count,
    character_count,
    page_coverage_bps,
    mean_confidence_milli,
    policy_version,
    toolchain_lock_sha256,
    toolchain_evidence
  ) values (
    v_job.municipality_id,
    v_job.id,
    v_artifact.id,
    v_change_set.id,
    v_candidate_version_id,
    v_job.attempt,
    encode(extensions.digest(p_lease_token, 'sha256'), 'hex'),
    lower(trim(p_engine_name)),
    trim(p_engine_version),
    'legal-ocr-artifacts',
    p_manifest_path,
    p_manifest_sha256,
    p_manifest_byte_size,
    encode(
      extensions.digest(
        p_manifest_evidence::text || ':' || p_pages::text,
        'sha256'
      ),
      'hex'
    ),
    v_page_evidence_sha256,
    v_content_sha256,
    v_page_count,
    char_length(v_content_text),
    v_page_coverage_bps,
    v_mean_confidence_milli,
    'ia-fiscal-knowledge-ocr-policy/v1',
    '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60',
    p_manifest_evidence -> 'toolchain'
  ) returning id into v_result_id;

  update private.legal_source_artifacts artifact
  set extraction_status = 'completed',
      extracted_text_sha256 = v_content_sha256,
      metadata = artifact.metadata || jsonb_build_object(
        'ocr_result_id', v_result_id,
        'ocr_engine', lower(trim(p_engine_name)),
        'ocr_engine_version', trim(p_engine_version),
        'ocr_manifest_sha256', p_manifest_sha256,
        'ocr_policy_version', 'ia-fiscal-knowledge-ocr-policy/v1',
        'ocr_toolchain_lock_sha256',
          '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60',
        'ocr_page_coverage_bps', v_page_coverage_bps,
        'ocr_mean_confidence_milli', v_mean_confidence_milli,
        'extraction_complete', true,
        'content_truncated', false,
        'extracted_char_count', char_length(v_content_text),
        'extraction_method', 'external_ocr'
      )
  where artifact.municipality_id = v_artifact.municipality_id
    and artifact.id = v_artifact.id;

  update private.legal_source_change_sets change_set
  set candidate_version_id = v_candidate_version_id,
      updated_at = now()
  where change_set.municipality_id = v_change_set.municipality_id
    and change_set.id = v_change_set.id;

  with chunks as (
    select
      page.page_number,
      part.chunk_start,
      substr(page.content_text, part.chunk_start, 6000) as content_text
    from private.legal_ocr_job_pages page
    cross join lateral generate_series(
      1,
      greatest(char_length(page.content_text), 1),
      6000
    ) part(chunk_start)
    where page.municipality_id = v_job.municipality_id
      and page.job_id = v_job.id
      and page.attempt = v_job.attempt
  ), bounded_chunks as (
    select * from chunks
    where nullif(trim(content_text), '') is not null
  )
  select jsonb_build_array(jsonb_build_object(
    'section_key', 'integral',
    'heading', 'Documento oficial extraído por OCR — revisão obrigatória',
    'ordinal', 1,
    'content_text', v_content_text,
    'chunks', jsonb_agg(
      jsonb_build_object(
        'content_text', bounded_chunks.content_text,
        'token_count', greatest(
          1,
          array_length(
            regexp_split_to_array(trim(bounded_chunks.content_text), E'\\s+'),
            1
          )
        )
      ) order by bounded_chunks.page_number, bounded_chunks.chunk_start
    )
  )) into v_sections
  from bounded_chunks;

  if v_sections is null
     or jsonb_array_length(v_sections -> 0 -> 'chunks') not between 1 and 5000 then
    raise exception 'OCR chunk set is empty or exceeds the governed limit';
  end if;

  v_stage := public.ia_fiscal_stage_knowledge_sections(
    v_change_set.id,
    v_sections
  );
  if v_stage ->> 'status' not in ('staged', 'already_staged')
     or not private.knowledge_staging_matches_payload(
       v_candidate_version_id,
       v_sections
     ) then
    raise exception 'OCR candidate staging did not preserve exact evidence';
  end if;

  update private.legal_ocr_jobs job
  set status = 'completed',
      lease_token_sha256 = null,
      lease_started_at = null,
      lease_expires_at = null,
      completed_at = now(),
      safe_error_code = null,
      safe_error_detail = null,
      updated_at = now()
  where job.id = v_job.id;

  insert into private.legal_ocr_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    oidc_request_id,
    metadata
  ) values (
    v_job.municipality_id,
    v_job.id,
    'completed',
    v_job.attempt,
    v_oidc_request_id,
    jsonb_build_object(
      'ocr_result_id', v_result_id,
      'candidate_version_id', v_candidate_version_id,
      'content_sha256', v_content_sha256,
      'manifest_sha256', p_manifest_sha256,
      'page_evidence_sha256', v_page_evidence_sha256,
      'page_count', v_page_count,
      'character_count', char_length(v_content_text),
      'page_coverage_bps', v_page_coverage_bps,
      'mean_confidence_milli', v_mean_confidence_milli,
      'policy_version', 'ia-fiscal-knowledge-ocr-policy/v1',
      'toolchain_lock_sha256',
        '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60',
      'workflow_sha', p_oidc_context ->> 'workflow_sha'
    )
  );

  return jsonb_build_object(
    'contract_version', 'ia-fiscal-knowledge-ocr/v1',
    'status', 'under_review',
    'job_id', v_job.id,
    'ocr_result_id', v_result_id,
    'artifact_id', v_artifact.id,
    'change_set_id', v_change_set.id,
    'candidate_version_id', v_candidate_version_id,
    'content_sha256', v_content_sha256,
    'page_count', v_page_count,
    'character_count', char_length(v_content_text),
    'publication_status', 'not_published'
  );
end;
$$;

alter function public.ia_get_knowledge_operations_snapshot(uuid)
  rename to ia_get_knowledge_operations_snapshot_pre_ocr;

create or replace function public.ia_get_knowledge_operations_snapshot(
  p_municipality_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_runtime_verified boolean;
  v_queued integer;
  v_processing integer;
  v_completed integer;
  v_dead_letter integer;
  v_page_limit_blocked integer;
  v_last_event_at timestamptz;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  v_base := public.ia_get_knowledge_operations_snapshot_pre_ocr(p_municipality_id);
  v_runtime_verified :=
    private.knowledge_runtime_is_verified()
    and private.current_legal_ocr_runtime_gate_id() is not null;

  select
    count(*) filter (where job.status = 'queued')::integer,
    count(*) filter (where job.status = 'processing')::integer,
    count(*) filter (where job.status = 'completed')::integer,
    count(*) filter (where job.status = 'dead_letter')::integer
  into v_queued, v_processing, v_completed, v_dead_letter
  from private.legal_ocr_jobs job
  where job.municipality_id = p_municipality_id;

  select max(event.event_at) into v_last_event_at
  from private.legal_ocr_job_events event
  where event.municipality_id = p_municipality_id;

  select count(*)::integer into v_page_limit_blocked
  from private.legal_source_artifacts artifact
  where artifact.municipality_id = p_municipality_id
    and artifact.extraction_status = 'requires_extraction'
    and artifact.metadata ->> 'extraction_blocker' =
      'external_ocr_page_limit_exceeded';

  return v_base || jsonb_build_object(
    'ocr', jsonb_build_object(
      'contract_version', 'ia-fiscal-knowledge-ocr/v1',
      'policy_version', 'ia-fiscal-knowledge-ocr-policy/v1',
      'runtime_verified', v_runtime_verified,
      'runtime_blocker', case when v_runtime_verified then null
        else 'knowledge_ocr_runtime_not_verified' end,
      'state', case
        when not v_runtime_verified then 'blocked'
        when v_dead_letter > 0 or v_page_limit_blocked > 0 then 'attention_required'
        when v_processing > 0 then 'processing'
        when v_queued > 0 then 'queued'
        else 'ready'
      end,
      'has_attention', v_dead_letter > 0 or v_page_limit_blocked > 0,
      'jobs', jsonb_build_object(
        'queued', v_queued,
        'processing', v_processing,
        'completed', v_completed,
        'dead_letter', v_dead_letter,
        'blocked_page_limit', v_page_limit_blocked
      ),
      'last_event_at', v_last_event_at,
      'limits', jsonb_build_object(
        'max_pages', 120,
        'max_page_characters', 1000000,
        'max_total_characters', 8000000,
        'above_page_limit', 'manual_review_required'
      ),
      'candidate_status', 'under_review',
      'auto_publish', false
    )
  );
end;
$$;

comment on table private.legal_ocr_jobs is
  'Private governed OCR queue. Raw official artifacts remain WORM; leases and retries are audited by append-only events.';
comment on table private.legal_ocr_job_pages is
  'Append-only page text and immutable Storage artifact hashes accepted only during atomic OCR finalization.';
comment on table private.legal_ocr_results is
  'Append-only link from official raw artifact and OCR manifest to an under-review candidate; never an approval or publication.';
comment on function public.ia_fiscal_claim_knowledge_ocr_job(jsonb, integer) is
  'Service-only fail-closed claim after GitHub OIDC validation, runtime attestation and lease recovery.';
comment on function public.ia_fiscal_heartbeat_knowledge_ocr_job(
  uuid, text, jsonb, text, integer
) is
  'Service-only bounded OCR lease heartbeat, also used before immutable upload parts.';
comment on function public.ia_fiscal_finalize_knowledge_ocr_job(
  uuid, text, jsonb, text, text, text, text, bigint, text, jsonb, jsonb
) is
  'Service-only atomic OCR consolidation into under_review evidence. It never approves or publishes.';
comment on function public.ia_fiscal_fail_knowledge_ocr_job(
  uuid, text, jsonb, text, text, boolean
) is
  'Service-only bounded retry/dead-letter transition for an active OCR lease.';

revoke all on function public.ia_fiscal_attest_knowledge_ocr_runtime_ready(
  text, uuid, text, text, text, text, integer, integer, text, text, timestamptz, text
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_attest_knowledge_ocr_runtime_ready(
  text, uuid, text, text, text, text, integer, integer, text, text, timestamptz, text
) to service_role;

revoke all on function public.ia_fiscal_revoke_knowledge_ocr_runtime_gate(
  uuid, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_revoke_knowledge_ocr_runtime_gate(
  uuid, text, text
) to service_role;

revoke all on function public.ia_fiscal_claim_knowledge_ocr_job(jsonb, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_claim_knowledge_ocr_job(jsonb, integer)
  to service_role;

revoke all on function public.ia_fiscal_heartbeat_knowledge_ocr_job(
  uuid, text, jsonb, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_heartbeat_knowledge_ocr_job(
  uuid, text, jsonb, text, integer
) to service_role;

revoke all on function public.ia_fiscal_finalize_knowledge_ocr_job(
  uuid, text, jsonb, text, text, text, text, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_finalize_knowledge_ocr_job(
  uuid, text, jsonb, text, text, text, text, bigint, text, jsonb, jsonb
) to service_role;

revoke all on function public.ia_fiscal_fail_knowledge_ocr_job(
  uuid, text, jsonb, text, text, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_fail_knowledge_ocr_job(
  uuid, text, jsonb, text, text, boolean
) to service_role;

revoke all on function public.ia_get_knowledge_operations_snapshot_pre_ocr(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_get_knowledge_operations_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_knowledge_operations_snapshot(uuid)
  to authenticated;

revoke all on function private.current_legal_ocr_runtime_gate_id()
  from public, anon, authenticated, service_role;
revoke all on function private.lock_current_legal_ocr_runtime_gate_id()
  from public, anon, authenticated, service_role;
revoke all on function private.consume_legal_ocr_oidc_request(text, jsonb, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.prevent_legal_ocr_evidence_truncate()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_ocr_job()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_source_artifact_ocr_transition()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_ocr_storage_object()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_ocr_storage_bucket()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_ocr_storage_truncate()
  from public, anon, authenticated, service_role;
revoke all on function private.enqueue_legal_ocr_job()
  from public, anon, authenticated, service_role;
revoke all on function private.cancel_legal_ocr_job_for_change_set()
  from public, anon, authenticated, service_role;

commit;
