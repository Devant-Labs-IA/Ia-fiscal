-- Make the complete Portuguese lexical corpus the canonical legal retrieval
-- path. Supabase/gte-small is English-only and truncates inputs after 512
-- tokens, so its historical vectors cannot represent this PT-BR corpus
-- honestly. They remain retained as audit evidence, but are no longer claimed,
-- generated, counted as usable coverage or consulted by search.

begin;

-- Cut over only from a quiescent runtime. This turns the runbook ordering into
-- an executable guard: no old worker may already hold a lease or an in-flight
-- pg_net request while the retired model is being made unreachable.
lock table private.knowledge_automation_settings in share row exclusive mode;
lock table private.legal_embedding_jobs in share row exclusive mode;

do $$
begin
  if private.knowledge_runtime_is_verified() then
    raise exception using
      errcode = '55000',
      message = 'revoke the current knowledge runtime gate before lexical cutover';
  end if;
  if exists (
    select 1
    from private.knowledge_automation_settings setting
    where setting.enabled
  ) then
    raise exception using
      errcode = '55000',
      message = 'disable every knowledge automation setting before lexical cutover';
  end if;
  if exists (
    select 1
    from private.legal_embedding_jobs job
    where job.model_revision = 'gte-small-384-v1'
      and job.status = 'processing'
  ) then
    raise exception using
      errcode = '55000',
      message = 'wait for every retired semantic lease before lexical cutover';
  end if;
  if exists (
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
  ) then
    raise exception using
      errcode = '55000',
      message = 'wait for every retired semantic dispatch before lexical cutover';
  end if;
end;
$$;

create or replace function private.normalize_portuguese_lexical_text(
  p_value text
)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select pg_catalog.translate(
    pg_catalog.lower(coalesce(p_value, '')),
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  );
$$;

-- The indexed unit is the immutable legal section, not a chunk. Search below
-- accepts only the integral section whose hash and text are identical to the
-- artifact-backed source version. This proves full-content coverage without
-- inferring it from the presence of one or more derived chunks.
create index legal_sections_search_portuguese_idx
  on public.legal_sections using gin (
    pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text(content_text)
    )
  );

-- Keep every superseded implementation available for an explicit, gated
-- forward rollback. Renaming preserves the function OID and dependencies;
-- revocation prevents accidental direct invocation while lexical PT-BR is
-- canonical.
alter function private.enqueue_legal_embedding_job()
  rename to enqueue_legal_embedding_job_pre_lexical_ptbr;
revoke all on function private.enqueue_legal_embedding_job_pre_lexical_ptbr()
  from public, anon, authenticated, service_role;

-- Preserve the trigger contract but make it lazy: a future multilingual model
-- must install its own queueing implementation and release gate. New legal
-- sections create zero retired-model jobs.
create or replace function private.enqueue_legal_embedding_job()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  return new;
end;
$$;

drop trigger legal_chunks_enqueue_embedding on private.legal_chunks;
create trigger legal_chunks_enqueue_embedding
after insert on private.legal_chunks
for each row execute function private.enqueue_legal_embedding_job();

-- Atomically terminalize every still-claimable historical gte-small job. The
-- event stores the exact previous state needed by the gated compensation
-- script. Completed vectors remain immutable audit evidence.
with previous as materialized (
  select
    job.id,
    job.municipality_id,
    job.model_revision,
    job.status as previous_status,
    job.available_at as previous_available_at,
    job.locked_at as previous_locked_at,
    job.completed_at as previous_completed_at,
    job.safe_error_code as previous_safe_error_code,
    job.attempts
  from private.legal_embedding_jobs job
  where job.model_revision = 'gte-small-384-v1'
    and job.status in ('queued', 'processing', 'failed', 'dead_letter')
  for update
), retirement_events as (
  insert into private.legal_embedding_job_events as retirement_event (
    municipality_id,
    job_id,
    event_type,
    attempt,
    safe_error_code,
    metadata
  )
  select
    previous.municipality_id,
    previous.id,
    'skipped',
    previous.attempts,
    'semantic_model_language_unsupported',
    jsonb_strip_nulls(jsonb_build_object(
      'canonical_retrieval', 'lexical_portuguese',
      'semantic_status', 'unsupported_language',
      'retained_model_revision', previous.model_revision,
      'retirement_migration', 'make_portuguese_lexical_search_canonical',
      'previous_status', previous.previous_status,
      'previous_available_at', previous.previous_available_at,
      'previous_locked_at', previous.previous_locked_at,
      'previous_completed_at', previous.previous_completed_at,
      'previous_safe_error_code', previous.previous_safe_error_code
    ))
  from previous
  returning retirement_event.job_id
)
update private.legal_embedding_jobs job
set status = 'skipped',
    locked_at = null,
    completed_at = null,
    safe_error_code = 'semantic_model_language_unsupported',
    updated_at = now()
