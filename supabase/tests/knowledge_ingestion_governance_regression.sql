-- Transactional regression for governed official-source ingestion.
-- Synthetic fixtures only; every row and state transition is rolled back.

begin;

do $test$
declare
  x_municipality_a constant uuid := '00000000-0000-4000-8000-00000000c001';
  x_municipality_b constant uuid := '00000000-0000-4000-8000-00000000c002';
  u_legal_a constant uuid := '00000000-0000-4000-8000-00000000c101';
  u_supervisor_a constant uuid := '00000000-0000-4000-8000-00000000c102';
  u_legal_b constant uuid := '00000000-0000-4000-8000-00000000c103';
  u_admin_a constant uuid := '00000000-0000-4000-8000-00000000c104';
  m_legal_a constant uuid := '00000000-0000-4000-8000-00000000c201';
  m_supervisor_a constant uuid := '00000000-0000-4000-8000-00000000c202';
  m_legal_b constant uuid := '00000000-0000-4000-8000-00000000c203';
  m_admin_a constant uuid := '00000000-0000-4000-8000-00000000c204';
  x_source_a constant uuid := '00000000-0000-4000-8000-00000000c301';
  x_article_current constant uuid := '00000000-0000-4000-8000-00000000c401';
  x_revision_current constant uuid := '00000000-0000-4000-8000-00000000c402';
  x_article_admin_denied constant uuid := '00000000-0000-4000-8000-00000000c403';
  x_revision_admin_denied constant uuid := '00000000-0000-4000-8000-00000000c404';
  x_article_future constant uuid := '00000000-0000-4000-8000-00000000c405';
  x_revision_future constant uuid := '00000000-0000-4000-8000-00000000c406';
  x_article_cutover constant uuid := '00000000-0000-4000-8000-00000000c407';
  x_revision_cutover constant uuid := '00000000-0000-4000-8000-00000000c408';
  v_source_id uuid;
  v_endpoint_id uuid;
  v_capture jsonb;
  v_replay jsonb;
  v_change_set_id uuid;
  v_version_id uuid;
  v_review_id uuid;
  v_snapshot jsonb;
  v_failure_run_id uuid;
  v_section_id uuid;
  v_article_review_id uuid;
  v_article_evidence jsonb;
  v_source_evidence jsonb;
  v_article_hash text := encode(extensions.digest('Resposta fiscal vigente com prova oficial.', 'sha256'), 'hex');
  v_legacy_source_id uuid;
  v_legacy_version_id uuid;
  v_legacy_change_id uuid;
  v_legacy_section_id uuid;
  v_legacy_endpoint_id uuid;
  v_legacy_capture jsonb;
  v_legacy_sha text := encode(extensions.digest('legacy content without captured artifact', 'sha256'), 'hex');
  v_legacy_raw_sha text := encode(extensions.digest('legacy official raw document', 'sha256'), 'hex');
  v_future_source_id uuid;
  v_future_endpoint_id uuid;
  v_future_change_id uuid;
  v_future_version_id uuid;
  v_future_section_id uuid;
  v_future_capture jsonb;
  v_future_raw_sha text := encode(extensions.digest('official future raw document', 'sha256'), 'hex');
  v_future_article_hash text := encode(extensions.digest('Resposta baseada em norma ainda futura.', 'sha256'), 'hex');
  v_cutover_article_hash text := encode(extensions.digest('Resposta candidata para corte temporal.', 'sha256'), 'hex');
  v_unstaged_fetch_id uuid;
  v_unstaged_artifact_id uuid;
  v_unstaged_version_id uuid;
  v_unstaged_change_id uuid;
  v_unstaged_raw_sha text := encode(extensions.digest('unstaged official raw document', 'sha256'), 'hex');
  v_unstaged_text_sha text := encode(extensions.digest('unstaged extracted legal text', 'sha256'), 'hex');
  v_partial_raw_sha text := encode(extensions.digest('partial official raw document', 'sha256'), 'hex');
  v_bad_metadata jsonb;
  v_pending_source_id uuid;
  v_pending_endpoint_id uuid;
  v_pending_capture jsonb;
  v_pending_replay jsonb;
  v_pending_raw_sha text := encode(extensions.digest('pending extraction raw document', 'sha256'), 'hex');
  v_pending_raw_sha_2 text := encode(extensions.digest('pending extraction raw document v2', 'sha256'), 'hex');
  v_missing_object_sha text := encode(extensions.digest('missing object raw document', 'sha256'), 'hex');
  v_semantic_raw_sha text := encode(extensions.digest('official raw document v1 repackaged', 'sha256'), 'hex');
  v_semantic_capture jsonb;
  v_denied boolean;
  v_error text;
  v_raw_sha text := encode(extensions.digest('official raw document v1', 'sha256'), 'hex');
  v_business_date date;
