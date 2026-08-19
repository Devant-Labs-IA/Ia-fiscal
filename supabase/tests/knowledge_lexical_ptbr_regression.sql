-- Read-only post-migration regression for the canonical PT-BR lexical path.
-- It validates PostgreSQL's real parser/ranker and the deployed fail-closed
-- function definitions, then rolls back without changing application data.

begin;

do $lexical_language_cases$
declare
  v_failed text[];
begin
  with cases(name, document_text, query_text) as (
    values
      (
        'accents',
        'obrigações tributárias do contribuinte',
        'obrigacoes tributarias contribuinte'
      ),
      (
        'inflections',
        'o contribuinte recolhe os tributos',
        'contribuintes recolher tributo'
      ),
      (
        'compound',
        'incidência do imposto sobre serviços',
        '"imposto sobre servicos"'
      )
  ), matches as (
    select
      cases.name,
      pg_catalog.to_tsvector(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(cases.document_text)
      ) @@ pg_catalog.websearch_to_tsquery(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(cases.query_text)
      ) as matched
    from cases
  )
  select array_agg(matches.name order by matches.name)
  into v_failed
  from matches
  where not matches.matched;

  if cardinality(coalesce(v_failed, '{}'::text[])) > 0 then
    raise exception 'PT-BR lexical cases failed: %', v_failed;
  end if;
end;
$lexical_language_cases$;

do $lexical_ranking$
declare
  v_ranking integer[];
  v_scores double precision[];
begin
  with documents(id, content_text) as (
    values
      (1, 'Incidência do imposto sobre serviços na prestação tributável.'),
      (
        2,
        'Serviços sujeitos às regras municipais. O contribuinte observa o imposto devido em outro capítulo.'
      )
  ), normalized as (
    select
      documents.id,
      pg_catalog.to_tsvector(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(documents.content_text)
      ) as document_vector
    from documents
  ), query as (
    select pg_catalog.websearch_to_tsquery(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text('imposto serviços')
    ) as query_vector
  ), ranked as (
    select
      normalized.id,
      pg_catalog.ts_rank_cd(
        normalized.document_vector,
        query.query_vector
      ) as score
    from normalized
    cross join query
    where normalized.document_vector @@ query.query_vector
  )
  select
    array_agg(ranked.id order by ranked.score desc, ranked.id),
    array_agg(ranked.score order by ranked.score desc, ranked.id)
  into v_ranking, v_scores
  from ranked;

  if v_ranking is distinct from array[1, 2]
     or v_scores[1] <= v_scores[2] then
    raise exception 'PT-BR cover-density ranking is not deterministic: %, %',
      v_ranking, v_scores;
  end if;
end;
$lexical_ranking$;

do $lexical_answer_boundary$
declare
  v_strong_score double precision;
  v_weak_score double precision;
  v_strong_confidence double precision;
  v_weak_confidence double precision;
  v_query_lexeme_count integer;
  v_strong_answered boolean;
  v_weak_answered boolean;
begin
  with documents(kind, content_text) as (
    values
      (
        'strong',
        'A incidência do imposto sobre serviços ocorre na prestação tributável.'
      ),
      (
        'weak',
        'O imposto ' || repeat('disciplina administrativa municipal ', 250)
          || 'serviços.'
      )
  ), query as (
    select pg_catalog.websearch_to_tsquery(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text('imposto serviços')
    ) as value
  ), scored as (
    select
      documents.kind,
      pg_catalog.ts_rank_cd(
        pg_catalog.to_tsvector(
          'pg_catalog.portuguese'::pg_catalog.regconfig,
          private.normalize_portuguese_lexical_text(documents.content_text)
        ),
        query.value
      ) as score
    from documents
    cross join query
  )
  select
    max(score) filter (where kind = 'strong'),
    max(score) filter (where kind = 'weak')
  into v_strong_score, v_weak_score
  from scored;

  v_query_lexeme_count := pg_catalog.cardinality(
    pg_catalog.tsvector_to_array(pg_catalog.to_tsvector(
      'pg_catalog.simple'::pg_catalog.regconfig,
      pg_catalog.querytree(pg_catalog.websearch_to_tsquery(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text('imposto serviços')
      ))
    ))
  );
  v_strong_confidence :=
    private.knowledge_portuguese_lexical_confidence(
      v_strong_score,
      v_query_lexeme_count
    );
  v_weak_confidence :=
    private.knowledge_portuguese_lexical_confidence(
      v_weak_score,
      v_query_lexeme_count
    );
  v_strong_answered := v_strong_confidence >= 0.35;
  v_weak_answered := v_weak_confidence >= 0.35;

  if v_strong_score <= v_weak_score or not v_strong_answered then
    raise exception
      'strong PT-BR match did not clear the answer boundary: scores %, %, confidence %',
      v_strong_score, v_weak_score, v_strong_confidence;
  end if;
  if v_weak_answered then
    raise exception
      'weak PT-BR match crossed the answer boundary: score %, confidence %',
      v_weak_score, v_weak_confidence;
  end if;
