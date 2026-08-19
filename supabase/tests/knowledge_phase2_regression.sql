-- Transactional runtime regression for Segundo Cerebro Fiscal Phase 2/2b.
--
-- Apply through 20260819042149 before running this file.  The activation
-- migration must NOT be present: runtime attestation and cron activation are
-- separate release gates.  All synthetic rows, Vault changes and pg_net
-- requests are rolled back.

begin;

-- Phase 1 may already contain more than one document page for a source.  The
-- Phase 2b seed must reactivate only the official Siscam ficha and preserve
-- secondary consolidation pages as paused alternatives.
do $canonical_ficha$
begin
  if exists (
    select 1
    from public.legal_sources source
    join public.municipalities municipality
      on municipality.id = source.municipality_id
    left join private.legal_source_endpoints endpoint
      on endpoint.municipality_id = source.municipality_id
     and endpoint.source_id = source.id
     and endpoint.content_mode = 'catalog_only'
     and endpoint.endpoint_kind = 'document_page'
    where (
      municipality.slug = 'cordeiropolis-sp'
      and source.official_identifier = 'Lei Complementar nº 399/2024'
    ) or (
      municipality.slug = 'araras-sp'
      and source.official_identifier = 'Lei nº 3.362/2001'
    )
    group by source.municipality_id, source.id
    having count(*) filter (where endpoint.status = 'active') <> 1
       or count(*) filter (
         where endpoint.status = 'active'
           and endpoint.parser_hint = 'siscam_document'
       ) <> 1
  ) then
    raise exception 'canonical Siscam ficha activation was ambiguous';
  end if;
end;
$canonical_ficha$;

do $fixtures$
declare
  x_municipality_a constant uuid := '00000000-0000-4000-8000-00000000d001';
  x_municipality_b constant uuid := '00000000-0000-4000-8000-00000000d002';
  u_admin_a constant uuid := '00000000-0000-4000-8000-00000000d101';
  u_capability_a constant uuid := '00000000-0000-4000-8000-00000000d102';
  u_support_a constant uuid := '00000000-0000-4000-8000-00000000d103';
  u_admin_b constant uuid := '00000000-0000-4000-8000-00000000d104';
  m_admin_a constant uuid := '00000000-0000-4000-8000-00000000d201';
  m_capability_a constant uuid := '00000000-0000-4000-8000-00000000d202';
  m_support_a constant uuid := '00000000-0000-4000-8000-00000000d203';
  m_admin_b constant uuid := '00000000-0000-4000-8000-00000000d204';
  x_source_main constant uuid := '00000000-0000-4000-8000-00000000d301';
  x_source_catalog_1 constant uuid := '00000000-0000-4000-8000-00000000d302';
  x_source_catalog_2 constant uuid := '00000000-0000-4000-8000-00000000d303';
  x_source_scheduler constant uuid := '00000000-0000-4000-8000-00000000d304';
  x_source_atomic constant uuid := '00000000-0000-4000-8000-00000000d305';
  x_version constant uuid := '00000000-0000-4000-8000-00000000d401';
  x_section constant uuid := '00000000-0000-4000-8000-00000000d501';
  x_chunk constant uuid := '00000000-0000-4000-8000-00000000d601';
  x_policy constant uuid := '00000000-0000-4000-8000-00000000d701';
  x_template constant uuid := '00000000-0000-4000-8000-00000000d702';
  x_template_version constant uuid := '00000000-0000-4000-8000-00000000d703';
  x_question constant uuid := '00000000-0000-4000-8000-00000000d704';
  x_change_set constant uuid := '00000000-0000-4000-8000-00000000d801';
  x_candidate constant uuid := '00000000-0000-4000-8000-00000000d802';
  x_catalog_endpoint_1 constant uuid := '00000000-0000-4000-8000-00000000d901';
  x_catalog_endpoint_2 constant uuid := '00000000-0000-4000-8000-00000000d902';
  x_scheduler_endpoint constant uuid := '00000000-0000-4000-8000-00000000d903';
  x_atomic_endpoint constant uuid := '00000000-0000-4000-8000-00000000d904';
  v_content text := 'Art. 1º O lançamento tributário municipal observará a lei vigente e a prova oficial integral.';
  v_sha text;