from previous
join retirement_events event on event.job_id = previous.id
where job.id = previous.id;

-- Preserve the worker RPC signature for a safe rolling deploy, while making
-- the retired model fail closed to an empty claim set.
alter function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  rename to ia_fiscal_claim_legal_embedding_jobs_pre_lexical_ptbr;
revoke all on function public.ia_fiscal_claim_legal_embedding_jobs_pre_lexical_ptbr(integer)
  from public, anon, authenticated, service_role;

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
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_batch_size not between 1 and 32 then
    raise exception 'embedding batch size must be between 1 and 32';
  end if;
  if private.lock_current_knowledge_runtime_gate_id() is null then
    raise exception using
      errcode = '55000',
      message = 'knowledge runtime is not verified';
  end if;

  -- gte-small-384-v1 is retained for audit only. A future multilingual model
  -- must introduce a new revision, explicit token contract and release gate.
  return;
end;
$$;

create or replace function private.knowledge_portuguese_lexical_confidence(
  p_lexical_score double precision,
  p_query_lexeme_count integer
)
returns double precision
language sql
immutable
parallel safe
set search_path = ''
as $$
  -- Cover density divides a compact cover by its lexeme count (for example,
  -- two adjacent PT-BR lexemes score about 0.05). Reapply that bounded count
  -- before the four-times calibration: a compact complete cover clears 0.35,
  -- while a distant cover remains far below it. The cap prevents an
  -- arbitrarily long query from inflating confidence.
  select least(1.0, greatest(
    0.0,
    coalesce(p_lexical_score, 0.0)
      * greatest(1, least(coalesce(p_query_lexeme_count, 1), 12))
      * 4.0
  ));
$$;

-- Ask PostgreSQL for its best cover fragment, map that normalized fragment
-- back to the literal official window and place the complete strong cover in
-- the compatible 1,500-character answer. Weak citations remain literal but do
-- not turn into an answer. Every mapping inconsistency fails closed.
create or replace function private.portuguese_lexical_literal_excerpt(
  p_window_text text,
  p_official_text text,
  p_query pg_catalog.tsquery,
  p_require_answer_cover boolean
)
returns text
language plpgsql
stable
parallel safe
set search_path = ''
as $$
declare
  v_window_text text := coalesce(p_window_text, '');
  v_official_text text := coalesce(p_official_text, '');
  v_normalized_text text;
  v_start_marker text;
  v_stop_marker text;
  v_fragment_marker text;
  v_highlighted_text text;
  v_plain_fragment text;
  v_fragment_start integer;
  v_first_marker_offset integer;
  v_hit_position integer;
  v_context_before integer;
  v_excerpt_start integer;
  v_excerpt text;