end;
$lexical_answer_boundary$;

do $lexical_boolean_fail_closed$
declare
  v_simple_or_query pg_catalog.tsquery;
  v_adversarial_or_query pg_catalog.tsquery;
  v_not_query pg_catalog.tsquery;
  v_adversarial_score double precision;
  v_adversarial_confidence double precision;
  v_adversarial_lexeme_count integer;
begin
  v_simple_or_query := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    private.normalize_portuguese_lexical_text('imposto OR taxa')
  );
  v_adversarial_or_query := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    private.normalize_portuguese_lexical_text(
      'imposto OR quasar OR nebulosa OR asteroide OR galaxia OR oceano'
      || ' OR montanha OR floresta OR satelite OR vulcao OR cometa OR deserto'
    )
  );
  v_not_query := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    private.normalize_portuguese_lexical_text('imposto -servicos')
  );

  if position('|' in pg_catalog.querytree(v_simple_or_query)) = 0
     or position('|' in pg_catalog.querytree(v_adversarial_or_query)) = 0 then
    raise exception 'real parser no longer exposes OR in canonical querytree';
  end if;
  if position('!' in v_not_query::text) = 0 then
    raise exception 'real parser no longer exposes NOT in canonical tsquery';
  end if;

  v_adversarial_score := pg_catalog.ts_rank_cd(
    pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text('imposto municipal')
    ),
    v_adversarial_or_query
  );
  v_adversarial_lexeme_count := pg_catalog.cardinality(
    pg_catalog.tsvector_to_array(pg_catalog.to_tsvector(
      'pg_catalog.simple'::pg_catalog.regconfig,
      pg_catalog.querytree(v_adversarial_or_query)
    ))
  );
  v_adversarial_confidence :=
    private.knowledge_portuguese_lexical_confidence(
      v_adversarial_score,
      v_adversarial_lexeme_count
    );

  -- Keep the fixture adversarial: one present OR branch plus eleven absent
  -- branches used to cross the answer boundary solely through multiplication.
  if v_adversarial_lexeme_count <> 12
     or v_adversarial_confidence < 0.35 then
    raise exception
      'OR inflation fixture no longer exercises the old bug: score %, lexemes %, confidence %',
      v_adversarial_score,
      v_adversarial_lexeme_count,
      v_adversarial_confidence;
  end if;
end;
$lexical_boolean_fail_closed$;

do $lexical_best_cover_excerpt$
declare
  v_document text := 'imposto '
    || repeat('administracao ', 300)
    || 'imposto serviços';
  v_weak_document text := 'imposto '
    || repeat('administracao ', 400)
    || 'serviços';
  v_case record;
  v_query pg_catalog.tsquery;
  v_presence_query pg_catalog.tsquery;
  v_score double precision;
  v_query_lexeme_count integer;
  v_confidence double precision;
  v_excerpt text;
  v_answer text;
