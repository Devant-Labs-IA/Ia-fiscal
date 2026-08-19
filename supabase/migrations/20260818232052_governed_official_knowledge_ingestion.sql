-- Segundo Cerebro Fiscal: governed ingestion of official municipal sources.
-- Automated collection may detect and stage changes, but it can never approve
-- or publish legal content. Human legal review at AAL2 remains mandatory.

begin;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'legal-source-artifacts',
  'legal-source-artifacts',
  false,
  262144000,
  array[
    'application/pdf',
    'text/html',
    'text/plain',
    'application/rtf',
    'text/rtf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/octet-stream'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table private.legal_source_endpoints (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_id uuid not null,
  endpoint_kind text not null
    check (endpoint_kind in (
      'document_page',
      'document_file',
      'catalog',
      'official_journal',
      'operational_guidance'
    )),
  trust_tier text not null
    check (trust_tier in (
      'primary_publication',
      'official_consolidation',
      'official_operational'
    )),
  content_mode text not null default 'catalog_only'
    check (content_mode in ('catalog_only', 'legal_body')),
  citable_body boolean not null default false,
  url text not null
    check (url ~ '^https://[^[:space:]]+$'),
  allowed_hosts text[] not null
    check (cardinality(allowed_hosts) between 1 and 10),
  expected_content_types text[] not null
    check (cardinality(expected_content_types) between 1 and 20),
  parser_hint text not null
    check (parser_hint ~ '^[a-z0-9][a-z0-9_-]{1,79}$'),
  poll_interval interval not null default interval '1 day'
    check (poll_interval between interval '5 minutes' and interval '30 days'),
  priority smallint not null default 100
    check (priority between 1 and 1000),
  status text not null default 'active'
    check (status in ('active', 'paused', 'retired')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_source_endpoints_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id) on delete cascade,
  constraint legal_source_endpoints_municipality_id_id_uq
    unique (municipality_id, id),
  constraint legal_source_endpoints_source_url_uq
    unique (municipality_id, source_id, url),
  constraint legal_source_endpoints_citable_mode_ck check (
    (content_mode = 'legal_body' and citable_body)
    or (content_mode = 'catalog_only' and not citable_body)
  )
);

comment on table private.legal_source_endpoints is
  'Worker-only allowlist of official HTTPS endpoints. It is not exposed through the Data API.';

create index legal_source_endpoints_due_idx
  on private.legal_source_endpoints (status, priority, municipality_id, source_id)
  where status = 'active';
create unique index legal_source_endpoints_one_active_source_uq
  on private.legal_source_endpoints (municipality_id, source_id)
  where status = 'active';

create table private.legal_source_fetch_runs (
  id uuid primary key default gen_random_uuid(),
  run_sequence bigint generated always as identity,
  municipality_id uuid not null,
  source_id uuid not null,
  endpoint_id uuid not null,
  correlation_id uuid not null unique,
  trigger_kind text not null default 'scheduled'
    check (trigger_kind in ('scheduled', 'manual', 'backfill')),
  status text not null
    check (status in (
      'completed_unchanged',
      'completed_changed',
      'failed',
      'blocked'
    )),
  requested_url text not null,
  final_url text,
  http_status integer check (http_status is null or http_status between 100 and 599),
  response_etag text,
  response_last_modified text,
  observed_content_sha256 text
    check (observed_content_sha256 is null or observed_content_sha256 ~ '^[a-f0-9]{64}$'),
  safe_error_code text
    check (safe_error_code is null or safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'),
  safe_error_detail text
    check (safe_error_detail is null or char_length(safe_error_detail) <= 1000),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  observed_at timestamptz not null,
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint legal_source_fetch_runs_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id) on delete cascade,
  constraint legal_source_fetch_runs_endpoint_fk
    foreign key (municipality_id, endpoint_id)
    references private.legal_source_endpoints(municipality_id, id),
  constraint legal_source_fetch_runs_success_ck check (
    (status in ('completed_unchanged', 'completed_changed')
      and http_status between 200 and 299
      and observed_content_sha256 is not null
      and safe_error_code is null
      and safe_error_detail is null)
    or
    (status in ('failed', 'blocked')
      and safe_error_code is not null
      and observed_content_sha256 is null)
  ),
  constraint legal_source_fetch_runs_municipality_id_id_uq
    unique (municipality_id, id),
  constraint legal_source_fetch_runs_sequence_uq
    unique (run_sequence)
);

create index legal_source_fetch_runs_source_latest_idx
  on private.legal_source_fetch_runs (
    municipality_id,
    source_id,
    endpoint_id,
    observed_at desc,
    run_sequence desc
  );
create index legal_source_fetch_runs_failure_idx
  on private.legal_source_fetch_runs (
    municipality_id,
    status,
    observed_at desc
  ) where status in ('failed', 'blocked');

create unique index legal_source_versions_one_published_source_uq
  on public.legal_source_versions (municipality_id, source_id)
  where status = 'published';

create unique index knowledge_articles_one_published_intent_uq
  on public.knowledge_articles (municipality_id, intent_key)
  where status = 'published' and not is_test;

create table private.legal_source_artifacts (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_id uuid not null,
  endpoint_id uuid not null,
  fetch_run_id uuid not null,
  storage_bucket text not null check (storage_bucket = 'legal-source-artifacts'),
  storage_path text not null
    check (storage_path !~ '(^|/)\.\.(/|$)' and storage_path !~ '^/'),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  byte_size bigint not null check (byte_size between 1 and 262144000),
  mime_type text not null,
  extracted_text_sha256 text
    check (extracted_text_sha256 is null or extracted_text_sha256 ~ '^[a-f0-9]{64}$'),
  extraction_status text not null
    check (extraction_status in ('completed', 'requires_extraction', 'failed')),
  response_etag text,
  response_last_modified text,
  observed_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  constraint legal_source_artifacts_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id) on delete cascade,
  constraint legal_source_artifacts_endpoint_fk
    foreign key (municipality_id, endpoint_id)
    references private.legal_source_endpoints(municipality_id, id),
  constraint legal_source_artifacts_fetch_run_fk
    foreign key (municipality_id, fetch_run_id)
    references private.legal_source_fetch_runs(municipality_id, id),
  constraint legal_source_artifacts_municipality_id_id_uq
    unique (municipality_id, id),
  constraint legal_source_artifacts_source_hash_uq
    unique (municipality_id, source_id, content_sha256),
  constraint legal_source_artifacts_storage_uq
    unique (storage_bucket, storage_path),
  constraint legal_source_artifacts_extraction_ck check (
    (extraction_status = 'completed' and extracted_text_sha256 is not null)
    or (extraction_status <> 'completed' and extracted_text_sha256 is null)
  )
);

create index legal_source_artifacts_source_latest_idx
  on private.legal_source_artifacts (
    municipality_id,
    source_id,
    observed_at desc,
    id desc
  );

create table private.legal_source_artifact_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  artifact_id uuid not null,
  source_version_id uuid not null,
  created_at timestamptz not null default now(),
  constraint legal_source_artifact_versions_artifact_fk
    foreign key (municipality_id, artifact_id)
    references private.legal_source_artifacts(municipality_id, id),
  constraint legal_source_artifact_versions_version_fk
    foreign key (municipality_id, source_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint legal_source_artifact_versions_artifact_uq
    unique (municipality_id, artifact_id)
);

