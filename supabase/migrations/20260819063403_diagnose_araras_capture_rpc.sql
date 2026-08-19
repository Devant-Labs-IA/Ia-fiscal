-- One-shot diagnostic replay after adding sanitized RPC rejection logging to
-- ingest v5.  The request reuses the immutable official blob and remains
-- capture-only; it cannot approve or publish content.

do $$
declare
  v_project_url text;
  v_scheduler_secret text;
  v_request_id bigint;
begin
  select secret.decrypted_secret into strict v_project_url
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_project_url';

  select secret.decrypted_secret into strict v_scheduler_secret
  from vault.decrypted_secrets secret
  where secret.name = 'ia_fiscal_knowledge_scheduler_secret';

  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/ia-fiscal-knowledge-ingest',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_scheduler_secret,
      'x-ia-scheduler-nonce', gen_random_uuid()::text,
      'x-ia-scheduler-issued-at', clock_timestamp()::text
    ),
    body := jsonb_build_object(
      'endpoint_id', '001c47a4-949c-47f6-ac2a-060b2ae5aafd',
      'dry_run', false
    ),
    timeout_milliseconds := 90000
  ) into v_request_id;

  if v_request_id is null then
    raise exception 'diagnostic ingest request was not queued';
  end if;
end;
$$;