begin
  for v_case in
    select *
    from (values
      ('and_cover', 'imposto servicos'),
      ('phrase_cover', '"imposto servicos"')
    ) cases(name, query_text)
  loop
    v_query := pg_catalog.websearch_to_tsquery(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text(v_case.query_text)
    );
    v_presence_query := pg_catalog.regexp_replace(
      pg_catalog.querytree(v_query),
      '(<->|<[0-9]+>)',
      '&',
      'g'
    )::pg_catalog.tsquery;
    v_query_lexeme_count := pg_catalog.cardinality(
      pg_catalog.tsvector_to_array(pg_catalog.to_tsvector(
        'pg_catalog.simple'::pg_catalog.regconfig,
        v_presence_query::text
      ))
    );
    v_score := pg_catalog.ts_rank_cd(
      pg_catalog.to_tsvector(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(v_document)
      ),
      v_query
    );
    v_confidence := private.knowledge_portuguese_lexical_confidence(
      v_score,
      v_query_lexeme_count
    );
    if v_confidence < 0.35 then
      raise exception
        'best-cover fixture is not strong for %: score %, confidence %',
        v_case.name,
        v_score,
        v_confidence;
    end if;

    v_excerpt := private.portuguese_lexical_literal_excerpt(
      v_document,
      v_document,
      v_query,
      true
    );
    v_answer := 'Trecho oficial localizado: ' || left(v_excerpt, 1500);

    if position(v_excerpt in v_document) <= 2000
       or position('imposto' in v_answer) = 0
       or position('serviços' in v_answer) = 0
       or not (
         pg_catalog.to_tsvector(
           'pg_catalog.portuguese'::pg_catalog.regconfig,
           private.normalize_portuguese_lexical_text(left(v_excerpt, 1500))
         ) @@ v_query
       ) then
      raise exception
        'answer used an isolated early lexeme instead of the best %: excerpt offset %, answer %',
        v_case.name,
        position(v_excerpt in v_document),
        v_answer;
    end if;
  end loop;

  -- A weak window still preserves a literal citation. It must not require the
  -- full distant AND cover to fit the 1,500-character answer that will be null.
  v_query := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    private.normalize_portuguese_lexical_text('imposto serviços')
  );
  v_score := pg_catalog.ts_rank_cd(
    pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text(v_weak_document)
    ),
    v_query
  );
  v_confidence := private.knowledge_portuguese_lexical_confidence(v_score, 2);
  if v_confidence >= 0.35 then
    raise exception
      'weak citation fixture unexpectedly crossed the answer boundary: %, %',
      v_score,
      v_confidence;
  end if;
  v_excerpt := private.portuguese_lexical_literal_excerpt(
    v_weak_document,
    v_weak_document,
    v_query,
    false
  );
  if char_length(v_excerpt) > 2000
     or position(v_excerpt in v_weak_document) = 0
     or pg_catalog.to_tsvector(
       'pg_catalog.portuguese'::pg_catalog.regconfig,
       private.normalize_portuguese_lexical_text(left(v_excerpt, 1500))
     ) @@ v_query then
    raise exception
      'weak distant citation did not remain literal and non-answering: %, %',
      char_length(v_excerpt),
      v_confidence;
  end if;
end;
$lexical_best_cover_excerpt$;

do $lexical_position_cap_windows$
declare
  v_distant_document text := repeat('termo ', 17000)
    || 'imposto ' || repeat('distante ', 5000) || 'serviços';
  v_deep_phrase_document text := repeat('termo ', 17000)
    || 'imposto sobre serviços';
  v_and_query pg_catalog.tsquery;
  v_phrase_query pg_catalog.tsquery;
  v_phrase_presence_query pg_catalog.tsquery;
  v_full_distant_score double precision;
  v_full_distant_confidence double precision;
  v_best_distant_window_score double precision;
  v_full_phrase_match boolean;
  v_presence_phrase_match boolean;
  v_best_phrase_window text;
  v_best_phrase_score double precision;
  v_excerpt text;
  v_answer text;
