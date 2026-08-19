-- Complete the controlled Araras Law 3.362/2001 capture after fixing the
-- capture-v2 raw-evidence identity.  This is capture-only: no approval or
-- publication is possible in this path.

do $$
declare
  v_endpoint_id constant uuid := '001c47a4-949c-47f6-ac2a-060b2ae5aafd'::uuid;
  v_municipality_id uuid;
  v_project_url text;
  v_scheduler_secret text;
  v_request_id bigint;
  v_dispatch_id bigint;
  v_nonce uuid := gen_random_uuid();
  v_issued_at timestamptz := clock_timestamp();
begin
  select endpoint.municipality_id
  into strict v_municipality_id
  from private.legal_source_endpoints endpoint
  join public.municipalities municipality
    on municipality.id = endpoint.municipality_id
  where endpoint.id = v_endpoint_id
    and municipality.slug = 'araras-sp'
    and endpoint.url = 'https://araras.siscam.com.br/arquivo?Id=43123'
    and endpoint.endpoint_kind = 'document_file'
    and endpoint.status = 'active'
    and endpoint.content_mode = 'legal_body'
    and endpoint.citable_body;

  if exists (
    select 1
    from private.legal_source_artifacts artifact
    where artifact.municipality_id = v_municipality_id
      and artifact.endpoint_id = v_endpoint_id
  ) then
    return;
  end if;

  select secret.decrypted_secret
  into v_project_url
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_project_url';

  select secret.decrypted_secret
  into v_scheduler_secret
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_scheduler_secret';

  if v_project_url is null or v_scheduler_secret is null then
    raise exception 'knowledge scheduler runtime configuration is incomplete';
  end if;

  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/ia-fiscal-knowledge-ingest',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_scheduler_secret,
      'x-ia-scheduler-nonce', v_nonce::text,
      'x-ia-scheduler-issued-at', v_issued_at::text
    ),
    body := jsonb_build_object(
      'endpoint_id', v_endpoint_id,
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
    v_municipality_id,
    v_endpoint_id,
    'ingest',
    v_request_id,
    1,
    'queued'
  ) returning id into v_dispatch_id;

  insert into private.knowledge_scheduler_dispatch_events (
    dispatch_id,
    event_type,
    metadata
  ) values (
    v_dispatch_id,
    'queued',
    jsonb_build_object(
      'lease_seconds', 120,
      'attempt', 1,
      'trigger', 'phase2_araras_3362_capture_after_raw_identity_fix',
      'publication_status', 'not_published'
    )
  );
end;
$$;