create table private.legal_source_change_sets (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_id uuid not null,
  from_artifact_id uuid,
  to_artifact_id uuid,
  candidate_version_id uuid,
  change_type text not null
    check (change_type in (
      'initial_document',
      'content_changed',
      'legacy_import'
    )),
  status text not null default 'detected'
    check (status in (
      'detected',
      'changes_requested',
      'accepted',
      'rejected',
      'superseded'
    )),
  from_sha256 text
    check (from_sha256 is null or from_sha256 ~ '^[a-f0-9]{64}$'),
  to_sha256 text not null check (to_sha256 ~ '^[a-f0-9]{64}$'),
  diff_sha256 text not null check (diff_sha256 ~ '^[a-f0-9]{64}$'),
  diff_summary text not null check (char_length(trim(diff_summary)) between 1 and 2000),
  detected_at timestamptz not null default now(),
  reviewer_membership_id uuid,
  reviewed_at timestamptz,
  review_notes text check (review_notes is null or char_length(review_notes) <= 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_source_change_sets_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id) on delete cascade,
  constraint legal_source_change_sets_from_artifact_fk
    foreign key (municipality_id, from_artifact_id)
    references private.legal_source_artifacts(municipality_id, id),
  constraint legal_source_change_sets_to_artifact_fk
    foreign key (municipality_id, to_artifact_id)
    references private.legal_source_artifacts(municipality_id, id),
  constraint legal_source_change_sets_version_fk
    foreign key (municipality_id, candidate_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint legal_source_change_sets_reviewer_fk
    foreign key (municipality_id, reviewer_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint legal_source_change_sets_artifact_uq
    unique (municipality_id, to_artifact_id),
  constraint legal_source_change_sets_version_uq
    unique (municipality_id, candidate_version_id),
  constraint legal_source_change_sets_municipality_id_id_uq
    unique (municipality_id, id),
  constraint legal_source_change_sets_review_ck check (
    (status in ('detected', 'changes_requested')
      and (status <> 'detected' or reviewer_membership_id is null))
    or
    (status in ('accepted', 'rejected')
      and reviewer_membership_id is not null
      and reviewed_at is not null)
    or
    (status = 'superseded' and reviewed_at is not null)
  ),
  constraint legal_source_change_sets_artifact_or_legacy_ck check (
    (change_type = 'legacy_import' and to_artifact_id is null and candidate_version_id is not null)
    or
    (change_type <> 'legacy_import' and to_artifact_id is not null)
  )
);

create index legal_source_change_sets_review_queue_idx
  on private.legal_source_change_sets (
    municipality_id,
    status,
    detected_at,
    id
  ) where status in ('detected', 'changes_requested');

create table private.legal_source_change_items (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  change_set_id uuid not null,
  ordinal integer not null check (ordinal > 0),
  item_kind text not null
    check (item_kind in ('document_hash', 'section', 'metadata')),
  item_path text not null check (char_length(trim(item_path)) between 1 and 500),
  before_sha256 text
    check (before_sha256 is null or before_sha256 ~ '^[a-f0-9]{64}$'),
  after_sha256 text
    check (after_sha256 is null or after_sha256 ~ '^[a-f0-9]{64}$'),
  before_excerpt text check (before_excerpt is null or char_length(before_excerpt) <= 2000),
  after_excerpt text check (after_excerpt is null or char_length(after_excerpt) <= 2000),
  summary text not null check (char_length(trim(summary)) between 1 and 2000),
  created_at timestamptz not null default now(),
  constraint legal_source_change_items_set_fk
    foreign key (municipality_id, change_set_id)
    references private.legal_source_change_sets(municipality_id, id) on delete cascade,
  constraint legal_source_change_items_ordinal_uq
    unique (municipality_id, change_set_id, ordinal)
);

create table private.legal_source_version_reviews (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  change_set_id uuid not null,
  source_version_id uuid not null,
  reviewer_membership_id uuid not null,
  decision text not null
    check (decision in ('approved', 'rejected', 'changes_requested')),
  reviewed_content_sha256 text not null
    check (reviewed_content_sha256 ~ '^[a-f0-9]{64}$'),
  reviewed_valid_from date,
  reviewed_valid_until date,
  reviewed_publication_date date,
  notes text check (notes is null or char_length(notes) <= 4000),
  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint legal_source_version_reviews_set_fk
    foreign key (municipality_id, change_set_id)
    references private.legal_source_change_sets(municipality_id, id),
  constraint legal_source_version_reviews_version_fk
    foreign key (municipality_id, source_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint legal_source_version_reviews_membership_fk
    foreign key (municipality_id, reviewer_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint legal_source_version_reviews_municipality_id_id_uq
    unique (municipality_id, id),
  constraint legal_source_version_reviews_validity_ck
    check (
      reviewed_valid_until is null
      or reviewed_valid_from is null
      or reviewed_valid_until >= reviewed_valid_from
    )
);

create index legal_source_version_reviews_version_idx
  on private.legal_source_version_reviews (
    municipality_id,
    source_version_id,
    reviewed_at desc,
    id desc
  );

alter table private.legal_source_endpoints enable row level security;
alter table private.legal_source_fetch_runs enable row level security;
alter table private.legal_source_artifacts enable row level security;
alter table private.legal_source_artifact_versions enable row level security;
alter table private.legal_source_change_sets enable row level security;
alter table private.legal_source_change_items enable row level security;
alter table private.legal_source_version_reviews enable row level security;

revoke all on private.legal_source_endpoints from public, anon, authenticated, service_role;
revoke all on private.legal_source_fetch_runs from public, anon, authenticated, service_role;
revoke all on private.legal_source_artifacts from public, anon, authenticated, service_role;
revoke all on private.legal_source_artifact_versions from public, anon, authenticated, service_role;
revoke all on private.legal_source_change_sets from public, anon, authenticated, service_role;
revoke all on private.legal_source_change_items from public, anon, authenticated, service_role;
revoke all on private.legal_source_version_reviews from public, anon, authenticated, service_role;

create trigger legal_source_endpoints_set_updated_at
  before update on private.legal_source_endpoints
  for each row execute function private.set_updated_at();
create trigger legal_source_change_sets_set_updated_at
  before update on private.legal_source_change_sets
  for each row execute function private.set_updated_at();

create trigger legal_source_fetch_runs_append_only
  before update or delete on private.legal_source_fetch_runs
  for each row execute function private.prevent_any_mutation();
create trigger legal_source_artifacts_append_only
  before update or delete on private.legal_source_artifacts
  for each row execute function private.prevent_any_mutation();
create trigger legal_source_artifact_versions_append_only
  before update or delete on private.legal_source_artifact_versions
  for each row execute function private.prevent_any_mutation();
create trigger legal_source_change_items_append_only
  before update or delete on private.legal_source_change_items
  for each row execute function private.prevent_any_mutation();
create trigger legal_source_version_reviews_append_only
  before update or delete on private.legal_source_version_reviews
  for each row execute function private.prevent_any_mutation();

create or replace function private.guard_legal_source_endpoint()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'legal source endpoints cannot be deleted';
  end if;
  if old.id is distinct from new.id
     or old.municipality_id is distinct from new.municipality_id
     or old.source_id is distinct from new.source_id
     or old.url is distinct from new.url
     or old.trust_tier is distinct from new.trust_tier then
    raise exception 'legal source endpoint identity is immutable';
  end if;
  return new;
end;
$$;

create trigger legal_source_endpoints_guard
  before update or delete on private.legal_source_endpoints
  for each row execute function private.guard_legal_source_endpoint();

create or replace function private.guard_legal_source_change_set()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'legal source change sets cannot be deleted';
  end if;
  if (to_jsonb(old)
        - 'status'
        - 'reviewer_membership_id'
        - 'reviewed_at'
        - 'review_notes'
        - 'updated_at')
     is distinct from
     (to_jsonb(new)
        - 'status'
        - 'reviewer_membership_id'
        - 'reviewed_at'
        - 'review_notes'
        - 'updated_at') then
    raise exception 'detected legal change evidence is immutable';
  end if;
  return new;
end;
$$;

create trigger legal_source_change_sets_guard
  before update or delete on private.legal_source_change_sets
  for each row execute function private.guard_legal_source_change_set();

create or replace function private.guard_reviewed_legal_source_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and old.status in ('approved', 'published', 'retired', 'revoked')
     and (
       old.valid_from is distinct from new.valid_from
       or old.valid_until is distinct from new.valid_until
       or old.publication_date is distinct from new.publication_date
     ) then
    raise exception 'reviewed legal source validity is immutable; stage a new version';
  end if;

  if new.status in ('approved', 'published')
     and (
       tg_op = 'INSERT'
       or old.status is distinct from new.status
       or old.content_sha256 is distinct from new.content_sha256
       or old.valid_from is distinct from new.valid_from
       or old.valid_until is distinct from new.valid_until
       or old.publication_date is distinct from new.publication_date
     ) then
    if auth.uid() is null or not private.is_aal2() then
      raise exception using
        errcode = '42501',
        message = 'aal2 authenticated legal review is required';
    end if;
    if not private.has_municipality_role(
      new.municipality_id,
      array['legal_reviewer']::text[]
    ) then
      raise exception using
        errcode = '42501',
        message = 'legal reviewer role required';
    end if;
    if not exists (
      select 1
      from private.legal_source_version_reviews review
      where review.municipality_id = new.municipality_id
        and review.source_version_id = new.id
        and review.decision = 'approved'
        and review.reviewed_content_sha256 = new.content_sha256
        and review.reviewed_valid_from is not distinct from new.valid_from
        and review.reviewed_valid_until is not distinct from new.valid_until
        and review.reviewed_publication_date is not distinct from new.publication_date
    ) then
      raise exception 'approved legal review snapshot is required';
    end if;
    if new.status = 'published'
       and (tg_op = 'INSERT' or old.status <> 'approved') then
      raise exception 'legal source version must be approved before publication';
    end if;
  end if;
  return new;
end;
$$;

create trigger legal_source_versions_review_guard
  before insert or update on public.legal_source_versions
  for each row execute function private.guard_reviewed_legal_source_version();

create or replace function private.guard_legal_source_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'governed legal sources cannot be deleted';
  end if;
  if old.id is distinct from new.id
     or old.municipality_id is distinct from new.municipality_id
     or old.source_type is distinct from new.source_type
     or old.jurisdiction is distinct from new.jurisdiction
     or old.issuing_authority is distinct from new.issuing_authority
     or old.title is distinct from new.title
     or old.official_identifier is distinct from new.official_identifier
     or old.official_url is distinct from new.official_url
     or old.tax_scope is distinct from new.tax_scope
     or old.divergence_scope is distinct from new.divergence_scope then
    raise exception 'governed legal source identity is immutable';
  end if;
  return new;
end;
$$;

create trigger legal_sources_identity_guard
  before update or delete on public.legal_sources
  for each row execute function private.guard_legal_source_identity();

create or replace function private.guard_legal_source_version_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'governed legal source versions cannot be deleted';
  end if;
  if encode(extensions.digest(new.content_text, 'sha256'), 'hex')
       is distinct from new.content_sha256 then
    raise exception 'legal source version content hash mismatch';
  end if;
  if tg_op = 'UPDATE' and (
    old.id is distinct from new.id
    or old.municipality_id is distinct from new.municipality_id
    or old.source_id is distinct from new.source_id
    or old.version is distinct from new.version
    or old.content_text is distinct from new.content_text
    or old.content_sha256 is distinct from new.content_sha256
    or old.supersedes_version_id is distinct from new.supersedes_version_id
  ) then
    raise exception 'governed legal source version evidence is immutable';
  end if;
  return new;
end;
$$;

alter table public.legal_source_versions
  drop constraint if exists legal_source_versions_content_digest_ck;
alter table public.legal_source_versions
  add constraint legal_source_versions_content_digest_ck
  check (
    encode(extensions.digest(content_text, 'sha256'), 'hex') = content_sha256
  ) not valid;

create trigger legal_source_versions_integrity_guard
  before insert or update or delete on public.legal_source_versions
  for each row execute function private.guard_legal_source_version_integrity();

create or replace function private.guard_legal_section_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'governed legal sections cannot be deleted';
  end if;
  if encode(extensions.digest(new.content_text, 'sha256'), 'hex')
       is distinct from new.content_sha256 then
    raise exception 'legal section content hash mismatch';
  end if;
  if tg_op = 'UPDATE' then
    raise exception 'governed legal sections are immutable';
  end if;
  return new;
end;
$$;

alter table public.legal_sections
  drop constraint if exists legal_sections_content_digest_ck;
alter table public.legal_sections
  add constraint legal_sections_content_digest_ck
  check (
    encode(extensions.digest(content_text, 'sha256'), 'hex') = content_sha256
  ) not valid;

create trigger legal_sections_integrity_guard
  before insert or update or delete on public.legal_sections
  for each row execute function private.guard_legal_section_integrity();

create or replace function private.guard_legal_chunk_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'governed legal chunks cannot be deleted';
  end if;
  if encode(extensions.digest(new.content_text, 'sha256'), 'hex')
       is distinct from new.content_sha256 then
    raise exception 'legal chunk content hash mismatch';
  end if;
  if tg_op = 'UPDATE' then
    raise exception 'governed legal chunks are immutable';
  end if;
  return new;
end;
$$;

alter table private.legal_chunks
  drop constraint if exists legal_chunks_content_digest_ck;
alter table private.legal_chunks
  add constraint legal_chunks_content_digest_ck
  check (
    encode(extensions.digest(content_text, 'sha256'), 'hex') = content_sha256
  ) not valid;

create trigger legal_chunks_integrity_guard
  before insert or update or delete on private.legal_chunks
  for each row execute function private.guard_legal_chunk_integrity();

create or replace function private.guard_legal_source_storage_object()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.bucket_id = 'legal-source-artifacts'
     or (tg_op = 'UPDATE' and new.bucket_id = 'legal-source-artifacts') then
    raise exception 'legal source storage objects are write-once';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger legal_source_storage_objects_worm
  before update or delete on storage.objects
  for each row execute function private.guard_legal_source_storage_object();

create or replace function private.guard_legal_source_storage_bucket()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.id = 'legal-source-artifacts'
     or (tg_op = 'UPDATE' and new.id = 'legal-source-artifacts') then
    raise exception 'legal source artifact bucket is immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger legal_source_storage_bucket_guard
  before update or delete on storage.buckets
  for each row execute function private.guard_legal_source_storage_bucket();

create or replace function private.guard_legal_source_storage_truncate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'governed legal source storage cannot be truncated';
end;
$$;

create trigger legal_source_storage_objects_truncate_guard
  before truncate on storage.objects
  for each statement execute function private.guard_legal_source_storage_truncate();

create trigger legal_source_storage_buckets_truncate_guard
  before truncate on storage.buckets
  for each statement execute function private.guard_legal_source_storage_truncate();

create or replace function private.municipality_current_date(
  p_municipality_id uuid
)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_timezone text;
begin
  select municipality.timezone into strict v_timezone
  from public.municipalities municipality
  where municipality.id = p_municipality_id;

  if not exists (
    select 1
    from pg_catalog.pg_timezone_names timezone_name
    where timezone_name.name = v_timezone
  ) then
    raise exception 'invalid municipality timezone';
  end if;

  return (pg_catalog.now() at time zone v_timezone)::date;
end;
$$;

create or replace function public.ia_fiscal_get_knowledge_source_endpoints()
returns table (
  endpoint_id uuid,
  municipality_id uuid,
  municipality_slug text,
  source_id uuid,
  source_title text,
  requested_url text,
  trust_tier text,
  endpoint_kind text,
  endpoint_status text,
  content_mode text,
  citable_body boolean,
  activation_blocker text,
  parser_hint text,
  expected_content_types text[],
  allowed_hosts text[]
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_service_role() then
    raise exception using
      errcode = '42501',
      message = 'service role required';
  end if;

  return query
  select
    endpoint.id,
    endpoint.municipality_id,
    municipality.slug,
    endpoint.source_id,
    source.title,
    endpoint.url,
    endpoint.trust_tier,
    endpoint.endpoint_kind,
    endpoint.status,
    endpoint.content_mode,
    endpoint.citable_body,
    endpoint.metadata ->> 'activation_blocker',
    endpoint.parser_hint,
    endpoint.expected_content_types,
    endpoint.allowed_hosts
  from private.legal_source_endpoints endpoint
  join public.legal_sources source
    on source.municipality_id = endpoint.municipality_id
   and source.id = endpoint.source_id
  join public.municipalities municipality
    on municipality.id = endpoint.municipality_id
  where endpoint.status = 'active'
    and source.status <> 'retired'
  order by endpoint.priority, municipality.slug, source.title, endpoint.url;
end;
$$;

create or replace function public.ia_fiscal_capture_knowledge_source(
  p_source_id uuid,
  p_requested_url text,
  p_final_url text,
  p_content_sha256 text,
  p_mime_type text,
  p_byte_size bigint,
  p_storage_bucket text,
  p_storage_path text,
  p_extracted_text text,
  p_etag text,
  p_last_modified text,
  p_http_status integer,
  p_observed_at timestamptz,
  p_correlation_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_endpoint private.legal_source_endpoints%rowtype;
  v_municipality_slug text;
  v_final_host text;
  v_normalized_mime text;
  v_expected_prefix text;
  v_existing_run private.legal_source_fetch_runs%rowtype;
  v_existing_artifact private.legal_source_artifacts%rowtype;
  v_previous_artifact private.legal_source_artifacts%rowtype;
  v_fetch_run_id uuid;
  v_artifact_id uuid;
  v_change_set_id uuid;
  v_candidate_version_id uuid;
  v_candidate_version_number integer;
  v_previous_version_id uuid;
  v_previous_version_sha256 text;
  v_previous_version_artifact_backed boolean := false;
  v_same_canonical_text boolean := false;
  v_extracted_sha256 text;
  v_diff_sha256 text;
  v_processing_status text;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;
  v_extracted_sha256 := case
    when nullif(trim(coalesce(p_extracted_text, '')), '') is null then null
    else encode(extensions.digest(p_extracted_text, 'sha256'), 'hex')
  end;
  if v_extracted_sha256 is not null and (
    coalesce(p_metadata ->> 'extraction_complete', '') <> 'true'
    or coalesce(p_metadata ->> 'content_truncated', '') <> 'false'
    or case
      when coalesce(p_metadata ->> 'extracted_char_count', '') ~ '^[0-9]+$'
        then (p_metadata ->> 'extracted_char_count')::numeric
               <> char_length(p_extracted_text)::numeric
      else true
    end
  ) then
    raise exception 'complete non-truncated extraction evidence is required';
  end if;
  if v_extracted_sha256 is null and (
    coalesce(p_metadata ->> 'extraction_complete', '') <> 'false'
    or coalesce(p_metadata ->> 'content_truncated', '') <> 'false'
    or coalesce(p_metadata ->> 'extracted_char_count', '') <> '0'
  ) then
    raise exception 'pending extraction metadata must be explicit';
  end if;
  if p_observed_at is null or p_observed_at > now() + interval '5 minutes' then
    raise exception 'invalid observation timestamp';
  end if;

  select endpoint.* into strict v_endpoint
  from private.legal_source_endpoints endpoint
  where endpoint.source_id = p_source_id
    and endpoint.url = p_requested_url
    and endpoint.status = 'active';

  select municipality.slug into strict v_municipality_slug
  from public.municipalities municipality
  where municipality.id = v_endpoint.municipality_id;

  if not v_endpoint.citable_body and v_extracted_sha256 is not null then
    raise exception 'catalog-only endpoint cannot submit citable legal text';
  end if;

  if p_final_url is null or p_final_url !~ '^https://[^[:space:]]+$' then
    raise exception 'final URL must use HTTPS';
  end if;
  v_final_host := substring(lower(p_final_url) from '^https://([^/:?#]+)');
  if v_final_host is null or not (v_final_host = any(v_endpoint.allowed_hosts)) then
    raise exception using
      errcode = '42501',
      message = 'redirected host is outside the official endpoint allowlist';
  end if;
  if p_content_sha256 is null or p_content_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'invalid artifact SHA-256';
  end if;
  if p_byte_size is null or p_byte_size not between 1 and 262144000 then
    raise exception 'artifact size is outside the allowed range';
  end if;
  if p_http_status not between 200 and 299 then
    raise exception 'successful capture requires a 2xx HTTP status';
  end if;

  v_normalized_mime := lower(split_part(coalesce(p_mime_type, ''), ';', 1));
  if v_normalized_mime = ''
     or not (v_normalized_mime = any(v_endpoint.expected_content_types)) then
    raise exception 'unexpected content type for official endpoint';
  end if;
  if p_storage_bucket <> 'legal-source-artifacts' then
    raise exception 'unexpected artifact storage bucket';
  end if;
  v_expected_prefix :=
    v_municipality_slug || '/' || p_source_id::text || '/' || p_content_sha256 || '/';
  if p_storage_path is null
     or p_storage_path not like v_expected_prefix || '%'
     or p_storage_path ~ '(^|/)\.\.(/|$)'
     or p_storage_path ~ '^/' then
    raise exception 'artifact storage path is outside the governed prefix';
  end if;
  if not exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'legal-source-artifacts'
      and object.name = p_storage_path
      and case
        when object.metadata ->> 'size' is null then true
        when object.metadata ->> 'size' ~ '^[0-9]+$'
          then (object.metadata ->> 'size')::numeric = p_byte_size::numeric
        else false
      end
      and (
        object.metadata ->> 'mimetype' is null
        or lower(split_part(object.metadata ->> 'mimetype', ';', 1)) = v_normalized_mime
      )
  ) then
    raise exception 'uploaded storage object evidence is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_correlation_id::text,
    0
  ));

  -- Serialize before the idempotency lookup so concurrent retries observe the
  -- run committed by the first caller instead of racing on correlation_id.
  perform 1
  from public.legal_sources source
  where source.id = p_source_id
    and source.municipality_id = v_endpoint.municipality_id
  for update;

  select run.* into v_existing_run
  from private.legal_source_fetch_runs run
  where run.correlation_id = p_correlation_id;

  if found then
    if v_existing_run.source_id <> p_source_id
       or v_existing_run.requested_url <> p_requested_url
       or v_existing_run.observed_content_sha256 is distinct from p_content_sha256 then
      raise exception 'correlation id was already used with different capture evidence';
    end if;

    select artifact.* into v_existing_artifact
    from private.legal_source_artifacts artifact
    where artifact.municipality_id = v_existing_run.municipality_id
      and artifact.source_id = v_existing_run.source_id
      and artifact.content_sha256 = v_existing_run.observed_content_sha256;

    select change_set.id, change_set.candidate_version_id
      into v_change_set_id, v_candidate_version_id
    from private.legal_source_change_sets change_set
    left join public.legal_source_versions version
      on version.municipality_id = change_set.municipality_id
     and version.id = change_set.candidate_version_id
    where change_set.municipality_id = v_existing_run.municipality_id
      and change_set.to_artifact_id = v_existing_artifact.id
      and change_set.status in ('detected', 'changes_requested')
      and (
        (not v_endpoint.citable_body and change_set.candidate_version_id is null)
        or (v_endpoint.citable_body and version.status = 'under_review')
      );

    return jsonb_build_object(
      'fetch_run_id', v_existing_run.id,
      'artifact_id', v_existing_artifact.id,
      'status', case
        when v_existing_run.status = 'completed_unchanged' then 'already_exists'
        else 'captured'
      end,
      'processing_status', case
        when not v_endpoint.citable_body
             or v_existing_artifact.extraction_status = 'requires_extraction'
          then 'requires_extraction'
        else 'under_review'
      end,
      'change_set_id', v_change_set_id,
      'candidate_version_id', v_candidate_version_id
    );
  end if;

  select artifact.* into v_existing_artifact
  from private.legal_source_artifacts artifact
  where artifact.municipality_id = v_endpoint.municipality_id
    and artifact.source_id = p_source_id
    and artifact.content_sha256 = p_content_sha256;

  if found then
    select change_set.id, change_set.candidate_version_id
      into v_change_set_id, v_candidate_version_id
    from private.legal_source_change_sets change_set
    left join public.legal_source_versions version
      on version.municipality_id = change_set.municipality_id
     and version.id = change_set.candidate_version_id
    where change_set.municipality_id = v_existing_artifact.municipality_id
      and change_set.to_artifact_id = v_existing_artifact.id
      and change_set.status in ('detected', 'changes_requested')
      and (
        (not v_endpoint.citable_body and change_set.candidate_version_id is null)
        or (v_endpoint.citable_body and version.status = 'under_review')
      );

    insert into private.legal_source_fetch_runs (
      municipality_id,
      source_id,
      endpoint_id,
      correlation_id,
      status,
      requested_url,
      final_url,
      http_status,
      response_etag,
      response_last_modified,
      observed_content_sha256,
      metadata,
      observed_at
    ) values (
      v_endpoint.municipality_id,
      p_source_id,
      v_endpoint.id,
      p_correlation_id,
      'completed_unchanged',
      p_requested_url,
      p_final_url,
      p_http_status,
      nullif(left(coalesce(p_etag, ''), 1000), ''),
      nullif(left(coalesce(p_last_modified, ''), 1000), ''),
      p_content_sha256,
      p_metadata,
      p_observed_at
    ) returning id into v_fetch_run_id;

    return jsonb_build_object(
      'fetch_run_id', v_fetch_run_id,
      'artifact_id', v_existing_artifact.id,
      'status', 'already_exists',
      'processing_status', case
        when not v_endpoint.citable_body
             or v_existing_artifact.extraction_status = 'requires_extraction'
          then 'requires_extraction'
        else 'under_review'
      end,
      'change_set_id', v_change_set_id,
      'candidate_version_id', v_candidate_version_id
    );
  end if;

  select artifact.* into v_previous_artifact
  from private.legal_source_artifacts artifact
  where artifact.municipality_id = v_endpoint.municipality_id
    and artifact.source_id = p_source_id
  order by artifact.observed_at desc, artifact.id desc
  limit 1;

  if v_endpoint.citable_body and v_extracted_sha256 is not null then
    select
      version.id,
      version.content_sha256,
      exists (
        select 1
        from private.legal_source_artifact_versions mapping
        where mapping.municipality_id = version.municipality_id
          and mapping.source_version_id = version.id
      )
    into
      v_previous_version_id,
      v_previous_version_sha256,
      v_previous_version_artifact_backed
    from public.legal_source_versions version
    where version.municipality_id = v_endpoint.municipality_id
      and version.source_id = p_source_id
    order by version.version desc, version.id desc
    limit 1;
    v_same_canonical_text := coalesce(
      v_previous_version_artifact_backed
      and v_previous_version_sha256 = v_extracted_sha256,
      false
    );
  end if;

  v_processing_status := case
    when v_extracted_sha256 is null then 'requires_extraction'
    else 'completed'
  end;

  insert into private.legal_source_fetch_runs (
    municipality_id,
    source_id,
    endpoint_id,
    correlation_id,
    status,
    requested_url,
    final_url,
    http_status,
    response_etag,
    response_last_modified,
    observed_content_sha256,
    metadata,
    observed_at
  ) values (
    v_endpoint.municipality_id,
    p_source_id,
    v_endpoint.id,
    p_correlation_id,
    case when v_same_canonical_text
      then 'completed_unchanged'
      else 'completed_changed'
    end,
    p_requested_url,
    p_final_url,
    p_http_status,
    nullif(left(coalesce(p_etag, ''), 1000), ''),
    nullif(left(coalesce(p_last_modified, ''), 1000), ''),
    p_content_sha256,
    p_metadata,
    p_observed_at
  ) returning id into v_fetch_run_id;

  insert into private.legal_source_artifacts (
    municipality_id,
    source_id,
    endpoint_id,
    fetch_run_id,
    storage_bucket,
    storage_path,
    content_sha256,
    byte_size,
    mime_type,
    extracted_text_sha256,
    extraction_status,
    response_etag,
    response_last_modified,
    observed_at,
    metadata
  ) values (
    v_endpoint.municipality_id,
    p_source_id,
    v_endpoint.id,
    v_fetch_run_id,
    p_storage_bucket,
    p_storage_path,
    p_content_sha256,
    p_byte_size,
    v_normalized_mime,
    v_extracted_sha256,
    v_processing_status,
    nullif(left(coalesce(p_etag, ''), 1000), ''),
    nullif(left(coalesce(p_last_modified, ''), 1000), ''),
    p_observed_at,
    p_metadata
  ) returning id into v_artifact_id;

  if v_same_canonical_text then
    insert into private.legal_source_artifact_versions (
      municipality_id,
      artifact_id,
      source_version_id
    ) values (
      v_endpoint.municipality_id,
      v_artifact_id,
      v_previous_version_id
    );
    return jsonb_build_object(
      'fetch_run_id', v_fetch_run_id,
      'artifact_id', v_artifact_id,
      'status', 'already_exists',
      'processing_status', 'under_review',
      'change_set_id', null,
      'candidate_version_id', null
    );
  end if;

  if v_extracted_sha256 is not null then
    select coalesce(max(version.version), 0) + 1
      into v_candidate_version_number
    from public.legal_source_versions version
    where version.municipality_id = v_endpoint.municipality_id
      and version.source_id = p_source_id;

    insert into public.legal_source_versions (
      municipality_id,
      source_id,
      version,
      status,
      content_text,
      content_sha256,
      supersedes_version_id
    ) values (
      v_endpoint.municipality_id,
      p_source_id,
      v_candidate_version_number,
      'under_review',
      p_extracted_text,
      v_extracted_sha256,
      v_previous_version_id
    ) returning id into v_candidate_version_id;

    insert into private.legal_source_artifact_versions (
      municipality_id,
      artifact_id,
      source_version_id
    ) values (
      v_endpoint.municipality_id,
      v_artifact_id,
      v_candidate_version_id
    );
  end if;

  update private.legal_source_change_sets
  set status = 'superseded',
      reviewed_at = now(),
      review_notes = 'Substituído automaticamente por uma captura oficial mais recente.'
  where municipality_id = v_endpoint.municipality_id
    and source_id = p_source_id
    and status in ('detected', 'changes_requested');

  v_diff_sha256 := encode(
    extensions.digest(
      coalesce(v_previous_artifact.content_sha256, '') || ':' || p_content_sha256,
      'sha256'
    ),
    'hex'
  );

  insert into private.legal_source_change_sets (
    municipality_id,
    source_id,
    from_artifact_id,
    to_artifact_id,
    candidate_version_id,
    change_type,
    status,
    from_sha256,
    to_sha256,
    diff_sha256,
    diff_summary,
    detected_at
  ) values (
    v_endpoint.municipality_id,
    p_source_id,
    v_previous_artifact.id,
    v_artifact_id,
    v_candidate_version_id,
    case when v_previous_artifact.id is null
      then 'initial_document'
      else 'content_changed'
    end,
    'detected',
    v_previous_artifact.content_sha256,
    p_content_sha256,
    v_diff_sha256,
    case
      when v_previous_artifact.id is null
        then 'Primeira captura oficial registrada; exige conferência humana.'
      when v_candidate_version_id is null
        then 'Mudança de conteúdo detectada; a extração precisa ser concluída antes da revisão.'
      else 'Mudança de conteúdo detectada; a versão extraída aguarda revisão humana.'
    end,
    p_observed_at
  ) returning id into v_change_set_id;

  insert into private.legal_source_change_items (
    municipality_id,
    change_set_id,
    ordinal,
    item_kind,
    item_path,
    before_sha256,
    after_sha256,
    summary
  ) values (
    v_endpoint.municipality_id,
    v_change_set_id,
    1,
    'document_hash',
    'documento_oficial',
    v_previous_artifact.content_sha256,
    p_content_sha256,
    case when v_previous_artifact.id is null
      then 'Documento oficial capturado pela primeira vez.'
      else 'O hash do documento oficial foi alterado.'
    end
  );

  -- HTML/plain-text captures get a conservative Phase-1
  -- segmentation: one document section and one lexical chunk. PDF captures
  -- remain `requires_extraction` and must be staged by the extractor.
  if v_candidate_version_id is not null then
    perform public.ia_fiscal_stage_knowledge_sections(
      v_change_set_id,
      jsonb_build_array(jsonb_build_object(
        'section_key', 'documento_integral',
        'heading', 'Documento oficial capturado',
        'ordinal', 1,
        'content_text', p_extracted_text
      ))
    );
  end if;

  return jsonb_build_object(
    'fetch_run_id', v_fetch_run_id,
    'artifact_id', v_artifact_id,
    'status', 'captured',
    'processing_status', case
      when v_candidate_version_id is null then 'requires_extraction'
      else 'under_review'
    end,
    'change_set_id', v_change_set_id,
    'candidate_version_id', v_candidate_version_id
  );
end;
$$;

create or replace function public.ia_fiscal_record_knowledge_fetch_failure(
  p_source_id uuid,
  p_requested_url text,
  p_http_status integer,
  p_error_code text,
  p_error_detail text,
  p_observed_at timestamptz,
  p_correlation_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_endpoint private.legal_source_endpoints%rowtype;
  v_existing_run private.legal_source_fetch_runs%rowtype;
  v_fetch_run_id uuid;
  v_error_code text;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;
  if p_observed_at is null or p_observed_at > now() + interval '5 minutes' then
    raise exception 'invalid observation timestamp';
  end if;

  select endpoint.* into strict v_endpoint
  from private.legal_source_endpoints endpoint
  where endpoint.source_id = p_source_id
    and endpoint.url = p_requested_url
    and endpoint.status = 'active';

  v_error_code := lower(trim(coalesce(p_error_code, '')));
  if v_error_code !~ '^[a-z0-9][a-z0-9_.:-]{1,119}$' then
    raise exception 'invalid safe error code';
  end if;
  if p_http_status is not null and p_http_status not between 100 and 599 then
    raise exception 'invalid HTTP status';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_correlation_id::text,
    0
  ));

  select run.* into v_existing_run
  from private.legal_source_fetch_runs run
  where run.correlation_id = p_correlation_id;
  if found then
    if v_existing_run.source_id <> p_source_id
       or v_existing_run.requested_url <> p_requested_url
       or v_existing_run.safe_error_code is distinct from v_error_code then
      raise exception 'correlation id was already used with different failure evidence';
    end if;
    return v_existing_run.id;
  end if;

  insert into private.legal_source_fetch_runs (
    municipality_id,
    source_id,
    endpoint_id,
    correlation_id,
    status,
    requested_url,
    http_status,
    safe_error_code,
    safe_error_detail,
    metadata,
    observed_at
  ) values (
    v_endpoint.municipality_id,
    p_source_id,
    v_endpoint.id,
    p_correlation_id,
    case when v_error_code in (
      'redirect_not_allowed',
      'content_type_not_allowed',
      'artifact_too_large',
      'integrity_check_failed',
      'source_host_not_registered',
      'source_host_not_allowed',
      'source_path_not_allowed',
      'source_url_not_allowed',
      'source_redirect_invalid',
      'source_redirect_limit_reached',
      'unsupported_source_mime',
      'unexpected_source_mime',
      'source_mime_content_mismatch',
      'source_artifact_too_large',
      'source_extracted_text_too_large'
    ) then 'blocked' else 'failed' end,
    p_requested_url,
    p_http_status,
    v_error_code,
    nullif(left(trim(coalesce(p_error_detail, '')), 1000), ''),
    p_metadata,
    p_observed_at
  ) returning id into v_fetch_run_id;

  return v_fetch_run_id;
end;
$$;

create or replace function private.legal_version_has_complete_evidence(
  p_municipality_id uuid,
  p_source_version_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.legal_source_versions version
    where version.municipality_id = p_municipality_id
      and version.id = p_source_version_id
      and exists (
        select 1
        from public.legal_sections integral_section
        where integral_section.municipality_id = version.municipality_id
          and integral_section.source_version_id = version.id
          and integral_section.content_sha256 = version.content_sha256
          and integral_section.content_text = version.content_text
      )
      and not exists (
        select 1
        from public.legal_sections section
        where section.municipality_id = version.municipality_id
          and section.source_version_id = version.id
          and position(section.content_text in version.content_text) = 0
      )
      and not exists (
        select 1
        from public.legal_sections section
        where section.municipality_id = version.municipality_id
          and section.source_version_id = version.id
          and not exists (
            select 1
            from private.legal_chunks chunk
            where chunk.municipality_id = section.municipality_id
              and chunk.legal_section_id = section.id
          )
      )
      and not exists (
        select 1
        from public.legal_sections section
        join private.legal_chunks chunk
          on chunk.municipality_id = section.municipality_id
         and chunk.legal_section_id = section.id
        where section.municipality_id = version.municipality_id
          and section.source_version_id = version.id
          and position(chunk.content_text in section.content_text) = 0
      )
  );
$$;

create or replace function public.ia_fiscal_stage_knowledge_sections(
  p_change_set_id uuid,
  p_sections jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change_set private.legal_source_change_sets%rowtype;
  v_version public.legal_source_versions%rowtype;
  v_section jsonb;
  v_chunk jsonb;
  v_section_id uuid;
  v_section_key text;
  v_heading text;
  v_content_text text;
  v_content_sha256 text;
  v_ordinal integer;
  v_chunk_index integer;
  v_chunk_text text;
  v_chunk_sha256 text;
  v_token_count integer;
  v_existing_count integer;
  v_inserted_sections integer := 0;
  v_inserted_chunks integer := 0;
  v_has_integral_section boolean := false;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_sections is null
     or jsonb_typeof(p_sections) <> 'array'
     or jsonb_array_length(p_sections) not between 1 and 5000 then
    raise exception 'sections must be a JSON array containing 1 to 5000 entries';
  end if;

  select change_set.* into strict v_change_set
  from private.legal_source_change_sets change_set
  where change_set.id = p_change_set_id
  for update;

  if v_change_set.candidate_version_id is null then
    raise exception 'change set has no extracted candidate version';
  end if;
  if v_change_set.status not in ('detected', 'changes_requested') then
    raise exception 'reviewed change set cannot be restaged';
  end if;

  select version.* into strict v_version
  from public.legal_source_versions version
  where version.municipality_id = v_change_set.municipality_id
    and version.id = v_change_set.candidate_version_id
  for update;

  if v_version.status <> 'under_review' then
    raise exception 'candidate version is not open for section staging';
  end if;

  select count(*) into v_existing_count
  from public.legal_sections section
  where section.municipality_id = v_version.municipality_id
    and section.source_version_id = v_version.id;

  if v_existing_count > 0 then
    if v_existing_count <> jsonb_array_length(p_sections)
       or exists (
         select 1
         from jsonb_array_elements(p_sections) input(section)
         left join public.legal_sections existing
           on existing.municipality_id = v_version.municipality_id
          and existing.source_version_id = v_version.id
          and existing.section_key = input.section ->> 'section_key'
          and existing.ordinal = (input.section ->> 'ordinal')::integer
          and existing.content_sha256 = encode(
            extensions.digest(input.section ->> 'content_text', 'sha256'),
            'hex'
          )
         where existing.id is null
       ) then
      raise exception 'sections were already staged with different evidence';
    end if;

    if not private.legal_version_has_complete_evidence(
      v_version.municipality_id,
      v_version.id
    ) then
      raise exception 'staged evidence is not fully derived from the candidate version';
    end if;

    return jsonb_build_object(
      'change_set_id', v_change_set.id,
      'candidate_version_id', v_version.id,
      'status', 'already_staged',
      'section_count', v_existing_count,
      'chunk_count', (
        select count(*)
        from private.legal_chunks chunk
        join public.legal_sections section
          on section.municipality_id = chunk.municipality_id
         and section.id = chunk.legal_section_id
        where section.municipality_id = v_version.municipality_id
          and section.source_version_id = v_version.id
      )
    );
  end if;

  for v_section in
    select value from jsonb_array_elements(p_sections)
  loop
    if jsonb_typeof(v_section) <> 'object' then
      raise exception 'every section must be a JSON object';
    end if;
    v_section_key := trim(coalesce(v_section ->> 'section_key', ''));
    v_heading := nullif(trim(coalesce(v_section ->> 'heading', '')), '');
    v_content_text := coalesce(v_section ->> 'content_text', '');
    begin
      v_ordinal := (v_section ->> 'ordinal')::integer;
    exception when others then
      raise exception 'section ordinal must be an integer';
    end;
    if v_section_key !~ '^[a-z0-9][a-z0-9:_-]{1,199}$'
       or v_ordinal <= 0
       or nullif(trim(v_content_text), '') is null then
      raise exception 'invalid legal section payload';
    end if;
    if position(v_content_text in v_version.content_text) = 0 then
      raise exception 'legal section content must be derived from the candidate version';
    end if;
    v_content_sha256 := encode(extensions.digest(v_content_text, 'sha256'), 'hex');
    v_has_integral_section := v_has_integral_section
      or (
        v_content_sha256 = v_version.content_sha256
        and v_content_text = v_version.content_text
      );

    insert into public.legal_sections (
      municipality_id,
      source_version_id,
      section_key,
      heading,
      ordinal,
      content_text,
      content_sha256
    ) values (
      v_version.municipality_id,
      v_version.id,
      v_section_key,
      v_heading,
      v_ordinal,
      v_content_text,
      v_content_sha256
    ) returning id into v_section_id;
    v_inserted_sections := v_inserted_sections + 1;

    if v_section ? 'chunks'
       and jsonb_typeof(v_section -> 'chunks') = 'array'
       and jsonb_array_length(v_section -> 'chunks') > 0 then
      v_chunk_index := 0;
      for v_chunk in
        select value from jsonb_array_elements(v_section -> 'chunks')
      loop
        if jsonb_typeof(v_chunk) <> 'object' then
          raise exception 'every chunk must be a JSON object';
        end if;
        v_chunk_text := coalesce(v_chunk ->> 'content_text', '');
        if nullif(trim(v_chunk_text), '') is null then
          raise exception 'legal chunk content cannot be empty';
        end if;
        if position(v_chunk_text in v_content_text) = 0 then
          raise exception 'legal chunk content must be derived from its section';
        end if;
        v_chunk_sha256 := encode(extensions.digest(v_chunk_text, 'sha256'), 'hex');
        begin
          v_token_count := nullif(v_chunk ->> 'token_count', '')::integer;
        exception when others then
          raise exception 'chunk token_count must be an integer';
        end;

        insert into private.legal_chunks (
          municipality_id,
          legal_section_id,
          chunk_index,
          content_text,
          token_count,
          content_sha256
        ) values (
          v_version.municipality_id,
          v_section_id,
          v_chunk_index,
          v_chunk_text,
          coalesce(v_token_count, greatest(
            1,
            array_length(regexp_split_to_array(trim(v_chunk_text), E'\\s+'), 1)
          )),
          v_chunk_sha256
        );
        v_chunk_index := v_chunk_index + 1;
        v_inserted_chunks := v_inserted_chunks + 1;
      end loop;
    else
      insert into private.legal_chunks (
        municipality_id,
        legal_section_id,
        chunk_index,
        content_text,
        token_count,
        content_sha256
      ) values (
        v_version.municipality_id,
        v_section_id,
        0,
        v_content_text,
        greatest(
          1,
          array_length(regexp_split_to_array(trim(v_content_text), E'\\s+'), 1)
        ),
        v_content_sha256
      );
      v_inserted_chunks := v_inserted_chunks + 1;
    end if;
  end loop;

  if not v_has_integral_section
     or not private.legal_version_has_complete_evidence(
       v_version.municipality_id,
       v_version.id
     ) then
    raise exception 'an integral candidate-derived section and chunks are required';
  end if;

  return jsonb_build_object(
    'change_set_id', v_change_set.id,
    'candidate_version_id', v_version.id,
    'status', 'staged',
    'section_count', v_inserted_sections,
    'chunk_count', v_inserted_chunks
  );
end;
$$;

create or replace function public.ia_review_legal_source_change(
  p_change_set_id uuid,
  p_decision text,
  p_review_notes text,
  p_confirmation text,
  p_valid_from date default null,
  p_valid_until date default null,
  p_publication_date date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change_set private.legal_source_change_sets%rowtype;
  v_version public.legal_source_versions%rowtype;
  v_membership_id uuid;
  v_review_id uuid;
  v_reviewed_valid_from date;
  v_reviewed_valid_until date;
  v_reviewed_publication_date date;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> 'REVISAR' then
    raise exception 'explicit review confirmation required';
  end if;
  if p_decision not in ('approved', 'rejected', 'changes_requested') then
    raise exception 'invalid legal source review decision';
  end if;
  if p_decision <> 'approved'
     and nullif(trim(coalesce(p_review_notes, '')), '') is null then
    raise exception 'review notes are required for a non-approval decision';
  end if;

  select change_set.* into strict v_change_set
  from private.legal_source_change_sets change_set
  where change_set.id = p_change_set_id
  for update;

  v_membership_id := private.current_municipality_membership_id(
    v_change_set.municipality_id,
    array['legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'legal reviewer role required';
  end if;
  v_business_date := private.municipality_current_date(v_change_set.municipality_id);
  if v_change_set.status not in ('detected', 'changes_requested') then
    raise exception 'legal source change set is not awaiting review';
  end if;
  if v_change_set.candidate_version_id is null then
    raise exception 'extracted candidate version is required before review';
  end if;
  if v_change_set.change_type = 'legacy_import' then
    raise exception 'legacy source version must be recaptured from an official endpoint before review';
  end if;

  select version.* into strict v_version
  from public.legal_source_versions version
  where version.municipality_id = v_change_set.municipality_id
    and version.id = v_change_set.candidate_version_id
    and version.source_id = v_change_set.source_id
  for update;

  if v_version.status not in ('draft', 'under_review')
     and not (
       v_change_set.change_type = 'legacy_import'
       and v_version.status = 'approved'
     ) then
    raise exception 'candidate version is not reviewable';
  end if;
  if v_version.content_sha256 <> v_change_set.to_sha256
     and v_change_set.change_type = 'legacy_import' then
    raise exception 'legacy review hash no longer matches candidate version';
  end if;
  if p_decision = 'approved' and not exists (
    select 1
    from public.legal_sources source
    where source.municipality_id = v_version.municipality_id
      and source.id = v_version.source_id
      and source.official_url ~ '^https://[^[:space:]]+$'
  ) then
    raise exception 'an official HTTPS source URL is required before approval';
  end if;
  if p_decision = 'approved' and not exists (
    select 1
    from private.legal_source_artifacts artifact
    join private.legal_source_fetch_runs run
      on run.municipality_id = artifact.municipality_id
     and run.id = artifact.fetch_run_id
    join private.legal_source_artifact_versions mapping
      on mapping.municipality_id = artifact.municipality_id
     and mapping.artifact_id = artifact.id
     and mapping.source_version_id = v_version.id
    join storage.objects object
      on object.bucket_id = artifact.storage_bucket
     and object.name = artifact.storage_path
    where artifact.municipality_id = v_change_set.municipality_id
      and artifact.id = v_change_set.to_artifact_id
      and artifact.source_id = v_change_set.source_id
      and artifact.content_sha256 = v_change_set.to_sha256
      and artifact.extraction_status = 'completed'
      and artifact.extracted_text_sha256 = v_version.content_sha256
      and artifact.metadata ->> 'extraction_complete' = 'true'
      and artifact.metadata ->> 'content_truncated' = 'false'
      and case
        when coalesce(artifact.metadata ->> 'extracted_char_count', '') ~ '^[0-9]+$'
          then (artifact.metadata ->> 'extracted_char_count')::numeric
                 = char_length(v_version.content_text)::numeric
        else false
      end
      and run.source_id = v_change_set.source_id
      and run.status = 'completed_changed'
      and run.final_url ~ '^https://[^[:space:]]+$'
  ) then
    raise exception 'captured artifact evidence is required before approval';
  end if;
  if p_decision = 'approved' and not private.legal_version_has_complete_evidence(
    v_version.municipality_id,
    v_version.id
  ) then
    raise exception 'reviewed sections and chunks are required before approval';
  end if;

  v_reviewed_valid_from := coalesce(p_valid_from, v_version.valid_from);
  v_reviewed_valid_until := coalesce(p_valid_until, v_version.valid_until);
  v_reviewed_publication_date := coalesce(
    p_publication_date,
    v_version.publication_date
  );
  if v_reviewed_valid_until is not null
     and v_reviewed_valid_from is not null
     and v_reviewed_valid_until < v_reviewed_valid_from then
    raise exception 'valid_until cannot precede valid_from';
  end if;
  if p_decision = 'approved'
     and v_reviewed_publication_date is not null
     and v_reviewed_publication_date > v_business_date then
    raise exception 'publication date cannot be in the future';
  end if;
  if p_decision = 'approved'
     and (v_reviewed_publication_date is null or v_reviewed_valid_from is null) then
    raise exception 'publication date and start of validity are required';
  end if;
  if p_decision = 'approved'
     and (
       v_reviewed_valid_from > v_business_date
       or (
         v_reviewed_valid_until is not null
         and v_reviewed_valid_until < v_business_date
       )
     ) then
    raise exception 'legal source version is not currently effective';
  end if;

  insert into private.legal_source_version_reviews (
    municipality_id,
    change_set_id,
    source_version_id,
    reviewer_membership_id,
    decision,
    reviewed_content_sha256,
    reviewed_valid_from,
    reviewed_valid_until,
    reviewed_publication_date,
    notes
  ) values (
    v_change_set.municipality_id,
    v_change_set.id,
    v_version.id,
    v_membership_id,
    p_decision,
    v_version.content_sha256,
    v_reviewed_valid_from,
    v_reviewed_valid_until,
    v_reviewed_publication_date,
    nullif(trim(coalesce(p_review_notes, '')), '')
  ) returning id into v_review_id;

  update private.legal_source_change_sets
  set status = case p_decision
        when 'approved' then 'accepted'
        when 'rejected' then 'rejected'
        else 'changes_requested'
      end,
      reviewer_membership_id = v_membership_id,
      reviewed_at = now(),
      review_notes = nullif(trim(coalesce(p_review_notes, '')), '')
  where id = v_change_set.id;

  update public.legal_source_versions
  set status = case p_decision
        when 'approved' then 'approved'
        when 'rejected' then 'revoked'
        else 'under_review'
      end,
      valid_from = case when p_decision = 'approved'
        then v_reviewed_valid_from else valid_from end,
      valid_until = case when p_decision = 'approved'
        then v_reviewed_valid_until else valid_until end,
      publication_date = case when p_decision = 'approved'
        then v_reviewed_publication_date else publication_date end,
      approved_by = case when p_decision = 'approved' then auth.uid() else null end,
      approved_at = case when p_decision = 'approved' then now() else null end
  where municipality_id = v_version.municipality_id
    and id = v_version.id;

  return v_review_id;
end;
$$;

create or replace function public.ia_publish_legal_source_version(
  p_source_version_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.legal_source_versions%rowtype;
  v_source_id uuid;
  v_municipality_id uuid;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> 'PUBLICAR' then
    raise exception 'explicit publication confirmation required';
  end if;

  select version.municipality_id, version.source_id
    into strict v_municipality_id, v_source_id
  from public.legal_source_versions version
  where version.id = p_source_version_id;

  perform 1
  from public.legal_sources source
  where source.municipality_id = v_municipality_id
    and source.id = v_source_id
  for update;

  if not exists (
    select 1
    from public.legal_sources source
    where source.municipality_id = v_municipality_id
      and source.id = v_source_id
      and source.status <> 'retired'
  ) then
    raise exception 'retired legal source cannot be published';
  end if;

  select version.* into strict v_version
  from public.legal_source_versions version
  where version.id = p_source_version_id
  for update;
  v_business_date := private.municipality_current_date(v_version.municipality_id);

  if not private.has_municipality_role(
    v_version.municipality_id,
    array['legal_reviewer']::text[]
  ) then
    raise exception using errcode = '42501', message = 'legal reviewer role required';
  end if;
  if v_version.status <> 'approved' then
    raise exception 'legal source version must be explicitly approved before publication';
  end if;
  if v_version.publication_date is null or v_version.valid_from is null then
    raise exception 'publication date and start of validity are required';
  end if;
  if v_version.publication_date > v_business_date then
    raise exception 'publication date cannot be in the future';
  end if;
  if v_version.valid_from > v_business_date
     or (v_version.valid_until is not null and v_version.valid_until < v_business_date) then
    raise exception 'legal source version is not currently effective';
  end if;
  if not exists (
    select 1
    from private.legal_source_version_reviews review
    where review.municipality_id = v_version.municipality_id
      and review.source_version_id = v_version.id
      and review.decision = 'approved'
      and review.reviewed_content_sha256 = v_version.content_sha256
      and review.reviewed_valid_from is not distinct from v_version.valid_from
      and review.reviewed_valid_until is not distinct from v_version.valid_until
      and review.reviewed_publication_date is not distinct from v_version.publication_date
  ) then
    raise exception 'approved legal review snapshot is missing';
  end if;
  if not private.legal_version_has_complete_evidence(
    v_version.municipality_id,
    v_version.id
  ) then
    raise exception 'reviewed sections and chunks are required before publication';
  end if;

  update public.legal_source_versions
  set status = 'retired'
  where municipality_id = v_version.municipality_id
    and source_id = v_version.source_id
    and id <> v_version.id
    and status = 'published';

  update public.legal_source_versions
  set status = 'published',
      published_at = now()
  where municipality_id = v_version.municipality_id
    and id = v_version.id;

  update public.legal_sources
  set status = 'active'
  where municipality_id = v_version.municipality_id
    and id = v_version.source_id;

  update private.legal_source_change_sets
  set status = 'superseded',
      reviewed_at = coalesce(reviewed_at, now()),
      review_notes = concat_ws(
        ' ',
        nullif(trim(coalesce(review_notes, '')), ''),
        'Versão publicada; item encerrado.'
      )
  where municipality_id = v_version.municipality_id
    and candidate_version_id = v_version.id
    and status = 'accepted';
end;
$$;

-- Homologation fixtures remain available in their source tables for tests,
-- but they are never reusable knowledge and can never route a live response.
create or replace view public.vw_reusable_knowledge_articles
with (security_invoker = true)
as
select
  article.municipality_id,
  article.id as article_id,
  article.intent_key,
  article.semantic_version,
  article.canonical_question,
  article.tax_scope,
  article.divergence_scope,
  article.is_test,
  revision.id as revision_id,
  revision.answer_body,
  revision.allowed_placeholders,
  revision.content_sha256,
  article.valid_from,
  article.valid_until,
  article.published_at,
  citation_payload.citations
from public.knowledge_articles article
join public.municipalities municipality
  on municipality.id = article.municipality_id
join public.knowledge_article_revisions revision
  on revision.municipality_id = article.municipality_id
 and revision.article_id = article.id
 and revision.revision_number = article.current_revision_number
cross join lateral (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'citation_id', citation.id,
      'citation_label', citation.citation_label,
      'quoted_excerpt', citation.quoted_excerpt,
      'source_id', source.id,
      'source_title', source.title,
      'source_status', source.status,
      'official_identifier', source.official_identifier,
      'official_url', source.official_url,
      'source_version_id', source_version.id,
      'source_version_number', source_version.version,
      'source_version_status', source_version.status,
      'source_sha256', citation.source_sha256,
      'publication_date', source_version.publication_date,
      'valid_from', source_version.valid_from,
      'valid_until', source_version.valid_until,
      'section_id', section.id,
      'section_key', section.section_key,
      'section_heading', section.heading,
      'section_content_sha256', section.content_sha256,
      'is_valid', true,
      'blockers', '[]'::jsonb
    ) order by section.ordinal, citation.id
  ), '[]'::jsonb) as citations
  from public.knowledge_article_citations citation
  join public.legal_source_versions source_version
    on source_version.municipality_id = citation.municipality_id
   and source_version.id = citation.source_version_id
  join public.legal_sources source
    on source.municipality_id = source_version.municipality_id
   and source.id = source_version.source_id
  join public.legal_sections section
    on section.municipality_id = citation.municipality_id
   and section.id = citation.legal_section_id
   and section.source_version_id = source_version.id
  where citation.municipality_id = article.municipality_id
    and citation.revision_id = revision.id
) citation_payload
where article.status = 'published'
  and not article.is_test
  and article.approval_basis = 'fiscal_review'
  and (article.valid_from is null or article.valid_from <= now())
  and (article.valid_until is null or article.valid_until > now())
  and exists (
    select 1
    from public.knowledge_article_citations citation
    where citation.municipality_id = article.municipality_id
      and citation.revision_id = revision.id
  )
  and exists (
    select 1
    from public.knowledge_article_reviews review
    where review.municipality_id = article.municipality_id
      and review.article_id = article.id
      and review.revision_id = revision.id
      and review.decision = 'approved'
      and review.approved_content_sha256 = revision.content_sha256
  )
  and not exists (
    select 1
    from public.knowledge_article_citations citation
    join public.legal_source_versions source_version
      on source_version.municipality_id = citation.municipality_id
     and source_version.id = citation.source_version_id
    join public.legal_sources source
      on source.municipality_id = source_version.municipality_id
     and source.id = source_version.source_id
    join public.legal_sections section
      on section.municipality_id = citation.municipality_id
     and section.id = citation.legal_section_id
    where citation.municipality_id = article.municipality_id
      and citation.revision_id = revision.id
      and (
        source.status <> 'active'
        or source_version.status <> 'published'
        or source_version.content_sha256 <> citation.source_sha256
        or source_version.publication_date is null
        or source_version.publication_date > (now() at time zone municipality.timezone)::date
        or source_version.valid_from is null
        or source_version.valid_from > (now() at time zone municipality.timezone)::date
        or (
          source_version.valid_until is not null
          and source_version.valid_until < (now() at time zone municipality.timezone)::date
        )
        or section.source_version_id <> source_version.id
        or source.official_url is null
        or source.official_url !~ '^https://[^[:space:]]+$'
        or nullif(trim(citation.quoted_excerpt), '') is null
        or char_length(citation.quoted_excerpt) > 2000
        or position(trim(citation.quoted_excerpt) in section.content_text) = 0
      )
  );

-- Municipal administrators may inspect governed knowledge in AAL2, but all
-- writes remain RPC-only and retain their narrower reviewer roles.
drop policy if exists legal_sources_select_fiscal_staff on public.legal_sources;
create policy legal_sources_select_fiscal_staff
  on public.legal_sources for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

drop policy if exists legal_source_versions_select_fiscal_staff on public.legal_source_versions;
create policy legal_source_versions_select_fiscal_staff
  on public.legal_source_versions for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

drop policy if exists legal_sections_select_fiscal_staff on public.legal_sections;
create policy legal_sections_select_fiscal_staff
  on public.legal_sections for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

drop policy if exists knowledge_articles_select_staff on public.knowledge_articles;
create policy knowledge_articles_select_staff
  on public.knowledge_articles for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_revisions_select_staff on public.knowledge_article_revisions;
create policy knowledge_article_revisions_select_staff
  on public.knowledge_article_revisions for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_patterns_select_staff on public.knowledge_article_patterns;
create policy knowledge_article_patterns_select_staff
  on public.knowledge_article_patterns for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_citations_select_staff on public.knowledge_article_citations;
create policy knowledge_article_citations_select_staff
  on public.knowledge_article_citations for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_reviews_select_staff on public.knowledge_article_reviews;
create policy knowledge_article_reviews_select_staff
  on public.knowledge_article_reviews for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  )));

create or replace function public.ia_get_knowledge_operations_snapshot(
  p_municipality_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership_id uuid;
  v_membership_role text;
  v_municipality jsonb;
  v_sources jsonb;
  v_changes jsonb;
  v_reviews jsonb;
  v_summary jsonb;
  v_health jsonb;
  v_can_review_sources boolean;
  v_can_review_articles boolean;
  v_can_publish_sources boolean;
  v_can_publish_articles boolean;
  v_stale_sources integer;
  v_failed_sources integer;
  v_blocked_sources integer;
  v_missing_endpoint_sources integer;
  v_missing_candidate_sources integer;
  v_pending_review_sources integer;
  v_pending_publish_sources integer;
  v_unpublished_sources integer;
  v_last_successful_fetch_at timestamptz;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;

  v_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array[
      'municipal_admin',
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer'
    ]::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'municipality staff access required';
  end if;

  select membership.role into strict v_membership_role
  from public.municipality_memberships membership
  where membership.municipality_id = p_municipality_id
    and membership.id = v_membership_id;

  v_can_review_sources := v_membership_role = 'legal_reviewer';
  v_can_review_articles := v_membership_role in (
    'fiscal_auditor',
    'supervisor',
    'legal_reviewer'
  );
  v_can_publish_sources := v_membership_role = 'legal_reviewer';
  v_can_publish_articles := v_membership_role = 'legal_reviewer';

  select jsonb_build_object(
    'id', municipality.id,
    'slug', municipality.slug,
    'name', municipality.name
  ) into strict v_municipality
  from public.municipalities municipality
  where municipality.id = p_municipality_id;
  v_business_date := private.municipality_current_date(p_municipality_id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'source_id', source.id,
      'title', source.title,
      'official_identifier', source.official_identifier,
      'source_type', source.source_type,
      'tax_scope', source.tax_scope,
      'status', source.status,
      'official_url', source.official_url,
      'trust_tier', coalesce(endpoint.trust_tier, 'not_configured'),
      'endpoint_status', coalesce(endpoint.status, 'not_configured'),
      'content_mode', coalesce(endpoint.content_mode, 'not_configured'),
      'citable_body', coalesce(endpoint.citable_body, false),
      'activation_blocker', endpoint.metadata ->> 'activation_blocker',
      'last_fetch_status', coalesce(latest_run.status, 'not_collected'),
      'last_checked_at', latest_run.observed_at,
      'last_change_detected_at', change_state.last_detected_at,
      'last_error_code', case
        when latest_run.status in ('failed', 'blocked') then latest_run.safe_error_code
        else null
      end,
      'last_error_detail', case
        when latest_run.status in ('failed', 'blocked') then latest_run.safe_error_detail
        else null
      end,
      'latest_version_id', latest_version.id,
      'latest_version_number', latest_version.version,
      'latest_version_status', latest_version.status,
      'latest_valid_from', latest_version.valid_from,
      'latest_valid_until', latest_version.valid_until,
      'blockers', to_jsonb(array_remove(array[
        case when source.official_url is null
               or source.official_url !~ '^https://[^[:space:]]+$'
          then 'missing_official_url' end,
        case when endpoint.id is null then 'collection_not_verified' end,
        case when (endpoint.id is not null and not endpoint.citable_body)
               or change_state.has_raw_extraction
          then 'legal_body_extraction_required' end,
        case when endpoint.status = 'paused' then 'stale_source' end,
        case when latest_run.id is null then 'collection_not_verified' end,
        case when latest_run.status = 'failed' then 'collection_failed' end,
        case when latest_run.status = 'blocked' then 'fetch_failed' end,
        case when change_state.has_candidate_review
          then 'source_review_required' end,
        case when change_state.has_legacy_recapture
          then 'legacy_recapture_required' end,
        case when change_state.has_accepted
          then 'source_publication_required' end,
        case when latest_version.id is not null and latest_version.valid_from is null
          then 'source_review_required' end,
        case when change_state.has_incomplete_evidence
          then 'collection_not_verified' end,
        case when published_version.id is null
          then 'no_published_source_version' end
      ]::text[], null)),
      'can_review', (
        v_can_review_sources
        and change_state.has_candidate_review
      ),
      'can_publish', (
        v_can_publish_sources
        and latest_version.status = 'approved'
        and latest_version.publication_date is not null
        and latest_version.publication_date <= v_business_date
        and latest_version.valid_from is not null
        and latest_version.valid_from <= v_business_date
        and (latest_version.valid_until is null or latest_version.valid_until >= v_business_date)
        and exists (
          select 1
          from private.legal_source_version_reviews review
          where review.municipality_id = source.municipality_id
            and review.source_version_id = latest_version.id
            and review.decision = 'approved'
            and review.reviewed_content_sha256 = latest_version.content_sha256
            and review.reviewed_valid_from is not distinct from latest_version.valid_from
            and review.reviewed_valid_until is not distinct from latest_version.valid_until
            and review.reviewed_publication_date is not distinct from latest_version.publication_date
        )
        and private.legal_version_has_complete_evidence(
          source.municipality_id,
          latest_version.id
        )
      )
    ) order by source.title, source.id
  ), '[]'::jsonb) into v_sources
  from public.legal_sources source
  left join lateral (
    select configured_endpoint.*
    from private.legal_source_endpoints configured_endpoint
    where configured_endpoint.municipality_id = source.municipality_id
      and configured_endpoint.source_id = source.id
      and configured_endpoint.status <> 'retired'
    order by configured_endpoint.priority, configured_endpoint.id
    limit 1
  ) endpoint on true
  left join lateral (
    select run.*
    from private.legal_source_fetch_runs run
    where run.municipality_id = source.municipality_id
      and run.source_id = source.id
      and run.endpoint_id = endpoint.id
    order by run.observed_at desc, run.run_sequence desc
    limit 1
  ) latest_run on true
  left join lateral (
    select
      max(change_set.detected_at) as last_detected_at,
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is null
      ), false) as has_raw_extraction,
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.change_type = 'legacy_import'
      ), false) as has_legacy_recapture,
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
      ), false) as has_candidate_review,
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
        and not private.legal_version_has_complete_evidence(
          change_set.municipality_id,
          change_set.candidate_version_id
        )
      ), false) as has_incomplete_evidence,
      coalesce(bool_or(
        change_set.status = 'accepted'
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
      ), false) as has_accepted
    from private.legal_source_change_sets change_set
    where change_set.municipality_id = source.municipality_id
      and change_set.source_id = source.id
  ) change_state on true
  left join lateral (
    select version.*
    from public.legal_source_versions version
    where version.municipality_id = source.municipality_id
      and version.source_id = source.id
    order by version.version desc, version.id desc
    limit 1
  ) latest_version on true
  left join lateral (
    select version.id
    from public.legal_source_versions version
    where version.municipality_id = source.municipality_id
      and version.source_id = source.id
      and version.status = 'published'
      and version.publication_date is not null
      and version.publication_date <= v_business_date
      and version.valid_from is not null
      and version.valid_from <= v_business_date
      and (version.valid_until is null or version.valid_until >= v_business_date)
    order by version.version desc, version.id desc
    limit 1
  ) published_version on true
  where source.municipality_id = p_municipality_id
    and source.status <> 'retired';

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'change_set_id', change_set.id,
      'source_id', change_set.source_id,
      'source_title', source.title,
      'official_url', source.official_url,
      'change_type', change_set.change_type,
      'status', change_set.status,
      'detected_at', change_set.detected_at,
      'from_sha256', change_set.from_sha256,
      'to_sha256', change_set.to_sha256,
      'candidate_version_id', version.id,
      'candidate_version_number', version.version,
      'candidate_version_status', version.status,
      'candidate_valid_from', version.valid_from,
      'candidate_valid_until', version.valid_until,
      'candidate_content_preview', case
        when version.id is null then null
        else left(version.content_text, 500)
      end,
      'section_count', case
        when version.id is null then null
        else (
          select count(*)::integer
          from public.legal_sections section
          where section.municipality_id = version.municipality_id
            and section.source_version_id = version.id
        )
      end,
      'diff_summary', change_set.diff_summary,
      'blockers', to_jsonb(array_remove(array[
        case when source.official_url is null
               or source.official_url !~ '^https://[^[:space:]]+$'
          then 'missing_official_url' end,
        case when change_set.candidate_version_id is null
          then 'candidate_version_missing' end,
        case when change_set.candidate_version_id is null
          then 'legal_body_extraction_required' end,
        case when change_set.change_type = 'legacy_import'
          then 'legacy_recapture_required' end,
        case when change_set.status = 'rejected'
          then 'approved_review_required' end,
        case when change_set.status = 'changes_requested'
          then 'source_review_required' end,
        case when version.id is not null and version.valid_from is null
          then 'source_review_required' end,
        case when version.id is not null and (
          (version.publication_date is not null and version.publication_date > v_business_date)
          or (version.valid_from is not null and version.valid_from > v_business_date)
          or (version.valid_until is not null and version.valid_until < v_business_date)
        ) then 'source_not_current' end,
        case when version.id is not null
          and not private.legal_version_has_complete_evidence(
            version.municipality_id,
            version.id
          ) then 'collection_not_verified' end
      ]::text[], null)),
      'can_review', (
        v_can_review_sources
        and change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
      ),
      'can_publish', (
        v_can_publish_sources
        and change_set.change_type <> 'legacy_import'
        and change_set.status = 'accepted'
        and version.status = 'approved'
        and version.publication_date is not null
        and version.publication_date <= v_business_date
        and version.valid_from is not null
        and version.valid_from <= v_business_date
        and (version.valid_until is null or version.valid_until >= v_business_date)
        and private.legal_version_has_complete_evidence(
          version.municipality_id,
          version.id
        )
      )
    ) order by change_set.detected_at desc, change_set.id desc
  ), '[]'::jsonb) into v_changes
  from (
    select pending_change.*
    from private.legal_source_change_sets pending_change
    where pending_change.municipality_id = p_municipality_id
    order by pending_change.detected_at desc, pending_change.id desc
    limit 100
  ) change_set
  join public.legal_sources source
    on source.municipality_id = change_set.municipality_id
   and source.id = change_set.source_id
  left join public.legal_source_versions version
    on version.municipality_id = change_set.municipality_id
   and version.id = change_set.candidate_version_id;

  select coalesce(jsonb_agg(review_item.payload order by review_item.submitted_at desc), '[]'::jsonb)
    into v_reviews
  from (
    select
      change_set.detected_at as submitted_at,
      jsonb_build_object(
        'queue_kind', 'source_version',
        'item_id', change_set.id,
        'title', source.title,
        'status', change_set.status,
        'content_sha256', version.content_sha256,
        'submitted_at', change_set.detected_at,
        'last_reviewed_at', change_set.reviewed_at,
        'blockers', to_jsonb(array_remove(array[
          case when source.official_url is null
                 or source.official_url !~ '^https://[^[:space:]]+$'
            then 'missing_official_url' end,
          case when version.id is not null and version.valid_from is null
            then 'source_review_required' end,
          case when version.id is not null and version.publication_date is null
            then 'source_review_required' end,
          case when version.id is not null and (
            (version.publication_date is not null and version.publication_date > v_business_date)
            or (version.valid_from is not null and version.valid_from > v_business_date)
            or (version.valid_until is not null and version.valid_until < v_business_date)
          ) then 'source_not_current' end,
          case when not private.legal_version_has_complete_evidence(
            version.municipality_id,
            version.id
          ) then 'collection_not_verified' end
        ]::text[], null)),
        'can_review', (
          v_can_review_sources
          and change_set.status in ('detected', 'changes_requested')
          and version.id is not null
          and change_set.change_type <> 'legacy_import'
        ),
        'can_publish', (
          v_can_publish_sources
          and change_set.change_type <> 'legacy_import'
          and change_set.status = 'accepted'
          and version.status = 'approved'
          and version.valid_from is not null
          and version.valid_from <= v_business_date
          and (version.valid_until is null or version.valid_until >= v_business_date)
          and version.publication_date is not null
          and version.publication_date <= v_business_date
          and private.legal_version_has_complete_evidence(
            version.municipality_id,
            version.id
          )
        ),
        'source_id', source.id,
        'change_set_id', change_set.id,
        'candidate_version_id', version.id,
        'official_url', source.official_url,
        'candidate_content_preview', left(version.content_text, 500),
        'section_count', (
          select count(*)::integer
          from public.legal_sections section
          where section.municipality_id = version.municipality_id
            and section.source_version_id = version.id
        ),
        'article_id', null,
        'revision_id', null,
        'revision_number', null,
        'answer_preview', null,
        'citation_count', null,
        'is_test', false,
        'tax_scope', source.tax_scope,
        'divergence_scope', source.divergence_scope,
        'valid_from', version.valid_from,
        'valid_until', version.valid_until
      ) as payload
    from private.legal_source_change_sets change_set
    join public.legal_sources source
      on source.municipality_id = change_set.municipality_id
     and source.id = change_set.source_id
    left join public.legal_source_versions version
      on version.municipality_id = change_set.municipality_id
     and version.id = change_set.candidate_version_id
    where change_set.municipality_id = p_municipality_id
      and change_set.status in ('detected', 'changes_requested', 'accepted')
      and version.id is not null
      and change_set.change_type <> 'legacy_import'

    union all

    select
      article.created_at as submitted_at,
      jsonb_build_object(
        'queue_kind', 'knowledge_article',
        'item_id', article.id,
        'title', article.canonical_question,
        'status', article.status,
        'content_sha256', revision.content_sha256,
        'submitted_at', article.created_at,
        'last_reviewed_at', (
          select max(article_review.reviewed_at)
          from public.knowledge_article_reviews article_review
          where article_review.municipality_id = article.municipality_id
            and article_review.article_id = article.id
            and article_review.revision_id = revision.id
        ),
        'blockers', to_jsonb(array_remove(array[
          case when citation_summary.citation_count = 0
            then 'citation_required' end,
          case when article.status <> 'approved'
            then 'article_not_approved' end,
          case when citation_summary.invalid_citation_count > 0
            then 'source_not_published' end
        ]::text[], null)),
        'can_review', (
          v_can_review_articles
          and article.status in ('under_review', 'revision_requested', 'draft')
          and citation_summary.citation_count > 0
        ),
        'can_publish', (
          v_can_publish_articles
          and article.status = 'approved'
          and (article.valid_from is null or article.valid_from <= now())
          and (article.valid_until is null or article.valid_until > now())
          and citation_summary.citation_count > 0
          and citation_summary.invalid_citation_count = 0
          and exists (
            select 1
            from public.knowledge_article_reviews article_review
            where article_review.municipality_id = article.municipality_id
              and article_review.article_id = article.id
              and article_review.revision_id = revision.id
              and article_review.decision = 'approved'
              and article_review.approved_content_sha256 = revision.content_sha256
          )
        ),
        'source_id', null,
        'change_set_id', null,
        'candidate_version_id', null,
        'official_url', null,
        'candidate_content_preview', null,
        'section_count', null,
        'article_id', article.id,
        'revision_id', revision.id,
        'revision_number', revision.revision_number,
        'answer_preview', left(revision.answer_body, 240),
        'citation_count', citation_summary.citation_count,
        'is_test', article.is_test,
        'tax_scope', article.tax_scope,
        'divergence_scope', article.divergence_scope,
        'valid_from', article.valid_from,
        'valid_until', article.valid_until
      ) as payload
    from public.knowledge_articles article
    join public.knowledge_article_revisions revision
      on revision.municipality_id = article.municipality_id
     and revision.article_id = article.id
     and revision.revision_number = article.current_revision_number
    cross join lateral (
      select
        count(*)::integer as citation_count,
        count(*) filter (where
          source.status <> 'active'
          or source_version.status <> 'published'
          or source_version.content_sha256 <> citation.source_sha256
          or source_version.publication_date is null
          or source_version.publication_date > v_business_date
          or source_version.valid_from is null
          or source_version.valid_from > v_business_date
          or (source_version.valid_until is not null and source_version.valid_until < v_business_date)
          or source.official_url is null
          or source.official_url !~ '^https://[^[:space:]]+$'
          or section.source_version_id <> source_version.id
          or nullif(trim(citation.quoted_excerpt), '') is null
          or char_length(citation.quoted_excerpt) > 2000
          or position(trim(citation.quoted_excerpt) in section.content_text) = 0
        )::integer as invalid_citation_count
      from public.knowledge_article_citations citation
      join public.legal_source_versions source_version
        on source_version.municipality_id = citation.municipality_id
       and source_version.id = citation.source_version_id
      join public.legal_sources source
        on source.municipality_id = source_version.municipality_id
       and source.id = source_version.source_id
      join public.legal_sections section
        on section.municipality_id = citation.municipality_id
       and section.id = citation.legal_section_id
      where citation.municipality_id = article.municipality_id
        and citation.revision_id = revision.id
    ) citation_summary
    where article.municipality_id = p_municipality_id
      and not article.is_test
      and article.approval_basis = 'fiscal_review'
      and article.status in ('draft', 'under_review', 'revision_requested', 'approved')
  ) review_item;

  select jsonb_build_object(
    'official_sources', count(*),
    'total_source_versions', (
      select count(*)
      from public.legal_source_versions version
      where version.municipality_id = p_municipality_id
    ),
    'published_source_versions', (
      select count(*)
      from public.legal_source_versions version
      where version.municipality_id = p_municipality_id
        and version.status = 'published'
        and version.publication_date is not null
        and version.publication_date <= v_business_date
        and version.valid_from is not null
        and version.valid_from <= v_business_date
        and (version.valid_until is null or version.valid_until >= v_business_date)
    ),
    'pending_source_reviews', (
      select count(*)
      from private.legal_source_change_sets change_set
      where change_set.municipality_id = p_municipality_id
        and change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
    ),
    'pending_source_extractions', (
      select count(*)
      from private.legal_source_change_sets change_set
      where change_set.municipality_id = p_municipality_id
        and change_set.status in ('detected', 'changes_requested')
        and (
          change_set.candidate_version_id is null
          or change_set.change_type = 'legacy_import'
        )
    ),
    'pending_source_publications', (
      select count(*)
      from private.legal_source_change_sets change_set
      where change_set.municipality_id = p_municipality_id
        and change_set.status = 'accepted'
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
    ),
    'pending_article_reviews', (
      select count(*)
      from public.knowledge_articles article
      where article.municipality_id = p_municipality_id
        and not article.is_test
        and article.approval_basis = 'fiscal_review'
        and article.status in ('draft', 'under_review', 'revision_requested')
    ),
    'open_changes', (
      select count(*)
      from private.legal_source_change_sets change_set
      where change_set.municipality_id = p_municipality_id
        and change_set.status in ('detected', 'changes_requested', 'accepted')
    ),
    'failed_fetches_24h', (
      select count(*)
      from private.legal_source_fetch_runs run
      where run.municipality_id = p_municipality_id
        and run.status in ('failed', 'blocked')
        and run.observed_at >= now() - interval '24 hours'
    )
  ) into v_summary
  from public.legal_sources source
  where source.municipality_id = p_municipality_id;

  select
    count(*) filter (
      where endpoint.status = 'paused'
         or (
           endpoint.status = 'active'
           and (
             latest_success.observed_at is null
             or latest_success.observed_at < now() - endpoint.poll_interval
           )
         )
    )::integer,
    count(*) filter (where latest_run.status = 'failed')::integer,
    count(*) filter (
      where endpoint.id is null
         or not endpoint.citable_body
         or source.official_url is null
         or source.official_url !~ '^https://[^[:space:]]+$'
         or latest_run.status = 'blocked'
         or change_state.has_raw_extraction
         or change_state.has_legacy_recapture
         or change_state.has_incomplete_evidence
         or published_version.id is null
    )::integer,
    count(*) filter (where endpoint.id is null)::integer,
    count(*) filter (
      where change_state.has_raw_extraction
         or change_state.has_legacy_recapture
    )::integer,
    count(*) filter (where published_version.id is null)::integer,
    count(*) filter (
      where change_state.has_complete_review
    )::integer,
    count(*) filter (where change_state.has_accepted)::integer,
    max(latest_success.observed_at)
  into
    v_stale_sources,
    v_failed_sources,
    v_blocked_sources,
    v_missing_endpoint_sources,
    v_missing_candidate_sources,
    v_unpublished_sources,
    v_pending_review_sources,
    v_pending_publish_sources,
    v_last_successful_fetch_at
  from public.legal_sources source
  left join lateral (
    select configured_endpoint.*
    from private.legal_source_endpoints configured_endpoint
    where configured_endpoint.municipality_id = source.municipality_id
      and configured_endpoint.source_id = source.id
      and configured_endpoint.status <> 'retired'
    order by
      case configured_endpoint.status when 'active' then 0 else 1 end,
      configured_endpoint.priority,
      configured_endpoint.id
    limit 1
  ) endpoint on true
  left join lateral (
    select run.status, run.observed_at
    from private.legal_source_fetch_runs run
    where run.municipality_id = source.municipality_id
      and run.source_id = source.id
      and run.endpoint_id = endpoint.id
    order by run.observed_at desc, run.run_sequence desc
    limit 1
  ) latest_run on true
  left join lateral (
    select run.observed_at
    from private.legal_source_fetch_runs run
    where run.municipality_id = source.municipality_id
      and run.source_id = source.id
      and run.endpoint_id = endpoint.id
      and run.status in ('completed_unchanged', 'completed_changed')
    order by run.observed_at desc, run.run_sequence desc
    limit 1
  ) latest_success on true
  left join lateral (
    select
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is null
      ), false) as has_raw_extraction,
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.change_type = 'legacy_import'
      ), false) as has_legacy_recapture,
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
        and private.legal_version_has_complete_evidence(
          change_set.municipality_id,
          change_set.candidate_version_id
        )
      ), false) as has_complete_review,
      coalesce(bool_or(
        change_set.status in ('detected', 'changes_requested')
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
        and not private.legal_version_has_complete_evidence(
          change_set.municipality_id,
          change_set.candidate_version_id
        )
      ), false) as has_incomplete_evidence,
      coalesce(bool_or(
        change_set.status = 'accepted'
        and change_set.candidate_version_id is not null
        and change_set.change_type <> 'legacy_import'
      ), false) as has_accepted
    from private.legal_source_change_sets change_set
    where change_set.municipality_id = source.municipality_id
      and change_set.source_id = source.id
  ) change_state on true
  left join lateral (
    select version.id
    from public.legal_source_versions version
    where version.municipality_id = source.municipality_id
      and version.source_id = source.id
      and version.status = 'published'
      and version.publication_date is not null
      and version.publication_date <= v_business_date
      and version.valid_from is not null
      and version.valid_from <= v_business_date
      and (version.valid_until is null or version.valid_until >= v_business_date)
    order by version.version desc, version.id desc
    limit 1
  ) published_version on true
  where source.municipality_id = p_municipality_id
    and source.status <> 'retired';

  v_health := jsonb_build_object(
    'status', case
      when coalesce(v_blocked_sources, 0) > 0 then 'blocked'
      when coalesce(v_failed_sources, 0) > 0
        or coalesce(v_stale_sources, 0) > 0
        or coalesce(v_pending_review_sources, 0) > 0
        or coalesce(v_pending_publish_sources, 0) > 0
        then 'attention'
      else 'healthy'
    end,
    'stale_sources', coalesce(v_stale_sources, 0),
    'failed_sources', coalesce(v_failed_sources, 0),
    'blocked_sources', coalesce(v_blocked_sources, 0),
    'pending_review_sources', coalesce(v_pending_review_sources, 0),
    'pending_publish_sources', coalesce(v_pending_publish_sources, 0),
    'last_successful_fetch_at', v_last_successful_fetch_at,
    'blockers', (
      select coalesce(jsonb_agg(distinct_blocker.blocker order by distinct_blocker.blocker), '[]'::jsonb)
      from (
        select distinct blocker.value as blocker
        from jsonb_array_elements(v_sources) source_item
        cross join lateral jsonb_array_elements_text(source_item -> 'blockers') blocker(value)
      ) distinct_blocker
    )
  );

  return jsonb_build_object(
    'verified', true,
    'checked_at', now(),
    'municipality', v_municipality,
    'capabilities', jsonb_build_object(
      'can_view', true,
      'can_review_source_versions', v_can_review_sources,
      'can_review_articles', v_can_review_articles,
      'can_publish_source_versions', v_can_publish_sources,
      'can_publish_articles', v_can_publish_articles
    ),
    'summary', v_summary,
    'sources', v_sources,
    'changes', v_changes,
    'reviews', v_reviews,
    'health', v_health
  );
