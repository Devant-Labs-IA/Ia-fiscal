-- Transactional regression for governed external OCR.
--
-- Apply through 20260819055931 before running. No runtime gate, Edge function,
-- workflow, GitHub token or real user is required. All fixtures and pointer
-- changes are rolled back.

begin;

do $catalog_contract$
declare
  v_table text;
  v_function regprocedure;
  v_finalize text;
begin
  foreach v_table in array array[
    'private.legal_ocr_runtime_gates',
    'private.legal_ocr_runtime_gate_events',
    'private.legal_ocr_jobs',
    'private.legal_ocr_oidc_requests',
    'private.legal_ocr_job_events',
    'private.legal_ocr_job_pages',
    'private.legal_ocr_results'
  ] loop
    if to_regclass(v_table) is null then
      raise exception 'required OCR table is missing: %', v_table;
    end if;
    if not (
      select class.relrowsecurity
      from pg_catalog.pg_class class
      where class.oid = to_regclass(v_table)
    ) then
      raise exception 'OCR table is missing RLS: %', v_table;
    end if;
    if has_table_privilege('authenticated', v_table, 'SELECT')
       or has_table_privilege('authenticated', v_table, 'INSERT')
       or has_table_privilege('service_role', v_table, 'SELECT')
       or has_table_privilege('service_role', v_table, 'INSERT') then
      raise exception 'OCR table has a direct API-role privilege: %', v_table;
    end if;
  end loop;

  foreach v_function in array array[
    'public.ia_fiscal_claim_knowledge_ocr_job(jsonb,integer)'::regprocedure,
    'public.ia_fiscal_heartbeat_knowledge_ocr_job(uuid,text,jsonb,text,integer)'::regprocedure,
    'public.ia_fiscal_fail_knowledge_ocr_job(uuid,text,jsonb,text,text,boolean)'::regprocedure,
    'public.ia_fiscal_finalize_knowledge_ocr_job(uuid,text,jsonb,text,text,text,text,bigint,text,jsonb,jsonb)'::regprocedure
  ] loop
    if has_function_privilege('authenticated', v_function, 'EXECUTE')
       or has_function_privilege('anon', v_function, 'EXECUTE')
       or not has_function_privilege('service_role', v_function, 'EXECUTE') then
      raise exception 'OCR RPC ACL is not service-only: %', v_function;
    end if;
  end loop;

  if not exists (
    select 1
    from storage.buckets bucket
    where bucket.id = 'legal-ocr-artifacts'
      and not bucket.public
      and bucket.file_size_limit = 5242880
      and bucket.allowed_mime_types = array['application/json']::text[]
  ) then
    raise exception 'private bounded OCR evidence bucket is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger
    where trigger.tgrelid = 'private.legal_ocr_results'::regclass
      and trigger.tgname = 'legal_ocr_results_no_truncate'
      and not trigger.tgisinternal
  ) or not exists (
    select 1
    from pg_catalog.pg_trigger trigger
    where trigger.tgrelid = 'storage.objects'::regclass
      and trigger.tgname = 'legal_ocr_storage_objects_truncate_guard'
      and not trigger.tgisinternal
  ) or not exists (
    select 1
    from pg_catalog.pg_trigger trigger
    where trigger.tgrelid = 'storage.buckets'::regclass
      and trigger.tgname = 'legal_ocr_storage_buckets_no_truncate'
      and not trigger.tgisinternal
  ) then
    raise exception 'OCR append-only TRUNCATE guard is missing';
  end if;

  v_finalize := pg_get_functiondef(
    'public.ia_fiscal_finalize_knowledge_ocr_job(uuid,text,jsonb,text,text,text,text,bigint,text,jsonb,jsonb)'::regprocedure
  );
  if position('completion_evidence_sha256' in v_finalize) = 0
     or position('already_completed' in v_finalize) = 0
     or position('under_review' in v_finalize) = 0
     or position('not_published' in v_finalize) = 0
     or position('ia_publish_legal_source_version' in v_finalize) > 0
     or position('status = ''published''' in v_finalize) > 0 then
    raise exception 'OCR finalization is not exact-idempotent and review-only';
  end if;

  if has_function_privilege(
    'service_role',
    'public.ia_publish_legal_source_version(uuid,uuid,text)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'OCR service role can execute human legal publication';
  end if;
end;
$catalog_contract$;

-- Claims must fail before OIDC consumption while the separately attested OCR
-- runtime gate is absent. This uses a synthetic service JWT claim, not auth data.
delete from private.legal_ocr_runtime_current_gates
where project_ref = 'qvgenxcrdrqyiyozxtdt';

select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text,
  true
);