begin
  v_and_query := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    private.normalize_portuguese_lexical_text('imposto serviços')
  );
  v_phrase_query := pg_catalog.websearch_to_tsquery(
    'pg_catalog.portuguese'::pg_catalog.regconfig,
    private.normalize_portuguese_lexical_text('"imposto sobre servicos"')
  );
  v_phrase_presence_query := pg_catalog.regexp_replace(
    pg_catalog.querytree(v_phrase_query),
    '(<->|<[0-9]+>)',
    '&',
    'g'
  )::pg_catalog.tsquery;

  v_full_distant_score := pg_catalog.ts_rank_cd(
    pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text(v_distant_document)
    ),
    v_and_query
  );
  v_full_distant_confidence :=
    private.knowledge_portuguese_lexical_confidence(
      v_full_distant_score,
      2
    );

  select max(windowed.score)
  into v_best_distant_window_score
  from (
    select pg_catalog.ts_rank_cd(
      pg_catalog.to_tsvector(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(substring(
          v_distant_document from starts.start_char for 12000
        ))
      ),
      v_and_query
    ) as score
    from pg_catalog.generate_series(
      1,
      char_length(v_distant_document),
      6000
    ) starts(start_char)
    where pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text(substring(
        v_distant_document from starts.start_char for 12000
      ))
    ) @@ v_and_query
  ) windowed;

  if v_full_distant_confidence < 0.35
     or v_best_distant_window_score is not null then
    raise exception
      'bounded windows did not neutralize the 16383-position inflation: full %, confidence %, window %',
      v_full_distant_score,
      v_full_distant_confidence,
      v_best_distant_window_score;
  end if;

  select
    vector.value @@ v_phrase_query,
    vector.value @@ v_phrase_presence_query
  into v_full_phrase_match, v_presence_phrase_match
  from (
    select pg_catalog.to_tsvector(
      'pg_catalog.portuguese'::pg_catalog.regconfig,
      private.normalize_portuguese_lexical_text(v_deep_phrase_document)
    ) as value
  ) vector;

  select
    windowed.content_text,
    pg_catalog.ts_rank_cd(windowed.search_vector, v_phrase_query)
  into v_best_phrase_window, v_best_phrase_score
  from (
    select
      starts.start_char,
      substring(
        v_deep_phrase_document from starts.start_char for 12000
      ) as content_text,
      pg_catalog.to_tsvector(
        'pg_catalog.portuguese'::pg_catalog.regconfig,
        private.normalize_portuguese_lexical_text(substring(
          v_deep_phrase_document from starts.start_char for 12000
        ))
      ) as search_vector
    from pg_catalog.generate_series(
      1,
      char_length(v_deep_phrase_document),
      6000
    ) starts(start_char)
  ) windowed
  where windowed.search_vector @@ v_phrase_query
  order by
    pg_catalog.ts_rank_cd(windowed.search_vector, v_phrase_query) desc,
    windowed.start_char
  limit 1;

  if v_full_phrase_match
     or not v_presence_phrase_match
     or v_best_phrase_window is null
     or v_best_phrase_score <= 0 then
    raise exception
      'presence/window split did not recover a deep phrase after position saturation: full %, presence %, score %',
      v_full_phrase_match,
      v_presence_phrase_match,
      v_best_phrase_score;
  end if;

  v_excerpt := private.portuguese_lexical_literal_excerpt(
    v_best_phrase_window,
    v_deep_phrase_document,
    v_phrase_query,
    true
  );
  v_answer := 'Trecho oficial localizado: ' || left(v_excerpt, 1500);

  if char_length(v_excerpt) > 2000
     or position(v_excerpt in v_deep_phrase_document) = 0
     or position('imposto sobre serviços' in v_excerpt) = 0
     or position('imposto sobre serviços' in v_answer) = 0 then
    raise exception
      'deep-match excerpt/answer is not bounded literal supporting evidence: excerpt %, answer %',
      char_length(v_excerpt),
      char_length(v_answer);
  end if;
end;
$lexical_position_cap_windows$;

do $deployed_search_boundary$
declare
  v_search_definition text;
  v_citable_definition text;
  v_excerpt_definition text;
  v_index_definition text;
  v_index_ready boolean;