end;
$$;

create or replace function public.ia_get_knowledge_article_evidence(
  p_municipality_id uuid,
  p_article_id uuid,
  p_revision_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_article public.knowledge_articles%rowtype;
  v_revision public.knowledge_article_revisions%rowtype;
  v_membership_id uuid;
  v_membership_role text;
  v_citations jsonb;
  v_citation_count integer;
  v_invalid_citation_count integer;
  v_case_id uuid;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;

  v_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'municipality staff access required';
  end if;
  select membership.role into strict v_membership_role
  from public.municipality_memberships membership
  where membership.municipality_id = p_municipality_id
    and membership.id = v_membership_id;

  select article.* into strict v_article
  from public.knowledge_articles article
  where article.municipality_id = p_municipality_id
    and article.id = p_article_id;
  v_business_date := private.municipality_current_date(v_article.municipality_id);
  if v_article.is_test or v_article.approval_basis <> 'fiscal_review' then
    raise exception using errcode = '42501', message = 'test knowledge is not reviewable';
  end if;

  select revision.* into strict v_revision
  from public.knowledge_article_revisions revision
  where revision.municipality_id = v_article.municipality_id
    and revision.article_id = v_article.id
    and revision.id = p_revision_id
    and revision.revision_number = v_article.current_revision_number;

  if char_length(v_revision.answer_body) > 20000 then
    raise exception 'knowledge answer exceeds the bounded review contract';
  end if;

  if v_article.source_question_id is not null then
    select question.case_id into strict v_case_id
    from public.case_questions question
    where question.municipality_id = v_article.municipality_id
      and question.id = v_article.source_question_id;
    if not private.can_view_case_staff(v_article.municipality_id, v_case_id) then
      raise exception using errcode = '42501', message = 'knowledge evidence access denied';
    end if;
  end if;

  select count(*)::integer into v_citation_count
  from public.knowledge_article_citations citation
  where citation.municipality_id = v_article.municipality_id
    and citation.revision_id = v_revision.id;
  if v_citation_count > 100 or exists (
    select 1
    from public.knowledge_article_citations citation
    where citation.municipality_id = v_article.municipality_id
      and citation.revision_id = v_revision.id
      and char_length(citation.quoted_excerpt) > 2000
  ) then
    raise exception 'citation evidence exceeds the bounded review contract';
  end if;

  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'citation_id', evidence.citation_id,
        'citation_label', evidence.citation_label,
        'quoted_excerpt', evidence.quoted_excerpt,
        'source_id', evidence.source_id,
        'source_title', evidence.source_title,
        'source_status', evidence.source_status,
        'official_identifier', evidence.official_identifier,
        'official_url', evidence.official_url,
        'source_version_id', evidence.source_version_id,
        'source_version_number', evidence.source_version_number,
        'source_version_status', evidence.source_version_status,
        'source_sha256', evidence.source_sha256,
        'publication_date', evidence.publication_date,
        'valid_from', evidence.valid_from,
        'valid_until', evidence.valid_until,
        'section_id', evidence.section_id,
        'section_key', evidence.section_key,
        'section_heading', evidence.section_heading,
        'section_content_sha256', evidence.section_content_sha256,
        'is_valid', cardinality(evidence.blockers) = 0,
        'blockers', to_jsonb(evidence.blockers)
      ) order by evidence.section_ordinal, evidence.citation_id
    ), '[]'::jsonb),
    count(*) filter (where cardinality(evidence.blockers) > 0)::integer
  into v_citations, v_invalid_citation_count
  from (
    select
      citation.id as citation_id,
      citation.citation_label,
      citation.quoted_excerpt,
      source.id as source_id,
      source.title as source_title,
      source.status as source_status,
      source.official_identifier,
      source.official_url,
      source_version.id as source_version_id,
      source_version.version as source_version_number,
      source_version.status as source_version_status,
      citation.source_sha256,
      source_version.publication_date,
      source_version.valid_from,
      source_version.valid_until,
      section.id as section_id,
      section.section_key,
      section.heading as section_heading,
      section.ordinal as section_ordinal,
      section.content_sha256 as section_content_sha256,
      array_remove(array[
        case when source.status <> 'active'
                   or source_version.status <> 'published'
                   or source_version.publication_date is null
                   or source_version.publication_date > v_business_date
          then 'source_not_published' end,
        case when source_version.content_sha256 <> citation.source_sha256 then 'source_hash_changed' end,
        case when source_version.valid_from is null
                   or source_version.valid_from > v_business_date
                   or (source_version.valid_until is not null and source_version.valid_until < v_business_date)
          then 'expired_source' end,
        case when source.official_url is null
                   or source.official_url !~ '^https://[^[:space:]]+$'
          then 'missing_official_url' end,
        case when section.source_version_id <> source_version.id
                   or nullif(trim(citation.quoted_excerpt), '') is null
                   or position(trim(citation.quoted_excerpt) in section.content_text) = 0
          then 'hash_mismatch' end
      ]::text[], null) as blockers
    from public.knowledge_article_citations citation
    join public.legal_source_versions source_version
      on source_version.municipality_id = citation.municipality_id
     and source_version.id = citation.source_version_id
    join public.legal_sources source
      on source.municipality_id = source_version.municipality_id
     and source.id = source_version.source_id
    join public.legal_sections section
      on section.municipality_id = citation.municipality_id
     and section.id = citation.legal_section_id
    where citation.municipality_id = v_article.municipality_id
      and citation.revision_id = v_revision.id
  ) evidence;

  return jsonb_build_object(
    'verified', true,
    'checked_at', now(),
    'municipality_id', v_article.municipality_id,
    'article_id', v_article.id,
    'revision_id', v_revision.id,
    'revision_number', v_revision.revision_number,
    'content_sha256', v_revision.content_sha256,
    'canonical_question', v_article.canonical_question,
    'answer_body', v_revision.answer_body,
    'answer_length', char_length(v_revision.answer_body),
    'citation_count', v_citation_count,
    'citations', v_citations,
    'status', v_article.status,
    'tax_scope', v_article.tax_scope,
    'divergence_scope', v_article.divergence_scope,
    'valid_from', v_article.valid_from,
    'valid_until', v_article.valid_until,
    'evidence_complete', v_citation_count > 0 and coalesce(v_invalid_citation_count, 0) = 0,
    'blockers', to_jsonb(array_remove(array[
      case when v_citation_count = 0 then 'citation_required' end,
      case when coalesce(v_invalid_citation_count, 0) > 0 then 'source_not_published' end,
      case when v_article.status <> 'approved' then 'article_not_approved' end
    ]::text[], null)),
    'can_review', (
      v_membership_role in ('supervisor', 'fiscal_auditor', 'legal_reviewer')
      and v_article.status in ('draft', 'under_review', 'revision_requested')
      and v_citation_count > 0
      and coalesce(v_invalid_citation_count, 0) = 0
    ),
    'can_publish', (
      v_membership_role = 'legal_reviewer'
      and v_article.status = 'approved'
      and (v_article.valid_from is null or v_article.valid_from <= now())
      and (v_article.valid_until is null or v_article.valid_until > now())
      and v_citation_count > 0
      and coalesce(v_invalid_citation_count, 0) = 0
    )
  );
