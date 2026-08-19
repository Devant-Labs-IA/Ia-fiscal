-- PostgreSQL 17 runtime fix: resolve pgvector cosine operators explicitly from the extensions schema under search_path=''.

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