begin
  if p_query is null or trim(p_query::text) in ('', 'T') then
    raise exception using
      errcode = '22023',
      message = 'lexical excerpt requires a positive query';
  end if;
  if p_require_answer_cover is null then
    raise exception using
      errcode = '22023',
      message = 'lexical excerpt requires an explicit answer-cover policy';
  end if;
  if char_length(v_window_text) not between 1 and 12000
     or position(v_window_text in v_official_text) = 0 then
    raise exception using
      errcode = '22000',
      message = 'lexical window is not a bounded literal of official text';
  end if;

  v_normalized_text := private.normalize_portuguese_lexical_text(v_window_text);
  if char_length(v_normalized_text) <> char_length(v_window_text) then
    raise exception using
      errcode = '22000',
      message = 'Portuguese lexical normalization changed official text length';
  end if;
  if not (
    pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      v_normalized_text
    ) @@ p_query
  ) then
    raise exception using
      errcode = '22000',
      message = 'lexical window does not contain the parser-confirmed query';
  end if;

  -- Grow a deterministic marker until neither delimiter occurs in the source.
  -- This prevents source-controlled text from spoofing the hit position.
  v_start_marker := '__IA_FISCAL_LEXICAL_HIT_'
    || pg_catalog.md5(v_normalized_text) || '_START__';
  v_stop_marker := '__IA_FISCAL_LEXICAL_HIT_'
    || pg_catalog.md5(v_normalized_text) || '_STOP__';
  v_fragment_marker := '__IA_FISCAL_LEXICAL_HIT_'
    || pg_catalog.md5(v_normalized_text) || '_FRAGMENT__';
  while position(v_start_marker in v_normalized_text) > 0
     or position(v_stop_marker in v_normalized_text) > 0
     or position(v_fragment_marker in v_normalized_text) > 0 loop
    v_start_marker := v_start_marker || '_';
    v_stop_marker := v_stop_marker || '_';
    v_fragment_marker := v_fragment_marker || '_';
  end loop;

  -- MaxFragments=1 makes ts_headline select the best cover instead of the
  -- first isolated lexeme. The marker-stripped fragment must remain an exact
  -- substring of the normalized window before its offset can be reused.
  v_highlighted_text := pg_catalog.ts_headline(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    v_normalized_text,
    p_query,
    'StartSel=' || v_start_marker
      || ', StopSel=' || v_stop_marker
      || ', MaxWords=80, MinWords=1, ShortWord=1, MaxFragments=1'
      || ', FragmentDelimiter=' || v_fragment_marker
  );
  v_first_marker_offset := position(v_start_marker in v_highlighted_text);
  v_plain_fragment := pg_catalog.replace(
    pg_catalog.replace(v_highlighted_text, v_start_marker, ''),
    v_stop_marker,
    ''
  );
  v_fragment_start := position(v_plain_fragment in v_normalized_text);

  if v_first_marker_offset <= 0
     or position(v_stop_marker in v_highlighted_text) <= 0
     or position(v_fragment_marker in v_highlighted_text) > 0
     or char_length(v_plain_fragment) not between 1 and 12000
     or v_fragment_start <= 0
     or left(v_highlighted_text, v_first_marker_offset - 1)
       is distinct from left(v_plain_fragment, v_first_marker_offset - 1) then
    raise exception using
      errcode = '22000',
      message = 'could not map best Portuguese lexical cover to official text';
  end if;

  if p_require_answer_cover then
    if char_length(v_plain_fragment) > 1500
       or not (
         pg_catalog.to_tsvector(
           'pg_catalog.portuguese'::pg_catalog.regconfig,
           v_plain_fragment
         ) @@ p_query
       ) then
      raise exception using
        errcode = '22000',
        message = 'best Portuguese lexical cover does not fit the compatible answer';
    end if;
    v_context_before := least(
      250,
      greatest(0, 1500 - char_length(v_plain_fragment))
    );
    v_excerpt_start := greatest(1, v_fragment_start - v_context_before);
  else
    -- A weak result has no answer. Keep its citation literal and near the best
    -- fragment without requiring a distant low-confidence cover to fit 1,500.
    v_hit_position := v_fragment_start + v_first_marker_offset - 1;
    v_excerpt_start := greatest(1, v_hit_position - 500);
  end if;
  v_excerpt := substring(v_window_text from v_excerpt_start for 2000);

  if char_length(v_excerpt) > 2000
     or position(v_excerpt in v_official_text) = 0 then
    raise exception using
      errcode = '22000',
      message = 'lexical excerpt is not a bounded literal of official text';
  end if;
  if p_require_answer_cover and not (
    pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text(left(v_excerpt, 1500))
    ) @@ p_query
  ) then
    raise exception using
      errcode = '22000',
      message = 'compatible answer does not contain the full Portuguese lexical cover';
  end if;
  return v_excerpt;
end;
$$;