end;
$$;

create or replace function public.ia_get_legal_source_change_evidence(
  p_municipality_id uuid,
  p_change_set_id uuid,
  p_content_offset integer default 0,
  p_content_limit integer default 20000,
  p_section_offset integer default 0,
  p_section_limit integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change_set private.legal_source_change_sets%rowtype;
  v_source public.legal_sources%rowtype;
  v_version public.legal_source_versions%rowtype;
  v_artifact private.legal_source_artifacts%rowtype;
  v_fetch_run private.legal_source_fetch_runs%rowtype;
  v_membership_id uuid;
  v_membership_role text;
  v_content_total integer;
  v_section_total integer;
  v_sections jsonb;
  v_change_items jsonb;
  v_change_item_total integer;
  v_has_staged_evidence boolean;
  v_has_artifact_mapping boolean;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_content_offset < 0 or p_content_limit not between 1 and 50000
     or p_section_offset < 0 or p_section_limit not between 1 and 100 then
    raise exception 'invalid evidence pagination';
  end if;

  v_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'municipality staff access required';
  end if;
  select membership.role into strict v_membership_role
  from public.municipality_memberships membership
  where membership.municipality_id = p_municipality_id
    and membership.id = v_membership_id;

  select change_set.* into strict v_change_set
  from private.legal_source_change_sets change_set
  where change_set.municipality_id = p_municipality_id
    and change_set.id = p_change_set_id;
  v_business_date := private.municipality_current_date(v_change_set.municipality_id);
  select source.* into strict v_source
  from public.legal_sources source
  where source.municipality_id = v_change_set.municipality_id
    and source.id = v_change_set.source_id;

  if v_change_set.candidate_version_id is not null then
    select version.* into strict v_version
    from public.legal_source_versions version
    where version.municipality_id = v_change_set.municipality_id
      and version.id = v_change_set.candidate_version_id;
  end if;
  if v_change_set.to_artifact_id is not null then
    select artifact.* into strict v_artifact
    from private.legal_source_artifacts artifact
    where artifact.municipality_id = v_change_set.municipality_id
      and artifact.id = v_change_set.to_artifact_id;
    select run.* into strict v_fetch_run
    from private.legal_source_fetch_runs run
    where run.municipality_id = v_artifact.municipality_id
      and run.id = v_artifact.fetch_run_id;
  end if;

  v_content_total := coalesce(char_length(v_version.content_text), 0);
  if p_content_offset > v_content_total then
    raise exception 'content offset exceeds candidate length';
  end if;

  select count(*)::integer into v_section_total
  from public.legal_sections section
  where section.municipality_id = v_change_set.municipality_id
    and section.source_version_id = v_change_set.candidate_version_id;

  select coalesce(jsonb_agg(section_page.payload order by section_page.ordinal), '[]'::jsonb)
    into v_sections
  from (
    select
      section.ordinal,
      jsonb_build_object(
        'section_id', section.id,
        'section_key', section.section_key,
        'heading', section.heading,
        'ordinal', section.ordinal,
        'content_preview', left(section.content_text, 2000),
        'content_total_chars', char_length(section.content_text),
        'content_sha256', section.content_sha256,
        'chunk_count', (
          select count(*)::integer
          from private.legal_chunks chunk
          where chunk.municipality_id = section.municipality_id
            and chunk.legal_section_id = section.id
        )
      ) as payload
    from public.legal_sections section
    where section.municipality_id = v_change_set.municipality_id
      and section.source_version_id = v_change_set.candidate_version_id
    order by section.ordinal, section.id
    offset p_section_offset
    limit p_section_limit
  ) section_page;

  select count(*)::integer into v_change_item_total
  from private.legal_source_change_items item
  where item.municipality_id = v_change_set.municipality_id
    and item.change_set_id = v_change_set.id;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'item_kind', item.item_kind,
      'item_path', item.item_path,
      'before_sha256', item.before_sha256,
      'after_sha256', item.after_sha256,
      'before_excerpt', item.before_excerpt,
      'after_excerpt', item.after_excerpt,
      'summary', item.summary
    ) order by item.ordinal, item.id
  ), '[]'::jsonb) into v_change_items
  from (
    select change_item.*
    from private.legal_source_change_items change_item
    where change_item.municipality_id = v_change_set.municipality_id
      and change_item.change_set_id = v_change_set.id
    order by change_item.ordinal, change_item.id
    limit 100
  ) item;

  v_has_staged_evidence := v_version.id is not null
    and private.legal_version_has_complete_evidence(
      v_version.municipality_id,
      v_version.id
    );
  v_has_artifact_mapping := v_artifact.id is not null
    and v_fetch_run.id is not null
    and v_fetch_run.status = 'completed_changed'
    and v_fetch_run.source_id = v_change_set.source_id
    and v_fetch_run.final_url ~ '^https://[^[:space:]]+$'
    and v_artifact.content_sha256 = v_change_set.to_sha256
    and v_artifact.extraction_status = 'completed'
    and v_artifact.extracted_text_sha256 = v_version.content_sha256
    and v_artifact.metadata ->> 'extraction_complete' = 'true'
    and v_artifact.metadata ->> 'content_truncated' = 'false'
    and case
      when coalesce(v_artifact.metadata ->> 'extracted_char_count', '') ~ '^[0-9]+$'
        then (v_artifact.metadata ->> 'extracted_char_count')::numeric
               = char_length(v_version.content_text)::numeric
      else false
    end
    and exists (
      select 1
      from storage.objects object
      where object.bucket_id = v_artifact.storage_bucket
        and object.name = v_artifact.storage_path
    )
    and exists (
      select 1
      from private.legal_source_artifact_versions mapping
      where mapping.municipality_id = v_change_set.municipality_id
        and mapping.artifact_id = v_artifact.id
        and mapping.source_version_id = v_version.id
    );

  return jsonb_build_object(
    'verified', true,
    'checked_at', now(),
    'municipality_id', v_change_set.municipality_id,
    'change_set_id', v_change_set.id,
    'change_type', v_change_set.change_type,
    'status', v_change_set.status,
    'source_id', v_source.id,
    'source_title', v_source.title,
    'official_identifier', v_source.official_identifier,
    'official_url', v_source.official_url,
    'captured_url', v_fetch_run.final_url,
    'requested_url', v_fetch_run.requested_url,
    'observed_at', v_artifact.observed_at,
    'artifact_id', v_artifact.id,
    'artifact_mime_type', v_artifact.mime_type,
    'artifact_byte_size', v_artifact.byte_size,
    'raw_content_sha256', v_artifact.content_sha256,
    'from_sha256', v_change_set.from_sha256,
    'to_sha256', v_change_set.to_sha256,
    'diff_sha256', v_change_set.diff_sha256,
    'diff_summary', v_change_set.diff_summary,
    'change_items', v_change_items,
    'change_item_total', v_change_item_total,
    'change_items_has_more', v_change_item_total > 100,
    'candidate_version_id', v_version.id,
    'candidate_version_number', v_version.version,
    'candidate_version_status', v_version.status,
    'content_sha256', v_version.content_sha256,
    'publication_date', v_version.publication_date,
    'valid_from', v_version.valid_from,
    'valid_until', v_version.valid_until,
    'content_text', case when v_version.id is null then null else substring(
      v_version.content_text from p_content_offset + 1 for p_content_limit
    ) end,
    'content_offset', p_content_offset,
    'content_limit', p_content_limit,
    'content_total_chars', v_content_total,
    'content_has_more', p_content_offset + p_content_limit < v_content_total,
    'sections', v_sections,
    'section_offset', p_section_offset,
    'section_limit', p_section_limit,
    'section_total', v_section_total,
    'section_has_more', p_section_offset + p_section_limit < v_section_total,
    'evidence_complete', v_has_artifact_mapping and v_has_staged_evidence,
    'blockers', to_jsonb(array_remove(array[
      case when v_version.id is null then 'candidate_version_missing' end,
      case when v_source.official_url is null
                 or v_source.official_url !~ '^https://[^[:space:]]+$'
        then 'missing_official_url' end,
      case when not v_has_artifact_mapping then 'collection_not_verified' end,
      case when v_artifact.id is not null
                 and v_artifact.content_sha256 <> v_change_set.to_sha256
        then 'hash_mismatch' end,
      case when not v_has_staged_evidence then 'collection_not_verified' end,
      case when v_change_set.status in ('detected', 'changes_requested')
        then 'source_review_required' end,
      case when v_change_set.change_type = 'legacy_import'
        then 'legacy_recapture_required' end,
      case when v_version.id is not null and (
        (v_version.publication_date is not null and v_version.publication_date > v_business_date)
        or (v_version.valid_from is not null and v_version.valid_from > v_business_date)
        or (v_version.valid_until is not null and v_version.valid_until < v_business_date)
      ) then 'source_not_current' end
    ]::text[], null)),
    'can_review', (
      v_membership_role = 'legal_reviewer'
      and v_change_set.status in ('detected', 'changes_requested')
      and v_version.id is not null
      and v_change_set.change_type <> 'legacy_import'
    ),
    'can_publish', (
      v_membership_role = 'legal_reviewer'
      and v_change_set.status = 'accepted'
      and v_version.status = 'approved'
      and v_version.publication_date is not null
      and v_version.publication_date <= v_business_date
      and v_version.valid_from is not null
      and v_version.valid_from <= v_business_date
      and (v_version.valid_until is null or v_version.valid_until >= v_business_date)
      and v_has_artifact_mapping
      and v_has_staged_evidence
    )
  );