begin
  v_sha := encode(extensions.digest(v_content, 'sha256'), 'hex');

  insert into public.municipalities (id, slug, name, state_code, status)
  values
    (x_municipality_a, 'qa-phase2-a', 'Prefeitura QA Phase 2 A', 'SP', 'active'),
    (x_municipality_b, 'qa-phase2-b', 'Prefeitura QA Phase 2 B', 'SP', 'active');

  insert into auth.users (
    id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values
    (u_admin_a, 'authenticated', 'authenticated', 'qa-p2-admin@example.invalid', '{}', '{}', now(), now()),
    (u_capability_a, 'authenticated', 'authenticated', 'qa-p2-capability@example.invalid', '{}', '{}', now(), now()),
    (u_support_a, 'authenticated', 'authenticated', 'qa-p2-support@example.invalid', '{}', '{}', now(), now()),
    (u_admin_b, 'authenticated', 'authenticated', 'qa-p2-admin-b@example.invalid', '{}', '{}', now(), now());

  insert into public.municipality_memberships (
    id, municipality_id, user_id, role, status, valid_from, activated_at
  ) values
    (m_admin_a, x_municipality_a, u_admin_a, 'municipal_admin', 'active', now() - interval '1 day', now()),
    (m_capability_a, x_municipality_a, u_capability_a, 'municipal_admin', 'active', now() - interval '1 day', now()),
    (m_support_a, x_municipality_a, u_support_a, 'support_readonly', 'active', now() - interval '1 day', now()),
    (m_admin_b, x_municipality_b, u_admin_b, 'municipal_admin', 'active', now() - interval '1 day', now());

  insert into private.knowledge_automation_settings (
    municipality_id, enabled, timezone, next_run_at, endpoint_batch_size
  ) values
    (x_municipality_a, false, 'America/Sao_Paulo', now(), 2),
    (x_municipality_b, false, 'America/Sao_Paulo', now(), 2);

  -- The legacy authority deliberately differs from municipality.name.  Phase
  -- 2b must deduplicate by semantic legal identity, never authority spelling.
  insert into public.legal_sources (
    id, municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values
    (
      x_source_main, x_municipality_a, 'law', 'municipal', 'Município QA legado',
      'Lei QA nº 123/2026', 'Lei nº 123/2026',
      'https://legacy.example.invalid/leis/123-2026', 'Tributos municipais',
      'fiscal_knowledge', 'draft'
    ),
    (
      x_source_catalog_1, x_municipality_a, 'official_guidance', 'municipal',
      'Prefeitura QA Phase 2 A', 'Catálogo QA classificação 1',
      'Catálogo QA 1',
      'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=1&Pagina=1',
      'Tributos municipais', 'source_catalog', 'draft'
    ),
    (
      x_source_catalog_2, x_municipality_a, 'official_guidance', 'municipal',
      'Prefeitura QA Phase 2 A', 'Catálogo QA classificação 2',
      'Catálogo QA 2',
      'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=2&Pagina=1',
      'Tributos municipais', 'source_catalog', 'draft'
    ),
    (
      x_source_scheduler, x_municipality_a, 'official_guidance', 'municipal',
      'Prefeitura QA Phase 2 A', 'Catálogo QA de escalonamento',
      'Catálogo QA scheduler',
      'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=3&Pagina=1',
      'Tributos municipais', 'source_catalog', 'draft'
    ),
    (
      x_source_atomic, x_municipality_a, 'law', 'municipal',
      'Prefeitura QA Phase 2 A', 'Lei QA de captura atômica',
      'Lei QA atômica nº 1/2026',
      'https://qa-siscam.example.invalid/arquivo/atomic.txt',
      'Tributos municipais', 'fiscal_knowledge', 'draft'
    );

  insert into public.legal_source_versions (
    id, municipality_id, source_id, version, status, content_text,
    content_sha256, valid_from, publication_date
  ) values (
    x_version, x_municipality_a, x_source_main, 1, 'under_review', v_content,
    v_sha, current_date, current_date
  );
  insert into public.legal_sections (
    id, municipality_id, source_version_id, section_key, heading, ordinal,
    content_text, content_sha256
  ) values (
    x_section, x_municipality_a, x_version, 'art-1', 'Artigo 1º', 1,
    v_content, v_sha
  );
  insert into private.legal_chunks (
    id, municipality_id, legal_section_id, chunk_index, content_text,
    token_count, content_sha256
  ) values (
    x_chunk, x_municipality_a, x_section, 0, v_content, 15, v_sha
  );

  insert into private.legal_source_change_sets (
    id, municipality_id, source_id, candidate_version_id, change_type,
    status, to_sha256, diff_sha256, diff_summary
  ) values (
    x_change_set, x_municipality_a, x_source_main, x_version, 'legacy_import',
    'detected', v_sha,
    encode(extensions.digest('qa phase2 diff', 'sha256'), 'hex'),
    'Conjunto sintético para validar paginação completa de evidências.'
  );
  insert into private.legal_source_change_items (
    municipality_id, change_set_id, ordinal, item_kind, item_path,
    after_sha256, after_excerpt, summary
  )
  select
    x_municipality_a, x_change_set, ordinal, 'section',
    'artigos[' || ordinal::text || ']',
    encode(extensions.digest('item-' || ordinal::text, 'sha256'), 'hex'),
    'Trecho sintético ' || ordinal::text,
    'Alteração sintética ' || ordinal::text
  from generate_series(1, 105) ordinal;

  insert into private.knowledge_candidate_submissions (
    id, municipality_id, submitted_by_membership_id, question,
    proposed_answer, citation_section_ids, content_sha256
  ) values (
    x_candidate, x_municipality_a, m_capability_a,
    'Como aplicar a Lei QA?',
    'Aplicar somente após revisão humana e validação da fonte oficial.',
    array[x_section],
    encode(extensions.digest('candidate-self-review', 'sha256'), 'hex')
  );

  insert into public.municipality_policy_versions (id, municipality_id, version)
  values (x_policy, x_municipality_a, 991);
  insert into public.notification_templates (
    id, municipality_id, code, name, notification_type
  ) values (
    x_template, x_municipality_a, 'qa-phase2-template',
    'Template QA Phase 2', 'initial_inspection_alert'
  );
  insert into public.notification_template_versions (
    id, municipality_id, template_id, version, subject, body_text, content_sha256
  ) values (
    x_template_version, x_municipality_a, x_template, 1,
    'Assunto QA', 'Corpo QA',
    encode(extensions.digest('Assunto QA|Corpo QA', 'sha256'), 'hex')
  );

  insert into private.legal_catalog_coverages (
    municipality_id, catalog_source_id, coverage_key, title,
    expected_document_count, upstream_status
  ) values
    (x_municipality_a, x_source_catalog_1, 'qa.catalog.1', 'Catálogo QA 1', 1, 'unverified'),
    (x_municipality_a, x_source_catalog_2, 'qa.catalog.2', 'Catálogo QA 2', 1, 'unverified');

  insert into private.legal_source_endpoints (
    id, municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
    citable_body, url, allowed_hosts, expected_content_types, parser_hint,
    poll_interval, priority, status, metadata
  ) values
    (
      x_catalog_endpoint_1, x_municipality_a, x_source_catalog_1, 'catalog',
      'primary_publication', 'catalog_only', false,
      'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=1&Pagina=1',
      array['qa-siscam.example.invalid'], array['text/html'], 'siscam_catalog',
      interval '6 hours', 10, 'active', jsonb_build_object('coverage_key', 'qa.catalog.1')
    ),
    (
      x_catalog_endpoint_2, x_municipality_a, x_source_catalog_2, 'catalog',
      'primary_publication', 'catalog_only', false,
      'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=2&Pagina=1',
      array['qa-siscam.example.invalid'], array['text/html'], 'siscam_catalog',
      interval '6 hours', 20, 'active', jsonb_build_object('coverage_key', 'qa.catalog.2')
    ),
    (
      x_scheduler_endpoint, x_municipality_a, x_source_scheduler, 'catalog',
      'primary_publication', 'catalog_only', false,
      'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=3&Pagina=1',
      array['qa-siscam.example.invalid'], array['text/html'], 'siscam_catalog',
      interval '6 hours', 30, 'active', '{}'::jsonb
    ),
    (
      x_atomic_endpoint, x_municipality_a, x_source_atomic, 'document_file',
      'primary_publication', 'legal_body', true,
      'https://qa-siscam.example.invalid/arquivo/atomic.txt',
      array['qa-siscam.example.invalid'], array['text/plain'], 'qa_text',
      interval '24 hours', 40, 'active', '{}'::jsonb
    );

  insert into storage.objects (bucket_id, name, metadata)
  values
    (
      'legal-source-artifacts',
      'qa-phase2-a/' || x_source_atomic::text || '/' ||
        encode(extensions.digest('atomic raw artifact v1', 'sha256'), 'hex') ||
        '/artifact.txt',
      jsonb_build_object('size', 123, 'mimetype', 'text/plain')
    ),
    (
      'legal-source-artifacts',
      'qa-phase2-a/' || x_source_atomic::text || '/' ||
        encode(extensions.digest('atomic raw artifact rollback', 'sha256'), 'hex') ||
        '/artifact.txt',
      jsonb_build_object('size', 123, 'mimetype', 'text/plain')
    );
end
$fixtures$;

-- A synthetic question is enough to prove the claim RPC rejects a narrow
-- legal capability before touching case assignment.  FK triggers are bypassed
-- only for this fixture and are restored immediately; CHECK constraints remain.
set local session_replication_role = replica;
insert into public.case_questions (
  id, municipality_id, case_id, message_id, status
) values (
  '00000000-0000-4000-8000-00000000d704',
  '00000000-0000-4000-8000-00000000d001',
  '00000000-0000-4000-8000-00000000d705',
  '00000000-0000-4000-8000-00000000d706',
  'submitted'
);
set local session_replication_role = origin;

do $acl$
begin
  if has_table_privilege('authenticated', 'private.legal_embedding_jobs', 'SELECT')
     or has_table_privilege('service_role', 'private.legal_embedding_claim_cursors', 'SELECT')
     or has_table_privilege('authenticated', 'private.knowledge_candidate_submissions', 'SELECT')
     or has_table_privilege('service_role', 'private.legal_reviewer_capability_grants', 'INSERT') then
    raise exception 'private Phase 2 tables leaked direct API privileges';
  end if;
  if has_function_privilege(
       'authenticated',
       'public.ia_get_legal_source_change_evidence(uuid,uuid,integer,integer,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.ia_get_legal_source_change_evidence(uuid,uuid,integer,integer,integer,integer,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.ia_get_legal_source_change_evidence(uuid,uuid,integer,integer,integer,integer,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'source evidence overload ACL is not fail-closed';
  end if;
  if not has_function_privilege(
       'authenticated', 'public.ia_list_legal_reviewer_capabilities(uuid)', 'EXECUTE'
     ) or has_function_privilege(
       'anon', 'public.ia_list_legal_reviewer_capabilities(uuid)', 'EXECUTE'
     ) or has_function_privilege(
       'authenticated',
       'private.expire_legal_reviewer_capabilities(integer,uuid,uuid)',
       'EXECUTE'
     ) or has_function_privilege(
       'service_role',
       'private.lock_current_knowledge_runtime_gate_id()',
       'EXECUTE'
     ) then
    raise exception 'reviewer aggregate/list ACL is incorrect';
  end if;
  if has_function_privilege(
       'authenticated',
       'public.ia_fiscal_capture_knowledge_source_v2(uuid,text,text,text,text,bigint,text,text,text,jsonb,text,text,integer,timestamp with time zone,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'public.ia_fiscal_stage_knowledge_sections_legacy_impl(uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'public.ia_fiscal_capture_knowledge_source(uuid,text,text,text,text,bigint,text,text,text,text,text,integer,timestamp with time zone,uuid,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.ia_fiscal_capture_knowledge_source_v2(uuid,text,text,text,text,bigint,text,text,text,jsonb,text,text,integer,timestamp with time zone,uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'atomic capture v2 ACL is not fail-closed';
  end if;
  if position('for update skip locked' in lower(pg_get_functiondef(
       'private.ia_fiscal_dispatch_due_knowledge_work(integer)'::regprocedure
     ))) = 0 then
    raise exception 'scheduler lacks its durable concurrent lease';
  end if;
end
$acl$;

-- Configure only a transaction-local fake project URL.  Runtime remains
-- unverified until the explicit attestation later in this test.
set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
select public.ia_fiscal_configure_knowledge_scheduler_project_url(
  'https://abcdefghijklmnop.supabase.co'
);

do $atomic_capture$
declare
  x_source constant uuid := '00000000-0000-4000-8000-00000000d305';
  x_correlation_1 constant uuid := '00000000-0000-4000-8000-00000000da01';
  x_correlation_2 constant uuid := '00000000-0000-4000-8000-00000000da02';
  x_correlation_rollback constant uuid := '00000000-0000-4000-8000-00000000da03';
  v_raw_sha text := encode(
    extensions.digest('atomic raw artifact v1', 'sha256'), 'hex'
  );
  v_rollback_sha text := encode(
    extensions.digest('atomic raw artifact rollback', 'sha256'), 'hex'
  );
  v_text text := repeat(
    'Artigo fiscal municipal com prova oficial integral e vigente. ',
    170
  );
  v_sections jsonb;
  v_first jsonb;
  v_retry jsonb;
  v_replay jsonb;
  v_failed_run_id uuid;
  v_failed_run_retry_id uuid;
  v_denied boolean := false;
begin
  v_sections := jsonb_build_array(jsonb_build_object(
    'section_key', 'integral',
    'heading', 'Texto integral oficial',
    'ordinal', 1,
    'content_text', v_text,
    'chunks', jsonb_build_array(
      jsonb_build_object(
        'chunk_index', 1,
        'content_text', left(v_text, 6000),
        'token_count', 100
      ),
      jsonb_build_object(
        'chunk_index', 2,
        'content_text', substring(v_text from 5501),
        'token_count', 100
      )
    )
  ));

  v_first := public.ia_fiscal_capture_knowledge_source_v2(
    x_source,
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    v_raw_sha,
    'text/plain',
    123,
    'legal-source-artifacts',
    'qa-phase2-a/' || x_source::text || '/' || v_raw_sha || '/artifact.txt',
    v_text,
    v_sections,
    null,
    null,
    200,
    now(),
    x_correlation_1,
    jsonb_build_object(
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(v_text)
    )
  );
  if v_first ->> 'status' <> 'captured'
     or v_first ->> 'staging_status' <> 'staged'
     or (v_first ->> 'staged_sections')::integer <> 1
     or (v_first ->> 'staged_chunks')::integer <> 2 then
    raise exception 'atomic capture did not return exact section/chunk counts';
  end if;

  v_retry := public.ia_fiscal_capture_knowledge_source_v2(
    x_source,
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    v_raw_sha,
    'text/plain',
    123,
    'legal-source-artifacts',
    'qa-phase2-a/' || x_source::text || '/' || v_raw_sha || '/artifact.txt',
    v_text,
    v_sections,
    null,
    null,
    200,
    now(),
    x_correlation_2,
    jsonb_build_object(
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(v_text)
    )
  );
  if v_retry ->> 'status' <> 'already_exists'
     or v_retry ->> 'staging_status' <> 'already_staged'
     or v_retry ->> 'candidate_version_id'
          is distinct from v_first ->> 'candidate_version_id'
     or (v_retry ->> 'staged_sections')::integer <> 1
     or (v_retry ->> 'staged_chunks')::integer <> 2 then
    raise exception 'artifact retry was not exactly idempotent';
  end if;

  v_replay := public.ia_fiscal_capture_knowledge_source_v2(
    x_source,
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    v_raw_sha,
    'text/plain',
    123,
    'legal-source-artifacts',
    'qa-phase2-a/' || x_source::text || '/' || v_raw_sha || '/artifact.txt',
    v_text,
    v_sections,
    null,
    null,
    200,
    now(),
    x_correlation_2,
    jsonb_build_object(
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(v_text)
    )
  );
  if v_replay is distinct from v_retry then
    raise exception 'correlation replay changed the atomic capture response';
  end if;

  begin
    perform public.ia_fiscal_capture_knowledge_source_v2(
      x_source,
      'https://qa-siscam.example.invalid/arquivo/atomic.txt',
      'https://qa-siscam.example.invalid/arquivo/atomic.txt',
      v_rollback_sha,
      'text/plain',
      123,
      'legal-source-artifacts',
      'qa-phase2-a/' || x_source::text || '/' || v_rollback_sha || '/artifact.txt',
      v_text || ' alteração',
      jsonb_build_array(jsonb_build_object(
        'section_key', 'integral',
        'heading', 'Texto integral oficial',
        'ordinal', 1,
        'content_text', v_text || ' alteração',
        'chunks', jsonb_build_array(jsonb_build_object(
          'chunk_index', 1,
          'content_text', left(v_text || ' alteração', 6000),
          'token_count', 999999999999999999999
        ))
      )),
      null,
      null,
      200,
      now(),
      x_correlation_rollback,
      jsonb_build_object(
        'extraction_complete', true,
        'content_truncated', false,
        'extracted_char_count', char_length(v_text || ' alteração')
      )
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'invalid staged chunk unexpectedly committed';
  end if;

  -- The Edge records the failed attempt only after the capture/staging RPC has
  -- rolled back.  Retrying that audit write with the same correlation and
  -- evidence must return the same row instead of conflicting or duplicating it.
  v_failed_run_id := public.ia_fiscal_record_knowledge_fetch_failure(
    x_source,
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    null,
    'capture_rpc_failed',
    null,
    now(),
    x_correlation_rollback,
    jsonb_build_object(
      'contract_version', 'knowledge-ingest-v2',
      'orphaned_storage_artifact', jsonb_build_object(
        'disposition', 'preserved_for_reconciliation',
        'storage_bucket', 'legal-source-artifacts',
        'storage_path',
          'qa-phase2-a/' || x_source::text || '/' || v_rollback_sha || '/artifact.txt',
        'content_sha256', v_rollback_sha,
        'upload_status', 'created'
      )
    )
  );
  v_failed_run_retry_id := public.ia_fiscal_record_knowledge_fetch_failure(
    x_source,
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    null,
    'capture_rpc_failed',
    null,
    now(),
    x_correlation_rollback,
    jsonb_build_object(
      'contract_version', 'knowledge-ingest-v2',
      'orphaned_storage_artifact', jsonb_build_object(
        'disposition', 'preserved_for_reconciliation',
        'storage_bucket', 'legal-source-artifacts',
        'storage_path',
          'qa-phase2-a/' || x_source::text || '/' || v_rollback_sha || '/artifact.txt',
        'content_sha256', v_rollback_sha,
        'upload_status', 'created'
      )
    )
  );
  if v_failed_run_retry_id is distinct from v_failed_run_id then
    raise exception 'failed fetch audit was not correlation-idempotent';
  end if;

  -- Persist only deterministic identifiers across the role boundary.  The
  -- service role may invoke the guarded RPCs, but intentionally has no direct
  -- SELECT privilege on the private evidence tables inspected below.
  perform set_config(
    'ia_fiscal.qa_candidate_version_id',
    v_first ->> 'candidate_version_id',
    true
  );
  perform set_config(
    'ia_fiscal.qa_failed_run_id',
    v_failed_run_id::text,
    true
  );
end
$atomic_capture$;
reset role;

do $atomic_capture_assertions$
declare
  x_source constant uuid := '00000000-0000-4000-8000-00000000d305';
  x_correlation_rollback constant uuid := '00000000-0000-4000-8000-00000000da03';
  v_candidate_version_id uuid := current_setting(
    'ia_fiscal.qa_candidate_version_id'
  )::uuid;
  v_failed_run_id uuid := current_setting('ia_fiscal.qa_failed_run_id')::uuid;
  v_rollback_sha text := encode(
    extensions.digest('atomic raw artifact rollback', 'sha256'), 'hex'
  );
begin

  if (select count(*) from private.legal_source_fetch_runs run
      where run.source_id = x_source) <> 3
     or (select count(*) from private.legal_source_artifacts artifact
         where artifact.source_id = x_source) <> 1
     or (select count(*) from public.legal_source_versions version
         where version.source_id = x_source) <> 1
     or (select count(*) from public.legal_sections section
         where section.source_version_id = v_candidate_version_id) <> 1
     or (select count(*)
         from private.legal_chunks chunk
         join public.legal_sections section
           on section.municipality_id = chunk.municipality_id
          and section.id = chunk.legal_section_id
         where section.source_version_id = v_candidate_version_id) <> 2
     or (select count(*)
         from private.legal_source_fetch_runs run
         where run.correlation_id = x_correlation_rollback
           and run.id = v_failed_run_id
           and run.status = 'failed'
           and run.safe_error_code = 'capture_rpc_failed'
           and run.metadata -> 'orphaned_storage_artifact' ->> 'disposition'
                 = 'preserved_for_reconciliation'
           and run.metadata -> 'orphaned_storage_artifact' ->> 'storage_bucket'
                 = 'legal-source-artifacts'
           and run.metadata -> 'orphaned_storage_artifact' ->> 'content_sha256'
                 = v_rollback_sha) <> 1
     or exists (
       select 1 from private.legal_source_fetch_runs run
       where run.correlation_id = x_correlation_rollback
         and run.id <> v_failed_run_id
     )
     or exists (
       select 1 from private.legal_source_artifacts artifact
       where artifact.content_sha256 = v_rollback_sha
     )
     or exists (
       select 1
       from private.legal_source_artifact_versions mapping
       join private.legal_source_artifacts artifact
         on artifact.municipality_id = mapping.municipality_id
        and artifact.id = mapping.artifact_id
       where artifact.content_sha256 = v_rollback_sha
     )
     or exists (
       select 1 from private.legal_source_change_sets change_set
       where change_set.source_id = x_source
         and change_set.to_sha256 = v_rollback_sha
     )
     or exists (
       select 1 from public.legal_source_versions version
       where version.source_id = x_source
         and version.content_sha256 = v_rollback_sha
     )
     or exists (
       select 1
       from public.legal_sections section
       join public.legal_source_versions version
         on version.municipality_id = section.municipality_id
        and version.id = section.source_version_id
       where version.source_id = x_source
         and version.content_sha256 = v_rollback_sha
     )
     or exists (
       select 1
       from private.legal_chunks chunk
       join public.legal_sections section
         on section.municipality_id = chunk.municipality_id
        and section.id = chunk.legal_section_id
       join public.legal_source_versions version
         on version.municipality_id = section.municipality_id
        and version.id = section.source_version_id
       where version.source_id = x_source
         and version.content_sha256 = v_rollback_sha
     ) then
    raise exception 'rollback/failure audit left partial or duplicate evidence';
  end if;
end
$atomic_capture_assertions$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d101', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d101","role":"authenticated","aal":"aal2"}',
  true
);

do $admin_grant$
declare
  v_grant_id uuid;
  v_list jsonb;
  v_denied boolean;
begin
  v_list := public.ia_list_legal_reviewer_capabilities(
    '00000000-0000-4000-8000-00000000d001'
  );
  if exists (
    select 1 from jsonb_array_elements(v_list -> 'eligible_staff') item
    where item ->> 'membership_id' = '00000000-0000-4000-8000-00000000d201'
  ) then
    raise exception 'reviewer list offered the current administrator a forbidden self-grant';
  end if;

  v_denied := false;
  begin
    perform public.ia_grant_legal_reviewer_capability(
      '00000000-0000-4000-8000-00000000d001',
      '00000000-0000-4000-8000-00000000d203',
      now() + interval '7 days',
      'Support portal cannot receive fiscal legal capability.',
      'CONFIRMAR REVISOR JURIDICO'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'support_readonly received a legal reviewer capability';
  end if;

  v_grant_id := public.ia_grant_legal_reviewer_capability(
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d202',
    now() + interval '7 days',
    'Revisão jurídica municipal supervisionada para a suíte QA.',
    'CONFIRMAR REVISOR JURIDICO'
  );
  if v_grant_id is null then
    raise exception 'fiscal staff capability grant did not return an id';
  end if;
  perform set_config('qa.phase2_expiring_grant_id', v_grant_id::text, true);

  v_denied := false;
  begin
    perform public.ia_configure_knowledge_schedule(
      '00000000-0000-4000-8000-00000000d001', true,
      'ATIVAR ATUALIZACAO OFICIAL'
    );
  exception when sqlstate '55000' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'schedule activated before all runtime contracts were attested';
  end if;
end
$admin_grant$;
reset role;

-- Simulate elapsed validity, then prove the governed clock materializes the
-- transition and its append-only system event without waiting for a regrant.
update private.legal_reviewer_capability_grants capability
set valid_from = now() - interval '2 hours',
    valid_until = now() - interval '1 hour'
where capability.id = current_setting('qa.phase2_expiring_grant_id')::uuid;

do $expiry_clock_transition$
declare
  v_old_grant_id uuid := current_setting('qa.phase2_expiring_grant_id')::uuid;
begin
  if private.expire_legal_reviewer_capabilities(
       500,
       '00000000-0000-4000-8000-00000000d001',
       '00000000-0000-4000-8000-00000000d202'
     ) <> 1
     or private.expire_legal_reviewer_capabilities(
       500,
       '00000000-0000-4000-8000-00000000d001',
       '00000000-0000-4000-8000-00000000d202'
     ) <> 0 then
    raise exception 'elapsed grant was not materialized before regrant';
  end if;
  if (
    select capability.status
    from private.legal_reviewer_capability_grants capability
    where capability.id = v_old_grant_id
  ) <> 'expired' or (
    select count(*)
    from private.legal_reviewer_capability_events event
    where event.grant_id = v_old_grant_id
      and event.event_type = 'expired'
      and event.actor_kind = 'system'
      and event.actor_membership_id is null
  ) <> 1 then
    raise exception 'expired grant did not emit exactly one append-only event';
  end if;
end
$expiry_clock_transition$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d101', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d101","role":"authenticated","aal":"aal2"}',
  true
);
do $expiry_and_regrant$
declare
  v_old_grant_id uuid := current_setting('qa.phase2_expiring_grant_id')::uuid;
  v_new_grant_id uuid;
  v_duplicate_denied boolean := false;
begin
  v_new_grant_id := public.ia_grant_legal_reviewer_capability(
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d202',
    now() + interval '7 days',
    'Renovacao supervisionada da capacidade juridica na suite transacional.',
    'CONFIRMAR REVISOR JURIDICO'
  );
  if v_new_grant_id is null or v_new_grant_id = v_old_grant_id then
    raise exception 'expired legal reviewer capability was not regranted';
  end if;
  perform set_config('qa.phase2_new_grant_id', v_new_grant_id::text, true);

  begin
    perform public.ia_grant_legal_reviewer_capability(
      '00000000-0000-4000-8000-00000000d001',
      '00000000-0000-4000-8000-00000000d202',
      now() + interval '7 days',
      'Tentativa repetida nao pode duplicar concessao ou evento de expiracao.',
      'CONFIRMAR REVISOR JURIDICO'
    );
  exception when others then
    v_duplicate_denied := position('already active' in sqlerrm) > 0;
  end;
  if not v_duplicate_denied then
    raise exception 'expiry transition was not idempotent across regrant retry';
  end if;
end
$expiry_and_regrant$;
reset role;

do $expiry_regrant_assertions$
declare
  v_old_grant_id uuid := current_setting('qa.phase2_expiring_grant_id')::uuid;
  v_new_grant_id uuid := current_setting('qa.phase2_new_grant_id')::uuid;
begin
  if (
    select count(*)
    from private.legal_reviewer_capability_events event
    where event.grant_id = v_old_grant_id
      and event.event_type = 'expired'
  ) <> 1 or (
    select capability.status
    from private.legal_reviewer_capability_grants capability
    where capability.id = v_old_grant_id
  ) <> 'expired' or (
    select capability.status
    from private.legal_reviewer_capability_grants capability
    where capability.id = v_new_grant_id
  ) <> 'active' then
    raise exception 'expiry transition was not idempotent across regrant retry';
  end if;
end
$expiry_regrant_assertions$;

-- Capability must disappear at AAL1 and must never alias the global role.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal1"}',
  true
);
do $aal1$
begin
  if private.has_legal_reviewer_capability(
       '00000000-0000-4000-8000-00000000d001'
     ) then
    raise exception 'legal reviewer capability was usable at AAL1';
  end if;
end
$aal1$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $capability_isolation$
begin
  if not private.has_legal_reviewer_capability(
       '00000000-0000-4000-8000-00000000d001'
     ) then
    raise exception 'active legal reviewer capability was not recognized at AAL2';
  end if;
  if private.has_legal_reviewer_capability(
       '00000000-0000-4000-8000-00000000d002'
     ) then
    raise exception 'legal reviewer capability crossed municipality boundary';
  end if;
  if private.has_municipality_role(
       '00000000-0000-4000-8000-00000000d001',
       array['legal_reviewer']::text[]
     ) then
    raise exception 'narrow capability aliased has_municipality_role';
  end if;
  if private.current_municipality_membership_id(
       '00000000-0000-4000-8000-00000000d001',
       array['legal_reviewer']::text[]
     ) is not null then
    raise exception 'narrow capability aliased current_municipality_membership_id';
  end if;
end
$capability_isolation$;

do $relevance_boundary$
begin
  if abs(private.knowledge_retrieval_confidence(0.0700, null) - 0.35) > 0.000000001
     or private.knowledge_retrieval_confidence(null, 0.6725) < 0.349999999 then
    raise exception 'exact lexical/semantic boundary was not releasable';
  end if;
  if private.knowledge_retrieval_confidence(0.0699, null) >= 0.35
     or private.knowledge_retrieval_confidence(null, 0.6724) >= 0.35
     or private.knowledge_retrieval_confidence(null, null) <> 0 then
    raise exception 'low-relevance retrieval crossed the answer boundary';
  end if;
end
$relevance_boundary$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $non_knowledge_denials$
declare
  v_denied boolean;
  v_result jsonb;
begin
  v_denied := false;
  begin
    perform public.ia_activate_policy_version(
      '00000000-0000-4000-8000-00000000d701', 'ATIVAR'
    );
  exception when others then v_denied := true;
  end;
  if not v_denied then
    raise exception 'legal capability activated a municipality policy';
  end if;

  v_denied := false;
  begin
    perform public.ia_activate_notification_template(
      '00000000-0000-4000-8000-00000000d703', 'ATIVAR'
    );
  exception when others then v_denied := true;
  end;
  if not v_denied then
    raise exception 'legal capability activated a notification template';
  end if;

  v_denied := false;
  begin
    perform public.ia_claim_case_question(
      '00000000-0000-4000-8000-00000000d704',
      '00000000-0000-4000-8000-00000000d001',
      '00000000-0000-4000-8000-00000000d202',
      'human'
    );
  exception when others then v_denied := true;
  end;
  if not v_denied then
    raise exception 'legal capability claimed a fiscal case question';
  end if;

  v_denied := false;
  begin
    perform public.ia_get_knowledge_operations_snapshot(
      '00000000-0000-4000-8000-00000000d002'
    );
  exception when sqlstate '42501' then v_denied := true;
  end;
  if not v_denied then
    raise exception 'knowledge snapshot crossed municipality boundary';
  end if;

  v_denied := false;
  begin
    perform public.ia_review_knowledge_candidate(
      '00000000-0000-4000-8000-00000000d001',
      '00000000-0000-4000-8000-00000000d802',
      'rejected', 'Autorrevisão não pode ser aceita pela governança.',
      'REVISAR CANDIDATO'
    );
  exception when others then
    v_denied := position('self-review' in sqlerrm) > 0;
  end;
  if not v_denied then
    raise exception 'candidate self-review was not rejected';
  end if;

  v_denied := false;
  begin
    v_result := public.ia_fiscal_hybrid_search_legal_knowledge(
      '00000000-0000-4000-8000-00000000d001', 'lançamento tributário', null, 8
    );
  exception when sqlstate '55000' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'hybrid search ran before runtime attestation';
  end if;

  v_denied := false;
  begin
    perform public.ia_submit_knowledge_candidate(
      '00000000-0000-4000-8000-00000000d001',
      'Pergunta QA?', 'Resposta QA suficientemente longa.',
      array['00000000-0000-4000-8000-00000000d501'::uuid],
      'ENVIAR PARA REVISAO'
    );
  exception when others then
    v_denied := position('confirmation' in sqlerrm) > 0;
  end;
  if not v_denied then
    raise exception 'unaccented candidate confirmation was accepted';
  end if;
end
$non_knowledge_denials$;
reset role;

-- gte-small is English-only and truncates at 512 tokens. The canonical PT-BR
-- release must terminalize every new job instead of claiming or completing a
-- vector that would overstate semantic coverage.
do $semantic_retirement_fixture$
begin
  if not exists (
    select 1
    from private.legal_embedding_jobs job
    where job.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and job.legal_chunk_id = '00000000-0000-4000-8000-00000000d601'
      and job.status = 'skipped'
      and job.safe_error_code = 'semantic_model_language_unsupported'
      and job.attempts = 0
  ) then
    raise exception 'PT-BR chunk created a claimable gte-small job';
  end if;
end
$semantic_retirement_fixture$;

update private.knowledge_automation_settings
set enabled = true
where municipality_id = '00000000-0000-4000-8000-00000000d001';

select set_config(
  'qa.phase2_scheduler_sha',
  (
    select encode(extensions.digest(secret.decrypted_secret, 'sha256'), 'hex')
    from vault.decrypted_secrets secret
    where secret.name = 'ia_fiscal_knowledge_scheduler_secret'
  ),
  true
);

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
do $embedding_and_scheduler_auth$
declare
  v_job_id uuid;
  v_secret_sha text := current_setting('qa.phase2_scheduler_sha');
  v_nonce uuid := '00000000-0000-4000-8000-00000000da01';
  v_gate_id uuid;
  v_denied boolean := false;
begin
  begin
    perform 1 from public.ia_fiscal_claim_legal_embedding_jobs(1);
  exception when sqlstate '55000' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'embedding claim ran before runtime attestation';
  end if;

  if public.ia_fiscal_validate_knowledge_scheduler_request(
       repeat('0', 64), gen_random_uuid(), now(), 'ingest'
     ) then
    raise exception 'scheduler accepted an invalid secret digest';
  end if;
  if not public.ia_fiscal_validate_knowledge_scheduler_request(
       v_secret_sha, v_nonce, now(), 'ingest'
     ) then
    raise exception 'scheduler rejected a valid first-use signed request';
  end if;
  if public.ia_fiscal_validate_knowledge_scheduler_request(
       v_secret_sha, v_nonce, now(), 'ingest'
     ) then
    raise exception 'scheduler accepted a replayed nonce';
  end if;

  v_gate_id := public.ia_fiscal_attest_knowledge_runtime_ready(
    'abcdefghijklmnop',
    'knowledge-ingest-v2', 'ingest-deployment-qa-1', repeat('1', 64),
    'knowledge-embed-v1', 'embed-deployment-qa-1', repeat('2', 64),
    'knowledge-search-v1', 'search-deployment-qa-1', repeat('3', 64),
    encode(extensions.digest('qa-runtime-smoke-evidence', 'sha256'), 'hex'),
    'qa-evidence:runtime-smoke-manifest-1',
    now() + interval '1 day',
    'ATESTAR RUNTIME SEGUNDO CEREBRO'
  );
  select claimed.job_id into v_job_id
  from public.ia_fiscal_claim_legal_embedding_jobs(1) claimed;
  if v_job_id is not null then
    raise exception 'retired gte-small worker claimed a PT-BR chunk';
  end if;

  if not public.ia_fiscal_revoke_knowledge_runtime_gate(
    v_gate_id,
    'Revogacao QA comprova que um gate selecionado deixa de autorizar ativacao.',
    'REVOGAR RUNTIME SEGUNDO CEREBRO'
  ) then
    raise exception 'revoked runtime gate remained current or verified';
  end if;

  v_denied := false;
  begin
    perform 1 from public.ia_fiscal_claim_legal_embedding_jobs(1);
  exception when sqlstate '55000' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'embedding claim ran with a revoked runtime gate';
  end if;
end
$embedding_and_scheduler_auth$;
reset role;

do $revoked_runtime_assertions$
begin
  if private.current_knowledge_runtime_gate_id() is not null
     or private.knowledge_runtime_is_verified() then
    raise exception 'revoked runtime gate remained current or verified';
  end if;
end
$revoked_runtime_assertions$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $revoked_runtime_search_fail_closed$
declare
  v_denied boolean := false;
begin
  begin
    perform public.ia_fiscal_hybrid_search_legal_knowledge(
      '00000000-0000-4000-8000-00000000d001', 'legislacao vigente', null, 8
    );
  exception when sqlstate '55000' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'hybrid search ran with a revoked runtime gate';
  end if;
end
$revoked_runtime_search_fail_closed$;
reset role;

do $revoked_runtime_dispatch_fail_closed$
declare
  v_before bigint;
  v_result jsonb;
begin
  update private.knowledge_automation_settings
  set enabled = true
  where municipality_id = '00000000-0000-4000-8000-00000000d002';
  select count(*) into v_before
  from private.knowledge_scheduler_dispatches;

  v_result := private.ia_fiscal_dispatch_due_knowledge_work(2);
  if v_result ->> 'status' <> 'runtime_not_verified'
     or (select count(*) from private.knowledge_scheduler_dispatches) <> v_before
     or not exists (
       select 1
       from private.knowledge_automation_settings setting
       where setting.municipality_id = '00000000-0000-4000-8000-00000000d002'
         and setting.last_run_status = 'failed'
         and setting.last_safe_error_code = 'knowledge_runtime_not_verified'
     ) then
    raise exception 'revoked runtime gate allowed scheduler claim or I/O';
  end if;

  update private.knowledge_automation_settings
  set enabled = municipality_id = '00000000-0000-4000-8000-00000000d001',
      last_run_at = null,
      last_run_status = null,
      last_safe_error_code = null
  where municipality_id in (
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d002'
  );
end
$revoked_runtime_dispatch_fail_closed$;

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
do $attest_expiring_runtime$
declare
  v_gate_id uuid;
begin
  v_gate_id := public.ia_fiscal_attest_knowledge_runtime_ready(
    'abcdefghijklmnop',
    'knowledge-ingest-v2', 'ingest-deployment-qa-2', repeat('4', 64),
    'knowledge-embed-v1', 'embed-deployment-qa-2', repeat('5', 64),
    'knowledge-search-v1', 'search-deployment-qa-2', repeat('6', 64),
    encode(extensions.digest('qa-runtime-smoke-evidence-expiry', 'sha256'), 'hex'),
    'qa-evidence:runtime-smoke-manifest-expiry',
    now() + interval '1 day',
    'ATESTAR RUNTIME SEGUNDO CEREBRO'
  );
  perform set_config('qa.phase2_expiring_runtime_gate_id', v_gate_id::text, true);
end
$attest_expiring_runtime$;
reset role;

insert into private.knowledge_runtime_release_gates (
  id,
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
  valid_from,
  valid_until
) values (
  '00000000-0000-4000-8000-00000000db01',
  'abcdefghijklmnop',
  'knowledge-ingest-v2', 'ingest-deployment-qa-expired', repeat('a', 64),
  'knowledge-embed-v1', 'embed-deployment-qa-expired', repeat('b', 64),
  'knowledge-search-v1', 'search-deployment-qa-expired', repeat('c', 64),
  encode(extensions.digest('qa-runtime-smoke-evidence-expired', 'sha256'), 'hex'),
  'qa-evidence:runtime-smoke-manifest-expired',
  now() - interval '2 days',
  now() - interval '1 day'
);
update private.knowledge_runtime_current_gates current_gate
set runtime_gate_id = '00000000-0000-4000-8000-00000000db01',
    selected_at = now()
where current_gate.project_ref = 'abcdefghijklmnop';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $expired_runtime_search_fail_closed$
declare
  v_denied boolean := false;
begin
  begin
    perform public.ia_fiscal_hybrid_search_legal_knowledge(
      '00000000-0000-4000-8000-00000000d001', 'legislacao vigente', null, 8
    );
  exception when sqlstate '55000' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'hybrid search ran with an expired runtime gate';
  end if;
end
$expired_runtime_search_fail_closed$;
reset role;

do $expired_runtime_dispatch_fail_closed$
declare
  v_before bigint;
  v_result jsonb;
begin
  select count(*) into v_before from private.knowledge_scheduler_dispatches;
  v_result := private.ia_fiscal_dispatch_due_knowledge_work(2);
  if v_result ->> 'status' <> 'runtime_not_verified'
     or (select count(*) from private.knowledge_scheduler_dispatches) <> v_before then
    raise exception 'expired runtime gate allowed scheduler claim or I/O';
  end if;
  update private.knowledge_automation_settings
  set last_run_at = null,
      last_run_status = null,
      last_safe_error_code = null
  where municipality_id = '00000000-0000-4000-8000-00000000d001';
end
$expired_runtime_dispatch_fail_closed$;

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
do $restore_current_runtime$
declare
  v_gate_id uuid;
begin
  v_gate_id := public.ia_fiscal_attest_knowledge_runtime_ready(
    'abcdefghijklmnop',
    'knowledge-ingest-v2', 'ingest-deployment-qa-3', repeat('7', 64),
    'knowledge-embed-v1', 'embed-deployment-qa-3', repeat('8', 64),
    'knowledge-search-v1', 'search-deployment-qa-3', repeat('9', 64),
    encode(extensions.digest('qa-runtime-smoke-evidence-current', 'sha256'), 'hex'),
    'qa-evidence:runtime-smoke-manifest-current',
    now() + interval '1 day',
    'ATESTAR RUNTIME SEGUNDO CEREBRO'
  );
  perform set_config('qa.phase2_current_gate_id', v_gate_id::text, true);
end
$restore_current_runtime$;
reset role;

do $restored_runtime_assertions$
declare
  v_gate_id uuid := current_setting('qa.phase2_current_gate_id')::uuid;
begin
  if private.current_knowledge_runtime_gate_id() is distinct from v_gate_id
     or not private.knowledge_runtime_is_verified() then
    raise exception 'exact current runtime gate was not restored after re-attestation';
  end if;
end
$restored_runtime_assertions$;

do $semantic_retirement_audit$
begin
  if (
    select count(*)
    from private.legal_embedding_job_events event
    where event.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and event.job_id = (
        select job.id
        from private.legal_embedding_jobs job
        where job.municipality_id = event.municipality_id
          and job.legal_chunk_id = '00000000-0000-4000-8000-00000000d601'
      )
      and event.event_type = 'skipped'
      and event.safe_error_code = 'semantic_model_language_unsupported'
  ) <> 1 then
    raise exception 'retired semantic job did not emit one terminal audit event';
  end if;
  if exists (
    select 1
    from private.legal_embeddings embedding
    where embedding.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and embedding.legal_chunk_id = '00000000-0000-4000-8000-00000000d601'
  ) then
    raise exception 'retired gte-small path persisted a new PT-BR vector';
  end if;
end
$semantic_retirement_audit$;

-- A legacy-looking published row with integral section/chunk but no governed
-- artifact mapping, successful fetch or Storage object must remain unusable
-- for both article approval and publication.
do $legacy_uncaptured_fixture$
declare
  v_legal_text text := 'Art. 9º Texto legado sem captura oficial que nao pode fundamentar conhecimento juridico publicado.';
  v_answer text := 'Resposta sintetica baseada apenas em evidencia legada sem artefato governado.';
  v_legal_sha text;
  v_answer_sha text;
begin
  v_legal_sha := encode(extensions.digest(v_legal_text, 'sha256'), 'hex');
  v_answer_sha := encode(extensions.digest(v_answer, 'sha256'), 'hex');

  insert into public.legal_sources (
    id, municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values (
    '00000000-0000-4000-8000-00000000dc01',
    '00000000-0000-4000-8000-00000000d001',
    'law', 'municipal', 'Prefeitura QA legado', 'Lei QA sem artefato',
    'Lei QA legado nº 9/2026', 'https://qa-legacy.example.invalid/lei-9-2026',
    'Tributos municipais', 'fiscal_knowledge', 'active'
  );

  set local session_replication_role = replica;
  insert into public.legal_source_versions (
    id, municipality_id, source_id, version, status, content_text,
    content_sha256, valid_from, publication_date,
    approved_by, approved_at, published_at
  ) values (
    '00000000-0000-4000-8000-00000000dc02',
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000dc01',
    1, 'published', v_legal_text, v_legal_sha,
    current_date - 1, current_date - 1,
    '00000000-0000-4000-8000-00000000d101', now(), now()
  );
  insert into public.legal_sections (
    id, municipality_id, source_version_id, section_key, heading, ordinal,
    content_text, content_sha256
  ) values (
    '00000000-0000-4000-8000-00000000dc03',
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000dc02',
    'integral', 'Texto integral legado', 1, v_legal_text, v_legal_sha
  );
  insert into private.legal_chunks (
    id, municipality_id, legal_section_id, chunk_index, content_text,
    token_count, content_sha256
  ) values (
    '00000000-0000-4000-8000-00000000dc04',
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000dc03',
    1, v_legal_text, 17, v_legal_sha
  );
  set local session_replication_role = origin;

  insert into public.knowledge_articles (
    id, municipality_id, intent_key, canonical_question, tax_scope,
    divergence_scope, status, current_revision_number, is_test,
    approval_basis, created_by
  ) values (
    '00000000-0000-4000-8000-00000000dc05',
    '00000000-0000-4000-8000-00000000d001',
    'qa:legacy-uncaptured',
    'A evidencia legada pode fundamentar resposta?',
    'ISSQN', 'fiscal_knowledge', 'under_review', 1, false,
    'fiscal_review', '00000000-0000-4000-8000-00000000d101'
  );
  insert into public.knowledge_article_revisions (
    id, municipality_id, article_id, revision_number, answer_body,
    source_type, content_sha256, created_by
  ) values (
    '00000000-0000-4000-8000-00000000dc06',
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000dc05',
    1, v_answer, 'legal_seed', v_answer_sha,
    '00000000-0000-4000-8000-00000000d101'
  );
  insert into public.knowledge_article_citations (
    id, municipality_id, revision_id, legal_section_id, source_version_id,
    citation_label, quoted_excerpt, source_sha256
  ) values (
    '00000000-0000-4000-8000-00000000dc07',
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000dc06',
    '00000000-0000-4000-8000-00000000dc03',
    '00000000-0000-4000-8000-00000000dc02',
    'Lei QA legado, art. 9º', v_legal_text, v_legal_sha
  );

  if private.legal_source_version_is_current_citable(
       '00000000-0000-4000-8000-00000000d001',
       '00000000-0000-4000-8000-00000000dc02'
     ) then
    raise exception 'legacy published version without artifact became citable';
  end if;
  perform set_config('qa.phase2_legacy_answer_sha', v_answer_sha, true);
end
$legacy_uncaptured_fixture$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $legacy_uncaptured_review_denied$
declare
  v_denied boolean := false;
begin
  begin
    perform public.ia_review_knowledge_article(
      '00000000-0000-4000-8000-00000000d001',
      '00000000-0000-4000-8000-00000000dc05',
      '00000000-0000-4000-8000-00000000dc06',
      'approved', null, 'REVISAR'
    );
  exception when others then
    v_denied := position('not current, verifiable and published' in sqlerrm) > 0;
  end;
  if not v_denied then
    raise exception 'article review accepted a legacy citation without artifact evidence';
  end if;
end
$legacy_uncaptured_review_denied$;
reset role;

set local session_replication_role = replica;
update public.knowledge_articles article
set status = 'approved'
where article.id = '00000000-0000-4000-8000-00000000dc05';
insert into public.knowledge_article_reviews (
  municipality_id, article_id, revision_id, decision,
  reviewer_membership_id, approved_content_sha256
) values (
  '00000000-0000-4000-8000-00000000d001',
  '00000000-0000-4000-8000-00000000dc05',
  '00000000-0000-4000-8000-00000000dc06',
  'approved',
  '00000000-0000-4000-8000-00000000d202',
  current_setting('qa.phase2_legacy_answer_sha')
);
set local session_replication_role = origin;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $legacy_uncaptured_publish_denied$
declare
  v_denied boolean := false;
begin
  begin
    perform public.ia_publish_knowledge_article(
      '00000000-0000-4000-8000-00000000d001',
      '00000000-0000-4000-8000-00000000dc05',
      'PUBLICAR'
    );
  exception when others then
    v_denied := position('not current, verifiable and published' in sqlerrm) > 0;
  end;
  if not v_denied then
    raise exception 'article publication accepted a legacy citation without artifact evidence';
  end if;
end
$legacy_uncaptured_publish_denied$;
reset role;

-- Add chunks for enabled and disabled tenants. Every one must be terminalized
-- identically because the retired semantic model is unsupported for PT-BR.
do $embedding_fairness_fixture$
declare
  v_content text := 'Conteudo juridico oficial sintetico do segundo municipio para validar justica entre filas de embeddings.';
  v_disabled_content text := 'Conteudo juridico oficial sintetico do terceiro municipio desabilitado que jamais pode ser reivindicado pelo worker.';
  v_sha text;
  v_disabled_sha text;
begin
  v_sha := encode(extensions.digest(v_content, 'sha256'), 'hex');
  v_disabled_sha := encode(extensions.digest(v_disabled_content, 'sha256'), 'hex');

  insert into private.legal_chunks (
    id, municipality_id, legal_section_id, chunk_index, content_text,
    token_count, content_sha256
  )
  select
    '00000000-0000-4000-8000-00000000d606',
    version.municipality_id,
    '00000000-0000-4000-8000-00000000d501',
    2,
    version.content_text,
    14,
    version.content_sha256
  from public.legal_source_versions version
  where version.id = '00000000-0000-4000-8000-00000000d401';

  insert into public.legal_sources (
    id, municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values (
    '00000000-0000-4000-8000-00000000d306',
    '00000000-0000-4000-8000-00000000d002',
    'law', 'municipal', 'Prefeitura QA Phase 2 B', 'Lei QA tenant B',
    'Lei QA B nº 1/2026', 'https://qa-b.example.invalid/lei-1-2026',
    'Tributos municipais', 'fiscal_knowledge', 'draft'
  );
  insert into public.legal_source_versions (
    id, municipality_id, source_id, version, status, content_text,
    content_sha256, valid_from, publication_date
  ) values (
    '00000000-0000-4000-8000-00000000d402',
    '00000000-0000-4000-8000-00000000d002',
    '00000000-0000-4000-8000-00000000d306',
    1, 'under_review', v_content, v_sha, current_date, current_date
  );
  insert into public.legal_sections (
    id, municipality_id, source_version_id, section_key, heading, ordinal,
    content_text, content_sha256
  ) values (
    '00000000-0000-4000-8000-00000000d502',
    '00000000-0000-4000-8000-00000000d002',
    '00000000-0000-4000-8000-00000000d402',
    'integral', 'Texto integral', 1, v_content, v_sha
  );
  insert into private.legal_chunks (
    id, municipality_id, legal_section_id, chunk_index, content_text,
    token_count, content_sha256
  ) values (
    '00000000-0000-4000-8000-00000000d602',
    '00000000-0000-4000-8000-00000000d002',
    '00000000-0000-4000-8000-00000000d502',
    1, v_content, 14, v_sha
  );

  insert into public.municipalities (id, slug, name, state_code, status)
  values (
    '00000000-0000-4000-8000-00000000d003',
    'qa-phase2-disabled',
    'Prefeitura QA Phase 2 desabilitada',
    'SP',
    'active'
  );
  insert into private.knowledge_automation_settings (
    municipality_id, enabled, timezone, next_run_at, endpoint_batch_size
  ) values (
    '00000000-0000-4000-8000-00000000d003',
    false,
    'America/Sao_Paulo',
    now(),
    2
  );
  insert into public.legal_sources (
    id, municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values (
    '00000000-0000-4000-8000-00000000d307',
    '00000000-0000-4000-8000-00000000d003',
    'law', 'municipal', 'Prefeitura QA Phase 2 C', 'Lei QA tenant desabilitado',
    'Lei QA C nº 1/2026', 'https://qa-c.example.invalid/lei-1-2026',
    'Tributos municipais', 'fiscal_knowledge', 'draft'
  );
  insert into public.legal_source_versions (
    id, municipality_id, source_id, version, status, content_text,
    content_sha256, valid_from, publication_date
  ) values (
    '00000000-0000-4000-8000-00000000d403',
    '00000000-0000-4000-8000-00000000d003',
    '00000000-0000-4000-8000-00000000d307',
    1, 'under_review', v_disabled_content, v_disabled_sha,
    current_date, current_date
  );
  insert into public.legal_sections (
    id, municipality_id, source_version_id, section_key, heading, ordinal,
    content_text, content_sha256
  ) values (
    '00000000-0000-4000-8000-00000000d503',
    '00000000-0000-4000-8000-00000000d003',
    '00000000-0000-4000-8000-00000000d403',
    'integral', 'Texto integral', 1, v_disabled_content, v_disabled_sha
  );
  insert into private.legal_chunks (
    id, municipality_id, legal_section_id, chunk_index, content_text,
    token_count, content_sha256
  ) values
    ('00000000-0000-4000-8000-00000000d603',
     '00000000-0000-4000-8000-00000000d003',
     '00000000-0000-4000-8000-00000000d503', 1,
     v_disabled_content, 16, v_disabled_sha),
    ('00000000-0000-4000-8000-00000000d604',
     '00000000-0000-4000-8000-00000000d003',
     '00000000-0000-4000-8000-00000000d503', 2,
     v_disabled_content, 16, v_disabled_sha),
    ('00000000-0000-4000-8000-00000000d605',
     '00000000-0000-4000-8000-00000000d003',
     '00000000-0000-4000-8000-00000000d503', 3,
     v_disabled_content, 16, v_disabled_sha);

  update private.knowledge_automation_settings setting
  set enabled = true
  where setting.municipality_id in (
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d002'
  );
end
$embedding_fairness_fixture$;

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
do $embedding_tenant_fairness$
declare
  v_first uuid;
  v_second uuid;
begin
  select claimed.municipality_id into v_first
  from public.ia_fiscal_claim_legal_embedding_jobs(1) claimed;
  select claimed.municipality_id into v_second
  from public.ia_fiscal_claim_legal_embedding_jobs(1) claimed;
  if v_first is not null
     or v_second is not null then
    raise exception 'retired semantic worker claimed work';
  end if;
end
$embedding_tenant_fairness$;
reset role;

do $embedding_disabled_scope_audit$
begin
  if exists (
    select 1
    from private.legal_embedding_jobs job
    where job.municipality_id = '00000000-0000-4000-8000-00000000d003'
      and (
        job.status <> 'skipped'
        or job.attempts <> 0
        or job.safe_error_code <> 'semantic_model_language_unsupported'
      )
  ) or exists (
    select 1
    from private.legal_embedding_job_events event
    where event.municipality_id = '00000000-0000-4000-8000-00000000d003'
      and event.event_type = 'claimed'
  ) then
    raise exception 'retired semantic work became claimable for a disabled tenant';
  end if;
end
$embedding_disabled_scope_audit$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $evidence_and_snapshot$
declare
  v_page jsonb;
  v_snapshot jsonb;
  v_result jsonb;
begin
  v_page := public.ia_get_legal_source_change_evidence(
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d801',
    0, 20000, 0, 25, 0, 50
  );
  if (v_page ->> 'change_item_total')::integer <> 105
     or jsonb_array_length(v_page -> 'change_items') <> 50
     or not (v_page ->> 'change_items_has_more')::boolean
     or char_length(v_page ->> 'change_items_full_sha256') <> 64 then
    raise exception 'change-item evidence pagination/hash contract failed';
  end if;
  v_page := public.ia_get_legal_source_change_evidence(
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d801',
    0, 20000, 0, 25, 100, 50
  );
  if jsonb_array_length(v_page -> 'change_items') <> 5
     or (v_page ->> 'change_items_has_more')::boolean then
    raise exception 'final evidence page is inconsistent';
  end if;

  v_snapshot := public.ia_get_knowledge_operations_snapshot(
    '00000000-0000-4000-8000-00000000d001'
  );
  if v_snapshot -> 'summary' ->> 'indexed_sections' <> '0'
     or v_snapshot -> 'summary' ->> 'indexed_chunks' <> '0'
     or v_snapshot -> 'summary' ->> 'pending_embeddings' <> '0'
     or v_snapshot -> 'search_policy' ->> 'canonical_retrieval' <> 'lexical_portuguese'
     or v_snapshot -> 'search_policy' ->> 'semantic_status' <> 'unsupported_language'
     or v_snapshot -> 'search_policy' ->> 'semantic_usable_chunks' <> '0' then
    raise exception 'snapshot overstated lexical or semantic search coverage';
  end if;
  if v_snapshot -> 'schedule' ->> 'last_run_status' <> 'never_run'
     or not (v_snapshot -> 'schedule' ->> 'runtime_verified')::boolean then
    raise exception 'initial schedule snapshot is null or runtime-unverified';
  end if;

  v_result := public.ia_fiscal_hybrid_search_legal_knowledge(
    '00000000-0000-4000-8000-00000000d001', 'lançamento tributário', null, 8
  );
  if coalesce((v_result ->> 'answered')::boolean, true)
     or v_result -> 'blockers' <> '["no_current_published_source"]'::jsonb then
    raise exception 'search answered from non-published evidence';
  end if;
end
$evidence_and_snapshot$;
reset role;

-- The municipal admin owns schedule configuration; a narrow reviewer grant
-- cannot enable it.  Runtime is now attested, so the explicit admin action is
-- expected to work.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d101', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d101","role":"authenticated","aal":"aal2"}',
  true
);
select public.ia_configure_knowledge_schedule(
  '00000000-0000-4000-8000-00000000d001', true,
  'ATIVAR ATUALIZACAO OFICIAL'
);
reset role;

-- pg_net is asynchronous.  Reconcile a retained synthetic response into one
-- immutable retry transition, then prove a repeated reconciliation is idempotent.
do $pg_net_reconciliation$
declare
  v_dispatch_id bigint;
  v_request_id constant bigint := -9223372036854770000;
  v_dispatch_207_id bigint;
  v_request_207_id constant bigint := -9223372036854769999;
  v_breaker_dispatch_id bigint;
  v_breaker_request_id constant bigint := -9223372036854769998;
begin
  insert into private.knowledge_scheduler_dispatches (
    scope, request_id, attempt, status
  ) values (
    'embed', v_request_id, 1, 'queued'
  ) returning id into v_dispatch_id;
  insert into private.knowledge_scheduler_dispatch_events (
    dispatch_id, event_type, metadata
  ) values (
    v_dispatch_id, 'queued', jsonb_build_object('fixture', 'pg_net_503')
  );
  insert into net._http_response (
    id, status_code, content_type, headers, content, timed_out, error_msg
  ) values (
    v_request_id, 503, 'application/json', '{}'::jsonb,
    '{"error":"synthetic_unavailable"}', false, null
  );

  perform private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(10);
  perform private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(10);
  if (
    select count(*)
    from private.knowledge_scheduler_dispatch_events event
    where event.dispatch_id = v_dispatch_id
      and event.event_type = 'retry_scheduled'
      and event.http_status = 503
      and event.safe_error_code = 'scheduler_http_503'
      and event.retry_at > now()
  ) <> 1 then
    raise exception 'pg_net response was not reconciled into one retry event';
  end if;

  insert into private.knowledge_scheduler_dispatches (
    scope, request_id, attempt, status
  ) values (
    'embed', v_request_207_id, 2, 'queued'
  ) returning id into v_dispatch_207_id;
  insert into private.knowledge_scheduler_dispatch_events (
    dispatch_id, event_type, metadata
  ) values (
    v_dispatch_207_id, 'queued', jsonb_build_object('fixture', 'pg_net_207')
  );
  insert into net._http_response (
    id, status_code, content_type, headers, content, timed_out, error_msg
  ) values (
    v_request_207_id, 207, 'application/json', '{}'::jsonb,
    '{"data":{"claimed":2,"completed":1,"failed":1}}', false, null
  );

  perform private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(10);
  perform private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(10);
  if (
    select count(*)
    from private.knowledge_scheduler_dispatch_events event
    where event.dispatch_id = v_dispatch_207_id
      and event.event_type = 'retry_scheduled'
      and event.http_status = 207
      and event.safe_error_code = 'scheduler_embed_batch_partial_failure'
      and event.retry_at > now()
  ) <> 1 then
    raise exception 'HTTP 207 embed response bypassed retry and breaker accounting';
  end if;

  insert into private.knowledge_scheduler_dispatches (
    scope, request_id, attempt, status
  ) values (
    'embed', v_breaker_request_id, 3, 'queued'
  ) returning id into v_breaker_dispatch_id;
  insert into private.knowledge_scheduler_dispatch_events (
    dispatch_id, event_type, metadata
  ) values (
    v_breaker_dispatch_id, 'queued', jsonb_build_object('fixture', 'pg_net_207_breaker')
  );
  insert into net._http_response (
    id, status_code, content_type, headers, content, timed_out, error_msg
  ) values (
    v_breaker_request_id, 207, 'application/json', '{}'::jsonb,
    '{"data":{"claimed":1,"completed":0,"failed":1}}', false, null
  );
  perform private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(10);
  if not exists (
    select 1
    from private.knowledge_scheduler_dispatch_events event
    where event.dispatch_id = v_breaker_dispatch_id
      and event.event_type = 'circuit_opened'
      and event.http_status = 207
      and event.safe_error_code = 'scheduler_embed_batch_partial_failure'
      and event.retry_at >= now() + interval '29 minutes'
  ) then
    raise exception 'HTTP 207 embed response did not contribute to the circuit breaker';
  end if;
end
$pg_net_reconciliation$;

-- Force the first due window, then a second window.  The durable dispatch
-- cursor is only a completed fetch or a still-pending dispatch, so the second
-- batch must choose the remaining endpoint rather than repeat the first two.
update private.knowledge_automation_settings
set next_run_at = now() - interval '1 minute', endpoint_batch_size = 2
where municipality_id = '00000000-0000-4000-8000-00000000d001';
select private.ia_fiscal_dispatch_due_knowledge_work(2);

do $scheduler_batch_one$
begin
  if (
    select count(*) from private.knowledge_scheduler_dispatches dispatch
    where dispatch.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and dispatch.scope = 'ingest' and dispatch.endpoint_id is not null
  ) <> 2 then
    raise exception 'scheduler first batch did not queue exactly two endpoints';
  end if;
end
$scheduler_batch_one$;

update private.knowledge_automation_settings
set next_run_at = now() - interval '1 minute'
where municipality_id = '00000000-0000-4000-8000-00000000d001';
select private.ia_fiscal_dispatch_due_knowledge_work(2);

do $scheduler_batch_two$
begin
  if (
    select count(distinct dispatch.endpoint_id)
    from private.knowledge_scheduler_dispatches dispatch
    where dispatch.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and dispatch.scope = 'ingest' and dispatch.endpoint_id is not null
  ) <> 3 or exists (
    select dispatch.endpoint_id
    from private.knowledge_scheduler_dispatches dispatch
    where dispatch.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and dispatch.scope = 'ingest' and dispatch.endpoint_id is not null
    group by dispatch.endpoint_id having count(*) > 1
  ) then
    raise exception 'scheduler repeated an endpoint or starved the second batch';
  end if;
end
$scheduler_batch_two$;

-- Establish a recently verified last-known-good legal body only after the
-- scheduler fairness scenario, so the cutover test does not add another due
-- endpoint to either bounded batch.
insert into private.legal_source_endpoints (
  id, municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
  citable_body, url, allowed_hosts, expected_content_types, parser_hint,
  poll_interval, priority, status, metadata
) values (
  '00000000-0000-4000-8000-00000000d905',
  '00000000-0000-4000-8000-00000000d001',
  '00000000-0000-4000-8000-00000000d301',
  'document_file', 'primary_publication', 'legal_body', true,
  'https://legacy.example.invalid/leis/123-2026.pdf',
  array['legacy.example.invalid'], array['application/pdf'],
  'legacy_last_known_good', interval '24 hours', 5, 'active',
  jsonb_build_object('fixture', 'last_known_good_before_validated_cutover')
);

-- Catalog discovery runs as the custom-authenticated service worker.  The
-- same semantic law discovered in two classifications must yield one source,
-- one promotion candidate and two coverage links.
set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
select public.ia_fiscal_record_knowledge_discoveries(
  '00000000-0000-4000-8000-00000000d901',
  jsonb_build_array(jsonb_build_object(
    'url', 'https://qa-siscam.example.invalid/Documentos/Documento/111',
    'relation_kind', 'related_document',
    'mime_type', 'text/html',
    'label', 'Lei nº 123/2026'
  )), now()
);
select public.ia_fiscal_record_knowledge_discoveries(
  '00000000-0000-4000-8000-00000000d902',
  jsonb_build_array(jsonb_build_object(
    'url', 'https://qa-siscam.example.invalid/Documentos/Documento/222',
    'relation_kind', 'related_document',
    'mime_type', 'text/html',
    'label', 'Lei nº 123/2026'
  )), now()
);
reset role;

do $catalog_identity$
declare
  v_candidate_id uuid;
  v_ficha_id uuid;
begin
  select candidate.id into strict v_candidate_id
  from private.legal_source_promotion_candidates candidate
  where candidate.municipality_id = '00000000-0000-4000-8000-00000000d001'
    and candidate.canonical_legal_key = 'law:123:2026';
  if (
    select candidate.promoted_source_id
    from private.legal_source_promotion_candidates candidate
    where candidate.id = v_candidate_id
  ) <> '00000000-0000-4000-8000-00000000d301'::uuid then
    raise exception 'canonical dedupe depended on authority spelling';
  end if;
  if (
    select count(*) from public.legal_sources source
    where source.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and source.official_identifier = 'Lei nº 123/2026'
  ) <> 1 then
    raise exception 'catalog discovery duplicated the legacy legal identity';
  end if;
  if (
    select count(*) from private.legal_catalog_coverage_candidates link
    where link.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and link.candidate_id = v_candidate_id
  ) <> 2 then
    raise exception 'one canonical candidate was not linked N:N to both coverages';
  end if;
  if not exists (
    select 1 from private.knowledge_automation_settings setting
    where setting.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and setting.last_run_status = 'partial'
      and setting.next_run_at <= now() + interval '6 minutes'
  ) then
    raise exception 'new catalog work did not advance the durable scheduler cursor';
  end if;
  select endpoint.id into strict v_ficha_id
  from private.legal_source_endpoints endpoint
  where endpoint.municipality_id = '00000000-0000-4000-8000-00000000d001'
    and endpoint.source_id = '00000000-0000-4000-8000-00000000d301'
    and endpoint.endpoint_kind = 'document_page'
    and endpoint.content_mode = 'catalog_only'
    and endpoint.status = 'active';
  perform set_config('qa.phase2_ficha_id', v_ficha_id::text, true);
end
$catalog_identity$;

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
select public.ia_fiscal_record_knowledge_discoveries(
  current_setting('qa.phase2_ficha_id')::uuid,
  jsonb_build_array(jsonb_build_object(
    'url', 'https://qa-siscam.example.invalid/arquivo?Id=901',
    'relation_kind', 'attachment',
    'mime_type', 'application/pdf',
    'byte_size', 1048576,
    'label', 'PDF integral A'
  )), now()
);
select public.ia_fiscal_record_knowledge_discoveries(
  current_setting('qa.phase2_ficha_id')::uuid,
  jsonb_build_array(jsonb_build_object(
    'url', 'https://qa-siscam.example.invalid/arquivo?Id=902',
    'relation_kind', 'attachment',
    'mime_type', 'application/pdf',
    'byte_size', 1048577,
    'label', 'PDF integral B'
  )), now()
);
-- Rediscovery must refresh observation metadata only.  It must never promote
-- a candidate that remains paused pending a validated cutover.
select public.ia_fiscal_record_knowledge_discoveries(
  current_setting('qa.phase2_ficha_id')::uuid,
  jsonb_build_array(jsonb_build_object(
    'url', 'https://qa-siscam.example.invalid/arquivo?Id=902',
    'relation_kind', 'attachment',
    'mime_type', 'application/pdf',
    'byte_size', 1048577,
    'label', 'PDF integral B (redescoberto)'
  )), now()
);
reset role;

do $cutover_and_health$
declare
  v_active_body uuid;
begin
  select endpoint.id into strict v_active_body
  from private.legal_source_endpoints endpoint
  where endpoint.municipality_id = '00000000-0000-4000-8000-00000000d001'
    and endpoint.source_id = '00000000-0000-4000-8000-00000000d301'
    and endpoint.content_mode = 'legal_body'
    and endpoint.status = 'active';
  if (
    select endpoint.url from private.legal_source_endpoints endpoint
    where endpoint.id = v_active_body
  ) in (
    'https://qa-siscam.example.invalid/arquivo?Id=901',
    'https://qa-siscam.example.invalid/arquivo?Id=902'
  ) then
    raise exception 'an unvalidated discovery displaced the last-known-good body';
  end if;
  if not exists (
    select 1 from private.legal_source_endpoints endpoint
    where endpoint.source_id = '00000000-0000-4000-8000-00000000d301'
      and endpoint.url = 'https://qa-siscam.example.invalid/arquivo?Id=901'
      and endpoint.status = 'paused'
      and endpoint.metadata ->> 'activation_blocker' = 'validated_cutover_required'
  ) or not exists (
    select 1 from private.legal_source_endpoints endpoint
    where endpoint.source_id = '00000000-0000-4000-8000-00000000d301'
      and endpoint.url = 'https://qa-siscam.example.invalid/arquivo?Id=902'
      and endpoint.status = 'paused'
      and endpoint.metadata ->> 'activation_blocker' = 'validated_cutover_required'
  ) or not exists (
    select 1 from private.legal_source_endpoints endpoint
    where endpoint.id = current_setting('qa.phase2_ficha_id')::uuid
      and endpoint.status = 'active'
      and endpoint.content_mode = 'catalog_only'
  ) then
    raise exception 'safe cutover backlog or discovery ficha state is inconsistent';
  end if;
  if (
    select count(*) from private.legal_body_endpoint_cutovers cutover
    where cutover.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and cutover.source_id = '00000000-0000-4000-8000-00000000d301'
  ) <> 2 then
    raise exception 'blocked cutover audit trail is incomplete';
  end if;
  if exists (
    select 1 from private.legal_body_endpoint_cutovers cutover
    where cutover.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and cutover.source_id = '00000000-0000-4000-8000-00000000d301'
      and cutover.status <> 'blocked'
  ) then
    raise exception 'an unvalidated attachment was marked active for collection';
  end if;

  insert into private.legal_source_fetch_runs (
    municipality_id, source_id, endpoint_id, correlation_id, status,
    requested_url, http_status, safe_error_code, observed_at
  ) values (
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d302',
    '00000000-0000-4000-8000-00000000d901',
    '00000000-0000-4000-8000-00000000db01', 'failed',
    'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=1&Pagina=1',
    503, 'upstream_http_503', now()
  );
  if (
    select coverage.upstream_status from private.legal_catalog_coverages coverage
    where coverage.coverage_key = 'qa.catalog.1'
      and coverage.municipality_id = '00000000-0000-4000-8000-00000000d001'
  ) <> 'blocked_503' then
    raise exception 'real 503 fetch did not update catalog health';
  end if;

  insert into private.legal_source_fetch_runs (
    municipality_id, source_id, endpoint_id, correlation_id, status,
    requested_url, final_url, http_status, observed_content_sha256, observed_at
  ) values (
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d302',
    '00000000-0000-4000-8000-00000000d901',
    '00000000-0000-4000-8000-00000000db02', 'completed_unchanged',
    'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=1&Pagina=1',
    'https://qa-siscam.example.invalid/Documentos/Pesquisa/75?Classificacao=1&Pagina=1',
    200, encode(extensions.digest('catalog-success', 'sha256'), 'hex'), now()
  );
  if exists (
    select 1 from private.legal_catalog_coverages coverage
    where coverage.coverage_key = 'qa.catalog.1'
      and coverage.municipality_id = '00000000-0000-4000-8000-00000000d001'
      and (coverage.upstream_status <> 'available' or coverage.blocker_code is not null)
  ) then
    raise exception 'latest successful fetch did not clear the upstream blocker';
  end if;
end
$cutover_and_health$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000d102', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated","aal":"aal2"}',
  true
);
do $coverage_snapshot$
declare
  v_snapshot jsonb;
begin
  v_snapshot := public.ia_get_knowledge_operations_snapshot(
    '00000000-0000-4000-8000-00000000d001'
  );
  if v_snapshot ->> 'coverage_label' <> 'Cobertura inicial governada'
     or (v_snapshot ->> 'corpus_integral')::boolean
     or jsonb_array_length(v_snapshot -> 'coverage') <> 2 then
    raise exception 'coverage snapshot falsely claimed integral corpus';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_snapshot -> 'coverage') item
    where (item ->> 'corpus_integral')::boolean
       or (item ->> 'discovered')::integer <> 1
       or (item ->> 'published')::integer <> 0
  ) then
    raise exception 'coverage item invariants are inconsistent';
  end if;
end
$coverage_snapshot$;
reset role;

-- A raw legal-body capture is a valid intermediate state: it must preserve an
-- auditable change set while leaving the candidate null until governed
-- extraction/OCR completes.  This is intentionally last so it cannot alter
-- the earlier snapshot/count assertions.
do $raw_capture_fixture$
declare
  v_sha text := encode(
    extensions.digest('atomic raw artifact pending extraction', 'sha256'),
    'hex'
  );
begin
  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-phase2-a/00000000-0000-4000-8000-00000000d305/' ||
      v_sha || '/artifact.txt',
    jsonb_build_object('size', 321, 'mimetype', 'text/plain')
  );
end
$raw_capture_fixture$;

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"service_role","aal":"aal2"}', true);
do $raw_capture_identity$
declare
  v_sha text := encode(
    extensions.digest('atomic raw artifact pending extraction', 'sha256'),
    'hex'
  );
  v_capture jsonb;
begin
  v_capture := public.ia_fiscal_capture_knowledge_source_v2(
    '00000000-0000-4000-8000-00000000d305',
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    'https://qa-siscam.example.invalid/arquivo/atomic.txt',
    v_sha,
    'text/plain',
    321,
    'legal-source-artifacts',
    'qa-phase2-a/00000000-0000-4000-8000-00000000d305/' ||
      v_sha || '/artifact.txt',
    null,
    null,
    null,
    null,
    200,
    now(),
    '00000000-0000-4000-8000-00000000da04',
    jsonb_build_object(
      'extraction_complete', false,
      'content_truncated', false,
      'extracted_char_count', 0,
      'extraction_blocker', 'source_pdf_text_missing',
      'extraction_page_count', 81
    )
  );

  if v_capture ->> 'status' <> 'captured'
     or v_capture ->> 'processing_status' <> 'requires_extraction'
     or nullif(v_capture ->> 'change_set_id', '') is null
     or nullif(v_capture ->> 'candidate_version_id', '') is not null
     or v_capture ->> 'staging_status' <> 'not_applicable'
     or (v_capture ->> 'staged_sections')::integer <> 0
     or (v_capture ->> 'staged_chunks')::integer <> 0 then
    raise exception 'raw capture did not preserve its governed pre-extraction identity';
  end if;
end
$raw_capture_identity$;
reset role;

rollback;
