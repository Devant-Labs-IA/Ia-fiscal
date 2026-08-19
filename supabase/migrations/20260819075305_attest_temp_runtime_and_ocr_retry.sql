-- Short-lived bootstrap gates for one corrected OCR workflow run.
-- Neither gate authorizes schedule activation, legal publication or communication.

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

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
  'fb36ef7af98dec286d953c3072b2bf4249d007548b2c22262f92a70ec87e827b',
  'https://github.com/AlmoreContabilidade/Ia-fiscal/blob/2b93f0666fe2e600c6fe537b19e7d13711a980af/docs/qa/evidence/knowledge-runtime-ocr-retry-2026-08-19.json',
  '2026-08-19T09:15:00Z'::timestamptz,
  'ATESTAR RUNTIME SEGUNDO CEREBRO'
);

select public.ia_fiscal_revoke_knowledge_runtime_gate(
  'd25d1e41-318a-45dd-a048-f9b8723164c6'::uuid,
  'Gate bootstrap anterior substituído por evidência imutável renovada exclusivamente para o smoke OCR corrigido.',
  'REVOGAR RUNTIME SEGUNDO CEREBRO'
);

select public.ia_fiscal_attest_knowledge_ocr_runtime_ready(
  'qvgenxcrdrqyiyozxtdt',
  '685ece05-684e-4812-8441-f81b46286169'::uuid,
  'c530312a53cb025466198df3520e73561f01599d11c698d4b8c15ae3194d463d',
  '9b5873ab8ce3da7257243f4a52f207db9b4f6817',
  'ia-fiscal-knowledge-ocr-policy/v1',
  '6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60',
  120,
  8000000,
  '93370b16f22668e16fe4c52d6596596b48d84b292d77dab8d9115f8963ee7248',
  'https://github.com/AlmoreContabilidade/Ia-fiscal/blob/2b93f0666fe2e600c6fe537b19e7d13711a980af/docs/qa/evidence/knowledge-ocr-bootstrap-retry-2026-08-19.json',
  '2026-08-19T09:10:00Z'::timestamptz,
  'ATESTAR RUNTIME OCR SEGUNDO CEREBRO'
);