alter function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) rename to ia_fiscal_hybrid_search_legal_knowledge_pre_lexical_ptbr;
revoke all on function public.ia_fiscal_hybrid_search_legal_knowledge_pre_lexical_ptbr(
  uuid, text, text, integer
) from public, anon, authenticated, service_role;

-- The public name remains unchanged for compatibility. The complete,
-- artifact-backed Portuguese section drives the first materialized GIN
-- presence filter. Ranking uses every deterministic 12k/6k overlapping window
-- derived literally from those sections, so PostgreSQL's 16,383-position cap
-- cannot manufacture proximity or hide a deep phrase. Artifact/URL lateral
-- lookups run only after window ranking and limit.
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
  v_normalized_query text;
  v_limit integer := coalesce(p_limit, 8);
  v_tsquery pg_catalog.tsquery;
  v_presence_tsquery pg_catalog.tsquery;
  v_parsed_query text;
  v_indexable_query text;
  v_query_lexeme_count integer;
  v_citations jsonb;
  v_hit_count integer;
  v_top_lexical_score double precision;
  v_confidence double precision;
  v_answered boolean;
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

  -- p_query_embedding is intentionally accepted but ignored so old callers do
  -- not break during rollout. The response always discloses that semantics are
  -- unavailable for the installed English-only model.
  v_normalized_query := private.normalize_portuguese_lexical_text(v_query);
  v_tsquery := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    v_normalized_query
  );
  v_parsed_query := v_tsquery::text;
  v_indexable_query := trim(pg_catalog.querytree(v_tsquery));
  if v_indexable_query = '' or v_indexable_query = 'T' then
    raise exception using
      errcode = '22023',
      message = 'query must contain positive searchable Portuguese terms';
  end if;
  -- ts_rank_cd scores a disjunction when only one branch matches. Multiplying
  -- that score by every absent OR lexeme would manufacture high confidence.
  if position('|' in v_parsed_query) > 0
     or position('|' in v_indexable_query) > 0 then
    raise exception using
      errcode = '22023',
      message = 'OR queries are not supported by the calibrated Portuguese lexical release';
  end if;
  -- Negative terms are global document predicates. Applying them separately
  -- to overlapping windows would change their meaning, so fail closed until a
  -- future revision implements document-wide negative coverage explicitly.
  if position('!' in v_parsed_query) > 0 then
    raise exception using
      errcode = '22023',
      message = 'NOT queries are not supported by the calibrated Portuguese lexical release';
  end if;

  -- The integral GIN index is a presence filter only. PostgreSQL clamps
  -- tsvector positions at 16,383, so phrase distances are replaced by AND for
  -- candidate discovery and reapplied unchanged inside bounded windows below.
  v_presence_tsquery := pg_catalog.regexp_replace(
    v_indexable_query,
    '(<->|<[0-9]+>)',
    '&',
    'g'
  )::pg_catalog.tsquery;
  v_query_lexeme_count := greatest(1, coalesce(pg_catalog.cardinality(
    pg_catalog.tsvector_to_array(pg_catalog.to_tsvector(
      'pg_catalog.simple'::pg_catalog.regconfig,
      v_presence_tsquery::text
    ))
  ), 1));

  with lexical_candidates as materialized (
    select
      section.id as legal_section_id,
      section.content_text,
      section.content_sha256 as section_content_sha256,
      section.section_key,
      section.heading,
      version.id as source_version_id,
      version.source_id,
      version.content_sha256 as source_version_content_sha256,
      version.publication_date,
      version.valid_from,
      version.valid_until
    from public.legal_sections section
    join public.legal_source_versions version
      on version.municipality_id = section.municipality_id
     and version.id = section.source_version_id
    where section.municipality_id = p_municipality_id
      and section.content_sha256 = version.content_sha256
      and section.content_text = version.content_text
      and pg_catalog.to_tsvector(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(section.content_text)
      ) @@ v_presence_tsquery
  ), current_candidates as materialized (
    select candidate.*
    from lexical_candidates candidate
    where private.legal_source_version_is_current_citable(
      p_municipality_id,
      candidate.source_version_id
    )
  ), window_vectors as materialized (
    select
      candidate.legal_section_id,
      window_start.start_char as window_start_char,
      lexical_window.content_text as window_content_text,
      pg_catalog.to_tsvector(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(lexical_window.content_text)
      ) as window_vector
    from current_candidates candidate
    cross join lateral pg_catalog.generate_series(
      1,
      greatest(1, char_length(candidate.content_text)),
      6000
    ) window_start(start_char)
    cross join lateral (
      select substring(
        candidate.content_text from window_start.start_char for 12000
      ) as content_text
    ) lexical_window
  ), window_matches as materialized (
    select
      windowed.*,
      pg_catalog.ts_rank_cd(windowed.window_vector, v_tsquery)
        as lexical_score
    from window_vectors windowed
    where windowed.window_vector @@ v_tsquery
  ), best_windows as materialized (
    select distinct on (matched.legal_section_id)
      matched.*
    from window_matches matched
    order by
      matched.legal_section_id,
      matched.lexical_score desc,
      matched.window_start_char
  ), ranked_windows as materialized (
    select best.*
    from best_windows best
    order by best.lexical_score desc, best.legal_section_id
    limit v_limit
  ), eligible as materialized (
    select
      candidate.*,
      selected.window_start_char,
      selected.window_content_text,
      selected.lexical_score,
      source.title as source_title,
      source.official_identifier,
      captured.final_url as official_url
    from ranked_windows selected
    join current_candidates candidate
      on candidate.legal_section_id = selected.legal_section_id
    join public.legal_sources source
      on source.municipality_id = p_municipality_id
     and source.id = candidate.source_id
    join lateral (
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
      where mapping.municipality_id = p_municipality_id
        and mapping.source_version_id = candidate.source_version_id
        and artifact.source_id = candidate.source_id
        and artifact.extraction_status = 'completed'
        and artifact.extracted_text_sha256 = candidate.source_version_content_sha256
        and artifact.metadata ->> 'extraction_complete' = 'true'
        and artifact.metadata ->> 'content_truncated' = 'false'
        and case
          when coalesce(artifact.metadata ->> 'extracted_char_count', '')
                 ~ '^[0-9]+$'
            then (artifact.metadata ->> 'extracted_char_count')::numeric
                   = char_length(candidate.content_text)::numeric
          else false
        end
        and fetch_run.source_id = candidate.source_id
        and fetch_run.status = 'completed_changed'
        and fetch_run.observed_content_sha256 = artifact.content_sha256
        and fetch_run.final_url ~ '^https://[^[:space:]]+$'
      order by artifact.observed_at desc, artifact.id desc
      limit 1
    ) captured on true
  ), ranked as materialized (
    select eligible.*
    from eligible
  )
  select
    count(*)::integer,
    (array_agg(
      ranked.lexical_score
      order by ranked.lexical_score desc, ranked.legal_section_id
    ))[1],
    coalesce(jsonb_agg(jsonb_build_object(
      'legal_section_id', ranked.legal_section_id,
      'source_version_id', ranked.source_version_id,
      'source_title', ranked.source_title,
      'official_identifier', ranked.official_identifier,
      'official_url', ranked.official_url,
      'section_key', ranked.section_key,
      'heading', ranked.heading,
      'excerpt', private.portuguese_lexical_literal_excerpt(
        ranked.window_content_text,
        ranked.content_text,
        v_tsquery,
        private.knowledge_portuguese_lexical_confidence(
          ranked.lexical_score,
          v_query_lexeme_count
        ) >= v_min_confidence
      ),
      'publication_date', ranked.publication_date,
      'valid_from', ranked.valid_from,
      'valid_until', ranked.valid_until,
      'score', round(
        private.knowledge_portuguese_lexical_confidence(
          ranked.lexical_score,
          v_query_lexeme_count
        )::numeric,
        8
      ),
      'lexical_score', round(ranked.lexical_score::numeric, 6),
      'semantic_score', 0,
      'semantic_status', 'unsupported_language'
    ) order by ranked.lexical_score desc, ranked.legal_section_id), '[]'::jsonb)
  into
    v_hit_count,
    v_top_lexical_score,
    v_citations
  from ranked;

  v_confidence := private.knowledge_portuguese_lexical_confidence(
    v_top_lexical_score,
    v_query_lexeme_count
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
    'retrieval_mode', 'lexical_portuguese',
    'lexical_language', 'pt-BR',
    'semantic_status', 'unsupported_language',
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

alter function private.ia_fiscal_dispatch_due_knowledge_work(integer)
  rename to ia_fiscal_dispatch_due_knowledge_work_pre_lexical_ptbr;
revoke all on function private.ia_fiscal_dispatch_due_knowledge_work_pre_lexical_ptbr(integer)
  from public, anon, authenticated, service_role;

-- The scheduler remains responsible for governed source ingestion and reviewer
-- capability expiry, but it has no retired-model queue inspection, pg_net
-- request or retry branch. The compatibility response keeps
-- embedding_dispatch=false for existing observability consumers.
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
  v_attempt smallint;
  v_reconciliation jsonb;
  v_runtime_gate_id uuid;
begin
  if p_endpoint_batch not between 1 and 50 then
    raise exception 'endpoint batch must be between 1 and 50';
  end if;

  perform private.expire_legal_reviewer_capabilities(500);

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
      'semantic_status', 'unsupported_language',
      'reconciliation', jsonb_build_object(
        'status', 'skipped_runtime_not_verified'
      ),
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
      null, 'ingest', 'configuration_missing',
      'scheduler_vault_configuration_missing'
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
      'embedding_dispatch', false,
      'semantic_status', 'unsupported_language',
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
          and terminal.event_type in (
            'retry_scheduled', 'circuit_opened', 'failed'
          )
        order by terminal.event_at desc, terminal.id desc
        limit 1
      ) latest_retry on true
      where endpoint.municipality_id = v_setting.municipality_id
        and endpoint.status = 'active'
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
        coalesce(
          completed_fetch.last_completed_fetch_at,
          '-infinity'::timestamptz
        ),
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
        and failure_event.event_type in (
          'retry_scheduled', 'circuit_opened', 'failed'
        )
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
        last_run_status = case
          when v_remaining > 0 then 'partial' else 'queued'
        end,
        last_safe_error_code = null,
        next_run_at = case when v_remaining > 0
          then now() + interval '5 minutes'
          else ((private.municipality_current_date(v_setting.municipality_id) + 1
            + v_setting.local_run_time) at time zone v_setting.timezone)
        end,
        updated_at = now()
    where municipality_id = v_setting.municipality_id;
  end loop;

  return jsonb_build_object(
    'queued', v_queued,
    'embedding_dispatch', false,
    'semantic_status', 'unsupported_language',
    'reconciliation', v_reconciliation,
    'status', 'queued'
  );