end;
$$;

revoke all on function public.ia_review_knowledge_article(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
drop function public.ia_review_knowledge_article(uuid, uuid, text, text);

create function public.ia_review_knowledge_article(
  p_article_id uuid,
  p_revision_id uuid,
  p_decision text,
  p_notes text,
  p_confirmation text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_article public.knowledge_articles%rowtype;
  v_revision public.knowledge_article_revisions%rowtype;
  v_membership_id uuid;
  v_review_id uuid;
  v_case_id uuid;
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_citation_count integer;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> 'REVISAR' then
    raise exception 'explicit review confirmation required';
  end if;
  if p_decision not in ('approved', 'rejected', 'revision_requested') then
    raise exception 'invalid knowledge review decision';
  end if;
  if char_length(coalesce(v_notes, '')) > 4000 then
    raise exception 'review notes exceed 4000 characters';
  end if;
  if p_decision in ('rejected', 'revision_requested')
     and char_length(coalesce(v_notes, '')) < 10 then
    raise exception 'at least 10 characters of review notes are required';
  end if;

  select article.* into strict v_article
  from public.knowledge_articles article
  where article.id = p_article_id
  for update;
  v_business_date := private.municipality_current_date(v_article.municipality_id);
  if v_article.is_test or v_article.approval_basis <> 'fiscal_review' then
    raise exception 'test fixture cannot become live knowledge';
  end if;
  if v_article.status not in ('draft', 'under_review', 'revision_requested') then
    raise exception 'knowledge article is not awaiting review';
  end if;

  v_membership_id := private.current_municipality_membership_id(
    v_article.municipality_id,
    array['fiscal_auditor', 'supervisor', 'legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'current municipal fiscal role required';
  end if;
  if v_article.source_question_id is not null then
    select question.case_id into strict v_case_id
    from public.case_questions question
    where question.municipality_id = v_article.municipality_id
      and question.id = v_article.source_question_id;
    if not private.can_review_case(v_article.municipality_id, v_case_id) then
      raise exception using errcode = '42501', message = 'knowledge review access denied';
    end if;
  end if;

  select revision.* into strict v_revision
  from public.knowledge_article_revisions revision
  where revision.municipality_id = v_article.municipality_id
    and revision.id = p_revision_id
    and revision.article_id = v_article.id
    and revision.revision_number = v_article.current_revision_number;
  if char_length(v_revision.answer_body) > 20000 then
    raise exception 'knowledge answer exceeds the bounded review contract';
  end if;

  select count(*)::integer into v_citation_count
  from public.knowledge_article_citations citation
  where citation.municipality_id = v_article.municipality_id
    and citation.revision_id = v_revision.id;
  if v_citation_count > 100 or exists (
    select 1
    from public.knowledge_article_citations citation
    where citation.municipality_id = v_article.municipality_id
      and citation.revision_id = v_revision.id
      and char_length(citation.quoted_excerpt) > 2000
  ) then
    raise exception 'citation evidence exceeds the bounded review contract';
  end if;
  if p_decision = 'approved' and v_citation_count = 0 then
    raise exception 'at least one legal citation is required';
  end if;
  if p_decision = 'approved' and exists (
    select 1
    from public.knowledge_article_citations citation
    join public.legal_source_versions source_version
      on source_version.municipality_id = citation.municipality_id
     and source_version.id = citation.source_version_id
    join public.legal_sources source
      on source.municipality_id = source_version.municipality_id
     and source.id = source_version.source_id
    join public.legal_sections section
      on section.municipality_id = citation.municipality_id
     and section.id = citation.legal_section_id
    where citation.municipality_id = v_article.municipality_id
      and citation.revision_id = v_revision.id
      and (
        source.status <> 'active'
        or source_version.status <> 'published'
        or source_version.content_sha256 <> citation.source_sha256
        or source_version.publication_date is null
        or source_version.publication_date > v_business_date
        or source_version.valid_from is null
        or source_version.valid_from > v_business_date
        or (source_version.valid_until is not null and source_version.valid_until < v_business_date)
        or section.source_version_id <> source_version.id
        or source.official_url is null
        or source.official_url !~ '^https://[^[:space:]]+$'
        or nullif(trim(citation.quoted_excerpt), '') is null
        or position(trim(citation.quoted_excerpt) in section.content_text) = 0
      )
  ) then
    raise exception 'one or more cited legal sources are not current, verifiable and published';
  end if;

  insert into public.knowledge_article_reviews (
    municipality_id,
    article_id,
    revision_id,
    decision,
    reviewer_membership_id,
    notes,
    approved_content_sha256
  ) values (
    v_article.municipality_id,
    v_article.id,
    v_revision.id,
    p_decision,
    v_membership_id,
    v_notes,
    case when p_decision = 'approved' then v_revision.content_sha256 end
  ) returning id into v_review_id;

  update public.knowledge_articles
  set status = case p_decision
        when 'approved' then 'approved'
        when 'rejected' then 'rejected'
        else 'revision_requested'
      end
  where municipality_id = v_article.municipality_id
    and id = v_article.id;

  return v_review_id;
end;
$$;

create or replace function public.ia_publish_knowledge_article(
  p_article_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_article public.knowledge_articles%rowtype;
  v_revision public.knowledge_article_revisions%rowtype;
  v_publisher_membership_id uuid;
  v_citation_count integer;
  v_lock_municipality_id uuid;
  v_lock_intent_key text;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> 'PUBLICAR' then
    raise exception 'explicit publication confirmation required';
  end if;

  select article.municipality_id, article.intent_key
    into strict v_lock_municipality_id, v_lock_intent_key
  from public.knowledge_articles article
  where article.id = p_article_id;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    v_lock_municipality_id::text || ':' || v_lock_intent_key,
    0
  ));

  select article.* into strict v_article
  from public.knowledge_articles article
  where article.id = p_article_id
  for update;
  v_business_date := private.municipality_current_date(v_article.municipality_id);
  v_publisher_membership_id := private.current_municipality_membership_id(
    v_article.municipality_id,
    array['legal_reviewer']::text[]
  );
  if v_publisher_membership_id is null then
    raise exception using errcode = '42501', message = 'current legal reviewer role required';
  end if;
  if v_article.is_test or v_article.approval_basis <> 'fiscal_review' then
    raise exception 'test fixture cannot be promoted to live knowledge';
  end if;
  if v_article.status <> 'approved' then
    raise exception 'knowledge article is not approved';
  end if;
  if (v_article.valid_from is not null and v_article.valid_from > now())
     or (v_article.valid_until is not null and v_article.valid_until <= now()) then
    raise exception 'knowledge article is not currently effective';
  end if;

  select revision.* into strict v_revision
  from public.knowledge_article_revisions revision
  where revision.municipality_id = v_article.municipality_id
    and revision.article_id = v_article.id
    and revision.revision_number = v_article.current_revision_number;
  if not exists (
    select 1
    from public.knowledge_article_reviews review
    where review.municipality_id = v_article.municipality_id
      and review.article_id = v_article.id
      and review.revision_id = v_revision.id
      and review.decision = 'approved'
      and review.approved_content_sha256 = v_revision.content_sha256
  ) then
    raise exception 'approved review hash missing';
  end if;

  select count(*)::integer into v_citation_count
  from public.knowledge_article_citations citation
  where citation.municipality_id = v_article.municipality_id
    and citation.revision_id = v_revision.id;
  if v_citation_count not between 1 and 100 then
    raise exception 'one to one hundred legal citations are required';
  end if;
  if exists (
    select 1
    from public.knowledge_article_citations citation
    join public.legal_source_versions source_version
      on source_version.municipality_id = citation.municipality_id
     and source_version.id = citation.source_version_id
    join public.legal_sources source
      on source.municipality_id = source_version.municipality_id
     and source.id = source_version.source_id
    join public.legal_sections section
      on section.municipality_id = citation.municipality_id
     and section.id = citation.legal_section_id
    where citation.municipality_id = v_article.municipality_id
      and citation.revision_id = v_revision.id
      and (
        source.status <> 'active'
        or source_version.status <> 'published'
        or source_version.content_sha256 <> citation.source_sha256
        or source_version.publication_date is null
        or source_version.publication_date > v_business_date
        or source_version.valid_from is null
        or source_version.valid_from > v_business_date
        or (source_version.valid_until is not null and source_version.valid_until < v_business_date)
        or section.source_version_id <> source_version.id
        or source.official_url is null
        or source.official_url !~ '^https://[^[:space:]]+$'
        or nullif(trim(citation.quoted_excerpt), '') is null
        or char_length(citation.quoted_excerpt) > 2000
        or position(trim(citation.quoted_excerpt) in section.content_text) = 0
      )
  ) then
    raise exception 'one or more cited legal sources are not current, verifiable and published';
  end if;

  update public.knowledge_articles
  set status = 'retired'
  where municipality_id = v_article.municipality_id
    and intent_key = v_article.intent_key
    and id <> v_article.id
    and status = 'published'
    and not is_test;

  update public.knowledge_articles
  set status = 'published',
      valid_from = coalesce(valid_from, now()),
      published_at = now()
  where municipality_id = v_article.municipality_id
    and id = v_article.id;
end;
$$;

-- Official catalog only: URLs and metadata verified on the municipal portals.
-- No legal body text is manufactured by this seed.
with source_seed (
  municipality_slug,
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
      'cordeiropolis-sp',
      'law',
      'municipal',
      'Município de Cordeirópolis',
      'Código Tributário do Município de Cordeirópolis',
      'Lei Complementar nº 399/2024',
      'https://cordeiropolis.siscam.com.br/Documentos/Documento/82280',
      'Tributos municipais',
      'fiscal_knowledge'
    ),
    (
      'cordeiropolis-sp',
      'law',
      'municipal',
      'Município de Cordeirópolis',
      'Parcelamento tributário municipal',
      'Lei Complementar nº 404/2025',
      'https://cordeiropolis.siscam.com.br/Documentos/Documento/83468',
      'Parcelamento e dívida ativa',
      'fiscal_knowledge'
    ),
    (
      'cordeiropolis-sp',
      'decree',
      'municipal',
      'Município de Cordeirópolis',
      'Atualização da UFIRCO para 2025',
      'Decreto nº 6.910/2024',
      'https://cordeiropolis.siscam.com.br/Documentos/Documento/81809',
      'Índices tributários',
      'fiscal_knowledge'
    ),
    (
      'cordeiropolis-sp',
      'official_guidance',
      'municipal',
      'Câmara Municipal de Cordeirópolis',
      'Catálogo oficial de legislação de Cordeirópolis',
      'Catálogo oficial de legislação',
      'https://cordeiropolis.siscam.com.br/index/81/8',
      'Tributos municipais',
      'source_catalog'
    ),
    (
      'cordeiropolis-sp',
      'official_guidance',
      'municipal',
      'Prefeitura Municipal de Cordeirópolis',
      'Jornal do Município de Cordeirópolis',
      'Jornal do Município',
      'https://cordeiropolis.sp.gov.br/jornal-do-municipio/',
      'Publicações oficiais',
      'official_journal'
    ),
    (
      'araras-sp',
      'law',
      'municipal',
      'Município de Araras',
      'Código Tributário do Município de Araras',
      'Lei nº 3.362/2001',
      'https://araras.siscam.com.br/Documentos/Documento/74258',
      'Tributos municipais',
      'fiscal_knowledge'
    ),
    (
      'araras-sp',
      'law',
      'municipal',
      'Município de Araras',
      'Planta Genérica de Valores do Município de Araras',
      'Lei Complementar nº 36/2013',
      'https://araras.siscam.com.br/Documentos/Documento/77629',
      'IPTU e ITBI',
      'fiscal_knowledge'
    ),
    (
      'araras-sp',
      'official_guidance',
      'municipal',
      'Câmara Municipal de Araras',
      'Catálogo oficial de legislação de Araras',
      'Catálogo oficial de legislação',
      'https://araras.siscam.com.br/index/75/8',
      'Tributos municipais',
      'source_catalog'
    ),
    (
      'araras-sp',
      'official_guidance',
      'municipal',
      'Prefeitura Municipal de Araras',
      'Diário Oficial Eletrônico do Município de Araras',
      'Diário Oficial Eletrônico',
      'https://app.assistechpublicacoes.com.br/diario-oficial/pmararassp',
      'Publicações oficiais',
      'official_journal'
    ),
    (
      'araras-sp',
      'official_guidance',
      'municipal',
      'Prefeitura Municipal de Araras',
      'Emissão de guia de ITBI em Araras',
      'Ganha Tempo — Emissão de Guia de ITBI',
      'https://ganhatempo.araras.sp.gov.br/guiafacil/pesquisa-publica/servicos/1070',
      'ITBI',
      'official_operations'
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
  municipality.id,
  seed.source_type,
  seed.jurisdiction,
  seed.issuing_authority,
  seed.title,
  seed.official_identifier,
  seed.official_url,
  seed.tax_scope,
  seed.divergence_scope,
  'draft'
from source_seed seed
join public.municipalities municipality
  on municipality.slug = seed.municipality_slug
on conflict (
  municipality_id,
  issuing_authority,
  official_identifier
) where official_identifier is not null
do nothing;

with endpoint_seed (
  municipality_slug,
  issuing_authority,
  official_identifier,
  endpoint_kind,
  trust_tier,
  url,
  allowed_hosts,
  expected_content_types,
  parser_hint,
  poll_interval,
  priority,
  metadata
) as (
  values
    (
      'cordeiropolis-sp',
      'Município de Cordeirópolis',
      'Lei Complementar nº 399/2024',
      'document_page',
      'official_consolidation',
      'https://cordeiropolis.siscam.com.br/Documentos/Documento/82280',
      array['cordeiropolis.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_document',
      interval '1 day',
      20,
      jsonb_build_object('scope', 'codigo_tributario')
    ),
    (
      'cordeiropolis-sp',
      'Município de Cordeirópolis',
      'Lei Complementar nº 399/2024',
      'document_file',
      'primary_publication',
      'https://cordeiropolis.siscam.com.br/arquivo?Id=121730',
      array['cordeiropolis.siscam.com.br']::text[],
      array['application/pdf', 'application/octet-stream']::text[],
      'pdf_text_or_ocr',
      interval '1 day',
      10,
      jsonb_build_object('scope', 'codigo_tributario', 'pages', 121)
    ),
    (
      'cordeiropolis-sp',
      'Município de Cordeirópolis',
      'Lei Complementar nº 404/2025',
      'document_page',
      'official_consolidation',
      'https://cordeiropolis.siscam.com.br/Documentos/Documento/83468',
      array['cordeiropolis.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_document',
      interval '1 day',
      30,
      '{}'::jsonb
    ),
    (
      'cordeiropolis-sp',
      'Município de Cordeirópolis',
      'Decreto nº 6.910/2024',
      'document_page',
      'official_consolidation',
      'https://cordeiropolis.siscam.com.br/Documentos/Documento/81809',
      array['cordeiropolis.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_document',
      interval '1 day',
      40,
      '{}'::jsonb
    ),
    (
      'cordeiropolis-sp',
      'Câmara Municipal de Cordeirópolis',
      'Catálogo oficial de legislação',
      'catalog',
      'official_consolidation',
      'https://cordeiropolis.siscam.com.br/index/81/8',
      array['cordeiropolis.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_index',
      interval '6 hours',
      50,
      '{}'::jsonb
    ),
    (
      'cordeiropolis-sp',
      'Prefeitura Municipal de Cordeirópolis',
      'Jornal do Município',
      'official_journal',
      'primary_publication',
      'https://cordeiropolis.siscam.com.br/index/647/8',
      array['cordeiropolis.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_official_journal',
      interval '6 hours',
      5,
      '{}'::jsonb
    ),
    (
      'cordeiropolis-sp',
      'Prefeitura Municipal de Cordeirópolis',
      'Jornal do Município',
      'official_journal',
      'primary_publication',
      'https://cordeiropolis.sp.gov.br/jornal-do-municipio/',
      array['cordeiropolis.sp.gov.br', 'www.cordeiropolis.sp.gov.br']::text[],
      array['text/html']::text[],
      'municipal_journal_index',
      interval '6 hours',
      6,
      '{}'::jsonb
    ),
    (
      'araras-sp',
      'Município de Araras',
      'Lei nº 3.362/2001',
      'document_page',
      'official_consolidation',
      'https://araras.siscam.com.br/Documentos/Documento/74258',
      array['araras.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_document',
      interval '1 day',
      20,
      jsonb_build_object('scope', 'codigo_tributario')
    ),
    (
      'araras-sp',
      'Município de Araras',
      'Lei nº 3.362/2001',
      'document_page',
      'official_consolidation',
      'https://www.legislacaodigital.com.br/Araras-SP/LeisOrdinarias/3362',
      array['www.legislacaodigital.com.br', 'legislacaodigital.com.br']::text[],
      array['text/html']::text[],
      'legislacao_digital',
      interval '1 day',
      25,
      jsonb_build_object('scope', 'codigo_tributario_compilado')
    ),
    (
      'araras-sp',
      'Município de Araras',
      'Lei Complementar nº 36/2013',
      'document_page',
      'official_consolidation',
      'https://araras.siscam.com.br/Documentos/Documento/77629',
      array['araras.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_document',
      interval '1 day',
      30,
      jsonb_build_object('scope', 'planta_generica_valores')
    ),
    (
      'araras-sp',
      'Câmara Municipal de Araras',
      'Catálogo oficial de legislação',
      'catalog',
      'official_consolidation',
      'https://araras.siscam.com.br/index/75/8',
      array['araras.siscam.com.br']::text[],
      array['text/html']::text[],
      'siscam_index',
      interval '6 hours',
      50,
      '{}'::jsonb
    ),
    (
      'araras-sp',
      'Prefeitura Municipal de Araras',
      'Diário Oficial Eletrônico',
      'official_journal',
      'primary_publication',
      'https://app.assistechpublicacoes.com.br/diario-oficial/pmararassp',
      array['app.assistechpublicacoes.com.br']::text[],
      array['text/html']::text[],
      'assistech_official_journal',
      interval '6 hours',
      5,
      '{}'::jsonb
    ),
    (
      'araras-sp',
      'Prefeitura Municipal de Araras',
      'Ganha Tempo — Emissão de Guia de ITBI',
      'operational_guidance',
      'official_operational',
      'https://ganhatempo.araras.sp.gov.br/guiafacil/pesquisa-publica/servicos/1070',
      array['ganhatempo.araras.sp.gov.br']::text[],
      array['text/html']::text[],
      'static_html',
      interval '1 day',
      80,
      jsonb_build_object('scope', 'itbi_guide_issuance')
    )
)
insert into private.legal_source_endpoints (
  municipality_id,
  source_id,
  endpoint_kind,
  trust_tier,
  content_mode,
  citable_body,
  url,
  allowed_hosts,
  expected_content_types,
  parser_hint,
  poll_interval,
  priority,
  status,
  metadata
)
select
  source.municipality_id,
  source.id,
  seed.endpoint_kind,
  seed.trust_tier,
  'catalog_only',
  false,
  seed.url,
  seed.allowed_hosts,
  seed.expected_content_types,
  seed.parser_hint,
  seed.poll_interval,
  seed.priority,
  case when seed.url in (
    'https://cordeiropolis.siscam.com.br/arquivo?Id=121730',
    'https://cordeiropolis.sp.gov.br/jornal-do-municipio/',
    'https://www.legislacaodigital.com.br/Araras-SP/LeisOrdinarias/3362'
  ) then 'paused' else 'active' end,
  seed.metadata || case when seed.url = 'https://cordeiropolis.siscam.com.br/arquivo?Id=121730'
    then jsonb_build_object('activation_blocker', 'pdf_extractor_required')
    when seed.url in (
      'https://cordeiropolis.sp.gov.br/jornal-do-municipio/',
      'https://www.legislacaodigital.com.br/Araras-SP/LeisOrdinarias/3362'
    ) then jsonb_build_object('activation_blocker', 'representation_comparison_required')
    else jsonb_build_object('activation_blocker', 'legal_body_parser_required')
  end
from endpoint_seed seed
join public.municipalities municipality
  on municipality.slug = seed.municipality_slug
join public.legal_sources source
  on source.municipality_id = municipality.id
 and source.issuing_authority = seed.issuing_authority
 and source.official_identifier = seed.official_identifier
on conflict (municipality_id, source_id, url) do update set
  endpoint_kind = excluded.endpoint_kind,
  content_mode = excluded.content_mode,
  citable_body = excluded.citable_body,
  allowed_hosts = excluded.allowed_hosts,
  expected_content_types = excluded.expected_content_types,
  parser_hint = excluded.parser_hint,
  poll_interval = excluded.poll_interval,
  priority = excluded.priority,
  status = excluded.status,
  metadata = excluded.metadata;

-- Existing draft/under-review versions become explicit review items without
-- fabricating a raw artifact that was never captured by this pipeline.
insert into private.legal_source_change_sets (
  municipality_id,
  source_id,
  candidate_version_id,
  change_type,
  status,
  to_sha256,
  diff_sha256,
  diff_summary,
  detected_at
)
select
  version.municipality_id,
  version.source_id,
  version.id,
  'legacy_import',
  'detected',
  version.content_sha256,
  encode(
    extensions.digest('legacy_import:' || version.content_sha256, 'sha256'),
    'hex'
  ),
  'Versão anterior à esteira de ingestão; exige revisão humana explícita.',
  version.created_at
from public.legal_source_versions version
join public.municipalities municipality
  on municipality.id = version.municipality_id
where municipality.slug in ('cordeiropolis-sp', 'araras-sp')
  and version.status in ('draft', 'under_review', 'approved')
  and not exists (
    select 1
    from private.legal_source_change_sets change_set
    where change_set.municipality_id = version.municipality_id
      and change_set.candidate_version_id = version.id
  );

insert into private.legal_source_change_items (
  municipality_id,
  change_set_id,
  ordinal,
  item_kind,
  item_path,
  after_sha256,
  summary
)
select
  change_set.municipality_id,
  change_set.id,
  1,
  'document_hash',
  'versao_legada',
  change_set.to_sha256,
  'Hash da versão existente registrado para revisão governada.'
from private.legal_source_change_sets change_set
where change_set.change_type = 'legacy_import'
  and not exists (
    select 1
    from private.legal_source_change_items item
    where item.municipality_id = change_set.municipality_id
      and item.change_set_id = change_set.id
      and item.ordinal = 1
  );

comment on function public.ia_fiscal_get_knowledge_source_endpoints() is
  'Service-only allowlisted source catalog for the official knowledge collector.';
comment on function public.ia_fiscal_capture_knowledge_source(
  uuid, text, text, text, text, bigint, text, text, text, text, text,
  integer, timestamptz, uuid, jsonb
) is
  'Service-only idempotent capture. Catalog hashes stay extraction-only; citable hashes stage under-review versions and never publish.';
comment on function public.ia_fiscal_record_knowledge_fetch_failure(
  uuid, text, integer, text, text, timestamptz, uuid, jsonb
) is
  'Service-only append-only record of a sanitized official-source fetch failure.';
comment on function public.ia_fiscal_stage_knowledge_sections(uuid, jsonb) is
  'Service-only idempotent staging of extracted legal sections and lexical chunks.';
comment on function public.ia_review_legal_source_change(
  uuid, text, text, text, date, date, date
) is
  'AAL2 legal-reviewer decision over immutable evidence, including the validity snapshot.';
comment on function public.ia_get_knowledge_operations_snapshot(uuid) is
  'AAL2 tenant-scoped read model for Segundo Cerebro operations; test articles are excluded.';
comment on function public.ia_get_knowledge_article_evidence(uuid, uuid, uuid) is
  'AAL2 tenant-scoped full article evidence and bounded verified citations for a review modal.';
comment on function public.ia_get_legal_source_change_evidence(
  uuid, uuid, integer, integer, integer, integer
) is
  'AAL2 tenant-scoped paginated source evidence; includes captured URL and hashes but never storage paths.';
comment on function public.ia_review_knowledge_article(
  uuid, uuid, text, text, text
) is
  'AAL2 municipal fiscal review with explicit confirmation, bounded evidence and verified citations.';

revoke all on function public.ia_fiscal_get_knowledge_source_endpoints()
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_get_knowledge_source_endpoints()
  to service_role;

revoke all on function public.ia_fiscal_capture_knowledge_source(
  uuid, text, text, text, text, bigint, text, text, text, text, text,
  integer, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_capture_knowledge_source(
  uuid, text, text, text, text, bigint, text, text, text, text, text,
  integer, timestamptz, uuid, jsonb
) to service_role;

revoke all on function public.ia_fiscal_record_knowledge_fetch_failure(
  uuid, text, integer, text, text, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_record_knowledge_fetch_failure(
  uuid, text, integer, text, text, timestamptz, uuid, jsonb
) to service_role;

revoke all on function public.ia_fiscal_stage_knowledge_sections(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_stage_knowledge_sections(uuid, jsonb)
  to service_role;

revoke all on function public.ia_review_legal_source_change(
  uuid, text, text, text, date, date, date
) from public, anon, authenticated, service_role;
grant execute on function public.ia_review_legal_source_change(
  uuid, text, text, text, date, date, date
) to authenticated;

revoke all on function public.ia_get_knowledge_operations_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_knowledge_operations_snapshot(uuid)
  to authenticated;

revoke all on function public.ia_get_knowledge_article_evidence(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_knowledge_article_evidence(uuid, uuid, uuid)
  to authenticated;

revoke all on function public.ia_get_legal_source_change_evidence(
  uuid, uuid, integer, integer, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.ia_get_legal_source_change_evidence(
  uuid, uuid, integer, integer, integer, integer
) to authenticated;

revoke all on function public.ia_review_knowledge_article(
  uuid, uuid, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.ia_review_knowledge_article(
  uuid, uuid, text, text, text
) to authenticated;

revoke all on function public.ia_publish_knowledge_article(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_publish_knowledge_article(uuid, text)
  to authenticated;

revoke all on function public.ia_publish_legal_source_version(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_publish_legal_source_version(uuid, text)
  to authenticated;

revoke all on function private.guard_legal_source_endpoint()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_source_change_set()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_reviewed_legal_source_version()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_source_identity()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_source_version_integrity()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_section_integrity()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_chunk_integrity()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_source_storage_object()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_source_storage_bucket()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_legal_source_storage_truncate()
  from public, anon, authenticated, service_role;
revoke all on function private.municipality_current_date(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.legal_version_has_complete_evidence(uuid, uuid)
  from public, anon, authenticated, service_role;

revoke insert, update, delete, truncate, references, trigger
  on public.legal_sources,
     public.legal_source_versions,
     public.legal_sections,
     private.legal_chunks
  from anon, authenticated, service_role;
revoke insert, update, delete, truncate, references, trigger
  on public.knowledge_articles,
     public.knowledge_article_revisions,
     public.knowledge_article_patterns,
     public.knowledge_article_citations,
     public.knowledge_article_reviews
  from anon, authenticated, service_role;

revoke all on public.vw_reusable_knowledge_articles from anon;
grant select on public.vw_reusable_knowledge_articles
  to authenticated, service_role;

commit;
