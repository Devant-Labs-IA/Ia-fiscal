-- One-shot runtime authentication smokes for the deployed ingest v5 bundle.
-- Every valid request is dry-run; no Storage or governed database row may be
-- created by this release check.

do $$
declare
  v_project_url text;
  v_scheduler_secret text;
  v_endpoint_id uuid;
  v_issued_at timestamptz := clock_timestamp();
  v_replay_nonce uuid := gen_random_uuid();
  v_request_id bigint;
begin
  select secret.decrypted_secret into strict v_project_url
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_project_url';

  select secret.decrypted_secret into strict v_scheduler_secret
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_scheduler_secret';

  select endpoint.id into strict v_endpoint_id
  from private.legal_source_endpoints endpoint
  join public.municipalities municipality
    on municipality.id = endpoint.municipality_id
  where municipality.slug = 'cordeiropolis-sp'
    and endpoint.url =
      'https://www.cordeiropolis.sp.gov.br/wp-content/uploads/2024/12/Edicao-1645-_C.pdf'
    and endpoint.status = 'active';

  -- Missing bearer.
  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/ia-fiscal-knowledge-ingest',
    headers := jsonb_build_object('content-type', 'application/json'),
    body := jsonb_build_object('endpoint_id', v_endpoint_id, 'dry_run', true),
    timeout_milliseconds := 90000
  ) into v_request_id;

  -- Wrong bearer with otherwise valid scheduler headers.
  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/ia-fiscal-knowledge-ingest',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer invalid-release-smoke-secret',
      'x-ia-scheduler-nonce', gen_random_uuid()::text,
      'x-ia-scheduler-issued-at', v_issued_at::text
    ),
    body := jsonb_build_object('endpoint_id', v_endpoint_id, 'dry_run', true),
    timeout_milliseconds := 90000
  ) into v_request_id;

  -- Correct bearer outside the two-minute window.
  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/ia-fiscal-knowledge-ingest',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_scheduler_secret,
      'x-ia-scheduler-nonce', gen_random_uuid()::text,
      'x-ia-scheduler-issued-at', (v_issued_at - interval '10 minutes')::text
    ),
    body := jsonb_build_object('endpoint_id', v_endpoint_id, 'dry_run', true),
    timeout_milliseconds := 90000
  ) into v_request_id;

  -- The same nonce is sent twice. Exactly one request may consume it; the
  -- other must fail closed as a replay. Both remain dry-run.
  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/ia-fiscal-knowledge-ingest',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_scheduler_secret,
      'x-ia-scheduler-nonce', v_replay_nonce::text,
      'x-ia-scheduler-issued-at', v_issued_at::text
    ),
    body := jsonb_build_object('endpoint_id', v_endpoint_id, 'dry_run', true),
    timeout_milliseconds := 90000
  ) into v_request_id;

  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/ia-fiscal-knowledge-ingest',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_scheduler_secret,
      'x-ia-scheduler-nonce', v_replay_nonce::text,
      'x-ia-scheduler-issued-at', v_issued_at::text
    ),
    body := jsonb_build_object('endpoint_id', v_endpoint_id, 'dry_run', true),
    timeout_milliseconds := 90000
  ) into v_request_id;
end;
$$;