end;
$$;

-- Reinterpret the legacy index counters as canonical lexical coverage and
-- expose semantic coverage separately. This avoids treating retained,
-- truncated English vectors as proof that Portuguese content was indexed.
alter function public.ia_get_knowledge_operations_snapshot(uuid)
  rename to ia_get_knowledge_operations_snapshot_pre_lexical_ptbr;

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
  v_eligible_sections integer;
  v_lexical_sections integer;
  v_lexical_chunks integer;
  v_last_lexical_index_at timestamptz;
  v_historical_semantic_chunks integer;
  v_lexical_index_ready boolean;
  v_lexical_full_content boolean;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception using errcode = '42501', message = 'aal2 authentication required';
  end if;

  v_base := public.ia_get_knowledge_operations_snapshot_pre_lexical_ptbr(
    p_municipality_id
  );

  -- A citable version already proves a complete artifact and an integral
  -- section. Count version-sized legal documents, never the existence of an
  -- arbitrary derived chunk.
  select count(distinct version.id)::integer
  into v_eligible_sections
  from public.legal_source_versions version
  where version.municipality_id = p_municipality_id
    and private.legal_source_version_is_current_citable(
      version.municipality_id,
      version.id
    );

  select
    count(distinct version.id)::integer,
    count(distinct section.id)::integer,
    max(section.created_at)
  into
    v_lexical_sections,
    v_lexical_chunks,
    v_last_lexical_index_at
  from public.legal_sections section
  join public.legal_source_versions version
    on version.municipality_id = section.municipality_id
   and version.id = section.source_version_id
  where section.municipality_id = p_municipality_id
    and section.content_sha256 = version.content_sha256
    and section.content_text = version.content_text
    and private.legal_source_version_is_current_citable(
      version.municipality_id,
      version.id
    );

  select coalesce(index_state.indisvalid and index_state.indisready, false)
  into v_lexical_index_ready
  from pg_catalog.pg_index index_state
  where index_state.indexrelid = pg_catalog.to_regclass(
    'public.legal_sections_search_portuguese_idx'
  );

  v_lexical_index_ready := coalesce(v_lexical_index_ready, false);
  v_lexical_full_content := v_lexical_index_ready
    and coalesce(v_eligible_sections, 0) = coalesce(v_lexical_sections, 0);

  select count(distinct embedding.legal_chunk_id)::integer
  into v_historical_semantic_chunks
  from private.legal_embeddings embedding
  where embedding.municipality_id = p_municipality_id
    and embedding.model_revision = 'gte-small-384-v1';

  return v_base || jsonb_build_object(
    'summary', coalesce(v_base -> 'summary', '{}'::jsonb) || jsonb_build_object(
      'eligible_sections', coalesce(v_eligible_sections, 0),
      'indexed_sections', case when v_lexical_index_ready
        then coalesce(v_lexical_sections, 0) else 0 end,
      'indexed_chunks', case when v_lexical_index_ready
        then coalesce(v_lexical_chunks, 0) else 0 end,
      'pending_embeddings', 0,
      'last_indexed_at', v_last_lexical_index_at
    ),
    'search_policy', jsonb_build_object(
      'canonical_retrieval', 'lexical_portuguese',
      'lexical_language', 'pt-BR',
      'lexical_full_content', v_lexical_full_content,
      'semantic_status', 'unsupported_language',
      'semantic_model', null,
      'semantic_usable_chunks', 0,
      'semantic_historical_chunks', coalesce(v_historical_semantic_chunks, 0),
      'retained_model_revision', 'gte-small-384-v1',
      'future_requirement',
        'multilingual_model_with_explicit_token_contract_and_new_release_gate'
    )
  );
