-- Revoke the retry gate after the GitHub runner stalled in apt before OIDC.

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select public.ia_fiscal_revoke_knowledge_ocr_runtime_gate(
  'beb7eaac-cdbd-46a6-91d5-b547ccf4768e'::uuid,
  'Run OCR 32230078189 cancelado antes do OIDC após ausência de progresso no mirror apt; gate revogado para hardening do workflow.',
  'REVOGAR RUNTIME OCR SEGUNDO CEREBRO'
);