begin
  select pg_catalog.pg_get_functiondef(
    'public.ia_fiscal_hybrid_search_legal_knowledge(uuid,text,text,integer)'::regprocedure
  ) into v_search_definition;
  select pg_catalog.pg_get_functiondef(
    'private.legal_source_version_is_current_citable(uuid,uuid)'::regprocedure
  ) into v_citable_definition;
  select pg_catalog.pg_get_functiondef(
    'private.portuguese_lexical_literal_excerpt(text,text,tsquery,boolean)'::regprocedure
  ) into v_excerpt_definition;
  select
    pg_catalog.pg_get_indexdef(index_state.indexrelid),
    index_state.indisvalid and index_state.indisready
  into v_index_definition, v_index_ready
  from pg_catalog.pg_index index_state
  where index_state.indexrelid = pg_catalog.to_regclass(
    'public.legal_sections_search_portuguese_idx'
  );

  if v_search_definition not like '%with lexical_candidates as materialized%'
     or v_search_definition not like '%current_candidates as materialized%'
     or v_search_definition not like '%window_vectors as materialized%'
     or v_search_definition not like '%window_matches as materialized%'
     or v_search_definition not like '%best_windows as materialized%'
     or v_search_definition not like '%ranked_windows as materialized%'
     or v_search_definition not like '%querytree(v_tsquery)%'
     or v_search_definition not like '%section.municipality_id = p_municipality_id%'
     or v_search_definition not like '%section.content_sha256 = version.content_sha256%'
     or v_search_definition not like '%section.content_text = version.content_text%'
     or v_search_definition not like '%legal_source_version_is_current_citable%'
     or v_search_definition not like '%) @@ v_presence_tsquery%'
     or v_search_definition not like '%windowed.window_vector @@ v_tsquery%'
     or v_search_definition not like '%generate_series(%'
     or v_search_definition not like '%for 12000%'
     or v_search_definition not like '%6000%'
     or v_search_definition like '%limit 100%'
     or v_search_definition not like '%OR queries are not supported%'
     or v_search_definition not like '%NOT queries are not supported%'
     or v_search_definition like '%private.legal_embeddings%'
     or v_search_definition like '%private.legal_chunks%'
     or v_search_definition like '%OPERATOR(extensions.<=>)%'
     or position(') @@ v_presence_tsquery' in v_search_definition) >=
       position('cross join lateral pg_catalog.generate_series' in v_search_definition)
     or position('pg_catalog.ts_rank_cd' in v_search_definition) <=
       position('window_matches as materialized' in v_search_definition)
     or position('limit v_limit' in v_search_definition) >=
       position('from private.legal_source_artifact_versions' in v_search_definition)
     or position('OR queries are not supported' in v_search_definition) >=
       position('with lexical_candidates as materialized' in v_search_definition)
     or position('NOT queries are not supported' in v_search_definition) >=
       position('with lexical_candidates as materialized' in v_search_definition)
     or v_search_definition not like '%' || '''retrieval_mode'', ''lexical_portuguese''' || '%'
     or v_search_definition not like '%' || '''semantic_status'', ''unsupported_language''' || '%' then
    raise exception 'deployed search does not preserve the canonical lexical boundary';
  end if;

  if not coalesce(v_index_ready, false)
     or v_index_definition not like '%USING gin%'
     or v_index_definition not like '%normalize_portuguese_lexical_text(content_text)%' then
    raise exception 'integral PT-BR GIN index is absent, invalid or uses another expression';
  end if;

  if v_citable_definition not like '%' || 'version.status = ''published''' || '%'
     or v_citable_definition not like '%version.valid_from%'
     or v_citable_definition not like '%version.valid_until%'
     or v_citable_definition not like '%legal_source_artifact_versions%'
     or v_citable_definition not like '%' || 'artifact.extraction_status = ''completed''' || '%'
     or v_citable_definition not like '%' || 'content_truncated'' = ''false''' || '%'
     or v_citable_definition not like '%storage.objects%' then
    raise exception 'citable evidence helper lost validity or artifact-backed checks';
  end if;

  if v_excerpt_definition not like '%MaxWords=80%'
     or v_excerpt_definition not like '%MaxFragments=1%'
     or v_excerpt_definition not like '%v_plain_fragment%'
     or v_excerpt_definition not like '%v_fragment_start%'
     or v_excerpt_definition not like '%position(v_window_text in v_official_text) = 0%'
     or v_excerpt_definition not like '%position(v_excerpt in v_official_text) = 0%'
     or v_excerpt_definition not like '%substring(v_window_text from v_excerpt_start for 2000)%'
     or v_excerpt_definition not like '%normalize_portuguese_lexical_text(left(v_excerpt, 1500))%'
     or v_excerpt_definition not like '%p_require_answer_cover%' then
    raise exception 'literal lexical excerpt lost bounded anti-spoof mapping checks';
  end if;