end;
$$;

comment on function private.normalize_portuguese_lexical_text(text) is
  'Immutable PT-BR accent normalization used identically for stored content and search queries.';
comment on function private.knowledge_portuguese_lexical_confidence(
  double precision, integer
) is
  'Calibrates absolute PT-BR cover-density rank for the fail-closed 0.35 answer boundary.';
comment on function private.portuguese_lexical_literal_excerpt(
  text, text, pg_catalog.tsquery, boolean
) is
  'Returns a bounded literal substring around the best PT-BR cover and verifies every strong answer contains the complete query.';
comment on function private.enqueue_legal_embedding_job() is
  'Lazy compatibility trigger: retired gte-small creates no new job.';
comment on function private.ia_fiscal_dispatch_due_knowledge_work(integer) is
  'Governed ingestion-only scheduler; retired semantic work is never inspected or dispatched.';
comment on function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) is
  'Compatibility RPC backed only by complete Portuguese lexical evidence; gte-small is retained but not used because its language/token contract is incompatible.';
comment on function public.ia_fiscal_claim_legal_embedding_jobs(integer) is
  'Compatibility no-op for retired gte-small jobs. A future multilingual revision requires a new attested release.';

revoke all on function private.normalize_portuguese_lexical_text(text)
  from public, anon, authenticated, service_role;
revoke all on function private.knowledge_portuguese_lexical_confidence(
  double precision, integer
)
  from public, anon, authenticated, service_role;
revoke all on function private.portuguese_lexical_literal_excerpt(
  text, text, pg_catalog.tsquery, boolean
)
  from public, anon, authenticated, service_role;
revoke all on function private.enqueue_legal_embedding_job()
  from public, anon, authenticated, service_role;
revoke all on function private.ia_fiscal_dispatch_due_knowledge_work(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_claim_legal_embedding_jobs(integer)
  to service_role;
revoke all on function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_hybrid_search_legal_knowledge(
  uuid, text, text, integer
) to authenticated;
revoke all on function public.ia_get_knowledge_operations_snapshot_pre_lexical_ptbr(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_get_knowledge_operations_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_knowledge_operations_snapshot(uuid)
  to authenticated;

commit;