do $runtime_fail_closed$
declare
  v_denied boolean := false;
  v_oidc_request_count bigint;
begin
  select count(*) into v_oidc_request_count
  from private.legal_ocr_oidc_requests;
  begin
    perform public.ia_fiscal_claim_knowledge_ocr_job('{}'::jsonb, 600);
  exception when sqlstate '55000' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'OCR claim ran without both attested runtime gates';
  end if;
  if (select count(*) from private.legal_ocr_oidc_requests) <>
       v_oidc_request_count then
    raise exception 'fail-closed runtime check consumed an OIDC request';
  end if;
end;
$runtime_fail_closed$;

do $queue_boundaries$
declare
  x_municipality constant uuid := '00000000-0000-4000-8000-00000000e001';
  x_source_120 constant uuid := '00000000-0000-4000-8000-00000000e101';
  x_source_121 constant uuid := '00000000-0000-4000-8000-00000000e102';
  x_source_manual constant uuid := '00000000-0000-4000-8000-00000000e103';
  x_endpoint_120 constant uuid := '00000000-0000-4000-8000-00000000e201';
  x_endpoint_121 constant uuid := '00000000-0000-4000-8000-00000000e202';
  x_endpoint_manual constant uuid := '00000000-0000-4000-8000-00000000e203';
  x_fetch_120 constant uuid := '00000000-0000-4000-8000-00000000e301';
  x_fetch_121 constant uuid := '00000000-0000-4000-8000-00000000e302';
  x_fetch_manual constant uuid := '00000000-0000-4000-8000-00000000e303';
  x_artifact_120 constant uuid := '00000000-0000-4000-8000-00000000e401';
  x_artifact_121 constant uuid := '00000000-0000-4000-8000-00000000e402';
  x_artifact_manual constant uuid := '00000000-0000-4000-8000-00000000e403';
  x_change_120 constant uuid := '00000000-0000-4000-8000-00000000e501';
  x_change_121 constant uuid := '00000000-0000-4000-8000-00000000e502';
  x_change_manual constant uuid := '00000000-0000-4000-8000-00000000e503';
  v_sha_120 text := encode(extensions.digest('qa-ocr-pdf-120', 'sha256'), 'hex');
  v_sha_121 text := encode(extensions.digest('qa-ocr-pdf-121', 'sha256'), 'hex');
  v_sha_manual text := encode(extensions.digest('qa-ocr-pdf-manual', 'sha256'), 'hex');
  v_denied boolean := false;