end;
$deployed_search_boundary$;

do $semantic_retirement$
declare
  v_claim_definition text;
  v_snapshot_definition text;
  v_dispatch_definition text;
  v_enqueue_definition text;
begin
  select pg_catalog.pg_get_functiondef(
    'public.ia_fiscal_claim_legal_embedding_jobs(integer)'::regprocedure
  ) into v_claim_definition;
  select pg_catalog.pg_get_functiondef(
    'public.ia_get_knowledge_operations_snapshot(uuid)'::regprocedure
  ) into v_snapshot_definition;
  select pg_catalog.pg_get_functiondef(
    'private.ia_fiscal_dispatch_due_knowledge_work(integer)'::regprocedure
  ) into v_dispatch_definition;
  select pg_catalog.pg_get_functiondef(
    'private.enqueue_legal_embedding_job()'::regprocedure
  ) into v_enqueue_definition;

  if v_claim_definition not like '%service role required%'
     or v_claim_definition not like '%knowledge runtime is not verified%'
     or v_claim_definition like '%update private.legal_embedding_jobs%'
     or v_claim_definition like '%return query%' then
    raise exception 'retired gte-small claim is not a fail-closed authenticated no-op';
  end if;

  if v_enqueue_definition like '%insert into private.legal_embedding_jobs%'
     or v_dispatch_definition like '%private.legal_embedding_jobs%'
     or v_dispatch_definition like '%ia-fiscal-knowledge-embed%'
     or v_dispatch_definition like '%' || '''embed''' || '%'
     or v_dispatch_definition not like '%' || '''embedding_dispatch'', false' || '%' then
    raise exception 'retired gte-small work can still be queued or dispatched';
  end if;

  if v_snapshot_definition not like '%' || '''semantic_status'', ''unsupported_language''' || '%'
     or v_snapshot_definition not like '%' || '''semantic_usable_chunks'', 0' || '%'
     or v_snapshot_definition not like '%' || '''lexical_full_content'', v_lexical_full_content' || '%'
     or v_snapshot_definition not like '%index_state.indisvalid%'
     or v_snapshot_definition not like '%section.content_sha256 = version.content_sha256%'
     or v_snapshot_definition not like '%section.content_text = version.content_text%' then
    raise exception 'snapshot does not disclose lexical and semantic coverage honestly';
  end if;

  if exists (
    select 1
    from private.legal_embedding_jobs job
    where job.model_revision = 'gte-small-384-v1'
      and job.status in ('queued', 'processing', 'failed', 'dead_letter')
  ) then
    raise exception 'retired semantic job remained claimable after migration';
  end if;

  if pg_catalog.to_regprocedure(
       'private.enqueue_legal_embedding_job_pre_lexical_ptbr()'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.ia_fiscal_claim_legal_embedding_jobs_pre_lexical_ptbr(integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.ia_fiscal_hybrid_search_legal_knowledge_pre_lexical_ptbr(uuid,text,text,integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'private.ia_fiscal_dispatch_due_knowledge_work_pre_lexical_ptbr(integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.ia_get_knowledge_operations_snapshot_pre_lexical_ptbr(uuid)'
     ) is null then
    raise exception 'a superseded implementation was not preserved for compensation';
  end if;
end;
$semantic_retirement$;

rollback;