begin
  insert into public.municipalities (id, slug, name, state_code, status)
  values
    (x_municipality_a, 'qa-knowledge-a', 'QA Conhecimento A', 'SP', 'active'),
    (x_municipality_b, 'qa-knowledge-b', 'QA Conhecimento B', 'SP', 'active');
  v_business_date := private.municipality_current_date(x_municipality_a);
  if v_business_date <> (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'municipality business date did not use its configured timezone';
  end if;

  insert into storage.buckets (id, name, public)
  values ('qa-control-artifacts', 'qa-control-artifacts', false);
  insert into storage.objects (bucket_id, name, metadata)
  values (
    'qa-control-artifacts',
    'control.txt',
    jsonb_build_object('size', 7, 'mimetype', 'text/plain')
  );

  insert into auth.users (
    id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values
    (u_legal_a, 'authenticated', 'authenticated', 'qa-legal-a@example.invalid', '{}', '{}', now(), now()),
    (u_supervisor_a, 'authenticated', 'authenticated', 'qa-supervisor-a@example.invalid', '{}', '{}', now(), now()),
    (u_legal_b, 'authenticated', 'authenticated', 'qa-legal-b@example.invalid', '{}', '{}', now(), now()),
    (u_admin_a, 'authenticated', 'authenticated', 'qa-admin-a@example.invalid', '{}', '{}', now(), now());

  insert into public.municipality_memberships (
    id, municipality_id, user_id, role, status, valid_from, activated_at
  ) values
    (m_legal_a, x_municipality_a, u_legal_a, 'legal_reviewer', 'active', now() - interval '1 day', now()),
    (m_supervisor_a, x_municipality_a, u_supervisor_a, 'supervisor', 'active', now() - interval '1 day', now()),
    (m_legal_b, x_municipality_b, u_legal_b, 'legal_reviewer', 'active', now() - interval '1 day', now()),
    (m_admin_a, x_municipality_a, u_admin_a, 'municipal_admin', 'active', now() - interval '1 day', now());

  insert into public.legal_sources (
    id,
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
  ) values (
    x_source_a,
    x_municipality_a,
    'law',
    'municipal',
    'Município QA A',
    'Código Tributário QA',
    'Lei QA nº 1/2026',
    'https://official-a.example.invalid/law/1',
    'Tributos municipais',
    'fiscal_knowledge',
    'draft'
  ) returning id into v_source_id;

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
    status
  ) values (
    x_municipality_a,
    v_source_id,
    'document_file',
    'primary_publication',
    'legal_body',
    true,
    'https://official-a.example.invalid/law/1',
    array['official-a.example.invalid'],
    array['text/plain'],
    'qa_text',
    'active'
  ) returning id into v_endpoint_id;

  v_denied := false;
  begin
    update public.legal_sources
    set official_url = 'https://attacker.example.invalid/replaced'
    where id = v_source_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'governed legal source identity is immutable';
  end;
  if not v_denied then
    raise exception 'official legal source URL was mutable outside governance';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.ia_fiscal_capture_knowledge_source(uuid,text,text,text,text,bigint,text,text,text,text,text,integer,timestamp with time zone,uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'authenticated can execute the service-only capture RPC';
  end if;
  if has_function_privilege(
       'service_role',
       'public.ia_review_legal_source_change(uuid,text,text,text,date,date,date)',
       'EXECUTE'
     ) then
    raise exception 'service role can execute the human legal-review RPC';
  end if;
  if has_function_privilege(
       'service_role',
       'public.ia_publish_legal_source_version(uuid,text)',
       'EXECUTE'
     ) then
    raise exception 'service role can execute legal publication';
  end if;
  if has_function_privilege(
       'authenticated',
       'private.municipality_current_date(uuid)',
       'EXECUTE'
     ) or has_function_privilege(
       'service_role',
       'private.legal_version_has_complete_evidence(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'API role can execute an internal SECURITY DEFINER helper directly';
  end if;
  if position(
    'pg_advisory_xact_lock' in pg_get_functiondef(
      'public.ia_fiscal_record_knowledge_fetch_failure(uuid,text,integer,text,text,timestamp with time zone,uuid,jsonb)'::regprocedure
    )
  ) = 0 then
    raise exception 'failure idempotency lacks correlation-level serialization';
  end if;
  if has_table_privilege('authenticated', 'private.legal_source_artifacts', 'SELECT')
     or has_table_privilege('authenticated', 'private.legal_source_artifacts', 'INSERT') then
    raise exception 'authenticated has direct artifact-table privileges';
  end if;
  if has_table_privilege('service_role', 'public.legal_sources', 'UPDATE')
     or has_table_privilege('service_role', 'public.legal_source_versions', 'UPDATE')
     or has_table_privilege('service_role', 'public.legal_source_versions', 'DELETE')
     or has_table_privilege('service_role', 'public.legal_sections', 'DELETE')
     or has_table_privilege('service_role', 'private.legal_chunks', 'UPDATE') then
    raise exception 'service_role retains direct mutation privileges over governed legal evidence';
  end if;
  if not (
    select class.relrowsecurity
    from pg_class class
    join pg_namespace namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'private'
      and class.relname = 'legal_source_artifacts'
  ) then
    raise exception 'artifact table does not have RLS enabled';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
    true
  );

  for v_bad_metadata in
    select value
    from jsonb_array_elements(jsonb_build_array(
      '{}'::jsonb,
      jsonb_build_object(
        'extraction_complete', false,
        'content_truncated', true,
        'extracted_char_count', char_length('partial extracted text')
      ),
      jsonb_build_object(
        'extraction_complete', false,
        'content_truncated', false,
        'extracted_char_count', char_length('partial extracted text')
      ),
      jsonb_build_object(
        'extraction_complete', true,
        'content_truncated', false,
        'extracted_char_count', char_length('partial extracted text') - 1
      )
    ))
  loop
    v_denied := false;
    begin
      perform public.ia_fiscal_capture_knowledge_source(
        v_source_id,
        'https://official-a.example.invalid/law/1',
        'https://official-a.example.invalid/law/1',
        v_partial_raw_sha,
        'text/plain',
        29,
        'legal-source-artifacts',
        'qa-knowledge-a/' || v_source_id::text || '/' || v_partial_raw_sha || '/partial.txt',
        'partial extracted text',
        null,
        null,
        200,
        now(),
        '00000000-0000-4000-8000-00000000c306',
        v_bad_metadata
      );
    exception when others then
      get stacked diagnostics v_error = message_text;
      v_denied := v_error = 'complete non-truncated extraction evidence is required';
    end;
    if not v_denied or exists (
      select 1
      from private.legal_source_fetch_runs run
      where run.correlation_id = '00000000-0000-4000-8000-00000000c306'
    ) then
      raise exception 'partial or incoherent extracted content entered the governed pipeline';
    end if;
  end loop;

  v_denied := false;
  begin
    perform public.ia_fiscal_capture_knowledge_source(
      v_source_id,
      'https://official-a.example.invalid/law/1',
      'https://official-a.example.invalid/law/1',
      v_missing_object_sha,
      'text/plain',
      31,
      'legal-source-artifacts',
      'qa-knowledge-a/' || v_source_id::text || '/' || v_missing_object_sha || '/missing.txt',
      'complete extracted text without object',
      null,
      null,
      200,
      now(),
      '00000000-0000-4000-8000-00000000c307',
      jsonb_build_object(
        'extraction_complete', true,
        'content_truncated', false,
        'extracted_char_count', char_length('complete extracted text without object')
      )
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'uploaded storage object evidence is required';
  end;
  if not v_denied or exists (
    select 1 from private.legal_source_fetch_runs run
    where run.correlation_id = '00000000-0000-4000-8000-00000000c307'
  ) then
    raise exception 'capture registered evidence without an uploaded storage object';
  end if;

  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_raw_sha || '/law-1.txt',
    jsonb_build_object('size', 24, 'mimetype', 'text/plain')
  );

  v_capture := public.ia_fiscal_capture_knowledge_source(
    v_source_id,
    'https://official-a.example.invalid/law/1',
    'https://official-a.example.invalid/law/1',
    v_raw_sha,
    'text/plain; charset=utf-8',
    24,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_raw_sha || '/law-1.txt',
    'Art. 1º. Conteúdo legal oficial para o ensaio de governança.',
    '"qa-etag-v1"',
    'Mon, 17 Aug 2026 12:00:00 GMT',
    200,
    now(),
    '00000000-0000-4000-8000-00000000c301',
    jsonb_build_object(
      'fixture', true,
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(
        'Art. 1º. Conteúdo legal oficial para o ensaio de governança.'
      )
    )
  );

  if v_capture ->> 'status' <> 'captured'
     or v_capture ->> 'processing_status' <> 'under_review'
     or v_capture ->> 'change_set_id' is null
     or v_capture ->> 'candidate_version_id' is null then
    raise exception 'first official capture returned an invalid contract: %', v_capture;
  end if;
  v_change_set_id := (v_capture ->> 'change_set_id')::uuid;
  v_version_id := (v_capture ->> 'candidate_version_id')::uuid;

  if not exists (
    select 1
    from public.legal_source_versions version
    where version.id = v_version_id
      and version.status = 'under_review'
      and version.published_at is null
  ) then
    raise exception 'automated capture did not remain under review';
  end if;
  if exists (
    select 1
    from public.legal_source_versions version
    where version.source_id = v_source_id
      and version.status = 'published'
  ) then
    raise exception 'automated capture published legal content';
  end if;
  if not exists (
    select 1
    from private.legal_chunks chunk
    join public.legal_sections section
      on section.municipality_id = chunk.municipality_id
     and section.id = chunk.legal_section_id
    where section.source_version_id = v_version_id
      and chunk.token_count > 1
  ) then
    raise exception 'lexical token counting collapsed a multi-word section to one token';
  end if;

  v_denied := false;
  begin
    update public.legal_source_versions
    set content_text = 'mutated text with stale hash'
    where id = v_version_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error in (
      'legal source version content hash mismatch',
      'governed legal source version evidence is immutable'
    );
  end;
  if not v_denied then
    raise exception 'legal source text changed without its digest';
  end if;

  v_denied := false;
  begin
    update public.legal_source_versions
    set content_text = 'mutated text and digest',
        content_sha256 = encode(extensions.digest('mutated text and digest', 'sha256'), 'hex')
    where id = v_version_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'governed legal source version evidence is immutable';
  end;
  if not v_denied then
    raise exception 'legal source text and digest changed together';
  end if;

  v_denied := false;
  begin
    delete from public.legal_source_versions where id = v_version_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error in (
      'governed legal source versions cannot be deleted',
      'legal_source_versions cannot be deleted after creation'
    );
  end;
  if not v_denied then
    raise exception 'governed legal source version was deleted';
  end if;

  v_denied := false;
  begin
    delete from public.legal_sections
    where municipality_id = x_municipality_a
      and source_version_id = v_version_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'governed legal sections cannot be deleted';
  end;
  if not v_denied then
    raise exception 'governed legal section was deleted';
  end if;

  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_semantic_raw_sha || '/law-1-repacked.txt',
    jsonb_build_object('size', 25, 'mimetype', 'text/plain')
  );
  v_semantic_capture := public.ia_fiscal_capture_knowledge_source(
    v_source_id,
    'https://official-a.example.invalid/law/1',
    'https://official-a.example.invalid/law/1',
    v_semantic_raw_sha,
    'text/plain',
    25,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_semantic_raw_sha || '/law-1-repacked.txt',
    'Art. 1º. Conteúdo legal oficial para o ensaio de governança.',
    '"qa-etag-v1-repacked"',
    null,
    200,
    now(),
    '00000000-0000-4000-8000-00000000c308',
    jsonb_build_object(
      'fixture', true,
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(
        'Art. 1º. Conteúdo legal oficial para o ensaio de governança.'
      )
    )
  );
  if v_semantic_capture ->> 'status' <> 'already_exists'
     or v_semantic_capture ->> 'change_set_id' is not null
     or v_semantic_capture ->> 'candidate_version_id' is not null
     or (select count(*) from private.legal_source_artifacts where source_id = v_source_id) <> 2
     or (select count(*) from public.legal_source_versions where source_id = v_source_id) <> 1
     or (select count(*) from private.legal_source_change_sets where source_id = v_source_id) <> 1
     or (
       select count(*)
       from private.legal_source_artifact_versions mapping
       where mapping.source_version_id = v_version_id
     ) <> 2 then
    raise exception 'raw repackaging created a false semantic legal change: %',
      v_semantic_capture;
  end if;

  v_replay := public.ia_fiscal_capture_knowledge_source(
    v_source_id,
    'https://official-a.example.invalid/law/1',
    'https://official-a.example.invalid/law/1',
    v_raw_sha,
    'text/plain',
    24,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_raw_sha || '/law-1.txt',
    'Art. 1º. Conteúdo legal oficial para o ensaio de governança.',
    '"qa-etag-v1"',
    'Mon, 17 Aug 2026 12:00:00 GMT',
    200,
    now(),
    '00000000-0000-4000-8000-00000000c301',
    jsonb_build_object(
      'fixture', true,
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(
        'Art. 1º. Conteúdo legal oficial para o ensaio de governança.'
      )
    )
  );
  if v_replay ->> 'candidate_version_id' <> v_version_id::text
     or (select count(*) from public.legal_source_versions where source_id = v_source_id) <> 1 then
    raise exception 'capture replay was not idempotent: %', v_replay;
  end if;

  v_replay := public.ia_fiscal_capture_knowledge_source(
    v_source_id,
    'https://official-a.example.invalid/law/1',
    'https://official-a.example.invalid/law/1',
    v_raw_sha,
    'text/plain',
    24,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_raw_sha || '/law-1.txt',
    'Art. 1º. Conteúdo legal oficial para o ensaio de governança.',
    null,
    null,
    200,
    now(),
    '00000000-0000-4000-8000-00000000c302',
    jsonb_build_object(
      'fixture', true,
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(
        'Art. 1º. Conteúdo legal oficial para o ensaio de governança.'
      )
    )
  );
  if v_replay ->> 'status' <> 'already_exists'
     or v_replay ->> 'change_set_id' <> v_change_set_id::text
     or v_replay ->> 'candidate_version_id' <> v_version_id::text
     or (select count(*) from public.legal_source_versions where source_id = v_source_id) <> 1
     or (select count(*) from private.legal_source_change_sets where source_id = v_source_id) <> 1 then
    raise exception 'same-hash collection created duplicate governed content';
  end if;

  perform public.ia_fiscal_stage_knowledge_sections(
    v_change_set_id,
    jsonb_build_array(jsonb_build_object(
      'section_key', 'documento_integral',
      'heading', 'Documento oficial capturado',
      'ordinal', 1,
      'content_text', 'Art. 1º. Conteúdo legal oficial para o ensaio de governança.'
    ))
  );

  v_denied := false;
  begin
    update public.legal_source_versions
    set status = 'published',
        approved_by = u_legal_a,
        approved_at = now(),
        published_at = now()
    where id = v_version_id;
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'service automation directly published a legal version';
  end if;

  perform set_config('request.jwt.claim.sub', u_legal_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_a, 'role', 'authenticated', 'aal', 'aal1')::text,
    true
  );
  v_denied := false;
  begin
    perform public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'AAL1 legal reviewer read the governed operations snapshot';
  end if;

  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_change_set_id,
      'approved',
      'QA approval',
      'REVISAR',
      v_business_date - 1,
      null,
      v_business_date
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'AAL1 legal reviewer approved a source version';
  end if;

  perform set_config('request.jwt.claim.sub', u_supervisor_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_supervisor_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_change_set_id,
      'approved',
      'QA approval',
      'REVISAR',
      v_business_date - 1,
      null,
      v_business_date
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'supervisor without legal role approved a source version';
  end if;

  perform set_config('request.jwt.claim.sub', u_legal_b::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_b, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_change_set_id,
      'approved',
      'Cross-tenant QA approval',
      'REVISAR',
      v_business_date - 1,
      null,
      v_business_date
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'cross-tenant legal reviewer approved a source version';
  end if;

  perform set_config('request.jwt.claim.sub', u_legal_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_snapshot := public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  if not exists (
    select 1
    from jsonb_array_elements(v_snapshot -> 'changes') item
    where item ->> 'change_set_id' = v_change_set_id::text
      and item -> 'blockers' ? 'source_review_required'
  ) then
    raise exception 'pending source change did not expose source_review_required';
  end if;
  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_change_set_id,
      'approved',
      'QA approval',
      'CONFIRMAR',
      v_business_date - 1,
      null,
      v_business_date
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'legal review accepted a wrong explicit-confirmation phrase';
  end if;

  insert into private.legal_source_fetch_runs (
    municipality_id, source_id, endpoint_id, correlation_id, status,
    requested_url, final_url, http_status, observed_content_sha256, observed_at
  ) values (
    x_municipality_a, v_source_id, v_endpoint_id,
    '00000000-0000-4000-8000-00000000c305', 'completed_changed',
    'https://official-a.example.invalid/law/1',
    'https://official-a.example.invalid/law/1', 200,
    v_unstaged_raw_sha, now()
  ) returning id into v_unstaged_fetch_id;
  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_unstaged_raw_sha || '/unstaged.txt',
    jsonb_build_object('size', 30, 'mimetype', 'text/plain')
  );
  insert into private.legal_source_artifacts (
    municipality_id, source_id, endpoint_id, fetch_run_id, storage_bucket,
    storage_path, content_sha256, byte_size, mime_type,
    extracted_text_sha256, extraction_status, observed_at, metadata
  ) values (
    x_municipality_a, v_source_id, v_endpoint_id, v_unstaged_fetch_id,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_source_id::text || '/' || v_unstaged_raw_sha || '/unstaged.txt',
    v_unstaged_raw_sha, 30, 'text/plain', v_unstaged_text_sha,
    'completed', now(), jsonb_build_object(
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length('unstaged extracted legal text')
    )
  ) returning id into v_unstaged_artifact_id;
  insert into public.legal_source_versions (
    municipality_id, source_id, version, status, content_text, content_sha256,
    supersedes_version_id
  ) values (
    x_municipality_a, v_source_id, 2, 'under_review',
    'unstaged extracted legal text', v_unstaged_text_sha, v_version_id
  ) returning id into v_unstaged_version_id;
  insert into private.legal_source_artifact_versions (
    municipality_id, artifact_id, source_version_id
  ) values (
    x_municipality_a, v_unstaged_artifact_id, v_unstaged_version_id
  );
  insert into private.legal_source_change_sets (
    municipality_id, source_id, from_artifact_id, to_artifact_id,
    candidate_version_id, change_type, status, from_sha256, to_sha256,
    diff_sha256, diff_summary
  ) select
    x_municipality_a, v_source_id, previous_artifact.id,
    v_unstaged_artifact_id, v_unstaged_version_id, 'content_changed',
    'detected', v_raw_sha, v_unstaged_raw_sha,
    encode(extensions.digest(v_raw_sha || ':' || v_unstaged_raw_sha, 'sha256'), 'hex'),
    'Mudança sintética ainda sem segmentação para o ensaio negativo.'
  from private.legal_source_artifacts previous_artifact
  where previous_artifact.municipality_id = x_municipality_a
    and previous_artifact.source_id = v_source_id
    and previous_artifact.content_sha256 = v_raw_sha
  returning id into v_unstaged_change_id;

  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_unstaged_change_id,
      'approved',
      'QA approval without staged evidence',
      'REVISAR',
      v_business_date - 1,
      null,
      v_business_date
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'reviewed sections and chunks are required before approval';
  end;
  if not v_denied then
    raise exception 'legal review approved a source version without staged sections/chunks';
  end if;

  insert into public.legal_sources (
    municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values (
    x_municipality_a, 'law', 'municipal', 'Município QA A',
    'Fonte legada sem artefato', 'Lei QA legada',
    'https://official-a.example.invalid/law/legacy',
    'Tributos municipais', 'fiscal_knowledge', 'draft'
  ) returning id into v_legacy_source_id;

  insert into public.legal_source_versions (
    municipality_id, source_id, version, status, content_text, content_sha256
  ) values (
    x_municipality_a, v_legacy_source_id, 1, 'under_review',
    'legacy content without captured artifact', v_legacy_sha
  ) returning id into v_legacy_version_id;

  insert into public.legal_sections (
    municipality_id, source_version_id, section_key, heading, ordinal,
    content_text, content_sha256
  ) values (
    x_municipality_a, v_legacy_version_id, 'documento_integral',
    'Documento legado', 1, 'legacy content without captured artifact', v_legacy_sha
  ) returning id into v_legacy_section_id;

  insert into private.legal_chunks (
    municipality_id, legal_section_id, chunk_index, content_text, token_count,
    content_sha256
  ) values (
    x_municipality_a, v_legacy_section_id, 0,
    'legacy content without captured artifact', 5, v_legacy_sha
  );

  insert into private.legal_source_change_sets (
    municipality_id, source_id, candidate_version_id, change_type, status,
    to_sha256, diff_sha256, diff_summary
  ) values (
    x_municipality_a, v_legacy_source_id, v_legacy_version_id,
    'legacy_import', 'detected', v_legacy_sha,
    encode(extensions.digest('legacy diff', 'sha256'), 'hex'),
    'Importação histórica sem prova de captura.'
  ) returning id into v_legacy_change_id;

  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_legacy_change_id,
      'approved',
      'Tentativa sem prova do artefato oficial.',
      'REVISAR',
      v_business_date - 1,
      null,
      v_business_date
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legacy source version must be recaptured from an official endpoint before review';
  end;
  if not v_denied then
    raise exception 'legal review approved a source without captured artifact evidence';
  end if;

  v_snapshot := public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  if not exists (
    select 1
    from jsonb_array_elements(v_snapshot -> 'changes') item
    where item ->> 'change_set_id' = v_legacy_change_id::text
      and item -> 'blockers' ? 'legacy_recapture_required'
      and item ->> 'can_review' = 'false'
      and item ->> 'can_publish' = 'false'
  ) or exists (
    select 1
    from jsonb_array_elements(v_snapshot -> 'reviews') item
    where item ->> 'change_set_id' = v_legacy_change_id::text
  ) then
    raise exception 'legacy evidence entered a review queue that cannot approve it';
  end if;

  insert into private.legal_source_endpoints (
    municipality_id, source_id, endpoint_kind, trust_tier,
    content_mode, citable_body, url, allowed_hosts,
    expected_content_types, parser_hint, status
  ) values (
    x_municipality_a, v_legacy_source_id, 'document_file', 'primary_publication',
    'legal_body', true, 'https://official-a.example.invalid/law/legacy',
    array['official-a.example.invalid'], array['text/plain'], 'qa_text', 'active'
  ) returning id into v_legacy_endpoint_id;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
    true
  );
  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_legacy_source_id::text || '/' || v_legacy_raw_sha || '/legacy.txt',
    jsonb_build_object('size', 36, 'mimetype', 'text/plain')
  );
  v_legacy_capture := public.ia_fiscal_capture_knowledge_source(
    v_legacy_source_id,
    'https://official-a.example.invalid/law/legacy',
    'https://official-a.example.invalid/law/legacy',
    v_legacy_raw_sha,
    'text/plain',
    36,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_legacy_source_id::text || '/' || v_legacy_raw_sha || '/legacy.txt',
    'legacy content without captured artifact',
    null,
    null,
    200,
    now(),
    '00000000-0000-4000-8000-00000000c309',
    jsonb_build_object(
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length('legacy content without captured artifact')
    )
  );
  if v_legacy_capture ->> 'candidate_version_id' is null
     or (v_legacy_capture ->> 'candidate_version_id')::uuid = v_legacy_version_id
     or not exists (
       select 1
       from private.legal_source_change_sets change_set
       where change_set.id = v_legacy_change_id
         and change_set.status = 'superseded'
     ) then
    raise exception 'official recapture did not replace the non-artifact-backed legacy candidate';
  end if;

  insert into public.legal_sources (
    municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values (
    x_municipality_a, 'official_guidance', 'municipal', 'Município QA A',
    'Catálogo QA sem corpo legal', 'Catálogo QA',
    'https://official-a.example.invalid/catalog',
    'Tributos municipais', 'official_operations', 'draft'
  ) returning id into v_pending_source_id;
  insert into private.legal_source_endpoints (
    municipality_id, source_id, endpoint_kind, trust_tier,
    content_mode, citable_body, url, allowed_hosts,
    expected_content_types, parser_hint, status, metadata
  ) values (
    x_municipality_a, v_pending_source_id, 'catalog', 'official_consolidation',
    'catalog_only', false, 'https://official-a.example.invalid/catalog',
    array['official-a.example.invalid'], array['text/html'], 'catalog_only',
    'active', jsonb_build_object('activation_blocker', 'legal_body_parser_required')
  ) returning id into v_pending_endpoint_id;

  v_denied := false;
  begin
    perform public.ia_fiscal_capture_knowledge_source(
      v_pending_source_id,
      'https://official-a.example.invalid/catalog',
      'https://official-a.example.invalid/catalog',
      v_pending_raw_sha,
      'text/html',
      32,
      'legal-source-artifacts',
      'qa-knowledge-a/' || v_pending_source_id::text || '/' || v_pending_raw_sha || '/catalog.html',
      'texto de ficha que não é corpo legal',
      null, null, 200, now(),
      '00000000-0000-4000-8000-00000000c310',
      jsonb_build_object(
        'extraction_complete', true,
        'content_truncated', false,
        'extracted_char_count', char_length('texto de ficha que não é corpo legal')
      )
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'catalog-only endpoint cannot submit citable legal text';
  end;
  if not v_denied then
    raise exception 'catalog-only endpoint accepted page furniture as citable law';
  end if;

  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_pending_source_id::text || '/' || v_pending_raw_sha || '/catalog.html',
    jsonb_build_object('size', 32, 'mimetype', 'text/html')
  );
  v_pending_capture := public.ia_fiscal_capture_knowledge_source(
    v_pending_source_id,
    'https://official-a.example.invalid/catalog',
    'https://official-a.example.invalid/catalog',
    v_pending_raw_sha,
    'text/html',
    32,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_pending_source_id::text || '/' || v_pending_raw_sha || '/catalog.html',
    null, null, null, 200, now(),
    '00000000-0000-4000-8000-00000000c311',
    jsonb_build_object(
      'extraction_complete', false,
      'content_truncated', false,
      'extracted_char_count', 0
    )
  );
  v_pending_replay := public.ia_fiscal_capture_knowledge_source(
    v_pending_source_id,
    'https://official-a.example.invalid/catalog',
    'https://official-a.example.invalid/catalog',
    v_pending_raw_sha,
    'text/html',
    32,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_pending_source_id::text || '/' || v_pending_raw_sha || '/catalog.html',
    null, null, null, 200, now(),
    '00000000-0000-4000-8000-00000000c312',
    jsonb_build_object(
      'extraction_complete', false,
      'content_truncated', false,
      'extracted_char_count', 0
    )
  );
  if v_pending_capture ->> 'processing_status' <> 'requires_extraction'
     or v_pending_capture ->> 'change_set_id' is null
     or v_pending_capture ->> 'candidate_version_id' is not null
     or v_pending_replay ->> 'status' <> 'already_exists'
     or v_pending_replay ->> 'change_set_id' <> v_pending_capture ->> 'change_set_id'
     or exists (
       select 1 from public.legal_source_versions version
       where version.source_id = v_pending_source_id
     ) then
    raise exception 'catalog-only capture did not remain a non-citable extraction item';
  end if;

  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_pending_source_id::text || '/' || v_pending_raw_sha_2 || '/catalog-v2.html',
    jsonb_build_object('size', 33, 'mimetype', 'text/html')
  );
  v_pending_replay := public.ia_fiscal_capture_knowledge_source(
    v_pending_source_id,
    'https://official-a.example.invalid/catalog',
    'https://official-a.example.invalid/catalog',
    v_pending_raw_sha_2,
    'text/html',
    33,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_pending_source_id::text || '/' || v_pending_raw_sha_2 || '/catalog-v2.html',
    null, null, null, 200, now(),
    '00000000-0000-4000-8000-00000000c313',
    jsonb_build_object(
      'extraction_complete', false,
      'content_truncated', false,
      'extracted_char_count', 0
    )
  );
  if v_pending_replay ->> 'processing_status' <> 'requires_extraction'
     or v_pending_replay ->> 'candidate_version_id' is not null
     or (
       select count(*) from private.legal_source_change_sets change_set
       where change_set.source_id = v_pending_source_id
         and change_set.status in ('detected', 'changes_requested')
     ) <> 1
     or not exists (
       select 1 from private.legal_source_change_sets change_set
       where change_set.id = (v_pending_capture ->> 'change_set_id')::uuid
         and change_set.status = 'superseded'
     ) then
    raise exception 'new catalog hash did not supersede the prior raw-only change';
  end if;

  perform set_config('request.jwt.claim.sub', u_legal_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_snapshot := public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  if not exists (
    select 1 from jsonb_array_elements(v_snapshot -> 'sources') item
    where item ->> 'source_id' = v_pending_source_id::text
      and item -> 'blockers' ? 'legal_body_extraction_required'
  ) or exists (
    select 1 from jsonb_array_elements(v_snapshot -> 'reviews') item
    where item ->> 'source_id' = v_pending_source_id::text
  ) then
    raise exception 'catalog-only extraction state was presented as reviewable legal content';
  end if;

  v_review_id := public.ia_review_legal_source_change(
    v_change_set_id,
    'approved',
    'Fonte e vigência conferidas no ensaio transacional.',
    'REVISAR',
    v_business_date,
    v_business_date,
    v_business_date
  );
  if v_review_id is null or not exists (
    select 1
    from public.legal_source_versions version
    where version.id = v_version_id
      and version.status = 'approved'
      and version.published_at is null
  ) then
    raise exception 'human legal review did not stop at approved state';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
    true
  );
  v_denied := false;
  begin
    update public.legal_source_versions
    set status = 'published', published_at = now()
    where id = v_version_id;
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'service role published an approved legal source directly';
  end if;

  perform set_config('request.jwt.claim.sub', u_legal_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_denied := false;
  begin
    perform public.ia_publish_legal_source_version(v_version_id, 'CONFIRMAR');
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'legal publication accepted a wrong confirmation phrase';
  end if;

  perform public.ia_publish_legal_source_version(v_version_id, 'PUBLICAR');
  if not exists (
    select 1
    from public.legal_source_versions version
    where version.id = v_version_id
      and version.status = 'published'
      and version.published_at is not null
  ) then
    raise exception 'explicit human publication did not publish the approved version';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
    true
  );
  v_denied := false;
  begin
    perform public.ia_fiscal_stage_knowledge_sections(
      v_unstaged_change_id,
      jsonb_build_array(jsonb_build_object(
        'section_key', 'fabricada',
        'heading', 'Texto não capturado',
        'ordinal', 1,
        'content_text', 'conteúdo fabricado fora do documento oficial'
      ))
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legal section content must be derived from the candidate version';
  end;
  if not v_denied then
    raise exception 'staging accepted a section outside the captured candidate';
  end if;

  v_denied := false;
  begin
    perform public.ia_fiscal_stage_knowledge_sections(
      v_unstaged_change_id,
      jsonb_build_array(jsonb_build_object(
        'section_key', 'documento_integral',
        'heading', 'Documento oficial capturado',
        'ordinal', 1,
        'content_text', 'unstaged extracted legal text',
        'chunks', jsonb_build_array(jsonb_build_object(
          'content_text', 'chunk fabricado fora da seção',
          'token_count', 5
        ))
      ))
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legal chunk content must be derived from its section';
  end;
  if not v_denied then
    raise exception 'staging accepted a chunk outside its captured section';
  end if;

  v_denied := false;
  begin
    perform public.ia_fiscal_stage_knowledge_sections(
      v_unstaged_change_id,
      jsonb_build_array(jsonb_build_object(
        'section_key', 'trecho_parcial',
        'heading', 'Trecho parcial',
        'ordinal', 1,
        'content_text', 'unstaged extracted'
      ))
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'an integral candidate-derived section and chunks are required';
  end;
  if not v_denied or exists (
    select 1 from public.legal_sections section
    where section.source_version_id = v_unstaged_version_id
  ) then
    raise exception 'partial-only corpus became complete legal evidence';
  end if;

  perform public.ia_fiscal_stage_knowledge_sections(
    v_unstaged_change_id,
    jsonb_build_array(jsonb_build_object(
      'section_key', 'documento_integral',
      'heading', 'Documento oficial capturado',
      'ordinal', 1,
      'content_text', 'unstaged extracted legal text'
    ))
  );

  perform set_config('request.jwt.claim.sub', u_legal_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_snapshot := public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  if coalesce((v_snapshot #>> '{health,pending_review_sources}')::integer, 0) < 1
     or v_snapshot #>> '{health,status}' = 'healthy' then
    raise exception 'staged official change awaiting review was reported as healthy';
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(v_snapshot -> 'sources') item
    where item ->> 'source_id' = v_source_id::text
      and item ->> 'can_review' = 'true'
      and item -> 'blockers' ? 'source_review_required'
  ) then
    raise exception 'source card hid an actionable change behind a same-timestamp change';
  end if;
  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_unstaged_change_id, 'approved', 'Metadados ausentes.', 'REVISAR',
      null, null, null
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'publication date and start of validity are required';
  end;
  if not v_denied then
    raise exception 'legal review approved a source without validity metadata';
  end if;

  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_unstaged_change_id, 'approved', 'Vigência ainda futura.', 'REVISAR',
      v_business_date + 30, null, v_business_date
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legal source version is not currently effective';
  end;
  if not v_denied then
    raise exception 'legal review approved a not-yet-effective source version';
  end if;

  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_unstaged_change_id, 'approved', 'Vigência já encerrada.', 'REVISAR',
      v_business_date - 30, v_business_date - 1, v_business_date - 30
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legal source version is not currently effective';
  end;
  if not v_denied then
    raise exception 'legal review approved an expired source version';
  end if;

  insert into private.legal_source_version_reviews (
    municipality_id, change_set_id, source_version_id,
    reviewer_membership_id, decision, reviewed_content_sha256,
    reviewed_valid_from, reviewed_valid_until, reviewed_publication_date,
    notes
  ) values (
    x_municipality_a, v_unstaged_change_id, v_unstaged_version_id,
    m_legal_a, 'approved', v_unstaged_text_sha,
    v_business_date + 30, null, v_business_date,
    'Fixture inconsistente para provar a barreira temporal da publicação.'
  );
  update public.legal_source_versions
  set status = 'approved',
      valid_from = v_business_date + 30,
      valid_until = null,
      publication_date = v_business_date,
      approved_by = u_legal_a,
      approved_at = now()
  where id = v_unstaged_version_id;
  update private.legal_source_change_sets
  set status = 'accepted',
      reviewer_membership_id = m_legal_a,
      reviewed_at = now(),
      review_notes = 'Fixture temporal aguardando data de vigência.'
  where id = v_unstaged_change_id;

  v_snapshot := public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  if not exists (
    select 1 from jsonb_array_elements(v_snapshot -> 'changes') item
    where item ->> 'change_set_id' = v_unstaged_change_id::text
      and item -> 'blockers' ? 'source_not_current'
      and item ->> 'can_publish' = 'false'
  ) then
    raise exception 'snapshot enabled publication outside the reviewed validity window';
  end if;
  if coalesce((v_snapshot #>> '{health,pending_publish_sources}')::integer, 0) < 1
     or not exists (
       select 1
       from jsonb_array_elements(v_snapshot -> 'sources') item
       where item ->> 'source_id' = v_source_id::text
         and item -> 'blockers' ? 'source_publication_required'
     ) then
    raise exception 'accepted source change was not reported as pending publication';
  end if;
  v_source_evidence := public.ia_get_legal_source_change_evidence(
    x_municipality_a, v_unstaged_change_id, 0, 20000, 0, 25
  );
  if not (v_source_evidence -> 'blockers' ? 'source_not_current')
     or v_source_evidence ->> 'can_publish' <> 'false' then
    raise exception 'source evidence enabled publication outside municipal validity: %',
      v_source_evidence;
  end if;
  v_denied := false;
  begin
    perform public.ia_publish_legal_source_version(v_unstaged_version_id, 'PUBLICAR');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legal source version is not currently effective';
  end;
  if not v_denied or not exists (
    select 1 from public.legal_source_versions version
    where version.id = v_version_id and version.status = 'published'
  ) then
    raise exception 'failed temporal cutover retired the current legal source version';
  end if;

  select section.id into strict v_section_id
  from public.legal_sections section
  where section.municipality_id = x_municipality_a
    and section.source_version_id = v_version_id
    and section.section_key = 'documento_integral';

  insert into public.knowledge_articles (
    id, municipality_id, intent_key, canonical_question, tax_scope,
    divergence_scope, status, current_revision_number, is_test,
    approval_basis, valid_from, created_by
  ) values (
    x_article_current, x_municipality_a, 'qa:official-current',
    'Qual é a orientação fiscal oficial vigente?', 'Tributos municipais',
    'fiscal_knowledge', 'under_review', 1, false, 'fiscal_review',
    now() - interval '1 day', u_legal_a
  );
  insert into public.knowledge_article_revisions (
    id, municipality_id, article_id, revision_number, answer_body,
    allowed_placeholders, source_type, content_sha256, created_by
  ) values (
    x_revision_current, x_municipality_a, x_article_current, 1,
    'Resposta fiscal vigente com prova oficial.', '[]'::jsonb,
    'legal_seed', v_article_hash, u_legal_a
  );
  insert into public.knowledge_article_citations (
    municipality_id, revision_id, legal_section_id, source_version_id,
    citation_label, quoted_excerpt, source_sha256
  ) select
    x_municipality_a, x_revision_current, v_section_id, v_version_id,
    'Art. 1º', 'Conteúdo legal oficial', version.content_sha256
  from public.legal_source_versions version
  where version.id = v_version_id;

  v_article_evidence := public.ia_get_knowledge_article_evidence(
    x_municipality_a, x_article_current, x_revision_current
  );
  if v_article_evidence ->> 'answer_body' <> 'Resposta fiscal vigente com prova oficial.'
     or v_article_evidence ->> 'content_sha256' <> v_article_hash
     or v_article_evidence ->> 'evidence_complete' <> 'true'
     or jsonb_array_length(v_article_evidence -> 'citations') <> 1
     or v_article_evidence #>> '{citations,0,official_url}'
          <> 'https://official-a.example.invalid/law/1'
     or v_article_evidence #>> '{citations,0,is_valid}' <> 'true' then
    raise exception 'article evidence omitted the bounded answer or verifiable citation: %',
      v_article_evidence;
  end if;

  v_denied := false;
  begin
    perform public.ia_review_knowledge_article(
      x_article_current, x_revision_current, 'approved',
      'Conteúdo e citação revisados.', 'CONFIRMAR'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'knowledge review accepted a wrong confirmation phrase';
  end if;

  v_article_review_id := public.ia_review_knowledge_article(
    x_article_current, x_revision_current, 'approved',
    'Conteúdo e citação revisados.', 'REVISAR'
  );
  if v_article_review_id is null or not exists (
    select 1 from public.knowledge_articles article
    where article.id = x_article_current and article.status = 'approved'
  ) then
    raise exception 'knowledge article did not stop at approved state';
  end if;
  perform public.ia_publish_knowledge_article(x_article_current, 'PUBLICAR');
  if not exists (
    select 1 from public.knowledge_articles article
    where article.id = x_article_current
      and article.status = 'published'
      and article.published_at is not null
  ) then
    raise exception 'reviewed knowledge article was not explicitly published';
  end if;

  insert into public.knowledge_articles (
    id, municipality_id, intent_key, canonical_question, tax_scope,
    divergence_scope, status, current_revision_number, is_test,
    approval_basis, semantic_version, valid_from, created_by
  ) values (
    x_article_cutover, x_municipality_a, 'qa:official-current',
    'A resposta futura pode substituir a vigente agora?', 'Tributos municipais',
    'fiscal_knowledge', 'under_review', 1, false, 'fiscal_review',
    2, now() + interval '30 days', u_legal_a
  );
  insert into public.knowledge_article_revisions (
    id, municipality_id, article_id, revision_number, answer_body,
    allowed_placeholders, source_type, content_sha256, created_by
  ) values (
    x_revision_cutover, x_municipality_a, x_article_cutover, 1,
    'Resposta candidata para corte temporal.', '[]'::jsonb,
    'legal_seed', v_cutover_article_hash, u_legal_a
  );
  insert into public.knowledge_article_citations (
    municipality_id, revision_id, legal_section_id, source_version_id,
    citation_label, quoted_excerpt, source_sha256
  ) select
    x_municipality_a, x_revision_cutover, v_section_id, v_version_id,
    'Art. 1º', 'Conteúdo legal oficial', version.content_sha256
  from public.legal_source_versions version
  where version.id = v_version_id;
  perform public.ia_review_knowledge_article(
    x_article_cutover, x_revision_cutover, 'approved',
    'Citação válida, mas início de vigência futuro.', 'REVISAR'
  );

  v_denied := false;
  begin
    perform public.ia_publish_knowledge_article(x_article_cutover, 'PUBLICAR');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'knowledge article is not currently effective';
  end;
  if not v_denied or not exists (
    select 1 from public.knowledge_articles article
    where article.id = x_article_current and article.status = 'published'
  ) then
    raise exception 'future article cutover retired the currently published answer';
  end if;

  update public.knowledge_articles
  set valid_from = now() - interval '30 days',
      valid_until = now() - interval '1 day'
  where id = x_article_cutover;
  v_denied := false;
  begin
    perform public.ia_publish_knowledge_article(x_article_cutover, 'PUBLICAR');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'knowledge article is not currently effective';
  end;
  if not v_denied or not exists (
    select 1 from public.knowledge_articles article
    where article.id = x_article_current and article.status = 'published'
  ) then
    raise exception 'expired article cutover retired the currently published answer';
  end if;

  update public.legal_sources set status = 'retired' where id = v_source_id;
  update public.knowledge_articles
  set valid_from = now() - interval '1 day', valid_until = null
  where id = x_article_cutover;
  v_denied := false;
  begin
    perform public.ia_publish_knowledge_article(x_article_cutover, 'PUBLICAR');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'one or more cited legal sources are not current, verifiable and published';
  end;
  if not v_denied or exists (
    select 1 from public.vw_reusable_knowledge_articles article
    where article.article_id = x_article_current
  ) then
    raise exception 'retired legal source remained reusable or publishable';
  end if;
  update public.legal_sources set status = 'active' where id = v_source_id;
  if not exists (
    select 1 from public.vw_reusable_knowledge_articles article
    where article.article_id = x_article_current
  ) then
    raise exception 'reactivated current source did not restore reusable knowledge';
  end if;

  insert into public.legal_sources (
    municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values (
    x_municipality_a, 'law', 'municipal', 'Município QA A',
    'Norma QA com publicação futura', 'Lei QA nº 2/2026',
    'https://official-a.example.invalid/law/2',
    'Tributos municipais', 'fiscal_knowledge', 'draft'
  ) returning id into v_future_source_id;
  insert into private.legal_source_endpoints (
    municipality_id, source_id, endpoint_kind, trust_tier,
    content_mode, citable_body, url,
    allowed_hosts, expected_content_types, parser_hint, status
  ) values (
    x_municipality_a, v_future_source_id, 'document_file',
    'primary_publication', 'legal_body', true,
    'https://official-a.example.invalid/law/2',
    array['official-a.example.invalid'], array['text/plain'], 'qa_text', 'active'
  ) returning id into v_future_endpoint_id;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
    true
  );
  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_future_source_id::text || '/' || v_future_raw_sha || '/law-2.txt',
    jsonb_build_object('size', 28, 'mimetype', 'text/plain')
  );
  v_future_capture := public.ia_fiscal_capture_knowledge_source(
    v_future_source_id,
    'https://official-a.example.invalid/law/2',
    'https://official-a.example.invalid/law/2',
    v_future_raw_sha,
    'text/plain',
    28,
    'legal-source-artifacts',
    'qa-knowledge-a/' || v_future_source_id::text || '/' || v_future_raw_sha || '/law-2.txt',
    'Art. 2º. Conteúdo oficial com vigência futura.',
    '"qa-etag-v2"',
    'Mon, 17 Aug 2026 13:00:00 GMT',
    200,
    now(),
    '00000000-0000-4000-8000-00000000c304',
    jsonb_build_object(
      'fixture', true,
      'extraction_complete', true,
      'content_truncated', false,
      'extracted_char_count', char_length(
        'Art. 2º. Conteúdo oficial com vigência futura.'
      )
    )
  );
  v_future_change_id := (v_future_capture ->> 'change_set_id')::uuid;
  v_future_version_id := (v_future_capture ->> 'candidate_version_id')::uuid;
  if v_future_change_id is null or v_future_version_id is null then
    raise exception 'future source capture did not create governed review evidence';
  end if;

  perform set_config('request.jwt.claim.sub', u_legal_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_denied := false;
  begin
    perform public.ia_review_legal_source_change(
      v_future_change_id,
      'approved',
      'Tentativa de aprovar publicação futura.',
      'REVISAR',
      v_business_date - 1,
      null,
      v_business_date + 30
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'publication date cannot be in the future';
  end;
  if not v_denied then
    raise exception 'legal source review accepted a future publication date';
  end if;

  insert into private.legal_source_version_reviews (
    municipality_id, change_set_id, source_version_id,
    reviewer_membership_id, decision, reviewed_content_sha256,
    reviewed_valid_from, reviewed_valid_until, reviewed_publication_date,
    notes
  ) select
    x_municipality_a, v_future_change_id, v_future_version_id,
    m_legal_a, 'approved', version.content_sha256,
    v_business_date - 1, null, v_business_date + 30,
    'Fixture legada inconsistente para testar defesa em profundidade.'
  from public.legal_source_versions version
  where version.id = v_future_version_id;
  update public.legal_source_versions
  set status = 'approved',
      valid_from = v_business_date - 1,
      publication_date = v_business_date + 30,
      approved_by = u_legal_a,
      approved_at = now()
  where id = v_future_version_id;

  v_denied := false;
  begin
    perform public.ia_publish_legal_source_version(v_future_version_id, 'PUBLICAR');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'publication date cannot be in the future';
  end;
  if not v_denied then
    raise exception 'legal source publication accepted a future publication date';
  end if;

  update public.legal_source_versions
  set status = 'published', published_at = now()
  where id = v_future_version_id;
  update public.legal_sources
  set status = 'active'
  where id = v_future_source_id;

  select section.id into strict v_future_section_id
  from public.legal_sections section
  where section.municipality_id = x_municipality_a
    and section.source_version_id = v_future_version_id
    and section.section_key = 'documento_integral';
  insert into public.knowledge_articles (
    id, municipality_id, intent_key, canonical_question, tax_scope,
    divergence_scope, status, current_revision_number, is_test,
    approval_basis, created_by
  ) values (
    x_article_future, x_municipality_a, 'qa:future-source',
    'Uma norma futura já pode fundamentar resposta?', 'Tributos municipais',
    'fiscal_knowledge', 'under_review', 1, false, 'fiscal_review', u_legal_a
  );
  insert into public.knowledge_article_revisions (
    id, municipality_id, article_id, revision_number, answer_body,
    allowed_placeholders, source_type, content_sha256, created_by
  ) values (
    x_revision_future, x_municipality_a, x_article_future, 1,
    'Resposta baseada em norma ainda futura.', '[]'::jsonb,
    'legal_seed', v_future_article_hash, u_legal_a
  );
  insert into public.knowledge_article_citations (
    municipality_id, revision_id, legal_section_id, source_version_id,
    citation_label, quoted_excerpt, source_sha256
  ) select
    x_municipality_a, x_revision_future, v_future_section_id,
    v_future_version_id, 'Art. 2º', 'Conteúdo oficial com vigência futura',
    version.content_sha256
  from public.legal_source_versions version
  where version.id = v_future_version_id;

  v_article_evidence := public.ia_get_knowledge_article_evidence(
    x_municipality_a, x_article_future, x_revision_future
  );
  if v_article_evidence ->> 'evidence_complete' <> 'false'
     or v_article_evidence #>> '{citations,0,is_valid}' <> 'false'
     or not (v_article_evidence #> '{citations,0,blockers}' ? 'source_not_published') then
    raise exception 'future publication date was considered valid evidence: %',
      v_article_evidence;
  end if;

  v_denied := false;
  begin
    perform public.ia_review_knowledge_article(
      x_article_future, x_revision_future, 'approved',
      'Tentativa com publicação futura.', 'REVISAR'
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'one or more cited legal sources are not current, verifiable and published';
  end;
  if not v_denied then
    raise exception 'knowledge review accepted a future publication date';
  end if;
  insert into public.knowledge_article_reviews (
    municipality_id, article_id, revision_id, decision,
    reviewer_membership_id, notes, approved_content_sha256
  ) values (
    x_municipality_a, x_article_future, x_revision_future, 'approved',
    m_legal_a, 'Fixture para testar a barreira da publicação.',
    v_future_article_hash
  );
  update public.knowledge_articles
  set status = 'approved'
  where id = x_article_future;

  v_denied := false;
  begin
    perform public.ia_publish_knowledge_article(x_article_future, 'PUBLICAR');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'one or more cited legal sources are not current, verifiable and published';
  end;
  if not v_denied then
    raise exception 'knowledge publication accepted a future publication date';
  end if;
  update public.knowledge_articles
  set status = 'published', published_at = now()
  where id = x_article_future;
  if exists (
    select 1
    from public.vw_reusable_knowledge_articles article
    where article.article_id = x_article_future
  ) then
    raise exception 'reusable knowledge view exposed a future publication date';
  end if;

  insert into public.knowledge_articles (
    id, municipality_id, intent_key, canonical_question, tax_scope,
    divergence_scope, status, current_revision_number, is_test,
    approval_basis, created_by
  ) values (
    x_article_admin_denied, x_municipality_a, 'qa:admin-read-only',
    'O administrador municipal pode revisar?', 'Tributos municipais',
    'fiscal_knowledge', 'under_review', 1, false, 'fiscal_review', u_admin_a
  );
  insert into public.knowledge_article_revisions (
    id, municipality_id, article_id, revision_number, answer_body,
    allowed_placeholders, source_type, content_sha256, created_by
  ) values (
    x_revision_admin_denied, x_municipality_a, x_article_admin_denied, 1,
    'Resposta ainda não aprovada.', '[]'::jsonb, 'legal_seed',
    encode(extensions.digest('Resposta ainda não aprovada.', 'sha256'), 'hex'),
    u_admin_a
  );

  v_snapshot := public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  v_source_evidence := public.ia_get_legal_source_change_evidence(
    x_municipality_a, v_change_set_id, 0, 20000, 0, 25
  );
  if v_source_evidence ->> 'captured_url'
       <> 'https://official-a.example.invalid/law/1'
     or v_source_evidence ->> 'raw_content_sha256' <> v_raw_sha
     or v_source_evidence ->> 'content_sha256' is null
     or v_source_evidence ->> 'diff_sha256' is null
     or v_source_evidence ->> 'observed_at' is null
     or v_source_evidence ->> 'evidence_complete' <> 'true'
     or jsonb_array_length(v_source_evidence -> 'sections') <> 1
     or v_source_evidence ->> 'section_has_more' <> 'false' then
    raise exception 'source evidence omitted the captured artifact proof: %',
      v_source_evidence;
  end if;
  if coalesce((v_snapshot ->> 'verified')::boolean, false) is not true
     or v_snapshot #>> '{municipality,id}' <> x_municipality_a::text
     or v_snapshot #>> '{capabilities,can_publish_source_versions}' <> 'true' then
    raise exception 'AAL2 tenant snapshot returned an invalid contract: %', v_snapshot;
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(v_snapshot -> 'reviews') item
    where item ->> 'queue_kind' = 'source_version'
      and item ->> 'change_set_id' = (v_legacy_capture ->> 'change_set_id')
      and item ->> 'official_url' = 'https://official-a.example.invalid/law/legacy'
      and item ->> 'candidate_content_preview' like 'legacy content%'
      and (item ->> 'section_count')::integer = 1
  ) then
    raise exception 'source review queue omitted safe official evidence fields';
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(v_snapshot -> 'changes') item
    where item ->> 'change_set_id' = v_change_set_id::text
      and item ->> 'official_url' = 'https://official-a.example.invalid/law/1'
      and item ->> 'candidate_content_preview' like 'Art. 1º.%'
      and (item ->> 'section_count')::integer = 1
  ) then
    raise exception 'change snapshot omitted safe official evidence fields';
  end if;
  if exists (
    with blocker_values(value) as (
      select blocker
      from jsonb_array_elements(v_snapshot -> 'sources') item
      cross join lateral jsonb_array_elements_text(item -> 'blockers') blocker
      union all
      select blocker
      from jsonb_array_elements(v_snapshot -> 'changes') item
      cross join lateral jsonb_array_elements_text(item -> 'blockers') blocker
      union all
      select blocker
      from jsonb_array_elements(v_snapshot -> 'reviews') item
      cross join lateral jsonb_array_elements_text(item -> 'blockers') blocker
      union all
      select blocker
      from jsonb_array_elements_text(v_snapshot #> '{health,blockers}') blocker
    )
    select 1
    from blocker_values
    where value not in (
      'source_review_required',
      'collection_failed',
      'fetch_failed',
      'stale_source',
      'collection_not_verified',
      'missing_official_url',
      'no_published_source_version',
      'candidate_version_missing',
      'approved_review_required',
      'citation_required',
      'article_not_approved',
      'source_not_published',
      'source_not_current',
      'source_publication_required',
      'legal_body_extraction_required',
      'legacy_recapture_required'
    )
  ) then
    raise exception 'snapshot exposed an unknown or presentation-only blocker';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_snapshot -> 'reviews') item
    where coalesce((item ->> 'is_test')::boolean, false)
  ) then
    raise exception 'snapshot exposed a homologation knowledge article';
  end if;
  if exists (
    select 1
    from public.vw_reusable_knowledge_articles article
    where article.is_test
  ) then
    raise exception 'reusable knowledge view still exposes test fixtures';
  end if;

  v_denied := false;
  begin
    perform public.ia_get_knowledge_operations_snapshot(x_municipality_b);
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'tenant A legal reviewer read tenant B knowledge operations';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
    true
  );
  v_denied := false;
  begin
    perform public.ia_fiscal_record_knowledge_fetch_failure(
      v_source_id,
      'https://official-a.example.invalid/law/1',
      500,
      'stage_failed',
      'Falha sintética após uma correlação já concluída.',
      now(),
      '00000000-0000-4000-8000-00000000c301',
      '{}'::jsonb
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'correlation id was already used with different failure evidence';
  end;
  if not v_denied then
    raise exception 'a successful capture correlation was silently rewritten as a failure';
  end if;
  v_failure_run_id := public.ia_fiscal_record_knowledge_fetch_failure(
    v_source_id,
    'https://official-a.example.invalid/law/1',
    302,
    'source_host_not_allowed',
    'Redirecionamento fora da allowlist.',
    now(),
    '00000000-0000-4000-8000-00000000c303',
    '{}'::jsonb
  );
  if not exists (
    select 1
    from private.legal_source_fetch_runs run
    where run.id = v_failure_run_id
      and run.status = 'blocked'
      and run.safe_error_code = 'source_host_not_allowed'
  ) then
    raise exception 'security failure was not recorded as blocked';
  end if;
  if not exists (
    select 1
    from private.legal_source_fetch_runs blocked_run
    join private.legal_source_fetch_runs completed_run
      on completed_run.id = (v_capture ->> 'fetch_run_id')::uuid
    where blocked_run.id = v_failure_run_id
      and blocked_run.observed_at = completed_run.observed_at
      and blocked_run.run_sequence > completed_run.run_sequence
  ) then
    raise exception 'fetch insertion sequence did not resolve equal observation timestamps';
  end if;

  v_denied := false;
  begin
    update private.legal_source_fetch_runs
    set safe_error_detail = 'mutated'
    where id = v_failure_run_id;
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'append-only fetch evidence was mutated';
  end if;

  perform set_config('request.jwt.claim.sub', u_legal_a::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_legal_a, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  v_snapshot := public.ia_get_knowledge_operations_snapshot(x_municipality_a);
  if not (v_snapshot #> '{health,blockers}' ? 'fetch_failed')
     or not exists (
       select 1
       from jsonb_array_elements(v_snapshot -> 'sources') item
       where item ->> 'source_id' = v_source_id::text
         and item -> 'blockers' ? 'fetch_failed'
     ) then
    raise exception 'blocked collection did not produce the stable fetch_failed blocker';
  end if;
end
$test$;

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
  true
);

do $service_role_dml$
declare
  v_denied boolean;
  v_error text;
  v_governed_object text :=
    'qa-knowledge-a/00000000-0000-4000-8000-00000000c301/'
    || encode(extensions.digest('official raw document v1', 'sha256'), 'hex')
    || '/law-1.txt';
begin
  v_denied := false;
  begin
    update public.legal_sources
    set official_url = 'https://attacker.example.invalid/replaced'
    where id = '00000000-0000-4000-8000-00000000c301'::uuid;
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'service_role mutated an official source URL directly';
  end if;

  v_denied := false;
  begin
    update public.legal_source_versions
    set content_text = 'worker mutation with stale hash'
    where source_id = '00000000-0000-4000-8000-00000000c301'::uuid;
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'service_role mutated governed legal text directly';
  end if;

  v_denied := false;
  begin
    delete from public.legal_source_versions
    where source_id = '00000000-0000-4000-8000-00000000c301'::uuid;
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'service_role deleted a governed legal version directly';
  end if;

  v_denied := false;
  begin
    delete from public.legal_sections
    where municipality_id = '00000000-0000-4000-8000-00000000c001'::uuid;
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'service_role deleted governed legal sections directly';
  end if;

  v_denied := false;
  begin
    update private.legal_chunks
    set content_text = 'worker chunk mutation'
    where municipality_id = '00000000-0000-4000-8000-00000000c001'::uuid;
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'service_role mutated governed legal chunks directly';
  end if;

  v_denied := false;
  begin
    update storage.objects
    set metadata = jsonb_build_object('mutated', true)
    where bucket_id = 'legal-source-artifacts'
      and name = v_governed_object;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legal source storage objects are write-once';
  end;
  if not v_denied then
    raise exception 'service_role overwrote a governed raw artifact object';
  end if;

  v_denied := false;
  begin
    delete from storage.objects
    where bucket_id = 'legal-source-artifacts'
      and name = v_governed_object;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := sqlstate = '42501'
      or v_error = 'legal source storage objects are write-once';
  end;
  if not v_denied then
    raise exception 'service_role deleted a governed raw artifact object';
  end if;

  v_denied := false;
  begin
    update storage.buckets
    set name = 'renamed-governed-artifacts'
    where id = 'legal-source-artifacts';
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'legal source artifact bucket is immutable';
  end;
  if not v_denied then
    raise exception 'service_role renamed the governed artifact bucket';
  end if;

  v_denied := false;
  begin
    delete from storage.buckets where id = 'legal-source-artifacts';
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := sqlstate = '42501'
      or v_error = 'legal source artifact bucket is immutable';
  end;
  if not v_denied then
    raise exception 'service_role deleted the governed artifact bucket';
  end if;

  v_denied := false;
  begin
    truncate table storage.objects cascade;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'governed legal source storage cannot be truncated';
  end;
  if not v_denied then
    raise exception 'service_role truncated Storage objects despite the WORM guard';
  end if;

  v_denied := false;
  begin
    truncate table storage.buckets cascade;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_denied := v_error = 'governed legal source storage cannot be truncated';
  end;
  if not v_denied then
    raise exception 'service_role truncated Storage buckets despite the WORM guard';
  end if;
  if not exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'legal-source-artifacts'
      and object.name = v_governed_object
  ) or not exists (
    select 1
    from storage.buckets bucket
    where bucket.id = 'legal-source-artifacts'
  ) then
    raise exception 'governed Storage evidence was not preserved after blocked TRUNCATE';
  end if;

  update storage.objects
  set metadata = jsonb_build_object('size', 8, 'mimetype', 'text/plain')
  where bucket_id = 'qa-control-artifacts'
    and name = 'control.txt';
  if not found then
    raise exception 'control storage object could not be updated';
  end if;
end
$service_role_dml$;

reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-00000000c104',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '00000000-0000-4000-8000-00000000c104',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);

do $municipal_admin_rls$
declare
  v_denied boolean;
begin
  if not exists (
    select 1
    from public.vw_reusable_knowledge_articles article
    where article.article_id = '00000000-0000-4000-8000-00000000c401'::uuid
      and jsonb_array_length(article.citations) = 1
  ) then
    raise exception 'municipal_admin could not read the current cited knowledge library through RLS';
  end if;

  v_denied := false;
  begin
    perform public.ia_review_knowledge_article(
      '00000000-0000-4000-8000-00000000c403'::uuid,
      '00000000-0000-4000-8000-00000000c404'::uuid,
      'rejected',
      'Administrador não pode revisar este conteúdo.',
      'REVISAR'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'municipal_admin reviewed a knowledge article';
  end if;

  v_denied := false;
  begin
    perform public.ia_publish_knowledge_article(
      '00000000-0000-4000-8000-00000000c401'::uuid,
      'PUBLICAR'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'municipal_admin published a knowledge article';
  end if;
end
$municipal_admin_rls$;

reset role;

rollback;