begin
  insert into public.municipalities (id, slug, name, state_code, status)
  values (x_municipality, 'qa-governed-ocr', 'Município QA OCR', 'SP', 'active');

  insert into private.knowledge_automation_settings (
    municipality_id, enabled, timezone, next_run_at, endpoint_batch_size
  ) values (x_municipality, true, 'America/Sao_Paulo', now(), 1);

  insert into public.legal_sources (
    id, municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  ) values
    (
      x_source_120, x_municipality, 'law', 'municipal', 'Município QA OCR',
      'Lei QA OCR 120', 'Lei QA OCR 120', 'https://ocr.example.invalid/120.pdf',
      'Tributos municipais', 'fiscal_knowledge', 'draft'
    ),
    (
      x_source_121, x_municipality, 'law', 'municipal', 'Município QA OCR',
      'Lei QA OCR 121', 'Lei QA OCR 121', 'https://ocr.example.invalid/121.pdf',
      'Tributos municipais', 'fiscal_knowledge', 'draft'
    ),
    (
      x_source_manual, x_municipality, 'law', 'municipal', 'Município QA OCR',
      'Lei QA OCR manual', 'Lei QA OCR manual',
      'https://ocr.example.invalid/manual.pdf', 'Tributos municipais',
      'fiscal_knowledge', 'draft'
    );

  insert into private.legal_source_endpoints (
    id, municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
    citable_body, url, allowed_hosts, expected_content_types, parser_hint,
    priority, status
  ) values
    (
      x_endpoint_120, x_municipality, x_source_120, 'document_file',
      'primary_publication', 'legal_body', true,
      'https://ocr.example.invalid/120.pdf', array['ocr.example.invalid'],
      array['application/pdf'], 'pdf_ocr', 10, 'active'
    ),
    (
      x_endpoint_121, x_municipality, x_source_121, 'document_file',
      'primary_publication', 'legal_body', true,
      'https://ocr.example.invalid/121.pdf', array['ocr.example.invalid'],
      array['application/pdf'], 'pdf_ocr', 20, 'active'
    ),
    (
      x_endpoint_manual, x_municipality, x_source_manual, 'document_file',
      'primary_publication', 'legal_body', true,
      'https://ocr.example.invalid/manual.pdf', array['ocr.example.invalid'],
      array['application/pdf'], 'pdf_ocr', 30, 'active'
    );

  insert into private.legal_source_fetch_runs (
    id, municipality_id, source_id, endpoint_id, correlation_id, status,
    requested_url, final_url, http_status, observed_content_sha256, observed_at
  ) values
    (
      x_fetch_120, x_municipality, x_source_120, x_endpoint_120,
      '00000000-0000-4000-8000-00000000e601', 'completed_changed',
      'https://ocr.example.invalid/120.pdf', 'https://ocr.example.invalid/120.pdf',
      200, v_sha_120, now()
    ),
    (
      x_fetch_121, x_municipality, x_source_121, x_endpoint_121,
      '00000000-0000-4000-8000-00000000e602', 'completed_changed',
      'https://ocr.example.invalid/121.pdf', 'https://ocr.example.invalid/121.pdf',
      200, v_sha_121, now()
    ),
    (
      x_fetch_manual, x_municipality, x_source_manual, x_endpoint_manual,
      '00000000-0000-4000-8000-00000000e603', 'completed_changed',
      'https://ocr.example.invalid/manual.pdf',
      'https://ocr.example.invalid/manual.pdf', 200, v_sha_manual, now()
    );

  insert into storage.objects (bucket_id, name, metadata) values
    (
      'legal-source-artifacts', 'qa-ocr/120.pdf',
      jsonb_build_object('size', 100, 'mimetype', 'application/pdf')
    ),
    (
      'legal-source-artifacts', 'qa-ocr/121.pdf',
      jsonb_build_object('size', 101, 'mimetype', 'application/pdf')
    ),
    (
      'legal-source-artifacts', 'qa-ocr/manual.pdf',
      jsonb_build_object('size', 102, 'mimetype', 'application/pdf')
    );

  insert into private.legal_source_artifacts (
    id, municipality_id, source_id, endpoint_id, fetch_run_id, storage_bucket,
    storage_path, content_sha256, byte_size, mime_type, extraction_status,
    observed_at, metadata
  ) values
    (
      x_artifact_120, x_municipality, x_source_120, x_endpoint_120, x_fetch_120,
      'legal-source-artifacts', 'qa-ocr/120.pdf', v_sha_120, 100,
      'application/pdf', 'requires_extraction', now(), jsonb_build_object(
        'extraction_blocker', 'source_pdf_text_missing',
        'extraction_page_count', 120,
        'extraction_complete', false,
        'content_truncated', false,
        'extracted_char_count', 0
      )
    ),
    (
      x_artifact_121, x_municipality, x_source_121, x_endpoint_121, x_fetch_121,
      'legal-source-artifacts', 'qa-ocr/121.pdf', v_sha_121, 101,
      'application/pdf', 'requires_extraction', now(), jsonb_build_object(
        'extraction_blocker', 'source_pdf_text_missing',
        'extraction_page_count', 121,
        'extraction_complete', false,
        'content_truncated', false,
        'extracted_char_count', 0
      )
    ),
    (
      x_artifact_manual, x_municipality, x_source_manual, x_endpoint_manual,
      x_fetch_manual, 'legal-source-artifacts', 'qa-ocr/manual.pdf', v_sha_manual,
      102, 'application/pdf', 'requires_extraction', now(), jsonb_build_object(
        'extraction_blocker', 'external_ocr_page_limit_exceeded',
        'extraction_page_count', 121,
        'extraction_complete', false,
        'content_truncated', false,
        'extracted_char_count', 0
      )
    );

  insert into private.legal_source_change_sets (
    id, municipality_id, source_id, to_artifact_id, change_type, status,
    to_sha256, diff_sha256, diff_summary
  ) values
    (
      x_change_120, x_municipality, x_source_120, x_artifact_120,
      'initial_document', 'detected', v_sha_120,
      encode(extensions.digest('qa-ocr-diff-120', 'sha256'), 'hex'),
      'QA: documento PDF elegível com exatamente 120 páginas.'
    ),
    (
      x_change_121, x_municipality, x_source_121, x_artifact_121,
      'initial_document', 'detected', v_sha_121,
      encode(extensions.digest('qa-ocr-diff-121', 'sha256'), 'hex'),
      'QA: documento PDF acima do limite, sem reclassificação do blocker.'
    ),
    (
      x_change_manual, x_municipality, x_source_manual, x_artifact_manual,
      'initial_document', 'detected', v_sha_manual,
      encode(extensions.digest('qa-ocr-diff-manual', 'sha256'), 'hex'),
      'QA: documento PDF preservado para revisão manual acima de 120 páginas.'
    );

  if (
    select count(*)
    from private.legal_ocr_jobs job
    where job.municipality_id = x_municipality
  ) <> 1 or not exists (
    select 1
    from private.legal_ocr_jobs job
    where job.municipality_id = x_municipality
      and job.source_artifact_id = x_artifact_120
      and job.change_set_id = x_change_120
      and job.status = 'queued'
  ) or exists (
    select 1
    from private.legal_ocr_jobs job
    where job.municipality_id = x_municipality
      and job.source_artifact_id in (x_artifact_121, x_artifact_manual)
  ) then
    raise exception 'OCR queue crossed the 120-page or blocker boundary';
  end if;

  if (
    select count(*)
    from private.legal_ocr_job_events event
    join private.legal_ocr_jobs job
      on job.municipality_id = event.municipality_id
     and job.id = event.job_id
    where job.municipality_id = x_municipality
      and event.event_type = 'queued'
  ) <> 1 then
    raise exception 'eligible OCR job did not retain one append-only queue event';
  end if;

  v_denied := false;
  begin
    update private.legal_source_artifacts artifact
    set metadata = artifact.metadata || jsonb_build_object('tampered', true)
    where artifact.id = x_artifact_120;
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'raw official artifact metadata was mutable before OCR';
  end if;

  insert into storage.objects (bucket_id, name, metadata)
  values (
    'legal-ocr-artifacts', 'qa-ocr/immutable.json',
    jsonb_build_object('size', 2, 'mimetype', 'application/json')
  );
  v_denied := false;
  begin
    update storage.objects object
    set metadata = object.metadata || jsonb_build_object('tampered', true)
    where object.bucket_id = 'legal-ocr-artifacts'
      and object.name = 'qa-ocr/immutable.json';
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'OCR Storage artifact was mutable';
  end if;

  v_denied := false;
  begin
    execute 'truncate table private.legal_ocr_results';
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'append-only OCR result ledger allowed TRUNCATE';
  end if;

  if exists (
    select 1
    from public.legal_source_versions version
    where version.municipality_id = x_municipality
  ) then
    raise exception 'queueing raw OCR work created a legal candidate or publication';
  end if;
end;
$queue_boundaries$;

rollback;
