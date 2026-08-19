-- Revoke the temporary OCR bootstrap gate after GitHub rejected the workflow
-- before startup. The gate and its audit history remain append-only.

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select public.ia_fiscal_revoke_knowledge_ocr_runtime_gate(
  'f22d4814-e5b6-464a-b4bf-ae7463729dea'::uuid,
  'Workflow OCR inválido no GitHub Actions: runner.temp não é permitido em jobs.env; gate temporário revogado antes da correção.',
  'REVOGAR RUNTIME OCR SEGUNDO CEREBRO'
);
