-- Revoke the short-lived bootstrap gates after OCR run #10 failed closed
-- during toolchain sandbox verification. No OCR/OIDC/database evidence was created.

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $preflight$
declare
  v_current_main uuid;
  v_current_ocr uuid;
  v_job private.legal_ocr_jobs%rowtype;
begin
  select runtime_gate_id
    into strict v_current_main
  from private.knowledge_runtime_current_gates
  where project_ref = 'qvgenxcrdrqyiyozxtdt'
  for update;

  select runtime_gate_id
    into strict v_current_ocr
  from private.legal_ocr_runtime_current_gates
  where project_ref = 'qvgenxcrdrqyiyozxtdt'
  for update;

  if v_current_main <> '652989bd-04d7-4fae-a5d6-61afbe1b962b'::uuid
     or v_current_ocr <> '223b72e8-7ef2-4311-8672-7094bd7b4956'::uuid then
    raise exception 'temporary runtime gate identity changed before revocation';
  end if;

  select job.* into strict v_job
  from private.legal_ocr_jobs job
  where job.id = '03c5dd76-beee-4363-9d3f-9335e2357da9'::uuid
  for update;

  if v_job.status <> 'queued'
     or v_job.attempt <> 0
     or v_job.lease_token_sha256 is not null
     or v_job.lease_started_at is not null
     or v_job.lease_expires_at is not null
     or v_job.completed_at is not null
     or v_job.safe_error_code is not null
     or (select count(*) from private.legal_ocr_job_events event
         where event.job_id = v_job.id) <> 1
     or not exists (
       select 1 from private.legal_ocr_job_events event
       where event.job_id = v_job.id
         and event.event_type = 'queued'
         and event.attempt = 0
     )
     or exists (select 1 from private.legal_ocr_oidc_requests)
     or exists (select 1 from private.legal_ocr_job_pages page where page.job_id = v_job.id)
     or exists (select 1 from private.legal_ocr_results result where result.job_id = v_job.id)
     or exists (select 1 from storage.objects object where object.bucket_id = 'legal-ocr-artifacts') then
    raise exception 'OCR run was not fail-closed before gate revocation';
  end if;

  if exists (select 1 from private.knowledge_automation_settings where enabled)
     or exists (select 1 from cron.job where jobname like 'ia-fiscal-knowledge%')
     or exists (select 1 from public.legal_source_versions where status = 'published') then
    raise exception 'production activation state changed before gate revocation';
  end if;
end;
$preflight$;

select public.ia_fiscal_revoke_knowledge_ocr_runtime_gate(
  '223b72e8-7ef2-4311-8672-7094bd7b4956'::uuid,
  'Retry OCR endurecido falhou fechado na verificação isolada do toolchain antes de OIDC, claim ou evidência; gate temporário revogado.',
  'REVOGAR RUNTIME OCR SEGUNDO CEREBRO'
);

select public.ia_fiscal_revoke_knowledge_runtime_gate(
  '652989bd-04d7-4fae-a5d6-61afbe1b962b'::uuid,
  'Retry OCR endurecido falhou fechado na verificação isolada do toolchain antes de OIDC, claim ou evidência; gate bootstrap temporário revogado.',
  'REVOGAR RUNTIME SEGUNDO CEREBRO'
);

do $postcheck$
begin
  if exists (
       select 1 from private.knowledge_runtime_current_gates
       where project_ref = 'qvgenxcrdrqyiyozxtdt'
     )
     or exists (
       select 1 from private.legal_ocr_runtime_current_gates
       where project_ref = 'qvgenxcrdrqyiyozxtdt'
     )
     or exists (select 1 from private.knowledge_automation_settings where enabled)
     or exists (select 1 from cron.job where jobname like 'ia-fiscal-knowledge%')
     or exists (select 1 from public.legal_source_versions where status = 'published')
     or exists (select 1 from private.legal_ocr_oidc_requests)
     or exists (
       select 1 from private.legal_ocr_job_pages
       where job_id = '03c5dd76-beee-4363-9d3f-9335e2357da9'::uuid
     )
     or exists (
       select 1 from private.legal_ocr_results
       where job_id = '03c5dd76-beee-4363-9d3f-9335e2357da9'::uuid
     ) then
    raise exception 'fail-closed gate revocation postconditions failed';
  end if;
end;
$postcheck$;
