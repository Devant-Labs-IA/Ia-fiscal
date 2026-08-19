-- Segundo Cerebro Fiscal, fase 2.
--
-- This migration installs the governed, tenant-first retrieval and learning
-- pipeline.  It intentionally does not create a cron job or enable any
-- municipality schedule.  Edge Functions must be deployed before the
-- separate activation migration is applied.

begin;

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

-- A legal reviewer is a capability, not a replacement for the holder's
-- municipal role.  In particular, a municipal_admin keeps that role and may
-- receive/revoke this narrowly-scoped capability with full audit history.
create table private.legal_reviewer_capability_grants (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  membership_id uuid not null,
  status text not null default 'active'
    check (status in ('active', 'revoked', 'expired')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_by_membership_id uuid not null,
  reason text not null check (char_length(trim(reason)) between 10 and 1000),
  revoked_by_membership_id uuid,
  revoked_at timestamptz,
  revocation_reason text check (
    revocation_reason is null
    or char_length(trim(revocation_reason)) between 10 and 1000
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_reviewer_capability_target_fk
    foreign key (municipality_id, membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint legal_reviewer_capability_grantor_fk
    foreign key (municipality_id, granted_by_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint legal_reviewer_capability_revoker_fk
    foreign key (municipality_id, revoked_by_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint legal_reviewer_capability_validity_ck
    check (valid_until is null or valid_until > valid_from),
  constraint legal_reviewer_capability_revocation_ck check (
    (status = 'revoked' and revoked_by_membership_id is not null and revoked_at is not null)
    or (status <> 'revoked' and revoked_by_membership_id is null and revoked_at is null)
  ),
  constraint legal_reviewer_capability_municipality_id_id_uq
    unique (municipality_id, id)
);

create unique index legal_reviewer_capability_one_active_idx
  on private.legal_reviewer_capability_grants (municipality_id, membership_id)
  where status = 'active';

create index legal_reviewer_capability_current_idx
  on private.legal_reviewer_capability_grants (
    municipality_id,
    membership_id,
    status,
    valid_until
  );

create table private.legal_reviewer_capability_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  grant_id uuid not null,
  event_type text not null check (event_type in ('granted', 'revoked', 'expired')),
  actor_kind text not null default 'municipal_staff'
    check (actor_kind in ('municipal_staff', 'system')),
  actor_membership_id uuid,
  reason text not null check (char_length(trim(reason)) between 10 and 1000),
  event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  constraint legal_reviewer_capability_events_grant_fk
    foreign key (municipality_id, grant_id)
    references private.legal_reviewer_capability_grants(municipality_id, id),
  constraint legal_reviewer_capability_events_actor_fk
    foreign key (municipality_id, actor_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint legal_reviewer_capability_events_actor_ck check (
    (actor_kind = 'municipal_staff' and actor_membership_id is not null)
    or (actor_kind = 'system' and actor_membership_id is null)
  ),
  constraint legal_reviewer_capability_events_once_uq
    unique (grant_id, event_type)
);

create or replace function private.expire_legal_reviewer_capabilities(
  p_limit integer default 500,
  p_municipality_id uuid default null,
  p_membership_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expired integer;
begin
  if p_limit not between 1 and 5000 then
    raise exception 'reviewer expiry batch must be between 1 and 5000';
  end if;

  with due as materialized (
    select capability.id
    from private.legal_reviewer_capability_grants capability
    where capability.status = 'active'
      and capability.valid_until is not null
      and capability.valid_until <= now()
      and (p_municipality_id is null or capability.municipality_id = p_municipality_id)
      and (p_membership_id is null or capability.membership_id = p_membership_id)
    order by capability.valid_until, capability.id
    for update skip locked
    limit p_limit
  ), expired as (
    update private.legal_reviewer_capability_grants capability
    set status = 'expired',
        updated_at = now()
    from due
    where capability.id = due.id
      and capability.status = 'active'
      and capability.valid_until <= now()
    returning capability.municipality_id, capability.id
  ), events as (
    insert into private.legal_reviewer_capability_events (
      municipality_id,
      grant_id,
      event_type,
      actor_kind,
      actor_membership_id,
      reason,
      metadata
    )
    select
      expired.municipality_id,
      expired.id,
      'expired',
      'system',
      null,
      'Vigencia do revisor juridico expirada automaticamente pelo relogio governado.',
      jsonb_build_object('transition', 'validity_elapsed')
    from expired
    returning grant_id
  )
  select count(*)::integer into v_expired from events;

  return v_expired;
end;
$$;

create or replace function private.has_legal_reviewer_capability(
  p_municipality_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and private.is_aal2()
     and exists (
       select 1
       from public.municipality_memberships membership
       where membership.municipality_id = p_municipality_id
         and membership.user_id = (select auth.uid())
         and membership.status = 'active'
         and membership.valid_from <= now()
         and (membership.valid_until is null or membership.valid_until > now())
         and (
           membership.role = 'legal_reviewer'
           or exists (
             select 1
             from private.legal_reviewer_capability_grants capability
             where capability.municipality_id = membership.municipality_id
               and capability.membership_id = membership.id
               and capability.status = 'active'
               and capability.valid_from <= now()
               and (capability.valid_until is null or capability.valid_until > now())
           )
         )
     );
$$;

create or replace function private.current_legal_reviewer_membership_id(
  p_municipality_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select membership.id
  from public.municipality_memberships membership
  where (select auth.uid()) is not null
    and private.is_aal2()
    and membership.municipality_id = p_municipality_id
    and membership.user_id = (select auth.uid())
    and membership.status = 'active'
    and membership.valid_from <= now()
    and (membership.valid_until is null or membership.valid_until > now())
    and (
      membership.role = 'legal_reviewer'
      or exists (
        select 1
        from private.legal_reviewer_capability_grants capability
        where capability.municipality_id = membership.municipality_id
          and capability.membership_id = membership.id
          and capability.status = 'active'
          and capability.valid_from <= now()
          and (capability.valid_until is null or capability.valid_until > now())
      )
    )
  order by membership.valid_from desc, membership.id
  limit 1;
$$;

create or replace function public.ia_grant_legal_reviewer_capability(
  p_municipality_id uuid,
  p_target_membership_id uuid,
  p_valid_until timestamptz,
  p_reason text,
  p_confirmation text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_membership_id uuid;
  v_target public.municipality_memberships%rowtype;
  v_grant_id uuid;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation is distinct from 'CONFIRMAR REVISOR JURIDICO' then
    raise exception 'explicit legal reviewer confirmation required';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception 'capability reason must contain 10 to 1000 characters';
  end if;
  if p_valid_until is not null and p_valid_until <= now() + interval '5 minutes' then
    raise exception 'legal reviewer validity must be in the future';
  end if;

  v_actor_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array['municipal_admin']::text[]
  );
  if v_actor_membership_id is null then
    raise exception using errcode = '42501', message = 'current municipal administrator required';
  end if;

  select membership.* into strict v_target
  from public.municipality_memberships membership
  where membership.municipality_id = p_municipality_id
    and membership.id = p_target_membership_id
    and membership.status = 'active'
    and membership.valid_from <= now()
    and (membership.valid_until is null or membership.valid_until > now())
  for update;

  if v_target.user_id = auth.uid() then
    raise exception 'self-grant of legal reviewer capability is prohibited';
  end if;
  if v_target.role not in ('municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer') then
    raise exception using errcode = '42501', message = 'legal reviewer capability requires fiscal staff membership';
  end if;

  -- The target membership row is locked above, so concurrent grants for the
  -- same person serialize here.  The governed clock transition records its
  -- system event atomically before a new grant can be evaluated.
  perform private.expire_legal_reviewer_capabilities(
    500,
    p_municipality_id,
    p_target_membership_id
  );

  select capability.id into v_grant_id
  from private.legal_reviewer_capability_grants capability
  where capability.municipality_id = p_municipality_id
    and capability.membership_id = p_target_membership_id
    and capability.status = 'active';

  if v_grant_id is not null then
    raise exception 'legal reviewer capability is already active';
  end if;

  insert into private.legal_reviewer_capability_grants (
    municipality_id,
    membership_id,
    valid_until,
    granted_by_membership_id,
    reason
  ) values (
    p_municipality_id,
    p_target_membership_id,
    p_valid_until,
    v_actor_membership_id,
    trim(p_reason)
  ) returning id into v_grant_id;

  insert into private.legal_reviewer_capability_events (
    municipality_id,
    grant_id,
    event_type,
    actor_membership_id,
    reason
  ) values (
    p_municipality_id,
    v_grant_id,
    'granted',
    v_actor_membership_id,
    trim(p_reason)
  );

  return v_grant_id;
end;
$$;

-- gte-small is available in Supabase Edge Runtime and produces 384 values.
-- Keep the exact model contract beside every vector so a future re-embedding
-- can coexist safely instead of silently mixing vector spaces.
do $$
begin
  if exists (
    select 1
    from private.legal_embeddings embedding
    where embedding.dimensions <> 384
       or extensions.vector_dims(embedding.embedding) <> 384
  ) then
    raise exception 'legacy legal embeddings are not compatible with gte-small-384-v1';
  end if;
end;
$$;

alter table private.legal_embeddings
  add column model_revision text not null default 'gte-small-384-v1';

alter table private.legal_embeddings
  alter column embedding type extensions.halfvec(384)
    using embedding::extensions.halfvec(384),
  drop constraint legal_embeddings_model_uq,
  add constraint legal_embeddings_provider_ck
    check (provider_code = 'supabase_ai'),
  add constraint legal_embeddings_model_ck
    check (model = 'gte-small'),
  add constraint legal_embeddings_dimensions_v2_ck
    check (dimensions = 384),
  add constraint legal_embeddings_revision_ck
    check (model_revision = 'gte-small-384-v1'),
  add constraint legal_embeddings_model_revision_uq
    unique (
      municipality_id,
      legal_chunk_id,
      provider_code,
      model,
      model_revision
    );

create index legal_embeddings_gte_small_hnsw_idx
  on private.legal_embeddings
  using hnsw (embedding extensions.halfvec_cosine_ops)
  with (m = 16, ef_construction = 64);

create table private.legal_embedding_jobs (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  legal_chunk_id uuid not null,
  source_sha256 text not null check (source_sha256 ~ '^[a-f0-9]{64}$'),
  provider_code text not null default 'supabase_ai'
    check (provider_code = 'supabase_ai'),
  model text not null default 'gte-small'
    check (model = 'gte-small'),
  model_revision text not null default 'gte-small-384-v1'
    check (model_revision = 'gte-small-384-v1'),
  dimensions integer not null default 384 check (dimensions = 384),
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'completed', 'failed', 'dead_letter', 'skipped')),
  attempts smallint not null default 0 check (attempts between 0 and 20),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  completed_at timestamptz,
  safe_error_code text check (
    safe_error_code is null
    or safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_embedding_jobs_chunk_fk
    foreign key (municipality_id, legal_chunk_id)
    references private.legal_chunks(municipality_id, id) on delete cascade,
  constraint legal_embedding_jobs_state_ck check (
    (status = 'processing' and locked_at is not null and completed_at is null)
    or (status = 'completed' and completed_at is not null)
    or (status not in ('processing', 'completed') and locked_at is null and completed_at is null)
  ),
  constraint legal_embedding_jobs_identity_uq
    unique (municipality_id, legal_chunk_id, model_revision, source_sha256),
  constraint legal_embedding_jobs_municipality_id_id_uq
    unique (municipality_id, id)
);

create index legal_embedding_jobs_claim_idx
  on private.legal_embedding_jobs (available_at, created_at, id)
  where status in ('queued', 'failed');

create index legal_embedding_jobs_tenant_claim_idx
  on private.legal_embedding_jobs (
    municipality_id,
    available_at,
    created_at,
    id
  )
  where status in ('queued', 'failed');

-- Claims are intentionally serialized per model revision through this tiny
-- cursor row.  Persisting the last served tenant makes round-robin fairness
-- survive worker restarts and batch boundaries instead of starting every
-- batch at the lexicographically first municipality.
create table private.legal_embedding_claim_cursors (
  model_revision text primary key
    check (model_revision = 'gte-small-384-v1'),
  last_municipality_id uuid
    references public.municipalities(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into private.legal_embedding_claim_cursors (
  model_revision,
  last_municipality_id
) values (
  'gte-small-384-v1',
  null
) on conflict (model_revision) do nothing;

create table private.legal_embedding_job_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  job_id uuid not null,
  event_type text not null
    check (event_type in ('queued', 'claimed', 'retried', 'completed', 'dead_lettered', 'skipped')),
  attempt smallint not null check (attempt between 0 and 20),
  safe_error_code text check (
    safe_error_code is null
    or safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  constraint legal_embedding_job_events_job_fk
    foreign key (municipality_id, job_id)
    references private.legal_embedding_jobs(municipality_id, id)
);

create or replace function private.enqueue_legal_embedding_job()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id uuid;
  v_status text;
begin
  v_status := case
    when char_length(new.content_text) between 80 and 8000 then 'queued'
    else 'skipped'
  end;

  insert into private.legal_embedding_jobs (
    municipality_id,
    legal_chunk_id,
    source_sha256,
    status,
    safe_error_code
  ) values (
    new.municipality_id,
    new.id,
    new.content_sha256,
    v_status,
    case when v_status = 'skipped' then 'chunk_length_out_of_bounds' end
  )
  on conflict (
    municipality_id,
    legal_chunk_id,
    model_revision,
    source_sha256
  ) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    insert into private.legal_embedding_job_events as job_event (
      municipality_id,
      job_id,
      event_type,
      attempt,
      safe_error_code
    ) values (
      new.municipality_id,
      v_job_id,
      case when v_status = 'queued' then 'queued' else 'skipped' end,
      0,
      case when v_status = 'skipped' then 'chunk_length_out_of_bounds' end
    );
  end if;
  return new;
end;
$$;

create trigger legal_chunks_enqueue_embedding
after insert on private.legal_chunks
for each row execute function private.enqueue_legal_embedding_job();

-- Phase 1 captured a candidate and immediately staged a coarse section inside
-- ia_fiscal_capture_knowledge_source.  Calling the richer section RPC from the
-- Edge afterwards therefore created two independently committed staging
-- attempts.  Keep that published contract available for legacy callers, but
-- interpose a transaction-local deferral used only by the atomic v2 RPC below.
alter function public.ia_fiscal_stage_knowledge_sections(uuid, jsonb)
  rename to ia_fiscal_stage_knowledge_sections_legacy_impl;

create or replace function public.ia_fiscal_stage_knowledge_sections(
  p_change_set_id uuid,
  p_sections jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;

  if current_setting('ia_fiscal.knowledge_staging_mode', true)
       = 'defer-for-capture-v2' then
    return jsonb_build_object(
      'change_set_id', p_change_set_id,
      'status', 'deferred',
      'section_count', 0,
      'chunk_count', 0
    );
  end if;

  return public.ia_fiscal_stage_knowledge_sections_legacy_impl(
    p_change_set_id,
    p_sections
  );
end;
$$;

-- Force every pooled session to recompile the Phase-1 capture body after the
-- staging function was interposed.  Otherwise a pre-migration PL/pgSQL plan
-- could retain the renamed implementation OID and bypass the v2 deferral.
alter function public.ia_fiscal_capture_knowledge_source(
  uuid, text, text, text, text, bigint, text, text, text,
  text, text, integer, timestamptz, uuid, jsonb
) set search_path = '';

create or replace function private.knowledge_staging_matches_payload(
  p_candidate_version_id uuid,
  p_sections jsonb
)
returns boolean
language sql
stable
set search_path = ''
as $$
  with candidate as (
    select version.id, version.municipality_id
    from public.legal_source_versions version
    where version.id = p_candidate_version_id
  ),
  expected_sections as (
    select
      candidate.municipality_id,
      candidate.id as source_version_id,
      input.section ->> 'section_key' as section_key,
      nullif(trim(coalesce(input.section ->> 'heading', '')), '') as heading,
      (input.section ->> 'ordinal')::integer as ordinal,
      input.section ->> 'content_text' as content_text,
      encode(
        extensions.digest(input.section ->> 'content_text', 'sha256'),
        'hex'
      ) as content_sha256,
      input.section
    from candidate
    cross join lateral jsonb_array_elements(p_sections) input(section)
  ),
  expected_chunks as (
    select
      section.municipality_id,
      section.source_version_id,
      section.section_key,
      chunk.ordinality::integer - 1 as chunk_index,
      chunk.value ->> 'content_text' as content_text,
      encode(
        extensions.digest(chunk.value ->> 'content_text', 'sha256'),
        'hex'
      ) as content_sha256,
      coalesce(
        nullif(chunk.value ->> 'token_count', '')::integer,
        greatest(
          1,
          array_length(regexp_split_to_array(
            trim(chunk.value ->> 'content_text'), E'\\s+'
          ), 1)
        )
      ) as token_count
    from expected_sections section
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(section.section -> 'chunks') = 'array'
             and jsonb_array_length(section.section -> 'chunks') > 0
          then section.section -> 'chunks'
        else jsonb_build_array(jsonb_build_object(
          'content_text', section.content_text
        ))
      end
    ) with ordinality chunk(value, ordinality)
  ),
  actual_sections as (
    select section.*
    from public.legal_sections section
    join candidate
      on candidate.municipality_id = section.municipality_id
     and candidate.id = section.source_version_id
  ),
  actual_chunks as (
    select
      section.municipality_id,
      section.source_version_id,
      section.section_key,
      chunk.chunk_index,
      chunk.content_text,
      chunk.content_sha256,
      chunk.token_count
    from actual_sections section
    join private.legal_chunks chunk
      on chunk.municipality_id = section.municipality_id
     and chunk.legal_section_id = section.id
  )
  select
    (select count(*) from candidate) = 1
    and (select count(*) from actual_sections)
      = (select count(*) from expected_sections)
    and (select count(*) from actual_chunks)
      = (select count(*) from expected_chunks)
    and not exists (
      select 1
      from expected_sections expected
      left join actual_sections actual
        on actual.municipality_id = expected.municipality_id
       and actual.source_version_id = expected.source_version_id
       and actual.section_key = expected.section_key
       and actual.heading is not distinct from expected.heading
       and actual.ordinal = expected.ordinal
       and actual.content_text = expected.content_text
       and actual.content_sha256 = expected.content_sha256
      where actual.id is null
    )
    and not exists (
      select 1
      from expected_chunks expected
      left join actual_chunks actual
        on actual.municipality_id = expected.municipality_id
       and actual.source_version_id = expected.source_version_id
       and actual.section_key = expected.section_key
       and actual.chunk_index = expected.chunk_index
       and actual.content_text = expected.content_text
       and actual.content_sha256 = expected.content_sha256
       and actual.token_count = expected.token_count
      where actual.source_version_id is null
    );
$$;

create or replace function public.ia_fiscal_capture_knowledge_source_v2(
  p_source_id uuid,
  p_requested_url text,
  p_final_url text,
  p_content_sha256 text,
  p_mime_type text,
  p_byte_size bigint,
  p_storage_bucket text,
  p_storage_path text,
  p_extracted_text text,
  p_sections jsonb,
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
  v_capture jsonb;
  v_stage jsonb;
  v_change_set_id uuid;
  v_candidate_version_id uuid;
  v_stage_status text := 'not_applicable';
  v_section_count integer := 0;
  v_chunk_count integer := 0;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;

  if nullif(trim(coalesce(p_extracted_text, '')), '') is null then
    if p_sections is not null then
      raise exception 'raw capture cannot submit staged sections';
    end if;
  else
    if p_sections is null
       or jsonb_typeof(p_sections) <> 'array'
       or jsonb_array_length(p_sections) <> 1
       or coalesce(jsonb_typeof(p_sections -> 0), 'null') <> 'object'
       or p_sections -> 0 ->> 'section_key' <> 'integral'
       or coalesce(p_sections -> 0 ->> 'content_text', '') <> p_extracted_text
       or coalesce(p_sections -> 0 ->> 'ordinal', '') <> '1'
       or coalesce(jsonb_typeof(p_sections -> 0 -> 'chunks'), 'null') <> 'array'
       or jsonb_array_length(p_sections -> 0 -> 'chunks') > 5000
       or exists (
         select 1
         from jsonb_array_elements(p_sections -> 0 -> 'chunks')
           with ordinality input(chunk, ordinality)
         where jsonb_typeof(input.chunk) <> 'object'
            or char_length(coalesce(input.chunk ->> 'content_text', '')) not between 1 and 8000
            or position(
              coalesce(input.chunk ->> 'content_text', '') in p_extracted_text
            ) = 0
            or coalesce(input.chunk ->> 'chunk_index', '') <> input.ordinality::text
            or coalesce(input.chunk ->> 'token_count', '') !~ '^[1-9][0-9]*$'
       ) then
      raise exception 'one bounded integral section exactly derived from extraction is required';
    end if;
  end if;

  perform set_config(
    'ia_fiscal.knowledge_staging_mode',
    'defer-for-capture-v2',
    true
  );
  v_capture := public.ia_fiscal_capture_knowledge_source(
    p_source_id,
    p_requested_url,
    p_final_url,
    p_content_sha256,
    p_mime_type,
    p_byte_size,
    p_storage_bucket,
    p_storage_path,
    p_extracted_text,
    p_etag,
    p_last_modified,
    p_http_status,
    p_observed_at,
    p_correlation_id,
    p_metadata
  );
  perform set_config('ia_fiscal.knowledge_staging_mode', 'off', true);

  begin
    v_change_set_id := nullif(v_capture ->> 'change_set_id', '')::uuid;
    v_candidate_version_id := nullif(v_capture ->> 'candidate_version_id', '')::uuid;
  exception when others then
    raise exception 'capture v2 received an invalid staging identity';
  end;

  if (v_change_set_id is null) <> (v_candidate_version_id is null) then
    raise exception 'capture v2 received an incomplete staging identity';
  end if;
  if v_candidate_version_id is not null then
    if p_sections is null then
      raise exception 'capture v2 candidate is missing its integral evidence';
    end if;
    v_stage := public.ia_fiscal_stage_knowledge_sections_legacy_impl(
      v_change_set_id,
      p_sections
    );
    if not private.knowledge_staging_matches_payload(
      v_candidate_version_id,
      p_sections
    ) then
      raise exception 'staged evidence does not exactly match the capture v2 payload';
    end if;
    begin
      v_stage_status := v_stage ->> 'status';
      v_section_count := (v_stage ->> 'section_count')::integer;
      v_chunk_count := (v_stage ->> 'chunk_count')::integer;
    exception when others then
      raise exception 'capture v2 received an invalid staging result';
    end;
    if v_stage_status not in ('staged', 'already_staged')
       or v_section_count <> 1
       or v_chunk_count < 1 then
      raise exception 'capture v2 staging result is incomplete';
    end if;
  end if;

  return v_capture || jsonb_build_object(
    'staging_status', v_stage_status,
    'staged_sections', v_section_count,
    'staged_chunks', v_chunk_count
  );
end;
$$;

create or replace function public.ia_fiscal_stage_knowledge_chunks(
  p_candidate_version_id uuid,
  p_chunks jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.legal_source_versions%rowtype;
  v_change private.legal_source_change_sets%rowtype;
  v_section public.legal_sections%rowtype;
  v_chunk jsonb;
  v_chunk_index integer;
  v_content text;
  v_sha text;
  v_token_count integer;
  v_inserted integer := 0;
  v_existing private.legal_chunks%rowtype;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_chunks is null
     or jsonb_typeof(p_chunks) <> 'array'
     or jsonb_array_length(p_chunks) not between 1 and 5000 then
    raise exception 'chunks must be a JSON array containing 1 to 5000 entries';
  end if;

  select version.* into strict v_version
  from public.legal_source_versions version
  where version.id = p_candidate_version_id
  for update;
  if v_version.status <> 'under_review' then
    raise exception 'candidate version is not open for chunk staging';
  end if;

  select change_set.* into strict v_change
  from private.legal_source_change_sets change_set
  where change_set.municipality_id = v_version.municipality_id
    and change_set.candidate_version_id = v_version.id
    and change_set.status in ('detected', 'changes_requested')
    and change_set.change_type <> 'legacy_import'
  order by change_set.detected_at desc, change_set.id desc
  limit 1;

  select section.* into strict v_section
  from public.legal_sections section
  where section.municipality_id = v_version.municipality_id
    and section.source_version_id = v_version.id
    and section.content_sha256 = v_version.content_sha256
    and section.content_text = v_version.content_text
  order by section.ordinal, section.id
  limit 1;

  for v_chunk in select value from jsonb_array_elements(p_chunks)
  loop
    if jsonb_typeof(v_chunk) <> 'object' then
      raise exception 'every chunk must be a JSON object';
    end if;
    begin
      v_chunk_index := (v_chunk ->> 'chunk_index')::integer;
      v_token_count := nullif(v_chunk ->> 'token_count', '')::integer;
    exception when others then
      raise exception 'chunk index and token count must be integers';
    end;
    v_content := coalesce(v_chunk ->> 'content_text', '');
    if v_chunk_index not between 1 and 5000
       or char_length(v_content) not between 1 and 8000
       or position(v_content in v_section.content_text) = 0 then
      raise exception 'chunk is outside the bounded candidate evidence';
    end if;
    v_sha := encode(extensions.digest(v_content, 'sha256'), 'hex');

    select chunk.* into v_existing
    from private.legal_chunks chunk
    where chunk.municipality_id = v_section.municipality_id
      and chunk.legal_section_id = v_section.id
      and chunk.chunk_index = v_chunk_index;
    if found then
      if v_existing.content_sha256 <> v_sha or v_existing.content_text <> v_content then
        raise exception 'chunk index was already staged with different evidence';
      end if;
      continue;
    end if;

    insert into private.legal_chunks (
      municipality_id,
      legal_section_id,
      chunk_index,
      content_text,
      token_count,
      content_sha256
    ) values (
      v_section.municipality_id,
      v_section.id,
      v_chunk_index,
      v_content,
      coalesce(v_token_count, greatest(
        1,
        array_length(regexp_split_to_array(trim(v_content), E'\\s+'), 1)
      )),
      v_sha
    );
    v_inserted := v_inserted + 1;
  end loop;

  return jsonb_build_object(
    'candidate_version_id', v_version.id,
    'change_set_id', v_change.id,
    'inserted_chunks', v_inserted,
    'total_chunks', (
      select count(*)
      from private.legal_chunks chunk
      where chunk.municipality_id = v_section.municipality_id
        and chunk.legal_section_id = v_section.id
    )
  );
end;
$$;

create or replace function public.ia_fiscal_claim_legal_embedding_jobs(
  p_batch_size integer default 16
)
returns table (
  job_id uuid,
  municipality_id uuid,
  legal_chunk_id uuid,
  content_text text,
  source_sha256 text,
  attempt smallint,
  provider_code text,
  model text,
  model_revision text,
  dimensions integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_runtime_gate_id uuid;
  v_last_municipality_id uuid;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_batch_size not between 1 and 32 then
    raise exception 'embedding batch size must be between 1 and 32';
  end if;

  -- Fail closed before recovering a lease or claiming any work.  The key-share
  -- locks retained by this helper also serialize a concurrent gate revocation
  -- behind this short claim transaction.
  v_runtime_gate_id := private.lock_current_knowledge_runtime_gate_id();
  if v_runtime_gate_id is null then
    raise exception using
      errcode = '55000',
      message = 'knowledge runtime is not verified';
  end if;

  select cursor.last_municipality_id into strict v_last_municipality_id
  from private.legal_embedding_claim_cursors cursor
  where cursor.model_revision = 'gte-small-384-v1'
  for update;

  -- A worker can disappear after claiming. Recover expired leases before the
  -- next claim so no chunk remains in `processing` forever.
  with stale as (
    update private.legal_embedding_jobs job
    set status = case when job.attempts >= 5 then 'dead_letter' else 'failed' end,
        available_at = now(),
        locked_at = null,
        safe_error_code = 'embedding_lease_expired',
        updated_at = now()
    where job.status = 'processing'
      and job.locked_at < now() - interval '10 minutes'
      and exists (
        select 1
        from private.knowledge_automation_settings setting
        where setting.municipality_id = job.municipality_id
          and setting.enabled
      )
    returning job.*
  )
  insert into private.legal_embedding_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    safe_error_code
  )
  select
    stale.municipality_id,
    stale.id,
    case when stale.status = 'dead_letter' then 'dead_lettered' else 'retried' end,
    stale.attempts,
    'embedding_lease_expired'
  from stale;

  return query
  with ranked as materialized (
    select
      job.id,
      job.municipality_id,
      job.available_at,
      job.created_at,
      row_number() over (
        partition by job.municipality_id
        order by job.available_at, job.created_at, job.id
      ) as tenant_rank
    from private.legal_embedding_jobs job
    join private.knowledge_automation_settings setting
      on setting.municipality_id = job.municipality_id
     and setting.enabled
    where job.status in ('queued', 'failed')
      and job.available_at <= now()
  ), candidates as materialized (
    select
      job.id,
      ranked.municipality_id,
      ranked.tenant_rank,
      case
        when v_last_municipality_id is null
          or ranked.municipality_id > v_last_municipality_id then 0
        else 1
      end as tenant_wrap,
      ranked.available_at,
      ranked.created_at
    from private.legal_embedding_jobs job
    join ranked on ranked.id = job.id
    order by
      ranked.tenant_rank,
      case
        when v_last_municipality_id is null
          or ranked.municipality_id > v_last_municipality_id then 0
        else 1
      end,
      ranked.municipality_id,
      ranked.available_at,
      ranked.created_at,
      ranked.id
    for update of job skip locked
    limit p_batch_size
  ), claimed as (
    update private.legal_embedding_jobs job
    set status = 'processing',
        attempts = job.attempts + 1,
        locked_at = now(),
        safe_error_code = null,
        updated_at = now()
    from candidates
    where job.id = candidates.id
    returning job.*
  ), events as (
    insert into private.legal_embedding_job_events as claimed_event (
      municipality_id,
      job_id,
      event_type,
      attempt
    )
    select claimed.municipality_id, claimed.id, 'claimed', claimed.attempts
    from claimed
    returning claimed_event.job_id
  ), cursor_advanced as (
    update private.legal_embedding_claim_cursors cursor
    set last_municipality_id = (
          select candidate.municipality_id
          from candidates candidate
          order by
            candidate.tenant_rank desc,
            candidate.tenant_wrap desc,
            candidate.municipality_id desc,
            candidate.available_at desc,
            candidate.created_at desc,
            candidate.id desc
          limit 1
        ),
        updated_at = now()
    where cursor.model_revision = 'gte-small-384-v1'
      and exists (select 1 from candidates)
    returning cursor.model_revision
  )
  select
    claimed.id,
    claimed.municipality_id,
    claimed.legal_chunk_id,
    chunk.content_text,
    claimed.source_sha256,
    claimed.attempts,
    claimed.provider_code,
    claimed.model,
    claimed.model_revision,
    claimed.dimensions
  from claimed
  join private.legal_chunks chunk
    on chunk.municipality_id = claimed.municipality_id
   and chunk.id = claimed.legal_chunk_id
  join candidates candidate on candidate.id = claimed.id
  join events on events.job_id = claimed.id
  cross join cursor_advanced
  where chunk.content_sha256 = claimed.source_sha256;
end;
$$;

create or replace function public.ia_fiscal_complete_legal_embedding_job(
  p_job_id uuid,
  p_embedding text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.legal_embedding_jobs%rowtype;
  v_embedding extensions.halfvec(384);
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  select job.* into strict v_job
  from private.legal_embedding_jobs job
  where job.id = p_job_id
  for update;
  if v_job.status <> 'processing' then
    raise exception 'embedding job is not processing';
  end if;
  if not exists (
    select 1 from private.legal_chunks chunk
    where chunk.municipality_id = v_job.municipality_id
      and chunk.id = v_job.legal_chunk_id
      and chunk.content_sha256 = v_job.source_sha256
  ) then
    raise exception 'embedding job source hash changed';
  end if;

  begin
    v_embedding := p_embedding::extensions.halfvec(384);
  exception when others then
    raise exception 'invalid 384-dimensional embedding';
  end;
  if extensions.vector_dims(v_embedding) <> 384 then
    raise exception 'invalid embedding dimensions';
  end if;

  insert into private.legal_embeddings (
    municipality_id,
    legal_chunk_id,
    provider_code,
    model,
    model_revision,
    dimensions,
    embedding,
    source_sha256
  ) values (
    v_job.municipality_id,
    v_job.legal_chunk_id,
    v_job.provider_code,
    v_job.model,
    v_job.model_revision,
    v_job.dimensions,
    v_embedding,
    v_job.source_sha256
  )
  on conflict (
    municipality_id,
    legal_chunk_id,
    provider_code,
    model,
    model_revision
  ) do update set
    embedding = excluded.embedding,
    source_sha256 = excluded.source_sha256,
    created_at = now();

  update private.legal_embedding_jobs
  set status = 'completed',
      locked_at = null,
      completed_at = now(),
      safe_error_code = null,
      updated_at = now()
  where id = v_job.id;

  insert into private.legal_embedding_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt
  ) values (v_job.municipality_id, v_job.id, 'completed', v_job.attempts);
end;
$$;

create or replace function public.ia_fiscal_fail_legal_embedding_job(
  p_job_id uuid,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.legal_embedding_jobs%rowtype;
  v_error_code text := lower(trim(coalesce(p_error_code, '')));
  v_dead boolean;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if v_error_code !~ '^[a-z0-9][a-z0-9_.:-]{1,119}$' then
    raise exception 'invalid safe error code';
  end if;
  select job.* into strict v_job
  from private.legal_embedding_jobs job
  where job.id = p_job_id
  for update;
  if v_job.status <> 'processing' then
    raise exception 'embedding job is not processing';
  end if;
  v_dead := v_job.attempts >= 5;

  update private.legal_embedding_jobs
  set status = case when v_dead then 'dead_letter' else 'failed' end,
      available_at = case when v_dead then available_at else
        now() + make_interval(mins => least(240, power(2, v_job.attempts)::integer))
      end,
      locked_at = null,
      safe_error_code = v_error_code,
      updated_at = now()
  where id = v_job.id;

  insert into private.legal_embedding_job_events (
    municipality_id,
    job_id,
    event_type,
    attempt,
    safe_error_code
  ) values (
    v_job.municipality_id,
    v_job.id,
    case when v_dead then 'dead_lettered' else 'retried' end,
    v_job.attempts,
    v_error_code
  );
end;
$$;

create or replace function public.ia_revoke_legal_reviewer_capability(
  p_grant_id uuid,
  p_reason text,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant private.legal_reviewer_capability_grants%rowtype;
  v_actor_membership_id uuid;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> 'REVOGAR REVISOR JURIDICO' then
    raise exception 'explicit legal reviewer revocation confirmation required';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception 'revocation reason must contain 10 to 1000 characters';
  end if;

  select capability.* into strict v_grant
  from private.legal_reviewer_capability_grants capability
  where capability.id = p_grant_id
  for update;

  v_actor_membership_id := private.current_municipality_membership_id(
    v_grant.municipality_id,
    array['municipal_admin']::text[]
  );
  if v_actor_membership_id is null then
    raise exception using errcode = '42501', message = 'current municipal administrator required';
  end if;
  if v_grant.status <> 'active' then
    raise exception 'legal reviewer capability is not active';
  end if;

  update private.legal_reviewer_capability_grants
  set status = 'revoked',
      revoked_by_membership_id = v_actor_membership_id,
      revoked_at = now(),
      revocation_reason = trim(p_reason),
      updated_at = now()
  where id = v_grant.id;

  insert into private.legal_reviewer_capability_events (
    municipality_id,
    grant_id,
    event_type,
    actor_membership_id,
    reason
  ) values (
    v_grant.municipality_id,
    v_grant.id,
    'revoked',
    v_actor_membership_id,
    trim(p_reason)
  );
end;
$$;

-- Learning candidates are explicitly non-canonical.  Approval records that a
create or replace function public.ia_list_legal_reviewer_capabilities(
  p_municipality_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_membership_id uuid;
  v_active jsonb;
  v_eligible jsonb;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  v_admin_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array['municipal_admin']::text[]
  );
  if v_admin_membership_id is null then
    raise exception using errcode = '42501', message = 'current municipal administrator required';
  end if;

  perform private.expire_legal_reviewer_capabilities(
    500,
    p_municipality_id,
    null
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'grant_id', capability.id,
    'membership_id', capability.membership_id,
    'role', membership.role,
    'status', capability.status,
    'valid_from', capability.valid_from,
    'valid_until', capability.valid_until,
    'is_current', capability.status = 'active'
      and capability.valid_from <= now()
      and (capability.valid_until is null or capability.valid_until > now())
  ) order by capability.created_at desc, capability.id), '[]'::jsonb)
    into v_active
  from private.legal_reviewer_capability_grants capability
  join public.municipality_memberships membership
    on membership.municipality_id = capability.municipality_id
   and membership.id = capability.membership_id
  where capability.municipality_id = p_municipality_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'membership_id', membership.id,
    'role', membership.role,
    'already_configured', exists (
      select 1 from private.legal_reviewer_capability_grants capability
      where capability.municipality_id = membership.municipality_id
        and capability.membership_id = membership.id
        and capability.status = 'active'
        and capability.valid_from <= now()
        and (capability.valid_until is null or capability.valid_until > now())
    )
  ) order by membership.valid_from desc, membership.id), '[]'::jsonb)
    into v_eligible
  from public.municipality_memberships membership
  where membership.municipality_id = p_municipality_id
    and membership.id <> v_admin_membership_id
    and membership.status = 'active'
    and membership.valid_from <= now()
    and (membership.valid_until is null or membership.valid_until > now())
    and membership.role in ('municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer');

  return jsonb_build_object(
    'verified', true,
    'municipality_id', p_municipality_id,
    'active_grants', v_active,
    'eligible_staff', v_eligible,
    'pii_exposed', false,
    'checked_at', now()
  );
end;
$$;

-- Learning candidates are explicitly non-canonical.  Approval records that a
-- qualified human considered the proposal useful; it never publishes or
-- promotes the text into the reusable knowledge base.
create table private.knowledge_candidate_submissions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  submitted_by_membership_id uuid not null,
  question text not null check (char_length(trim(question)) between 5 and 1000),
  proposed_answer text not null
    check (char_length(trim(proposed_answer)) between 10 and 20000),
  citation_section_ids uuid[] not null
    check (cardinality(citation_section_ids) between 1 and 20),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'pending_review'
    check (status in ('pending_review', 'approved', 'rejected')),
  reviewed_by_membership_id uuid,
  review_notes text check (review_notes is null or char_length(review_notes) <= 4000),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint knowledge_candidate_submitter_fk
    foreign key (municipality_id, submitted_by_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint knowledge_candidate_reviewer_fk
    foreign key (municipality_id, reviewed_by_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint knowledge_candidate_review_state_ck check (
    (status = 'pending_review' and reviewed_by_membership_id is null and reviewed_at is null)
    or (status in ('approved', 'rejected') and reviewed_by_membership_id is not null and reviewed_at is not null)
  ),
  constraint knowledge_candidate_no_self_review_ck check (
    reviewed_by_membership_id is null
    or reviewed_by_membership_id <> submitted_by_membership_id
  ),
  constraint knowledge_candidate_idempotency_uq
    unique (municipality_id, submitted_by_membership_id, content_sha256),
  constraint knowledge_candidate_municipality_id_id_uq
    unique (municipality_id, id)
);

create index knowledge_candidate_pending_idx
  on private.knowledge_candidate_submissions (municipality_id, created_at, id)
  where status = 'pending_review';

create table private.knowledge_candidate_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  candidate_id uuid not null,
  event_type text not null check (event_type in ('submitted', 'approved', 'rejected')),
  actor_membership_id uuid not null,
  event_at timestamptz not null default now(),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  constraint knowledge_candidate_events_candidate_fk
    foreign key (municipality_id, candidate_id)
    references private.knowledge_candidate_submissions(municipality_id, id),
  constraint knowledge_candidate_events_actor_fk
    foreign key (municipality_id, actor_membership_id)
    references public.municipality_memberships(municipality_id, id)
);

create or replace function public.ia_submit_knowledge_candidate(
  p_municipality_id uuid,
  p_question text,
  p_proposed_answer text,
  p_citation_section_ids uuid[],
  p_confirmation text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership_id uuid;
  v_question text := trim(coalesce(p_question, ''));
  v_answer text := trim(coalesce(p_proposed_answer, ''));
  v_citations uuid[];
  v_content_sha256 text;
  v_candidate_id uuid;
  v_created boolean := false;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> 'ENVIAR PARA REVISÃO' then
    raise exception 'explicit candidate submission confirmation required';
  end if;
  if char_length(v_question) not between 5 and 1000
     or char_length(v_answer) not between 10 and 20000 then
    raise exception 'candidate text exceeds the bounded contract';
  end if;
  if p_citation_section_ids is null
     or cardinality(p_citation_section_ids) not between 1 and 20 then
    raise exception 'one to twenty legal citations are required';
  end if;

  v_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'municipality staff access required';
  end if;
  v_business_date := private.municipality_current_date(p_municipality_id);

  select array_agg(distinct citation_id order by citation_id)
    into v_citations
  from unnest(p_citation_section_ids) citation_id;
  if cardinality(v_citations) <> cardinality(p_citation_section_ids) then
    raise exception 'duplicate citation section ids are not allowed';
  end if;
  if (
    select count(*)
    from unnest(v_citations) citation_id
    join public.legal_sections section
      on section.municipality_id = p_municipality_id
     and section.id = citation_id
    join public.legal_source_versions version
      on version.municipality_id = section.municipality_id
     and version.id = section.source_version_id
    join public.legal_sources source
      on source.municipality_id = version.municipality_id
     and source.id = version.source_id
    where source.status = 'active'
      and source.official_url ~ '^https://[^[:space:]]+$'
      and version.status = 'published'
      and version.publication_date is not null
      and version.publication_date <= v_business_date
      and version.valid_from is not null
      and version.valid_from <= v_business_date
      and (version.valid_until is null or version.valid_until >= v_business_date)
      and private.legal_version_has_complete_evidence(version.municipality_id, version.id)
  ) <> cardinality(v_citations) then
    raise exception 'all citations must be current, official, published tenant evidence';
  end if;

  v_content_sha256 := encode(extensions.digest(
    v_question || E'\\x1f' || v_answer || E'\\x1f' || array_to_string(v_citations, ','),
    'sha256'
  ), 'hex');

  insert into private.knowledge_candidate_submissions (
    municipality_id,
    submitted_by_membership_id,
    question,
    proposed_answer,
    citation_section_ids,
    content_sha256
  ) values (
    p_municipality_id,
    v_membership_id,
    v_question,
    v_answer,
    v_citations,
    v_content_sha256
  )
  on conflict (municipality_id, submitted_by_membership_id, content_sha256)
  do nothing
  returning id into v_candidate_id;

  if v_candidate_id is not null then
    v_created := true;
  else
    select candidate.id into strict v_candidate_id
    from private.knowledge_candidate_submissions candidate
    where candidate.municipality_id = p_municipality_id
      and candidate.submitted_by_membership_id = v_membership_id
      and candidate.content_sha256 = v_content_sha256;
  end if;

  if v_created then
    insert into private.knowledge_candidate_events (
      municipality_id,
      candidate_id,
      event_type,
      actor_membership_id,
      content_sha256,
      metadata
    ) values (
      p_municipality_id,
      v_candidate_id,
      'submitted',
      v_membership_id,
      v_content_sha256,
      jsonb_build_object('citation_count', cardinality(v_citations))
    );
  end if;
  return v_candidate_id;
end;
$$;

create or replace function public.ia_get_knowledge_candidate_evidence(
  p_municipality_id uuid,
  p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership_id uuid;
  v_candidate private.knowledge_candidate_submissions%rowtype;
  v_citations jsonb;
  v_invalid_count integer;
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
  select candidate.* into strict v_candidate
  from private.knowledge_candidate_submissions candidate
  where candidate.municipality_id = p_municipality_id
    and candidate.id = p_candidate_id;
  v_business_date := private.municipality_current_date(p_municipality_id);

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'legal_section_id', evidence.section_id,
      'source_version_id', evidence.source_version_id,
      'source_title', evidence.source_title,
      'official_identifier', evidence.official_identifier,
      'official_url', evidence.official_url,
      'section_key', evidence.section_key,
      'heading', evidence.heading,
      'excerpt', left(evidence.content_text, 2000),
      'publication_date', evidence.publication_date,
      'valid_from', evidence.valid_from,
      'valid_until', evidence.valid_until,
      'is_valid', cardinality(evidence.blockers) = 0,
      'blockers', to_jsonb(evidence.blockers)
    ) order by evidence.source_title, evidence.section_key), '[]'::jsonb),
    count(*) filter (where cardinality(evidence.blockers) > 0)::integer
  into v_citations, v_invalid_count
  from (
    select
      section.id as section_id,
      section.section_key,
      section.heading,
      section.content_text,
      version.id as source_version_id,
      version.publication_date,
      version.valid_from,
      version.valid_until,
      source.title as source_title,
      source.official_identifier,
      source.official_url,
      array_remove(array[
        case when source.status <> 'active'
                    or source.official_url is null
                    or source.official_url !~ '^https://[^[:space:]]+$'
          then 'source_not_official' end,
        case when version.status <> 'published'
                    or version.publication_date is null
                    or version.publication_date > v_business_date
          then 'source_not_published' end,
        case when version.valid_from is null
                    or version.valid_from > v_business_date
                    or (version.valid_until is not null and version.valid_until < v_business_date)
          then 'expired_source' end,
        case when not private.legal_version_has_complete_evidence(
          version.municipality_id,
          version.id
        ) then 'collection_not_verified' end
      ]::text[], null) as blockers
    from unnest(v_candidate.citation_section_ids) citation_id
    join public.legal_sections section
      on section.municipality_id = v_candidate.municipality_id
     and section.id = citation_id
    join public.legal_source_versions version
      on version.municipality_id = section.municipality_id
     and version.id = section.source_version_id
    join public.legal_sources source
      on source.municipality_id = version.municipality_id
     and source.id = version.source_id
  ) evidence;

  return jsonb_build_object(
    'verified', true,
    'checked_at', now(),
    'municipality_id', v_candidate.municipality_id,
    'candidate_id', v_candidate.id,
    'question', v_candidate.question,
    'proposed_answer', v_candidate.proposed_answer,
    'content_sha256', v_candidate.content_sha256,
    'status', v_candidate.status,
    'submitted_at', v_candidate.created_at,
    'reviewed_at', v_candidate.reviewed_at,
    'citations', v_citations,
    'evidence_complete', coalesce(v_invalid_count, 0) = 0,
    'blockers', to_jsonb(array_remove(array[
      case when coalesce(v_invalid_count, 0) > 0 then 'citation_not_current' end,
      case when v_candidate.status = 'pending_review' then 'candidate_not_reviewed' end
    ]::text[], null)),
    'can_review', (
      private.has_legal_reviewer_capability(v_candidate.municipality_id)
      and v_candidate.status = 'pending_review'
      and v_candidate.submitted_by_membership_id <> v_membership_id
      and coalesce(v_invalid_count, 0) = 0
    ),
    'can_publish', false
  );
end;
$$;

-- The public contract returns UUID.  Event ids are bigint, so reviews need a
-- stable UUID identity of their own instead of an unsafe cast.
alter table private.knowledge_candidate_events
  add column event_uuid uuid not null default gen_random_uuid();
alter table private.knowledge_candidate_events
  add constraint knowledge_candidate_events_event_uuid_uq unique (event_uuid);

create or replace function public.ia_review_knowledge_candidate(
  p_candidate_id uuid,
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
  v_candidate private.knowledge_candidate_submissions%rowtype;
  v_reviewer_membership_id uuid;
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_event_uuid uuid;
  v_business_date date;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> 'REVISAR CANDIDATO' then
    raise exception 'explicit candidate review confirmation required';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'candidate decision must be approved or rejected';
  end if;
  if char_length(coalesce(v_notes, '')) > 4000
     or (p_decision = 'rejected' and char_length(coalesce(v_notes, '')) < 10) then
    raise exception 'review notes do not satisfy the bounded contract';
  end if;
  select candidate.* into strict v_candidate
  from private.knowledge_candidate_submissions candidate
  where candidate.id = p_candidate_id
  for update;
  if v_candidate.status <> 'pending_review' then
    raise exception 'candidate is not awaiting review';
  end if;
  v_reviewer_membership_id := private.current_legal_reviewer_membership_id(
    v_candidate.municipality_id
  );
  if v_reviewer_membership_id is null then
    raise exception using errcode = '42501', message = 'current legal reviewer capability required';
  end if;
  if v_reviewer_membership_id = v_candidate.submitted_by_membership_id then
    raise exception 'candidate self-review is prohibited';
  end if;
  v_business_date := private.municipality_current_date(v_candidate.municipality_id);
  if p_decision = 'approved' and exists (
    select 1
    from unnest(v_candidate.citation_section_ids) citation_id
    left join public.legal_sections section
      on section.municipality_id = v_candidate.municipality_id and section.id = citation_id
    left join public.legal_source_versions version
      on version.municipality_id = section.municipality_id and version.id = section.source_version_id
    left join public.legal_sources source
      on source.municipality_id = version.municipality_id and source.id = version.source_id
    where section.id is null
       or source.status <> 'active'
       or source.official_url is null
       or source.official_url !~ '^https://[^[:space:]]+$'
       or version.status <> 'published'
       or version.publication_date is null
       or version.publication_date > v_business_date
       or version.valid_from is null
       or version.valid_from > v_business_date
       or (version.valid_until is not null and version.valid_until < v_business_date)
       or not private.legal_version_has_complete_evidence(version.municipality_id, version.id)
  ) then
    raise exception 'candidate citations are no longer current and verifiable';
  end if;
  update private.knowledge_candidate_submissions
  set status = p_decision,
      reviewed_by_membership_id = v_reviewer_membership_id,
      review_notes = v_notes,
      reviewed_at = now(),
      updated_at = now()
  where id = v_candidate.id;
  insert into private.knowledge_candidate_events (
    municipality_id, candidate_id, event_type, actor_membership_id,
    content_sha256, metadata
  ) values (
    v_candidate.municipality_id, v_candidate.id, p_decision,
    v_reviewer_membership_id, v_candidate.content_sha256,
    jsonb_build_object('notes_present', v_notes is not null)
  ) returning event_uuid into v_event_uuid;
  return v_event_uuid;
end;
$$;

create or replace function private.prevent_knowledge_self_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reviewer_user_id uuid;
  v_creator_user_id uuid;
begin
  select membership.user_id into strict v_reviewer_user_id
  from public.municipality_memberships membership
  where membership.municipality_id = new.municipality_id
    and membership.id = new.reviewer_membership_id;

  if tg_table_schema = 'public' and tg_table_name = 'knowledge_article_reviews' then
    select coalesce(revision.created_by, article.created_by)
      into v_creator_user_id
    from public.knowledge_article_revisions revision
    join public.knowledge_articles article
      on article.municipality_id = revision.municipality_id
     and article.id = revision.article_id
    where revision.municipality_id = new.municipality_id
      and revision.id = new.revision_id;
  else
    select version.created_by into v_creator_user_id
    from public.legal_source_versions version
    where version.municipality_id = new.municipality_id
      and version.id = new.source_version_id;
  end if;

  if v_creator_user_id is not null and v_creator_user_id = v_reviewer_user_id then
    raise exception 'self-review of governed knowledge is prohibited';
  end if;
  return new;
end;
$$;

create trigger knowledge_article_reviews_no_self_review
before insert on public.knowledge_article_reviews
for each row execute function private.prevent_knowledge_self_review();

create trigger legal_source_version_reviews_no_self_review
before insert on private.legal_source_version_reviews
for each row execute function private.prevent_knowledge_self_review();

-- RRF is excellent for ordering but does not measure absolute relevance.
-- Normalize the first citation's absolute lexical/semantic signals and keep a
-- single, testable confidence boundary for answer release.
create or replace function private.knowledge_retrieval_confidence(
  p_lexical_score double precision,
  p_semantic_score double precision
)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select least(1.0, greatest(
    0.0,
    coalesce(p_lexical_score, 0.0) * 5.0,
    (coalesce(p_semantic_score, 0.0) - 0.55) / 0.35
  ));
$$;

-- One reusable definition of legally current/citable source evidence.  Search
-- and coverage calculations must agree on this predicate.
create or replace function private.legal_source_version_is_current_citable(
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
    join public.legal_sources source
      on source.municipality_id = version.municipality_id
     and source.id = version.source_id
    where version.municipality_id = p_municipality_id
      and version.id = p_source_version_id
      and source.status = 'active'
      and source.official_url ~ '^https://[^[:space:]]+$'
      and version.status = 'published'
      and version.publication_date is not null
      and version.publication_date <= private.municipality_current_date(p_municipality_id)
      and version.valid_from is not null
      and version.valid_from <= private.municipality_current_date(p_municipality_id)
      and (
        version.valid_until is null
        or version.valid_until >= private.municipality_current_date(p_municipality_id)
      )
      and private.legal_version_has_complete_evidence(
        version.municipality_id,
        version.id
      )
      and exists (
        select 1
        from private.legal_source_artifact_versions mapping
        join private.legal_source_artifacts artifact
          on artifact.municipality_id = mapping.municipality_id
         and artifact.id = mapping.artifact_id
        join private.legal_source_fetch_runs fetch_run
          on fetch_run.municipality_id = artifact.municipality_id
         and fetch_run.id = artifact.fetch_run_id
        join storage.objects object
          on object.bucket_id = artifact.storage_bucket
         and object.name = artifact.storage_path
        where mapping.municipality_id = version.municipality_id
          and mapping.source_version_id = version.id
          and artifact.source_id = version.source_id
          and artifact.extraction_status = 'completed'
          and artifact.extracted_text_sha256 = version.content_sha256
          and artifact.metadata ->> 'extraction_complete' = 'true'
          and artifact.metadata ->> 'content_truncated' = 'false'
          and case
            when coalesce(artifact.metadata ->> 'extracted_char_count', '')
                   ~ '^[0-9]+$'
              then (artifact.metadata ->> 'extracted_char_count')::numeric
                     = char_length(version.content_text)::numeric
            else false
          end
          and fetch_run.source_id = version.source_id
          and fetch_run.status = 'completed_changed'
          and fetch_run.observed_content_sha256 = artifact.content_sha256
          and fetch_run.final_url ~ '^https://[^[:space:]]+$'
      )
  );
$$;

-- Tenant and legal-validity predicates are evaluated in the materialized
-- eligible CTE before either lexical or semantic rank is calculated.
create or replace function public.ia_fiscal_hybrid_search_legal_knowledge(
  p_municipality_id uuid,
  p_query text,
  p_query_embedding text default null,
  p_limit integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_query text := trim(coalesce(p_query, ''));
  v_limit integer := coalesce(p_limit, 8);
  v_query_embedding extensions.halfvec(384);
  v_tsquery pg_catalog.tsquery;
  v_citations jsonb;
  v_hit_count integer;
  v_top_score double precision;
  v_top_lexical_score double precision;
  v_top_semantic_score double precision;
  v_confidence double precision;
  v_answered boolean;
  v_retrieval_mode text;
  v_min_confidence constant double precision := 0.35;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if not private.has_municipality_role(
    p_municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  ) then
    raise exception using errcode = '42501', message = 'municipality staff access required';
  end if;
  if private.lock_current_knowledge_runtime_gate_id() is null then
    raise exception using
      errcode = '55000',
      message = 'knowledge runtime is not verified';
  end if;
  if char_length(v_query) not between 2 and 500 then
    raise exception 'query must contain 2 to 500 characters';
  end if;
  if v_limit not between 1 and 20 then
    raise exception 'search limit must be between 1 and 20';
  end if;
  if p_query_embedding is not null then
    begin
      v_query_embedding := p_query_embedding::extensions.halfvec(384);
    exception when others then
      raise exception 'invalid 384-dimensional query embedding';
    end;
    if extensions.vector_dims(v_query_embedding) <> 384 then
      raise exception 'invalid query embedding dimensions';
    end if;
  end if;
  v_tsquery := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    v_query
  );

  with eligible as materialized (
    select
      chunk.id as chunk_id,
      chunk.content_text,
      chunk.search_vector,
      section.id as legal_section_id,
      section.section_key,
      section.heading,
      version.id as source_version_id,
      version.publication_date,
      version.valid_from,
      version.valid_until,
      source.id as source_id,
      source.title as source_title,
      source.official_identifier,
      captured.final_url as official_url,
      embedding.embedding
    from private.legal_chunks chunk
    join public.legal_sections section
      on section.municipality_id = chunk.municipality_id
     and section.id = chunk.legal_section_id
    join public.legal_source_versions version
      on version.municipality_id = section.municipality_id
     and version.id = section.source_version_id
    join public.legal_sources source
      on source.municipality_id = version.municipality_id
     and source.id = version.source_id
    left join private.legal_embeddings embedding
      on embedding.municipality_id = chunk.municipality_id
     and embedding.legal_chunk_id = chunk.id
     and embedding.source_sha256 = chunk.content_sha256
     and embedding.provider_code = 'supabase_ai'
     and embedding.model = 'gte-small'
     and embedding.model_revision = 'gte-small-384-v1'
     and embedding.dimensions = 384
    left join lateral (
      select fetch_run.final_url
      from private.legal_source_artifact_versions mapping
      join private.legal_source_artifacts artifact
        on artifact.municipality_id = mapping.municipality_id
       and artifact.id = mapping.artifact_id
      join private.legal_source_fetch_runs fetch_run
        on fetch_run.municipality_id = artifact.municipality_id
       and fetch_run.id = artifact.fetch_run_id
      join storage.objects object
        on object.bucket_id = artifact.storage_bucket
       and object.name = artifact.storage_path
      where mapping.municipality_id = version.municipality_id
        and mapping.source_version_id = version.id
        and artifact.source_id = version.source_id
        and artifact.extraction_status = 'completed'
        and artifact.extracted_text_sha256 = version.content_sha256
        and artifact.metadata ->> 'extraction_complete' = 'true'
        and artifact.metadata ->> 'content_truncated' = 'false'
        and case
          when coalesce(artifact.metadata ->> 'extracted_char_count', '')
                 ~ '^[0-9]+$'
            then (artifact.metadata ->> 'extracted_char_count')::numeric
                   = char_length(version.content_text)::numeric
          else false
        end
        and fetch_run.source_id = version.source_id
        and fetch_run.status = 'completed_changed'
        and fetch_run.observed_content_sha256 = artifact.content_sha256
        and fetch_run.final_url ~ '^https://[^[:space:]]+$'
      order by artifact.observed_at desc, artifact.id desc
      limit 1
    ) captured on true
    where chunk.municipality_id = p_municipality_id
      and private.legal_source_version_is_current_citable(
        version.municipality_id,
        version.id
      )
  ), lexical as (
    select
      eligible.chunk_id,
      row_number() over (
        order by pg_catalog.ts_rank_cd(eligible.search_vector, v_tsquery) desc,
                 eligible.chunk_id
      ) as lexical_rank,
      pg_catalog.ts_rank_cd(eligible.search_vector, v_tsquery) as lexical_score
    from eligible
    where eligible.search_vector @@ v_tsquery
    order by lexical_score desc, eligible.chunk_id
    limit 100
  ), semantic as (
    select
      eligible.chunk_id,
      row_number() over (
        order by eligible.embedding OPERATOR(extensions.<=>) v_query_embedding,
                 eligible.chunk_id
      ) as semantic_rank,
      1 - (
        eligible.embedding OPERATOR(extensions.<=>) v_query_embedding
      ) as semantic_score
    from eligible
    where v_query_embedding is not null
      and eligible.embedding is not null
    order by
      eligible.embedding OPERATOR(extensions.<=>) v_query_embedding,
      eligible.chunk_id
    limit 100
  ), candidate_ids as (
    select lexical.chunk_id from lexical
    union
    select semantic.chunk_id from semantic
  ), ranked as (
    select
      eligible.*,
      lexical.lexical_rank,
      lexical.lexical_score,
      semantic.semantic_rank,
      semantic.semantic_score,
      coalesce(1.0 / (60.0 + lexical.lexical_rank), 0.0)
        + coalesce(1.0 / (60.0 + semantic.semantic_rank), 0.0) as rrf_score
    from candidate_ids
    join eligible on eligible.chunk_id = candidate_ids.chunk_id
    left join lexical on lexical.chunk_id = candidate_ids.chunk_id
    left join semantic on semantic.chunk_id = candidate_ids.chunk_id
    order by rrf_score desc, eligible.chunk_id
    limit v_limit
  )
  select
    count(*)::integer,
    max(ranked.rrf_score),
    (array_agg(ranked.lexical_score order by ranked.rrf_score desc, ranked.chunk_id))[1],
    (array_agg(ranked.semantic_score order by ranked.rrf_score desc, ranked.chunk_id))[1],
    coalesce(jsonb_agg(jsonb_build_object(
      'legal_section_id', ranked.legal_section_id,
      'source_version_id', ranked.source_version_id,
      'source_title', ranked.source_title,
      'official_identifier', ranked.official_identifier,
      'official_url', ranked.official_url,
      'section_key', ranked.section_key,
      'heading', ranked.heading,
      'excerpt', left(ranked.content_text, 2000),
      'publication_date', ranked.publication_date,
      'valid_from', ranked.valid_from,
      'valid_until', ranked.valid_until,
      'score', round(ranked.rrf_score::numeric, 8),
      'lexical_score', round(coalesce(ranked.lexical_score, 0)::numeric, 6),
      'semantic_score', round(coalesce(ranked.semantic_score, 0)::numeric, 6)
    ) order by ranked.rrf_score desc, ranked.chunk_id), '[]'::jsonb)
  into
    v_hit_count,
    v_top_score,
    v_top_lexical_score,
    v_top_semantic_score,
    v_citations
  from ranked;

  v_retrieval_mode := case
    when v_query_embedding is null then 'lexical'
    else 'hybrid'
  end;
  v_confidence := private.knowledge_retrieval_confidence(
    v_top_lexical_score,
    v_top_semantic_score
  );
  v_answered := coalesce(v_hit_count, 0) > 0
    and v_confidence >= v_min_confidence;

  return jsonb_build_object(
    'verified', true,
    'municipality_id', p_municipality_id,
    'query', v_query,
    'answered', v_answered,
    'answer', case when not v_answered then null
      else 'Trecho oficial localizado: ' || left(v_citations -> 0 ->> 'excerpt', 1500)
    end,
    'confidence', round(v_confidence::numeric, 4),
    'retrieval_mode', v_retrieval_mode,
    'citations', v_citations,
    'blockers', case
      when coalesce(v_hit_count, 0) = 0
        then jsonb_build_array('no_current_published_source')
      when not v_answered
        then jsonb_build_array('insufficient_relevance')
      else '[]'::jsonb
    end,
    'searched_at', now()
  );
end;
$$;

-- Scheduler configuration contains no credential material.  Secrets live
-- only in Supabase Vault.  Municipality schedules are disabled by default.
-- Redefine only knowledge-domain review and publication RPCs.  The narrow
-- capability never aliases the global municipal role helpers used by cases,
-- attendance, templates or policies.
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

  v_membership_id := private.current_legal_reviewer_membership_id(
    v_change_set.municipality_id
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'current legal reviewer capability required';
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

  if private.current_legal_reviewer_membership_id(
    v_version.municipality_id
  ) is null then
    raise exception using errcode = '42501', message = 'current legal reviewer capability required';
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

create or replace function public.ia_review_knowledge_article(
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
    v_membership_id := private.current_legal_reviewer_membership_id(
      v_article.municipality_id
    );
  end if;
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
    join public.legal_sections section
      on section.municipality_id = citation.municipality_id
     and section.id = citation.legal_section_id
    where citation.municipality_id = v_article.municipality_id
      and citation.revision_id = v_revision.id
      and (
        not private.legal_source_version_is_current_citable(
          source_version.municipality_id,
          source_version.id
        )
        or source_version.content_sha256 <> citation.source_sha256
        or section.source_version_id <> source_version.id
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
  v_publisher_membership_id := private.current_legal_reviewer_membership_id(
    v_article.municipality_id
  );
  if v_publisher_membership_id is null then
    raise exception using errcode = '42501', message = 'current legal reviewer capability required';
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
    join public.legal_sections section
      on section.municipality_id = citation.municipality_id
     and section.id = citation.legal_section_id
    where citation.municipality_id = v_article.municipality_id
      and citation.revision_id = v_revision.id
      and (
        not private.legal_source_version_is_current_citable(
          source_version.municipality_id,
          source_version.id
        )
        or source_version.content_sha256 <> citation.source_sha256
        or section.source_version_id <> source_version.id
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

-- Tenant-explicit mutation overloads.  Legacy signatures remain internal so
-- the mature validation bodies above can be reused, but are revoked below.
create or replace function public.ia_review_legal_source_change(
  p_expected_municipality_id uuid,
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
begin
  if not exists (
    select 1 from private.legal_source_change_sets change_set
    where change_set.id = p_change_set_id
      and change_set.municipality_id = p_expected_municipality_id
  ) then
    raise exception using errcode = '42501', message = 'tenant-bound legal change not found';
  end if;
  return public.ia_review_legal_source_change(
    p_change_set_id, p_decision, p_review_notes, p_confirmation,
    p_valid_from, p_valid_until, p_publication_date
  );
end;
$$;

create or replace function public.ia_publish_legal_source_version(
  p_expected_municipality_id uuid,
  p_source_version_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.legal_source_versions version
    where version.id = p_source_version_id
      and version.municipality_id = p_expected_municipality_id
  ) then
    raise exception using errcode = '42501', message = 'tenant-bound legal version not found';
  end if;
  perform public.ia_publish_legal_source_version(p_source_version_id, p_confirmation);
end;
$$;

create or replace function public.ia_review_knowledge_article(
  p_expected_municipality_id uuid,
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
begin
  if not exists (
    select 1 from public.knowledge_articles article
    where article.id = p_article_id
      and article.municipality_id = p_expected_municipality_id
  ) then
    raise exception using errcode = '42501', message = 'tenant-bound knowledge article not found';
  end if;
  return public.ia_review_knowledge_article(
    p_article_id, p_revision_id, p_decision, p_notes, p_confirmation
  );
end;
$$;

create or replace function public.ia_publish_knowledge_article(
  p_expected_municipality_id uuid,
  p_article_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.knowledge_articles article
    where article.id = p_article_id
      and article.municipality_id = p_expected_municipality_id
  ) then
    raise exception using errcode = '42501', message = 'tenant-bound knowledge article not found';
  end if;
  perform public.ia_publish_knowledge_article(p_article_id, p_confirmation);
end;
$$;

create or replace function public.ia_review_knowledge_candidate(
  p_expected_municipality_id uuid,
  p_candidate_id uuid,
  p_decision text,
  p_notes text,
  p_confirmation text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from private.knowledge_candidate_submissions candidate
    where candidate.id = p_candidate_id
      and candidate.municipality_id = p_expected_municipality_id
  ) then
    raise exception using errcode = '42501', message = 'tenant-bound learning candidate not found';
  end if;
  return public.ia_review_knowledge_candidate(
    p_candidate_id, p_decision, p_notes, p_confirmation
  );
end;
$$;

create table private.knowledge_automation_settings (
  municipality_id uuid primary key references public.municipalities(id) on delete cascade,
  enabled boolean not null default false,
  cadence_minutes integer not null default 1440
    check (cadence_minutes between 60 and 43200),
  local_run_time time not null default time '03:15',
  timezone text not null,
  endpoint_batch_size smallint not null default 20 check (endpoint_batch_size between 1 and 50),
  next_run_at timestamptz,
  last_run_at timestamptz,
  last_run_status text check (
    last_run_status is null
    or last_run_status in ('queued', 'completed', 'partial', 'failed', 'configuration_missing')
  ),
  last_safe_error_code text check (
    last_safe_error_code is null
    or last_safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  configured_by_membership_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint knowledge_automation_settings_configurator_fk
    foreign key (municipality_id, configured_by_membership_id)
    references public.municipality_memberships(municipality_id, id)
);

insert into private.knowledge_automation_settings (
  municipality_id,
  enabled,
  cadence_minutes,
  local_run_time,
  timezone,
  next_run_at
)
select
  municipality.id,
  false,
  1440,
  time '03:15',
  municipality.timezone,
  case
    when ((private.municipality_current_date(municipality.id) + time '03:15')
      at time zone municipality.timezone) > now()
      then ((private.municipality_current_date(municipality.id) + time '03:15')
        at time zone municipality.timezone)
    else ((private.municipality_current_date(municipality.id) + 1 + time '03:15')
      at time zone municipality.timezone)
  end
from public.municipalities municipality
on conflict (municipality_id) do nothing;

create table private.knowledge_scheduler_nonces (
  nonce uuid primary key,
  scope text not null check (scope in ('ingest', 'embed')),
  issued_at timestamptz not null,
  consumed_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint knowledge_scheduler_nonces_expiry_ck check (expires_at > issued_at)
);

create index knowledge_scheduler_nonces_expiry_idx
  on private.knowledge_scheduler_nonces (expires_at);

create table private.knowledge_scheduler_dispatches (
  id bigint generated always as identity primary key,
  municipality_id uuid references public.municipalities(id) on delete set null,
  endpoint_id uuid,
  scope text not null check (scope in ('ingest', 'embed')),
  request_id bigint,
  attempt smallint not null default 1 check (attempt between 1 and 20),
  status text not null check (status in ('queued', 'configuration_missing', 'failed')),
  safe_error_code text check (
    safe_error_code is null
    or safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  created_at timestamptz not null default now(),
  lease_expires_at timestamptz not null default (now() + interval '2 minutes'),
  constraint knowledge_scheduler_dispatch_endpoint_fk
    foreign key (municipality_id, endpoint_id)
    references private.legal_source_endpoints(municipality_id, id),
  constraint knowledge_scheduler_dispatch_request_uq unique (request_id),
  constraint knowledge_scheduler_dispatch_lease_ck check (
    lease_expires_at > created_at
    and lease_expires_at <= created_at + interval '5 minutes'
  )
);

create index knowledge_scheduler_dispatch_endpoint_idx
  on private.knowledge_scheduler_dispatches (
    municipality_id,
    endpoint_id,
    scope,
    created_at desc
  )
  where endpoint_id is not null;

-- Dispatch rows and their transitions are immutable.  pg_net returns only a
-- request id at enqueue time; the next scheduler tick reconciles that id with
-- net._http_response and appends exactly one terminal outcome here.
create table private.knowledge_scheduler_dispatch_events (
  id bigint generated always as identity primary key,
  dispatch_id bigint not null
    references private.knowledge_scheduler_dispatches(id),
  event_type text not null check (event_type in (
    'queued',
    'succeeded',
    'retry_scheduled',
    'circuit_opened',
    'failed',
    'configuration_missing'
  )),
  http_status integer check (http_status is null or http_status between 100 and 599),
  safe_error_code text check (
    safe_error_code is null
    or safe_error_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  retry_at timestamptz,
  event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  constraint knowledge_scheduler_dispatch_event_once_uq
    unique (dispatch_id, event_type),
  constraint knowledge_scheduler_dispatch_event_shape_ck check (
    (event_type = 'queued'
      and http_status is null and safe_error_code is null and retry_at is null)
    or (event_type = 'succeeded'
      and http_status between 200 and 299
      and safe_error_code is null and retry_at is null)
    or (event_type in ('retry_scheduled', 'circuit_opened')
      and safe_error_code is not null and retry_at is not null)
    or (event_type = 'failed'
      and safe_error_code is not null and retry_at is not null)
    or (event_type = 'configuration_missing'
      and http_status is null and safe_error_code is not null and retry_at is not null)
  )
);

create unique index knowledge_scheduler_dispatch_one_terminal_idx
  on private.knowledge_scheduler_dispatch_events (dispatch_id)
  where event_type in (
    'succeeded',
    'retry_scheduled',
    'circuit_opened',
    'failed',
    'configuration_missing'
  );

create index knowledge_scheduler_dispatch_events_retry_idx
  on private.knowledge_scheduler_dispatch_events (retry_at, event_at, dispatch_id)
  where retry_at is not null;

-- A runtime attestation is created only after all three Edge contracts have
-- been deployed and their read-only smoke suite has produced a retained hash.
-- Keeping this gate in the core migration lets every scheduler entry point
-- fail closed before the separate activation migration exists.
create table private.knowledge_runtime_release_gates (
  id uuid primary key default gen_random_uuid(),
  project_ref text not null check (project_ref ~ '^[a-z0-9]{15,40}$'),
  ingest_contract text not null check (ingest_contract = 'knowledge-ingest-v2'),
  ingest_deployment_id text not null
    check (ingest_deployment_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'),
  ingest_release_fingerprint text not null
    check (ingest_release_fingerprint ~ '^[a-f0-9]{64}$'),
  embed_contract text not null check (embed_contract = 'knowledge-embed-v1'),
  embed_deployment_id text not null
    check (embed_deployment_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'),
  embed_release_fingerprint text not null
    check (embed_release_fingerprint ~ '^[a-f0-9]{64}$'),
  search_contract text not null check (search_contract = 'knowledge-search-v1'),
  search_deployment_id text not null
    check (search_deployment_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'),
  search_release_fingerprint text not null
    check (search_release_fingerprint ~ '^[a-f0-9]{64}$'),
  smoke_evidence_sha256 text not null check (smoke_evidence_sha256 ~ '^[a-f0-9]{64}$'),
  smoke_evidence_locator text not null check (
    char_length(trim(smoke_evidence_locator)) between 8 and 500
    and smoke_evidence_locator !~ '[[:cntrl:]]'
  ),
  valid_from timestamptz not null default now(),
  valid_until timestamptz not null,
  attested_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint knowledge_runtime_release_gate_validity_ck check (
    valid_until > valid_from
    and valid_until <= valid_from + interval '7 days'
  ),
  constraint knowledge_runtime_release_gate_project_id_uq unique (project_ref, id),
  constraint knowledge_runtime_release_gate_evidence_uq unique (
    project_ref,
    ingest_deployment_id,
    embed_deployment_id,
    search_deployment_id,
    smoke_evidence_sha256
  )
);

create table private.knowledge_runtime_gate_events (
  id bigint generated always as identity primary key,
  project_ref text not null,
  runtime_gate_id uuid not null,
  event_type text not null check (event_type in ('attested', 'selected', 'revoked')),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'),
  event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  constraint knowledge_runtime_gate_events_gate_fk
    foreign key (project_ref, runtime_gate_id)
    references private.knowledge_runtime_release_gates(project_ref, id)
);

create unique index knowledge_runtime_gate_one_revocation_idx
  on private.knowledge_runtime_gate_events (runtime_gate_id)
  where event_type = 'revoked';

-- This explicit pointer is what makes a gate current.  Activation never picks
-- an arbitrary or merely latest attestation.
create table private.knowledge_runtime_current_gates (
  project_ref text primary key,
  runtime_gate_id uuid not null unique,
  selected_at timestamptz not null default now(),
  constraint knowledge_runtime_current_gate_fk
    foreign key (project_ref, runtime_gate_id)
    references private.knowledge_runtime_release_gates(project_ref, id)
);

create table private.knowledge_schedule_activation_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  enabled boolean not null,
  actor_kind text not null check (actor_kind in ('municipal_admin', 'release_migration')),
  actor_membership_id uuid,
  runtime_gate_id uuid,
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'),
  event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  constraint knowledge_schedule_activation_actor_fk
    foreign key (municipality_id, actor_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint knowledge_schedule_activation_gate_fk
    foreign key (runtime_gate_id)
    references private.knowledge_runtime_release_gates(id),
  constraint knowledge_schedule_activation_actor_ck check (
    (actor_kind = 'municipal_admin' and actor_membership_id is not null)
    or (actor_kind = 'release_migration' and actor_membership_id is null)
  ),
  constraint knowledge_schedule_activation_runtime_ck check (
    not enabled or runtime_gate_id is not null
  )
);

create or replace function private.knowledge_scheduler_project_ref()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select substring(
    secret.decrypted_secret
    from '^https://([a-z0-9]{15,40})\.supabase\.co$'
  )
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_project_url';
$$;

create or replace function private.current_knowledge_runtime_gate_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select current_gate.runtime_gate_id
  from private.knowledge_runtime_current_gates current_gate
  join private.knowledge_runtime_release_gates gate
    on gate.project_ref = current_gate.project_ref
   and gate.id = current_gate.runtime_gate_id
  where current_gate.project_ref = private.knowledge_scheduler_project_ref()
    and gate.ingest_contract = 'knowledge-ingest-v2'
    and gate.embed_contract = 'knowledge-embed-v1'
    and gate.search_contract = 'knowledge-search-v1'
    and gate.valid_from <= now()
    and gate.valid_until > now()
    and not exists (
      select 1
      from private.knowledge_runtime_gate_events event
      where event.runtime_gate_id = gate.id
        and event.event_type = 'revoked'
    );
$$;

create or replace function private.knowledge_runtime_is_verified()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_knowledge_runtime_gate_id() is not null;
$$;

-- Runtime consumers take key-share locks on both the selected pointer and its
-- exact attestation.  A concurrent revocation or pointer replacement must
-- therefore complete before a new claim/dispatch can pass this gate, while a
-- consumer that already passed it retains a coherent gate for its transaction.
create or replace function private.lock_current_knowledge_runtime_gate_id()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_runtime_gate_id uuid;
begin
  select current_gate.runtime_gate_id into v_runtime_gate_id
  from private.knowledge_runtime_current_gates current_gate
  join private.knowledge_runtime_release_gates gate
    on gate.project_ref = current_gate.project_ref
   and gate.id = current_gate.runtime_gate_id
  where current_gate.project_ref = private.knowledge_scheduler_project_ref()
    and current_gate.runtime_gate_id = private.current_knowledge_runtime_gate_id()
  for key share of current_gate, gate;

  return v_runtime_gate_id;
end;
$$;

do $$
begin
  if not exists (
    select 1 from vault.secrets secret
    where secret.name = 'ia_fiscal_knowledge_scheduler_secret'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'ia_fiscal_knowledge_scheduler_secret',
      'Bearer secret for IA Fiscal knowledge scheduler; rotate through Vault only.'
    );
  end if;
end;
$$;

create or replace function public.ia_fiscal_configure_knowledge_scheduler_project_url(
  p_project_url text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text := regexp_replace(lower(trim(coalesce(p_project_url, ''))), '/+$', '');
  v_secret_id uuid;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if v_url !~ '^https://[a-z0-9]{15,40}\.supabase\.co$' then
    raise exception 'project URL must be a canonical Supabase project URL';
  end if;
  select secret.id into v_secret_id
  from vault.secrets secret
  where secret.name = 'ia_fiscal_knowledge_project_url';
  if v_secret_id is null then
    perform vault.create_secret(
      v_url,
      'ia_fiscal_knowledge_project_url',
      'Environment-local base URL used by the IA Fiscal knowledge scheduler.'
    );
  else
    perform vault.update_secret(
      v_secret_id,
      v_url,
      'ia_fiscal_knowledge_project_url',
      'Environment-local base URL used by the IA Fiscal knowledge scheduler.'
    );
  end if;
end;
$$;

create or replace function public.ia_fiscal_validate_knowledge_scheduler_request(
  p_secret_sha256 text,
  p_nonce uuid,
  p_issued_at timestamptz,
  p_scope text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected_sha256 text;
  v_inserted integer;
begin
  if not private.is_service_role() then
    return false;
  end if;
  if p_secret_sha256 !~ '^[a-f0-9]{64}$'
     or p_scope not in ('ingest', 'embed')
     or p_issued_at is null
     or p_issued_at < now() - interval '2 minutes'
     or p_issued_at > now() + interval '30 seconds' then
    return false;
  end if;

  select encode(extensions.digest(secret.decrypted_secret, 'sha256'), 'hex')
    into v_expected_sha256
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_scheduler_secret';
  if v_expected_sha256 is null or v_expected_sha256 <> p_secret_sha256 then
    return false;
  end if;

  delete from private.knowledge_scheduler_nonces nonce
  where nonce.expires_at < now() - interval '1 hour';
  insert into private.knowledge_scheduler_nonces (
    nonce,
    scope,
    issued_at,
    expires_at
  ) values (
    p_nonce,
    p_scope,
    p_issued_at,
    p_issued_at + interval '2 minutes'
  ) on conflict (nonce) do nothing;
  get diagnostics v_inserted = row_count;
  return v_inserted = 1;
end;
$$;

create or replace function public.ia_configure_knowledge_schedule(
  p_municipality_id uuid,
  p_enabled boolean,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership_id uuid;
  v_timezone text;
  v_next_run_at timestamptz;
  v_runtime_gate_id uuid;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;
  if p_confirmation <> (case when p_enabled
    then 'ATIVAR ATUALIZACAO OFICIAL'
    else 'DESATIVAR ATUALIZACAO OFICIAL'
  end) then
    raise exception 'explicit scheduler confirmation required';
  end if;
  v_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array['municipal_admin']::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'current municipal administrator required';
  end if;
  if p_enabled and not exists (
    select 1 from vault.secrets secret
    where secret.name = 'ia_fiscal_knowledge_project_url'
  ) then
    raise exception 'knowledge scheduler project URL is not configured';
  end if;
  if p_enabled then
    v_runtime_gate_id := private.current_knowledge_runtime_gate_id();
    if v_runtime_gate_id is null then
      raise exception using
        errcode = '55000',
        message = 'knowledge runtime is not verified',
        hint = 'Deploy all Edge contracts, run the smoke suite and attest the retained SHA-256 before enabling.';
    end if;
    -- Keep the exact pointer/gate stable through this transaction.  A release
    -- replacement or revocation must wait and then observes the committed
    -- activation event tied to this gate id.
    perform 1
    from private.knowledge_runtime_release_gates gate
    where gate.project_ref = private.knowledge_scheduler_project_ref()
      and gate.id = v_runtime_gate_id
    for share;
    if not found then
      raise exception using errcode = '55000', message = 'current runtime gate changed';
    end if;
    perform 1
    from private.knowledge_runtime_current_gates current_gate
    where current_gate.project_ref = private.knowledge_scheduler_project_ref()
      and current_gate.runtime_gate_id = v_runtime_gate_id
    for share;
    if not found then
      raise exception using errcode = '55000', message = 'current runtime gate changed';
    end if;
  end if;

  select municipality.timezone into strict v_timezone
  from public.municipalities municipality
  where municipality.id = p_municipality_id;
  v_next_run_at := case
    when ((private.municipality_current_date(p_municipality_id) + time '03:15')
      at time zone v_timezone) > now()
      then ((private.municipality_current_date(p_municipality_id) + time '03:15')
        at time zone v_timezone)
    else ((private.municipality_current_date(p_municipality_id) + 1 + time '03:15')
      at time zone v_timezone)
  end;

  insert into private.knowledge_automation_settings (
    municipality_id,
    enabled,
    cadence_minutes,
    local_run_time,
    timezone,
    next_run_at,
    configured_by_membership_id,
    last_run_status,
    last_safe_error_code
  ) values (
    p_municipality_id,
    p_enabled,
    1440,
    time '03:15',
    v_timezone,
    v_next_run_at,
    v_membership_id,
    null,
    null
  ) on conflict (municipality_id) do update set
    enabled = excluded.enabled,
    cadence_minutes = excluded.cadence_minutes,
    local_run_time = excluded.local_run_time,
    timezone = excluded.timezone,
    next_run_at = excluded.next_run_at,
    configured_by_membership_id = excluded.configured_by_membership_id,
    updated_at = now(),
    last_safe_error_code = null;

  insert into private.knowledge_schedule_activation_events (
    municipality_id,
    enabled,
    actor_kind,
    actor_membership_id,
    runtime_gate_id,
    reason_code,
    metadata
  ) values (
    p_municipality_id,
    p_enabled,
    'municipal_admin',
    v_membership_id,
    case when p_enabled then v_runtime_gate_id end,
    case when p_enabled
      then 'municipal_admin_enabled_official_refresh'
      else 'municipal_admin_disabled_official_refresh'
    end,
    jsonb_build_object('cadence_minutes', 1440, 'local_run_time', '03:15')
  );

  return jsonb_build_object(
    'enabled', p_enabled,
    'cadence', 'Diariamente, às 03:15',
    'next_run_at', case when p_enabled then v_next_run_at else null end
  );
end;
$$;

create or replace function private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(
  p_limit integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dispatch private.knowledge_scheduler_dispatches%rowtype;
  v_http_status integer;
  v_timed_out boolean;
  v_transport_error text;
  v_has_response boolean;
  v_has_completed_fetch boolean;
  v_retryable boolean;
  v_event_type text;
  v_safe_error_code text;
  v_retry_at timestamptz;
  v_recent_failures integer;
  v_succeeded integer := 0;
  v_retried integer := 0;
  v_failed integer := 0;
begin
  if p_limit not between 1 and 1000 then
    raise exception 'scheduler reconciliation limit must be between 1 and 1000';
  end if;

  for v_dispatch in
    select dispatch.*
    from private.knowledge_scheduler_dispatches dispatch
    where dispatch.status = 'queued'
      and dispatch.request_id is not null
      and not exists (
        select 1
        from private.knowledge_scheduler_dispatch_events terminal
        where terminal.dispatch_id = dispatch.id
          and terminal.event_type in (
            'succeeded', 'retry_scheduled', 'circuit_opened', 'failed'
          )
      )
      and (
        dispatch.lease_expires_at <= now()
        or exists (
          select 1 from net._http_response response
          where response.id = dispatch.request_id
        )
      )
    order by dispatch.lease_expires_at, dispatch.id
    for update of dispatch skip locked
    limit p_limit
  loop
    v_http_status := null;
    v_timed_out := false;
    v_transport_error := null;
    v_has_response := false;
    v_has_completed_fetch := false;
    v_retryable := false;
    v_event_type := null;
    v_safe_error_code := null;
    v_retry_at := null;

    select
      response.status_code,
      coalesce(response.timed_out, false),
      response.error_msg,
      true
    into
      v_http_status,
      v_timed_out,
      v_transport_error,
      v_has_response
    from net._http_response response
    where response.id = v_dispatch.request_id
    order by response.created desc
    limit 1;
    v_has_response := coalesce(v_has_response, false);
    v_timed_out := coalesce(v_timed_out, false);

    if v_dispatch.scope = 'ingest' and v_dispatch.endpoint_id is not null then
      select exists (
        select 1
        from private.legal_source_fetch_runs fetch_run
        where fetch_run.municipality_id = v_dispatch.municipality_id
          and fetch_run.endpoint_id = v_dispatch.endpoint_id
          and fetch_run.status in ('completed_unchanged', 'completed_changed')
          and fetch_run.completed_at >= v_dispatch.created_at - interval '5 seconds'
      ) into v_has_completed_fetch;
    end if;

    if v_has_response
       and v_http_status between 200 and 299
       and not v_timed_out
       and v_transport_error is null
       and (
         (v_dispatch.scope = 'embed' and v_http_status = 200)
         or (v_dispatch.scope = 'ingest' and v_has_completed_fetch)
       ) then
      v_event_type := 'succeeded';
      v_succeeded := v_succeeded + 1;
    else
      v_retryable := not v_has_response
        or v_timed_out
        or v_transport_error is not null
        or v_http_status is null
        or v_http_status in (408, 425, 429)
        or v_http_status >= 500
        or (
          v_dispatch.scope = 'embed'
          and v_http_status between 200 and 299
          and v_http_status <> 200
        )
        or (
          v_dispatch.scope = 'ingest'
          and v_http_status between 200 and 299
          and not v_has_completed_fetch
        );
      v_safe_error_code := case
        when not v_has_response then 'scheduler_response_lease_expired'
        when v_timed_out then 'scheduler_http_timed_out'
        when v_transport_error is not null then 'scheduler_http_transport_error'
        when v_dispatch.scope = 'embed' and v_http_status = 207
          then 'scheduler_embed_batch_partial_failure'
        when v_dispatch.scope = 'embed' and v_http_status between 200 and 299
          then 'scheduler_embed_response_invalid'
        when v_http_status between 200 and 299 then 'scheduler_fetch_evidence_missing'
        when v_http_status is null then 'scheduler_http_status_missing'
        else 'scheduler_http_' || v_http_status::text
      end;

      select count(*) + 1
      into v_recent_failures
      from private.knowledge_scheduler_dispatch_events failure_event
      join private.knowledge_scheduler_dispatches failed_dispatch
        on failed_dispatch.id = failure_event.dispatch_id
      where failure_event.event_type in ('retry_scheduled', 'circuit_opened', 'failed')
        and failure_event.event_at >= now() - interval '30 minutes'
        and failed_dispatch.scope = v_dispatch.scope
        and (
          (v_dispatch.scope = 'embed' and failed_dispatch.scope = 'embed')
          or (
            failed_dispatch.municipality_id = v_dispatch.municipality_id
            and failed_dispatch.endpoint_id = v_dispatch.endpoint_id
          )
        );

      if v_retryable and v_recent_failures >= 3 then
        v_event_type := 'circuit_opened';
        v_retry_at := now() + interval '30 minutes';
        v_retried := v_retried + 1;
      elsif v_retryable then
        v_event_type := 'retry_scheduled';
        v_retry_at := now() + make_interval(
          mins => least(60, power(2, least(v_dispatch.attempt - 1, 6))::integer)
        );
        v_retried := v_retried + 1;
      else
        v_event_type := 'failed';
        v_retry_at := now() + interval '24 hours';
        v_failed := v_failed + 1;
      end if;
    end if;

    insert into private.knowledge_scheduler_dispatch_events (
      dispatch_id,
      event_type,
      http_status,
      safe_error_code,
      retry_at,
      metadata
    ) values (
      v_dispatch.id,
      v_event_type,
      v_http_status,
      v_safe_error_code,
      v_retry_at,
      jsonb_build_object(
        'scope', v_dispatch.scope,
        'attempt', v_dispatch.attempt,
        'response_observed', v_has_response,
        'completed_fetch_observed', v_has_completed_fetch
      )
    ) on conflict do nothing;

    if v_dispatch.scope = 'ingest'
       and v_dispatch.municipality_id is not null
       and v_event_type <> 'succeeded' then
      update private.knowledge_automation_settings setting
      set next_run_at = least(coalesce(setting.next_run_at, v_retry_at), v_retry_at),
          last_run_status = case
            when v_event_type = 'failed' then 'failed' else 'partial'
          end,
          last_safe_error_code = v_safe_error_code,
          updated_at = now()
      where setting.municipality_id = v_dispatch.municipality_id
        and setting.enabled;
    end if;
  end loop;

  return jsonb_build_object(
    'succeeded', v_succeeded,
    'retry_scheduled', v_retried,
    'failed', v_failed
  );
end;
$$;

create or replace function private.ia_fiscal_dispatch_due_knowledge_work(
  p_endpoint_batch integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_url text;
  v_scheduler_secret text;
  v_setting private.knowledge_automation_settings%rowtype;
  v_endpoint private.legal_source_endpoints%rowtype;
  v_dispatch_id bigint;
  v_request_id bigint;
  v_nonce uuid;
  v_issued_at timestamptz;
  v_queued integer := 0;
  v_remaining integer;
  v_embedding_jobs integer;
  v_attempt smallint;
  v_embedding_dispatched boolean := false;
  v_reconciliation jsonb;
  v_runtime_gate_id uuid;
begin
  if p_endpoint_batch not between 1 and 50 then
    raise exception 'endpoint batch must be between 1 and 50';
  end if;

  -- This five-minute cron is also the governed clock for reviewer capability
  -- expiry.  It remains independent of runtime readiness and records the
  -- state transition plus its append-only event in one transaction.
  perform private.expire_legal_reviewer_capabilities(500);

  -- Fail closed before reconciliation, scheduler secret/URL consumption,
  -- queue inspection, claims, or pg_net I/O.  Gate resolution itself reads
  -- the configured project ref from Vault so the attestation cannot drift to
  -- another project.  The retained row locks serialize gate revocation with
  -- this dispatch transaction.
  v_runtime_gate_id := private.lock_current_knowledge_runtime_gate_id();
  if v_runtime_gate_id is null then
    update private.knowledge_automation_settings setting
    set last_run_at = now(),
        last_run_status = 'failed',
        last_safe_error_code = 'knowledge_runtime_not_verified',
        updated_at = now()
    where setting.enabled;

    return jsonb_build_object(
      'queued', 0,
      'embedding_dispatch', false,
      'reconciliation', jsonb_build_object('status', 'skipped_runtime_not_verified'),
      'status', 'runtime_not_verified'
    );
  end if;

  v_reconciliation := private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(200);

  select secret.decrypted_secret into v_project_url
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_project_url';
  select secret.decrypted_secret into v_scheduler_secret
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_scheduler_secret';

  if v_project_url is null or v_scheduler_secret is null then
    update private.knowledge_automation_settings setting
    set last_run_at = now(),
        last_run_status = 'configuration_missing',
        last_safe_error_code = 'scheduler_vault_configuration_missing',
        updated_at = now()
    where setting.enabled
      and setting.next_run_at <= now();
    insert into private.knowledge_scheduler_dispatches (
      municipality_id, scope, status, safe_error_code
    ) values (
      null, 'ingest', 'configuration_missing', 'scheduler_vault_configuration_missing'
    ) returning id into v_dispatch_id;
    insert into private.knowledge_scheduler_dispatch_events (
      dispatch_id, event_type, safe_error_code, retry_at
    ) values (
      v_dispatch_id,
      'configuration_missing',
      'scheduler_vault_configuration_missing',
      now() + interval '5 minutes'
    );
    return jsonb_build_object(
      'queued', 0,
      'reconciliation', v_reconciliation,
      'status', 'configuration_missing'
    );
  end if;

  for v_setting in
    select setting.*
    from private.knowledge_automation_settings setting
    where setting.enabled
      and private.knowledge_runtime_is_verified()
      and setting.next_run_at <= now()
    order by setting.next_run_at, setting.municipality_id
    for update skip locked
    limit 20
  loop
    for v_endpoint in
      select endpoint.*
      from private.legal_source_endpoints endpoint
      left join lateral (
        select max(fetch_run.completed_at) as last_completed_fetch_at
        from private.legal_source_fetch_runs fetch_run
        where fetch_run.municipality_id = endpoint.municipality_id
          and fetch_run.endpoint_id = endpoint.id
          and fetch_run.status in ('completed_unchanged', 'completed_changed')
      ) completed_fetch on true
      left join lateral (
        select max(dispatch.created_at) as pending_dispatch_at
        from private.knowledge_scheduler_dispatches dispatch
        where dispatch.municipality_id = endpoint.municipality_id
          and dispatch.endpoint_id = endpoint.id
          and dispatch.scope = 'ingest'
          and dispatch.status = 'queued'
          and not exists (
            select 1
            from private.knowledge_scheduler_dispatch_events terminal
            where terminal.dispatch_id = dispatch.id
              and terminal.event_type in (
                'succeeded', 'retry_scheduled', 'circuit_opened', 'failed'
              )
          )
      ) pending_dispatch on true
      left join lateral (
        select terminal.retry_at
        from private.knowledge_scheduler_dispatch_events terminal
        join private.knowledge_scheduler_dispatches prior_dispatch
          on prior_dispatch.id = terminal.dispatch_id
        where prior_dispatch.municipality_id = endpoint.municipality_id
          and prior_dispatch.endpoint_id = endpoint.id
          and prior_dispatch.scope = 'ingest'
          and terminal.event_type in ('retry_scheduled', 'circuit_opened', 'failed')
        order by terminal.event_at desc, terminal.id desc
        limit 1
      ) latest_retry on true
      where endpoint.municipality_id = v_setting.municipality_id
        and endpoint.status = 'active'
        -- The durable cursor is a completed fetch or a dispatch whose short
        -- lease is still pending; failed/terminal dispatches never advance it.
        and pending_dispatch.pending_dispatch_at is null
        and coalesce(
          completed_fetch.last_completed_fetch_at,
          '-infinity'::timestamptz
        ) + endpoint.poll_interval <= now()
        and (latest_retry.retry_at is null or latest_retry.retry_at <= now())
        and greatest(
          (
            select count(*)
            from private.legal_source_fetch_runs recent_failure
            where recent_failure.municipality_id = endpoint.municipality_id
              and recent_failure.endpoint_id = endpoint.id
              and recent_failure.status in ('failed', 'blocked')
              and recent_failure.completed_at >= now() - interval '30 minutes'
          ),
          (
            select count(*)
            from private.knowledge_scheduler_dispatch_events recent_dispatch_failure
            join private.knowledge_scheduler_dispatches failed_dispatch
              on failed_dispatch.id = recent_dispatch_failure.dispatch_id
            where failed_dispatch.municipality_id = endpoint.municipality_id
              and failed_dispatch.endpoint_id = endpoint.id
              and recent_dispatch_failure.event_type in (
                'retry_scheduled', 'circuit_opened', 'failed'
              )
              and recent_dispatch_failure.event_at >= now() - interval '30 minutes'
          )
        ) < 3
      order by
        coalesce(completed_fetch.last_completed_fetch_at, '-infinity'::timestamptz),
        endpoint.priority,
        endpoint.id
      limit least(p_endpoint_batch, v_setting.endpoint_batch_size)
    loop
      select least(20, 1 + count(*))::smallint into v_attempt
      from private.knowledge_scheduler_dispatch_events failure_event
      join private.knowledge_scheduler_dispatches failed_dispatch
        on failed_dispatch.id = failure_event.dispatch_id
      where failed_dispatch.municipality_id = v_endpoint.municipality_id
        and failed_dispatch.endpoint_id = v_endpoint.id
        and failure_event.event_type in ('retry_scheduled', 'circuit_opened', 'failed')
        and failure_event.event_at > coalesce((
          select max(success_event.event_at)
          from private.knowledge_scheduler_dispatch_events success_event
          join private.knowledge_scheduler_dispatches success_dispatch
            on success_dispatch.id = success_event.dispatch_id
          where success_dispatch.municipality_id = v_endpoint.municipality_id
            and success_dispatch.endpoint_id = v_endpoint.id
            and success_event.event_type = 'succeeded'
        ), '-infinity'::timestamptz);

      v_nonce := gen_random_uuid();
      v_issued_at := clock_timestamp();
      select net.http_post(
        url := v_project_url || '/functions/v1/ia-fiscal-knowledge-ingest',
        headers := jsonb_build_object(
          'content-type', 'application/json',
          'authorization', 'Bearer ' || v_scheduler_secret,
          'x-ia-scheduler-nonce', v_nonce::text,
          'x-ia-scheduler-issued-at', v_issued_at::text
        ),
        body := jsonb_build_object(
          'endpoint_id', v_endpoint.id,
          'dry_run', false
        ),
        timeout_milliseconds := 90000
      ) into v_request_id;
      insert into private.knowledge_scheduler_dispatches (
        municipality_id,
        endpoint_id,
        scope,
        request_id,
        attempt,
        status
      ) values (
        v_setting.municipality_id,
        v_endpoint.id,
        'ingest',
        v_request_id,
        v_attempt,
        'queued'
      ) returning id into v_dispatch_id;
      insert into private.knowledge_scheduler_dispatch_events (
        dispatch_id, event_type, metadata
      ) values (
        v_dispatch_id,
        'queued',
        jsonb_build_object('lease_seconds', 120, 'attempt', v_attempt)
      );
      v_queued := v_queued + 1;
    end loop;

    select count(*) into v_remaining
    from private.legal_source_endpoints endpoint
    left join lateral (
      select max(fetch_run.completed_at) as last_completed_fetch_at
      from private.legal_source_fetch_runs fetch_run
      where fetch_run.municipality_id = endpoint.municipality_id
        and fetch_run.endpoint_id = endpoint.id
        and fetch_run.status in ('completed_unchanged', 'completed_changed')
    ) completed_fetch on true
    left join lateral (
      select max(dispatch.created_at) as pending_dispatch_at
      from private.knowledge_scheduler_dispatches dispatch
      where dispatch.municipality_id = endpoint.municipality_id
        and dispatch.endpoint_id = endpoint.id
        and dispatch.scope = 'ingest'
        and dispatch.status = 'queued'
        and not exists (
          select 1
          from private.knowledge_scheduler_dispatch_events terminal
          where terminal.dispatch_id = dispatch.id
            and terminal.event_type in (
              'succeeded', 'retry_scheduled', 'circuit_opened', 'failed'
            )
        )
    ) pending_dispatch on true
    where endpoint.municipality_id = v_setting.municipality_id
      and endpoint.status = 'active'
      and pending_dispatch.pending_dispatch_at is null
      and coalesce(
        completed_fetch.last_completed_fetch_at,
        '-infinity'::timestamptz
      ) + endpoint.poll_interval <= now();

    update private.knowledge_automation_settings
    set last_run_at = now(),
        last_run_status = case when v_remaining > 0 then 'partial' else 'queued' end,
        last_safe_error_code = null,
        next_run_at = case when v_remaining > 0
          then now() + interval '5 minutes'
          else ((private.municipality_current_date(v_setting.municipality_id) + 1
            + v_setting.local_run_time) at time zone v_setting.timezone)
        end,
        updated_at = now()
    where municipality_id = v_setting.municipality_id;
  end loop;

  select count(*) into v_embedding_jobs
  from private.legal_embedding_jobs job
  join private.knowledge_automation_settings setting
    on setting.municipality_id = job.municipality_id
   and setting.enabled
  where job.status in ('queued', 'failed') and job.available_at <= now();
  if v_embedding_jobs > 0
     and not exists (
       select 1
       from private.knowledge_scheduler_dispatches dispatch
       where dispatch.scope = 'embed'
         and dispatch.status = 'queued'
         and not exists (
           select 1
           from private.knowledge_scheduler_dispatch_events terminal
           where terminal.dispatch_id = dispatch.id
             and terminal.event_type in (
               'succeeded', 'retry_scheduled', 'circuit_opened', 'failed'
             )
         )
     )
     and not exists (
       select 1
       from private.knowledge_scheduler_dispatch_events terminal
       join private.knowledge_scheduler_dispatches dispatch
         on dispatch.id = terminal.dispatch_id
       where dispatch.scope = 'embed'
         and terminal.event_type in ('retry_scheduled', 'circuit_opened', 'failed')
         and terminal.retry_at > now()
     ) then
    select least(20, 1 + count(*))::smallint into v_attempt
    from private.knowledge_scheduler_dispatch_events failure_event
    join private.knowledge_scheduler_dispatches failed_dispatch
      on failed_dispatch.id = failure_event.dispatch_id
    where failed_dispatch.scope = 'embed'
      and failure_event.event_type in ('retry_scheduled', 'circuit_opened', 'failed')
      and failure_event.event_at > coalesce((
        select max(success_event.event_at)
        from private.knowledge_scheduler_dispatch_events success_event
        join private.knowledge_scheduler_dispatches success_dispatch
          on success_dispatch.id = success_event.dispatch_id
        where success_dispatch.scope = 'embed'
          and success_event.event_type = 'succeeded'
      ), '-infinity'::timestamptz);

    v_nonce := gen_random_uuid();
    v_issued_at := clock_timestamp();
    select net.http_post(
      url := v_project_url || '/functions/v1/ia-fiscal-knowledge-embed',
      headers := jsonb_build_object(
        'content-type', 'application/json',
        'authorization', 'Bearer ' || v_scheduler_secret,
        'x-ia-scheduler-nonce', v_nonce::text,
        'x-ia-scheduler-issued-at', v_issued_at::text
      ),
      body := jsonb_build_object('batch_size', least(32, v_embedding_jobs)),
      timeout_milliseconds := 90000
    ) into v_request_id;
    insert into private.knowledge_scheduler_dispatches (
      municipality_id, scope, request_id, attempt, status
    ) values (
      null, 'embed', v_request_id, v_attempt, 'queued'
    ) returning id into v_dispatch_id;
    insert into private.knowledge_scheduler_dispatch_events (
      dispatch_id, event_type, metadata
    ) values (
      v_dispatch_id,
      'queued',
      jsonb_build_object('lease_seconds', 120, 'attempt', v_attempt)
    );
    v_embedding_dispatched := true;
  end if;

  return jsonb_build_object(
    'queued', v_queued,
    'embedding_dispatch', v_embedding_dispatched,
    'reconciliation', v_reconciliation,
    'status', 'queued'
  );
end;
$$;

alter function public.ia_get_knowledge_operations_snapshot(uuid)
  rename to ia_get_knowledge_operations_snapshot_v1;

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
  v_membership_id uuid;
  v_can_review_candidates boolean;
  v_candidate_reviews jsonb;
  v_schedule jsonb;
  v_reviewer jsonb;
  v_phase2_summary jsonb;
  v_business_date date;
  v_runtime_verified boolean;
begin
  v_base := public.ia_get_knowledge_operations_snapshot_v1(p_municipality_id);
  v_membership_id := private.current_municipality_membership_id(
    p_municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception using errcode = '42501', message = 'municipality staff access required';
  end if;
  perform private.expire_legal_reviewer_capabilities(
    500,
    p_municipality_id,
    null
  );
  v_can_review_candidates := private.has_legal_reviewer_capability(p_municipality_id);
  v_business_date := private.municipality_current_date(p_municipality_id);
  v_runtime_verified := private.knowledge_runtime_is_verified();

  select coalesce(jsonb_agg(jsonb_build_object(
    'queue_kind', 'learning_candidate',
    'item_id', candidate.id,
    'candidate_id', candidate.id,
    'title', candidate.question,
    'status', candidate.status,
    'content_sha256', candidate.content_sha256,
    'submitted_at', candidate.created_at,
    'last_reviewed_at', candidate.reviewed_at,
    'blockers', case when candidate.status = 'pending_review'
      then jsonb_build_array('candidate_not_reviewed')
      else '[]'::jsonb
    end,
    'can_review', (
      v_can_review_candidates
      and candidate.status = 'pending_review'
      and candidate.submitted_by_membership_id <> v_membership_id
    ),
    'can_publish', false,
    'question', candidate.question,
    'proposed_answer_preview', left(candidate.proposed_answer, 240),
    'citation_count', cardinality(candidate.citation_section_ids),
    'source_id', null,
    'change_set_id', null,
    'candidate_version_id', null,
    'article_id', null,
    'revision_id', null
  ) order by candidate.created_at desc, candidate.id desc), '[]'::jsonb)
  into v_candidate_reviews
  from private.knowledge_candidate_submissions candidate
  where candidate.municipality_id = p_municipality_id
    and candidate.status in ('pending_review', 'approved', 'rejected');

  select jsonb_build_object(
    'enabled', setting.enabled and v_runtime_verified,
    'cadence', case setting.cadence_minutes
      when 1440 then 'Diariamente, às ' || to_char(setting.local_run_time, 'HH24:MI')
      else 'A cada ' || setting.cadence_minutes || ' minutos'
    end,
    'next_run_at', case when setting.enabled and v_runtime_verified
      then setting.next_run_at else null end,
    'last_run_at', setting.last_run_at,
    'last_run_status', coalesce(setting.last_run_status, 'never_run'),
    'timezone', setting.timezone,
    'runtime_verified', v_runtime_verified,
    'runtime_blocker', case when v_runtime_verified
      then null else 'knowledge_runtime_not_verified' end
  ) into v_schedule
  from private.knowledge_automation_settings setting
  where setting.municipality_id = p_municipality_id;

  select jsonb_build_object(
    'verified', true,
    'configured', count(*) > 0,
    'active_count', count(*),
    'current_user_can_review', v_can_review_candidates,
    'blockers', case when count(*) > 0 then '[]'::jsonb
      else jsonb_build_array('legal_reviewer_not_configured') end
  ) into v_reviewer
  from (
    select capability.membership_id
    from private.legal_reviewer_capability_grants capability
    where capability.municipality_id = p_municipality_id
      and capability.status = 'active'
      and capability.valid_from <= now()
      and (capability.valid_until is null or capability.valid_until > now())
    union
    select membership.id
    from public.municipality_memberships membership
    where membership.municipality_id = p_municipality_id
      and membership.role = 'legal_reviewer'
      and membership.status = 'active'
      and membership.valid_from <= now()
      and (membership.valid_until is null or membership.valid_until > now())
  ) active_reviewer;

  select jsonb_build_object(
    'eligible_sections', (
      select count(distinct section.id)
      from public.legal_sections section
      join public.legal_source_versions version
        on version.municipality_id = section.municipality_id
       and version.id = section.source_version_id
      join public.legal_sources source
        on source.municipality_id = version.municipality_id
       and source.id = version.source_id
      where section.municipality_id = p_municipality_id
        and private.legal_source_version_is_current_citable(
          version.municipality_id,
          version.id
        )
    ),
    'indexed_sections', (
      select count(distinct section.id)
      from public.legal_sections section
      join public.legal_source_versions version
        on version.municipality_id = section.municipality_id
       and version.id = section.source_version_id
      join public.legal_sources source
        on source.municipality_id = version.municipality_id
       and source.id = version.source_id
      join private.legal_chunks chunk
        on chunk.municipality_id = section.municipality_id
       and chunk.legal_section_id = section.id
      join private.legal_embeddings embedding
        on embedding.municipality_id = chunk.municipality_id
       and embedding.legal_chunk_id = chunk.id
       and embedding.source_sha256 = chunk.content_sha256
       and embedding.model_revision = 'gte-small-384-v1'
      where section.municipality_id = p_municipality_id
        and private.legal_source_version_is_current_citable(
          version.municipality_id,
          version.id
        )
    ),
    'indexed_chunks', (
      select count(*)
      from private.legal_embeddings embedding
      where embedding.municipality_id = p_municipality_id
        and embedding.model_revision = 'gte-small-384-v1'
    ),
    'pending_embeddings', (
      select count(*)
      from private.legal_embedding_jobs job
      where job.municipality_id = p_municipality_id
        and job.status in ('queued', 'processing', 'failed')
    ),
    'pending_candidates', (
      select count(*)
      from private.knowledge_candidate_submissions candidate
      where candidate.municipality_id = p_municipality_id
        and candidate.status = 'pending_review'
    ),
    'last_indexed_at', (
      select max(embedding.created_at)
      from private.legal_embeddings embedding
      where embedding.municipality_id = p_municipality_id
        and embedding.model_revision = 'gte-small-384-v1'
    )
  ) into v_phase2_summary;

  return v_base
    || jsonb_build_object(
      'capabilities', coalesce(v_base -> 'capabilities', '{}'::jsonb)
        || jsonb_build_object(
          'can_search', v_runtime_verified,
          'can_submit_candidates', true,
          'can_review_candidates', v_can_review_candidates,
          'can_review_source_versions', v_can_review_candidates,
          'can_publish_source_versions', v_can_review_candidates,
          'can_publish_articles', v_can_review_candidates
        ),
      'summary', coalesce(v_base -> 'summary', '{}'::jsonb) || v_phase2_summary,
      'schedule', coalesce(v_schedule, jsonb_build_object(
        'enabled', false,
        'cadence', 'Diariamente, às 03:15',
        'next_run_at', null,
        'last_run_at', null,
        'last_run_status', 'never_run',
        'timezone', (
          select municipality.timezone from public.municipalities municipality
          where municipality.id = p_municipality_id
        ),
        'runtime_verified', v_runtime_verified,
        'runtime_blocker', case when v_runtime_verified
          then null else 'knowledge_runtime_not_verified' end
      )),
      'reviewer', v_reviewer,
      'reviews', coalesce(v_base -> 'reviews', '[]'::jsonb) || v_candidate_reviews
    );
end;
$$;

alter function public.ia_get_knowledge_article_evidence(uuid, uuid, uuid)
  rename to ia_get_knowledge_article_evidence_v1;

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
  v_base jsonb;
  v_legal_reviewer boolean;
begin
  v_base := public.ia_get_knowledge_article_evidence_v1(
    p_municipality_id,
    p_article_id,
    p_revision_id
  );
  v_legal_reviewer := private.has_legal_reviewer_capability(p_municipality_id);
  return v_base || jsonb_build_object(
    'can_review', (
      coalesce((v_base ->> 'can_review')::boolean, false)
      or (
        v_legal_reviewer
        and v_base ->> 'status' in ('draft', 'under_review', 'revision_requested')
        and coalesce((v_base ->> 'evidence_complete')::boolean, false)
      )
    ),
    'can_publish', (
      v_legal_reviewer
      and v_base ->> 'status' = 'approved'
      and coalesce((v_base ->> 'evidence_complete')::boolean, false)
    )
  );
end;
$$;

alter function public.ia_get_legal_source_change_evidence(
  uuid, uuid, integer, integer, integer, integer
) rename to ia_get_legal_source_change_evidence_v1;

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
  v_base jsonb;
  v_legal_reviewer boolean;
begin
  v_base := public.ia_get_legal_source_change_evidence_v1(
    p_municipality_id,
    p_change_set_id,
    p_content_offset,
    p_content_limit,
    p_section_offset,
    p_section_limit
  );
  v_legal_reviewer := private.has_legal_reviewer_capability(p_municipality_id);
  return v_base || jsonb_build_object(
    'can_review', (
      v_legal_reviewer
      and v_base ->> 'status' in ('detected', 'changes_requested')
      and v_base ->> 'candidate_version_id' is not null
      and v_base ->> 'change_type' <> 'legacy_import'
    ),
    'can_publish', (
      v_legal_reviewer
      and v_base ->> 'status' = 'accepted'
      and v_base ->> 'candidate_version_status' = 'approved'
      and coalesce((v_base ->> 'evidence_complete')::boolean, false)
    )
  );
end;
$$;

-- Discovery is separate from evidence.  Links found on an official ficha may
-- The eight-argument overload pages every change item and carries a stable
-- hash of the full ordered set.  Approval still recomputes all evidence in
-- the database and never trusts the client-side page or hash.
create or replace function public.ia_get_legal_source_change_evidence(
  p_municipality_id uuid,
  p_change_set_id uuid,
  p_content_offset integer,
  p_content_limit integer,
  p_section_offset integer,
  p_section_limit integer,
  p_change_item_offset integer,
  p_change_item_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_items jsonb;
  v_total integer;
  v_full_sha256 text;
begin
  if p_change_item_offset < 0 or p_change_item_limit not between 1 and 100 then
    raise exception 'invalid change item pagination';
  end if;
  v_base := public.ia_get_legal_source_change_evidence(
    p_municipality_id,
    p_change_set_id,
    p_content_offset,
    p_content_limit,
    p_section_offset,
    p_section_limit
  );

  select count(*)::integer,
         encode(extensions.digest(coalesce(string_agg(
           concat_ws('|', item.ordinal::text, item.item_kind, item.item_path,
             coalesce(item.before_sha256, ''), coalesce(item.after_sha256, ''),
             item.summary), E'\n' order by item.ordinal, item.id
         ), ''), 'sha256'), 'hex')
    into v_total, v_full_sha256
  from private.legal_source_change_items item
  where item.municipality_id = p_municipality_id
    and item.change_set_id = p_change_set_id;

  select coalesce(jsonb_agg(page.payload order by page.ordinal, page.id), '[]'::jsonb)
    into v_items
  from (
    select item.ordinal, item.id, jsonb_build_object(
      'ordinal', item.ordinal,
      'item_kind', item.item_kind,
      'item_path', item.item_path,
      'before_sha256', item.before_sha256,
      'after_sha256', item.after_sha256,
      'before_excerpt', item.before_excerpt,
      'after_excerpt', item.after_excerpt,
      'summary', item.summary
    ) as payload
    from private.legal_source_change_items item
    where item.municipality_id = p_municipality_id
      and item.change_set_id = p_change_set_id
    order by item.ordinal, item.id
    offset p_change_item_offset
    limit p_change_item_limit
  ) page;

  return v_base || jsonb_build_object(
    'change_items', v_items,
    'change_item_offset', p_change_item_offset,
    'change_item_limit', p_change_item_limit,
    'change_item_total', v_total,
    'change_items_has_more', p_change_item_offset + p_change_item_limit < v_total,
    'change_items_full_sha256', v_full_sha256
  );
end;
$$;

-- Discovery is separate from evidence.  Links found on an official ficha may
-- be queued and reconciled, but are never treated as a canonical legal body
-- merely because they appeared on the page.
create table private.legal_source_discovered_assets (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  source_id uuid not null,
  endpoint_id uuid not null,
  asset_url text not null check (asset_url ~ '^https://[^[:space:]]+$'),
  relation_kind text not null
    check (relation_kind in ('attachment', 'previous_version', 'related_document', 'publication_copy')),
  declared_mime_type text,
  declared_byte_size bigint check (declared_byte_size is null or declared_byte_size >= 0),
  status text not null default 'discovered'
    check (status in ('discovered', 'selected', 'blocked', 'reconciled')),
  blocker_code text check (
    blocker_code is null
    or blocker_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  first_observed_at timestamptz not null,
  last_observed_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_source_discovered_assets_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_source_discovered_assets_endpoint_fk
    foreign key (municipality_id, endpoint_id)
    references private.legal_source_endpoints(municipality_id, id),
  constraint legal_source_discovered_assets_url_uq
    unique (municipality_id, source_id, asset_url),
  constraint legal_source_discovered_assets_municipality_id_id_uq
    unique (municipality_id, id)
);

create index legal_source_discovered_assets_queue_idx
  on private.legal_source_discovered_assets (municipality_id, status, first_observed_at)
  where status in ('discovered', 'blocked');

create or replace function public.ia_fiscal_record_knowledge_discoveries(
  p_endpoint_id uuid,
  p_assets jsonb,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_endpoint private.legal_source_endpoints%rowtype;
  v_asset jsonb;
  v_url text;
  v_host text;
  v_relation_kind text;
  v_mime_type text;
  v_byte_size bigint;
  v_blocker text;
  v_count integer := 0;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_assets is null
     or jsonb_typeof(p_assets) <> 'array'
     or jsonb_array_length(p_assets) not between 1 and 100 then
    raise exception 'discoveries must contain 1 to 100 assets';
  end if;
  if p_observed_at is null or p_observed_at > now() + interval '5 minutes' then
    raise exception 'invalid discovery timestamp';
  end if;
  select endpoint.* into strict v_endpoint
  from private.legal_source_endpoints endpoint
  where endpoint.id = p_endpoint_id and endpoint.status <> 'retired';

  for v_asset in select value from jsonb_array_elements(p_assets)
  loop
    if jsonb_typeof(v_asset) <> 'object' then
      raise exception 'every discovery must be a JSON object';
    end if;
    v_url := trim(coalesce(v_asset ->> 'url', ''));
    v_host := lower(split_part(split_part(v_url, '://', 2), '/', 1));
    v_relation_kind := coalesce(v_asset ->> 'relation_kind', 'attachment');
    v_mime_type := nullif(lower(trim(coalesce(v_asset ->> 'mime_type', ''))), '');
    begin
      v_byte_size := nullif(v_asset ->> 'byte_size', '')::bigint;
    exception when others then
      raise exception 'discovery byte size must be an integer';
    end;
    if v_url !~ '^https://[^[:space:]]+$'
       or not (v_host = any(v_endpoint.allowed_hosts))
       or v_relation_kind not in ('attachment', 'previous_version', 'related_document', 'publication_copy')
       or (v_byte_size is not null and v_byte_size < 0) then
      raise exception 'discovered asset is outside the endpoint allowlist';
    end if;
    v_blocker := case
      when v_byte_size > 50 * 1024 * 1024 then 'external_large_file_extractor_required'
      when v_mime_type in ('application/rtf', 'text/rtf', 'application/msword')
        then 'legacy_document_extractor_required'
      else null
    end;

    insert into private.legal_source_discovered_assets (
      municipality_id,
      source_id,
      endpoint_id,
      asset_url,
      relation_kind,
      declared_mime_type,
      declared_byte_size,
      status,
      blocker_code,
      first_observed_at,
      last_observed_at
    ) values (
      v_endpoint.municipality_id,
      v_endpoint.source_id,
      v_endpoint.id,
      v_url,
      v_relation_kind,
      v_mime_type,
      v_byte_size,
      case when v_blocker is null then 'discovered' else 'blocked' end,
      v_blocker,
      p_observed_at,
      p_observed_at
    ) on conflict (municipality_id, source_id, asset_url) do update set
      last_observed_at = greatest(
        private.legal_source_discovered_assets.last_observed_at,
        excluded.last_observed_at
      ),
      declared_mime_type = coalesce(
        excluded.declared_mime_type,
        private.legal_source_discovered_assets.declared_mime_type
      ),
      declared_byte_size = coalesce(
        excluded.declared_byte_size,
        private.legal_source_discovered_assets.declared_byte_size
      ),
      updated_at = now();
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('endpoint_id', v_endpoint.id, 'recorded_assets', v_count);
end;
$$;

-- Wave 1: only representations for which the current extractor is viable are
-- citable.  Ficha/catalog endpoints remain discovery-only.  LC 36/2013 is
-- intentionally blocked because its available PDF/RTF/DOC files exceed or
-- fall outside this worker's safe parser contract.
update private.legal_source_endpoints endpoint
set status = 'paused',
    metadata = endpoint.metadata || jsonb_build_object(
      'activation_blocker', 'superseded_by_verified_publication_copy'
    )
from public.legal_sources source
join public.municipalities municipality on municipality.id = source.municipality_id
where endpoint.municipality_id = source.municipality_id
  and endpoint.source_id = source.id
  and municipality.slug = 'cordeiropolis-sp'
  and source.official_identifier = 'Lei Complementar nº 399/2024'
  and endpoint.status = 'active';

insert into private.legal_source_endpoints (
  municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
  citable_body, url, allowed_hosts, expected_content_types, parser_hint,
  poll_interval, priority, status, metadata
)
select
  source.municipality_id,
  source.id,
  'document_file',
  'primary_publication',
  'legal_body',
  true,
  'https://www.cordeiropolis.sp.gov.br/wp-content/uploads/2024/12/Edicao-1645-_C.pdf',
  array['www.cordeiropolis.sp.gov.br']::text[],
  array['application/pdf', 'application/octet-stream']::text[],
  'pdf_text',
  interval '6 hours',
  1,
  'active',
  jsonb_build_object(
    'scope', 'codigo_tributario',
    'publication', 'Jornal do Municipio, edicao 1645',
    'page_range', '2-31',
    'representation_status', 'awaiting_human_reconciliation_with_siscam_121758'
  )
from public.legal_sources source
join public.municipalities municipality on municipality.id = source.municipality_id
where municipality.slug = 'cordeiropolis-sp'
  and source.official_identifier = 'Lei Complementar nº 399/2024'
on conflict (municipality_id, source_id, url) do update set
  content_mode = 'legal_body',
  citable_body = true,
  parser_hint = 'pdf_text',
  poll_interval = interval '6 hours',
  priority = 1,
  status = 'active',
  metadata = excluded.metadata;

update private.legal_source_endpoints endpoint
set status = 'paused',
    metadata = endpoint.metadata || jsonb_build_object(
      'activation_blocker', 'superseded_by_primary_pdf_attachment'
    )
from public.legal_sources source
join public.municipalities municipality on municipality.id = source.municipality_id
where endpoint.municipality_id = source.municipality_id
  and endpoint.source_id = source.id
  and municipality.slug = 'araras-sp'
  and source.official_identifier = 'Lei nº 3.362/2001'
  and endpoint.status = 'active';

insert into private.legal_source_endpoints (
  municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
  citable_body, url, allowed_hosts, expected_content_types, parser_hint,
  poll_interval, priority, status, metadata
)
select
  source.municipality_id,
  source.id,
  'document_file',
  'primary_publication',
  'legal_body',
  true,
  'https://araras.siscam.com.br/arquivo?Id=43123',
  array['araras.siscam.com.br']::text[],
  array['application/pdf', 'application/octet-stream']::text[],
  'pdf_text',
  interval '1 day',
  1,
  'active',
  jsonb_build_object(
    'scope', 'codigo_tributario',
    'ficha_id', 74258,
    'alternate_docx_id', 55229,
    'alternate_rtf_id', 50282,
    'representation_status', 'awaiting_human_reconciliation'
  )
from public.legal_sources source
join public.municipalities municipality on municipality.id = source.municipality_id
where municipality.slug = 'araras-sp'
  and source.official_identifier = 'Lei nº 3.362/2001'
on conflict (municipality_id, source_id, url) do update set
  content_mode = 'legal_body',
  citable_body = true,
  parser_hint = 'pdf_text',
  priority = 1,
  status = 'active',
  metadata = excluded.metadata;

update private.legal_source_endpoints endpoint
set content_mode = 'catalog_only',
    citable_body = false,
    poll_interval = interval '6 hours',
    metadata = endpoint.metadata || jsonb_build_object(
      'activation_blocker', 'large_or_legacy_attachment_extractor_required',
      'known_assets', jsonb_build_array(
        jsonb_build_object('id', 49705, 'mime', 'application/rtf', 'bytes', 24600000),
        jsonb_build_object('id', 49707, 'mime', 'application/pdf', 'bytes', 136000000),
        jsonb_build_object('id', 49708, 'mime', 'application/msword', 'bytes', 13700000)
      )
    )
from public.legal_sources source
join public.municipalities municipality on municipality.id = source.municipality_id
where endpoint.municipality_id = source.municipality_id
  and endpoint.source_id = source.id
  and municipality.slug = 'araras-sp'
  and source.official_identifier = 'Lei Complementar nº 36/2013'
  and endpoint.status <> 'retired';

create or replace function public.ia_fiscal_attest_knowledge_runtime_ready(
  p_project_ref text,
  p_ingest_contract text,
  p_ingest_deployment_id text,
  p_ingest_release_fingerprint text,
  p_embed_contract text,
  p_embed_deployment_id text,
  p_embed_release_fingerprint text,
  p_search_contract text,
  p_search_deployment_id text,
  p_search_release_fingerprint text,
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
  if p_confirmation is distinct from 'ATESTAR RUNTIME SEGUNDO CEREBRO' then
    raise exception 'explicit runtime attestation confirmation required';
  end if;
  if p_project_ref is null
     or p_project_ref !~ '^[a-z0-9]{15,40}$'
     or p_project_ref is distinct from private.knowledge_scheduler_project_ref() then
    raise exception 'runtime project reference does not match the configured scheduler project';
  end if;
  if p_ingest_contract is distinct from 'knowledge-ingest-v2'
     or p_embed_contract is distinct from 'knowledge-embed-v1'
     or p_search_contract is distinct from 'knowledge-search-v1'
     or coalesce(p_ingest_deployment_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'
     or coalesce(p_embed_deployment_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'
     or coalesce(p_search_deployment_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'
     or coalesce(p_ingest_release_fingerprint, '') !~ '^[a-f0-9]{64}$'
     or coalesce(p_embed_release_fingerprint, '') !~ '^[a-f0-9]{64}$'
     or coalesce(p_search_release_fingerprint, '') !~ '^[a-f0-9]{64}$'
     or coalesce(p_smoke_evidence_sha256, '') !~ '^[a-f0-9]{64}$'
     or char_length(trim(coalesce(p_smoke_evidence_locator, ''))) not between 8 and 500
     or p_smoke_evidence_locator ~ '[[:cntrl:]]'
     or p_valid_until is null
     or p_valid_until <= now() + interval '15 minutes'
     or p_valid_until > now() + interval '7 days' then
    raise exception 'runtime contract or smoke evidence is invalid';
  end if;
  insert into private.knowledge_runtime_release_gates (
    project_ref,
    ingest_contract,
    ingest_deployment_id,
    ingest_release_fingerprint,
    embed_contract,
    embed_deployment_id,
    embed_release_fingerprint,
    search_contract,
    search_deployment_id,
    search_release_fingerprint,
    smoke_evidence_sha256,
    smoke_evidence_locator,
    valid_until
  ) values (
    p_project_ref,
    p_ingest_contract,
    p_ingest_deployment_id,
    p_ingest_release_fingerprint,
    p_embed_contract,
    p_embed_deployment_id,
    p_embed_release_fingerprint,
    p_search_contract,
    p_search_deployment_id,
    p_search_release_fingerprint,
    p_smoke_evidence_sha256,
    trim(p_smoke_evidence_locator),
    p_valid_until
  ) returning id into v_gate_id;

  insert into private.knowledge_runtime_gate_events (
    project_ref,
    runtime_gate_id,
    event_type,
    reason_code,
    metadata
  ) values (
    p_project_ref,
    v_gate_id,
    'attested',
    'runtime_smoke_evidence_attested',
    jsonb_build_object(
      'ingest_deployment_id', p_ingest_deployment_id,
      'embed_deployment_id', p_embed_deployment_id,
      'search_deployment_id', p_search_deployment_id,
      'evidence_locator', trim(p_smoke_evidence_locator),
      'valid_until', p_valid_until
    )
  );

  insert into private.knowledge_runtime_current_gates (
    project_ref,
    runtime_gate_id,
    selected_at
  ) values (
    p_project_ref,
    v_gate_id,
    now()
  ) on conflict (project_ref) do update set
    runtime_gate_id = excluded.runtime_gate_id,
    selected_at = excluded.selected_at;

  insert into private.knowledge_runtime_gate_events (
    project_ref,
    runtime_gate_id,
    event_type,
    reason_code
  ) values (
    p_project_ref,
    v_gate_id,
    'selected',
    'runtime_gate_selected_for_activation'
  );
  return v_gate_id;
end;
$$;

create or replace function public.ia_fiscal_revoke_knowledge_runtime_gate(
  p_runtime_gate_id uuid,
  p_reason text,
  p_confirmation text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gate private.knowledge_runtime_release_gates%rowtype;
  v_inserted integer;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_confirmation is distinct from 'REVOGAR RUNTIME SEGUNDO CEREBRO' then
    raise exception 'explicit runtime revocation confirmation required';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 10 and 500 then
    raise exception 'runtime revocation reason must contain 10 to 500 characters';
  end if;

  select gate.* into strict v_gate
  from private.knowledge_runtime_release_gates gate
  where gate.id = p_runtime_gate_id
  for update;

  insert into private.knowledge_runtime_gate_events (
    project_ref,
    runtime_gate_id,
    event_type,
    reason_code,
    metadata
  ) values (
    v_gate.project_ref,
    v_gate.id,
    'revoked',
    'runtime_gate_revoked',
    jsonb_build_object('reason', trim(p_reason))
  ) on conflict do nothing;
  get diagnostics v_inserted = row_count;

  delete from private.knowledge_runtime_current_gates current_gate
  where current_gate.project_ref = v_gate.project_ref
    and current_gate.runtime_gate_id = v_gate.id;

  return v_inserted = 1;
end;
$$;

create or replace function private.guard_knowledge_candidate_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'knowledge candidates are retained as governed evidence';
  end if;
  if (to_jsonb(old)
        - 'status'
        - 'reviewed_by_membership_id'
        - 'review_notes'
        - 'reviewed_at'
        - 'updated_at')
     is distinct from
     (to_jsonb(new)
        - 'status'
        - 'reviewed_by_membership_id'
        - 'review_notes'
        - 'reviewed_at'
        - 'updated_at') then
    raise exception 'knowledge candidate content is immutable';
  end if;
  return new;
end;
$$;

create trigger knowledge_candidate_submission_guard
before update or delete on private.knowledge_candidate_submissions
for each row execute function private.guard_knowledge_candidate_submission();

create trigger legal_reviewer_capability_set_updated_at
before update on private.legal_reviewer_capability_grants
for each row execute function private.set_updated_at();

create trigger knowledge_automation_settings_set_updated_at
before update on private.knowledge_automation_settings
for each row execute function private.set_updated_at();

create trigger legal_source_discovered_assets_set_updated_at
before update on private.legal_source_discovered_assets
for each row execute function private.set_updated_at();

create trigger legal_reviewer_capability_events_append_only
before update or delete on private.legal_reviewer_capability_events
for each row execute function private.prevent_any_mutation();

create trigger legal_embedding_job_events_append_only
before update or delete on private.legal_embedding_job_events
for each row execute function private.prevent_any_mutation();

create trigger knowledge_candidate_events_append_only
before update or delete on private.knowledge_candidate_events
for each row execute function private.prevent_any_mutation();

create trigger knowledge_scheduler_dispatches_append_only
before update or delete on private.knowledge_scheduler_dispatches
for each row execute function private.prevent_any_mutation();

create trigger knowledge_scheduler_dispatch_events_append_only
before update or delete on private.knowledge_scheduler_dispatch_events
for each row execute function private.prevent_any_mutation();

create trigger knowledge_runtime_release_gates_append_only
before update or delete on private.knowledge_runtime_release_gates
for each row execute function private.prevent_any_mutation();

create trigger knowledge_runtime_gate_events_append_only
before update or delete on private.knowledge_runtime_gate_events
for each row execute function private.prevent_any_mutation();

create trigger knowledge_schedule_activation_events_append_only
before update or delete on private.knowledge_schedule_activation_events
for each row execute function private.prevent_any_mutation();

alter table private.legal_reviewer_capability_grants enable row level security;
alter table private.legal_reviewer_capability_events enable row level security;
alter table private.legal_embedding_jobs enable row level security;
alter table private.legal_embedding_claim_cursors enable row level security;
alter table private.legal_embedding_job_events enable row level security;
alter table private.knowledge_candidate_submissions enable row level security;
alter table private.knowledge_candidate_events enable row level security;
alter table private.knowledge_automation_settings enable row level security;
alter table private.knowledge_scheduler_nonces enable row level security;
alter table private.knowledge_scheduler_dispatches enable row level security;
alter table private.knowledge_scheduler_dispatch_events enable row level security;
alter table private.legal_source_discovered_assets enable row level security;
alter table private.knowledge_runtime_release_gates enable row level security;
alter table private.knowledge_runtime_gate_events enable row level security;
alter table private.knowledge_runtime_current_gates enable row level security;
alter table private.knowledge_schedule_activation_events enable row level security;

revoke all on
  private.legal_reviewer_capability_grants,
  private.legal_reviewer_capability_events,
  private.legal_embedding_jobs,
  private.legal_embedding_claim_cursors,
  private.legal_embedding_job_events,
  private.knowledge_candidate_submissions,
  private.knowledge_candidate_events,
  private.knowledge_automation_settings,
  private.knowledge_scheduler_nonces,
  private.knowledge_scheduler_dispatches,
  private.knowledge_scheduler_dispatch_events,
  private.legal_source_discovered_assets,
  private.knowledge_runtime_release_gates,
  private.knowledge_runtime_gate_events,
  private.knowledge_runtime_current_gates,
  private.knowledge_schedule_activation_events
from public, anon, authenticated, service_role;

revoke all on function private.has_legal_reviewer_capability(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.expire_legal_reviewer_capabilities(integer, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.current_legal_reviewer_membership_id(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.knowledge_runtime_is_verified()
  from public, anon, authenticated, service_role;
revoke all on function private.knowledge_scheduler_project_ref()
  from public, anon, authenticated, service_role;
revoke all on function private.current_knowledge_runtime_gate_id()
  from public, anon, authenticated, service_role;
revoke all on function private.lock_current_knowledge_runtime_gate_id()
  from public, anon, authenticated, service_role;
revoke all on function private.enqueue_legal_embedding_job()
  from public, anon, authenticated, service_role;
revoke all on function private.prevent_knowledge_self_review()
  from public, anon, authenticated, service_role;
revoke all on function private.knowledge_retrieval_confidence(double precision, double precision)
  from public, anon, authenticated, service_role;
revoke all on function private.legal_source_version_is_current_citable(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.knowledge_staging_matches_payload(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.guard_knowledge_candidate_submission()
  from public, anon, authenticated, service_role;
revoke all on function private.ia_fiscal_dispatch_due_knowledge_work(integer)
  from public, anon, authenticated, service_role;
revoke all on function private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(integer)
  from public, anon, authenticated, service_role;

revoke all on function public.ia_grant_legal_reviewer_capability(
  uuid, uuid, timestamptz, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.ia_grant_legal_reviewer_capability(
  uuid, uuid, timestamptz, text, text
) to authenticated;

revoke all on function public.ia_revoke_legal_reviewer_capability(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_revoke_legal_reviewer_capability(uuid, text, text)
  to authenticated;

revoke all on function public.ia_list_legal_reviewer_capabilities(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_list_legal_reviewer_capabilities(uuid)
  to authenticated;

revoke all on function public.ia_submit_knowledge_candidate(
  uuid, text, text, uuid[], text
) from public, anon, authenticated, service_role;
grant execute on function public.ia_submit_knowledge_candidate(
  uuid, text, text, uuid[], text
) to authenticated;

revoke all on function public.ia_get_knowledge_candidate_evidence(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_knowledge_candidate_evidence(uuid, uuid)
  to authenticated;

revoke all on function public.ia_review_knowledge_candidate(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_review_knowledge_candidate(uuid, uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_review_knowledge_candidate(uuid, uuid, text, text, text)
  to authenticated;

revoke all on function public.ia_review_legal_source_change(
  uuid, text, text, text, date, date, date
) from public, anon, authenticated, service_role;
revoke all on function public.ia_review_legal_source_change(
  uuid, uuid, text, text, text, date, date, date
) from public, anon, authenticated, service_role;
grant execute on function public.ia_review_legal_source_change(
  uuid, uuid, text, text, text, date, date, date
) to authenticated;

revoke all on function public.ia_publish_legal_source_version(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_publish_legal_source_version(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_publish_legal_source_version(uuid, uuid, text)
  to authenticated;

revoke all on function public.ia_review_knowledge_article(uuid, uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_review_knowledge_article(uuid, uuid, uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_review_knowledge_article(uuid, uuid, uuid, text, text, text)
  to authenticated;

revoke all on function public.ia_publish_knowledge_article(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_publish_knowledge_article(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_publish_knowledge_article(uuid, uuid, text)
  to authenticated;

revoke all on function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) to authenticated;

revoke all on function public.ia_configure_knowledge_schedule(uuid, boolean, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_configure_knowledge_schedule(uuid, boolean, text)
  to authenticated;

revoke all on function public.ia_fiscal_stage_knowledge_sections_legacy_impl(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_fiscal_stage_knowledge_sections(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_stage_knowledge_sections(uuid, jsonb)
  to service_role;

revoke all on function public.ia_fiscal_capture_knowledge_source(
  uuid, text, text, text, text, bigint, text, text, text,
  text, text, integer, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;

revoke all on function public.ia_fiscal_capture_knowledge_source_v2(
  uuid, text, text, text, text, bigint, text, text, text, jsonb,
  text, text, integer, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_capture_knowledge_source_v2(
  uuid, text, text, text, text, bigint, text, text, text, jsonb,
  text, text, integer, timestamptz, uuid, jsonb
) to service_role;

revoke all on function public.ia_fiscal_stage_knowledge_chunks(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_stage_knowledge_chunks(uuid, jsonb)
  to service_role;

revoke all on function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  to service_role;

revoke all on function public.ia_fiscal_complete_legal_embedding_job(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_complete_legal_embedding_job(uuid, text)
  to service_role;

revoke all on function public.ia_fiscal_fail_legal_embedding_job(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_fail_legal_embedding_job(uuid, text)
  to service_role;

revoke all on function public.ia_fiscal_validate_knowledge_scheduler_request(
  text, uuid, timestamptz, text
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_validate_knowledge_scheduler_request(
  text, uuid, timestamptz, text
) to service_role;

revoke all on function public.ia_fiscal_configure_knowledge_scheduler_project_url(text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_configure_knowledge_scheduler_project_url(text)
  to service_role;

revoke all on function public.ia_fiscal_record_knowledge_discoveries(
  uuid, jsonb, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_record_knowledge_discoveries(
  uuid, jsonb, timestamptz
) to service_role;

revoke all on function public.ia_fiscal_attest_knowledge_runtime_ready(
  text, text, text, text, text, text, text, text, text, text,
  text, text, timestamptz, text
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_attest_knowledge_runtime_ready(
  text, text, text, text, text, text, text, text, text, text,
  text, text, timestamptz, text
) to service_role;

revoke all on function public.ia_fiscal_revoke_knowledge_runtime_gate(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_revoke_knowledge_runtime_gate(uuid, text, text)
  to service_role;

revoke all on function public.ia_get_knowledge_operations_snapshot_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_get_knowledge_article_evidence_v1(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_get_legal_source_change_evidence_v1(
  uuid, uuid, integer, integer, integer, integer
) from public, anon, authenticated, service_role;

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
revoke all on function public.ia_get_legal_source_change_evidence(
  uuid, uuid, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.ia_get_legal_source_change_evidence(
  uuid, uuid, integer, integer, integer, integer, integer, integer
) to authenticated;

comment on table private.knowledge_candidate_submissions is
  'Non-canonical supervised learning queue. Approval never publishes knowledge automatically.';
comment on function public.ia_fiscal_hybrid_search_legal_knowledge(uuid, text, text, integer) is
  'AAL2 tenant-first hybrid legal retrieval over current, published, artifact-backed evidence.';
comment on function public.ia_fiscal_validate_knowledge_scheduler_request(text, uuid, timestamptz, text) is
  'Service-only fail-closed Vault hash, time-window and nonce validation for scheduler requests.';
comment on function public.ia_fiscal_capture_knowledge_source_v2(
  uuid, text, text, text, text, bigint, text, text, text, jsonb,
  text, text, integer, timestamptz, uuid, jsonb
) is
  'Service-only atomic capture, candidate version, integral section and exact chunk staging with retry/replay validation.';

commit;
