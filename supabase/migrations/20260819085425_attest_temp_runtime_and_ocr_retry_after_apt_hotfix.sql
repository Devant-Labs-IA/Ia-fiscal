-- Short-lived audited gates for one hardened OCR retry.
-- This migration does not enable schedules, communication or publication.

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $preflight$
declare
  v_current_main uuid;
  v_job private.legal_ocr_jobs%rowtype;
begin
  select current_gate.runtime_gate_id
    into v_current_main
  from private.knowledge_runtime_current_gates current_gate
  where current_gate.project_ref = 'qvgenxcrdrqyiyozxtdt'
  for update;

  if v_current_main is distinct from
       'a4dabd24-b1c2-4689-9317-190bb52ff0fd'::uuid then
    raise exception 'unexpected current main runtime gate';
  end if;

  if exists (
    select 1
    from private.legal_ocr_runtime_current_gates
    where project_ref = 'qvgenxcrdrqyiyozxtdt'
  ) then
    raise exception 'an OCR runtime gate is already current';
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
     or v_job.safe_error_code is not null then
    raise exception 'target OCR job is not pristine and queued';
  end if;

  if (select count(*) from private.legal_ocr_job_events event
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
     or exists (select 1 from storage.objects object where object.bucket_id = 'legal-ocr-artifacts')
     or exists (
       select 1
       from private.legal_source_change_sets change_set
       where change_set.id = v_job.change_set_id
         and change_set.candidate_version_id is not null
     ) then
    raise exception 'target OCR job already has derived evidence or OIDC consumption';
  end if;

  if exists (select 1 from private.knowledge_automation_settings where enabled)
     or exists (select 1 from cron.job where jobname like 'ia-fiscal-knowledge%')
     or exists (select 1 from public.legal_source_versions where status = 'published')
     or exists (
       select 1
       from private.legal_reviewer_capability_grants capability
       where capability.status = 'active'
         and capability.valid_from <= now()
         and (capability.valid_until is null or capability.valid_until > now())
     )
     or exists (
       select 1
       from public.municipality_portal_settings setting
       where setting.external_email_enabled
          or not setting.external_delivery_locked
     ) then
    raise exception 'fail-closed production preconditions changed';
  end if;
end;
$preflight$;

select public.ia_fiscal_attest_knowledge_runtime_ready(
  'qvgenxcrdrqyiyozxtdt',
  'knowledge-ingest-v2',
  'ed316143-8ebb-4ea4-a293-559ac1c9f8bd',
  '0f7ffacc7b5cd7c225d175f1ed2c3252c7a1f44cb514f88319ec1aa4ee4edc91',
  'knowledge-embed-v1',
  '34bb78c5-97e0-4390-b0c0-ea97f322a7a3',
  '630f6e81cb822ab6eb962930db4f4c83f8b21bbf5b573d82a5abc84cd09bee9a',
  'knowledge-search-v1',
  '47ce1797-4eb8-43a9-afcd-92d89667ea56',
  'be3df4a48011b199abd1164f67c7fa02fa992ef5a6761b49327daef2e1702159',
  '484316c72749a2e1f0474b080e3d58b41d3235b2dd41abdc9a5861b86f82f4e3',
  'https://github.com/AlmoreContabilidade/Ia-fiscal/blob/4aeeefa4f90892a862f9077f5cc36e7eaf2fc011/docs/qa/evidence/knowledge-runtime-ocr-retry-apt-hotfix-2026-08-19.json',
  '2026-08-19T11:00:00Z'::timestamptz,
  'ATESTAR RUNTIME SEGUNDO CEREBRO'
);

select public.ia_fiscal_revoke_knowledge_runtime_gate(
  'a4dabd24-b1c2-4689-9317-190bb52ff0fd'::uuid,
  'Gate temporário anterior substituído por evidência imutável do workflow OCR endurecido contra indisponibilidade dos mirrors apt.',
  'REVOGAR RUNTIME SEGUNDO CEREBRO'
);

select public.ia_fiscal_attest_knowledge_ocr_runtime_ready(
  'qvgenxcrdrqyiyozxtdt',
  '685ece05-684e-4812-8441-f81b46286169'::uuid,
  'c530312a53cb025466198df3520e73561f01599d11c698d4b8c15ae3194d463d',
  'd7fbd651fd43f6ebeab42be3c9e442f3afedefaa',
  'ia-fiscal-knowledge-ocr-policy/v1',
  '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60',
  120,
  8000000,
  '288f0673c49240c43d75aded2a5e356a3dda8223baf4c42c7ed5189e9b40af59',
  'https://github.com/AlmoreContabilidade/Ia-fiscal/blob/4aeeefa4f90892a862f9077f5cc36e7eaf2fc011/docs/qa/evidence/knowledge-ocr-bootstrap-retry-apt-hotfix-2026-08-19.json',
  '2026-08-19T10:55:00Z'::timestamptz,
  'ATESTAR RUNTIME OCR SEGUNDO CEREBRO'
);

do $postcheck$
declare
  v_main private.knowledge_runtime_release_gates%rowtype;
  v_ocr private.legal_ocr_runtime_gates%rowtype;
begin
  select gate.* into strict v_main
  from private.knowledge_runtime_current_gates current_gate
  join private.knowledge_runtime_release_gates gate
    on gate.id = current_gate.runtime_gate_id
  where current_gate.project_ref = 'qvgenxcrdrqyiyozxtdt'
  for key share of gate;

  select gate.* into strict v_ocr
  from private.legal_ocr_runtime_current_gates current_gate
  join private.legal_ocr_runtime_gates gate
    on gate.id = current_gate.runtime_gate_id
  where current_gate.project_ref = 'qvgenxcrdrqyiyozxtdt'
  for key share of gate;

  if v_main.smoke_evidence_sha256 <>
       '484316c72749a2e1f0474b080e3d58b41d3235b2dd41abdc9a5861b86f82f4e3'
     or v_ocr.smoke_evidence_sha256 <>
       '288f0673c49240c43d75aded2a5e356a3dda8223baf4c42c7ed5189e9b40af59'
     or v_ocr.workflow_commit_sha <>
       'd7fbd651fd43f6ebeab42be3c9e442f3afedefaa'
     or v_main.valid_until < '2026-08-19T11:00:00Z'::timestamptz
     or v_ocr.valid_until < '2026-08-19T10:55:00Z'::timestamptz
     or v_main.valid_until <= v_ocr.valid_until
     or exists (select 1 from private.knowledge_automation_settings where enabled)
     or exists (select 1 from cron.job where jobname like 'ia-fiscal-knowledge%') then
    raise exception 'temporary OCR gate postconditions failed';
  end if;
end;
$postcheck$;
