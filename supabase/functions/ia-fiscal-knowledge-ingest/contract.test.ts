import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

function source(path: string): string {
  return readFileSync(resolve(process.cwd(), path), "utf8");
}

describe("knowledge ingest Edge contract", () => {
  const index = source("supabase/functions/ia-fiscal-knowledge-ingest/index.ts");
  const policy = source("supabase/functions/ia-fiscal-knowledge-ingest/policy.ts");
  const extraction = source("supabase/functions/ia-fiscal-knowledge-ingest/extraction.ts");
  const officialPdfSmoke = source(
    "supabase/functions/ia-fiscal-knowledge-ingest/official-pdf.smoke.ts",
  );
  const core = source("supabase/migrations/20260819040404_knowledge_phase2_core.sql");
  const schedulerAuth = source("supabase/functions/_shared/knowledge-scheduler-auth.ts");
  const config = source("supabase/config.toml");

  it("uses a fail-closed Vault hash, time window and nonce instead of a gateway JWT", () => {
    expect(config).toMatch(
      /\[functions\.ia-fiscal-knowledge-ingest\]\s*(?:#[^\n]*\s*)*verify_jwt\s*=\s*false/,
    );
    expect(index).toContain('requiredEnv("SUPABASE_SERVICE_ROLE_KEY")');
    expect(index).toContain('assertKnowledgeSchedulerRequest(request, supabase, "ingest")');
    expect(schedulerAuth).toContain('"ia_fiscal_validate_knowledge_scheduler_request"');
    expect(schedulerAuth).toContain('request.headers.get("x-ia-scheduler-nonce")');
    expect(schedulerAuth).toContain('request.headers.get("x-ia-scheduler-issued-at")');
    expect(index).not.toContain("auth.getClaims");
    expect(index).not.toContain('requiredEnv("SUPABASE_ANON_KEY")');
  });

  it("uses only the governed service RPCs and private raw-artifact bucket", () => {
    expect(index).toContain('"ia_fiscal_get_knowledge_source_endpoints"');
    expect(index).toContain('"ia_fiscal_capture_knowledge_source_v2"');
    expect(index).toContain('"ia_fiscal_record_knowledge_fetch_failure"');
    expect(index).toContain('"ia_fiscal_record_knowledge_discoveries"');
    expect(index).not.toContain('const STAGE_SECTIONS_RPC = "ia_fiscal_stage_knowledge_sections"');
    expect(policy).toContain('STORAGE_BUCKET = "legal-source-artifacts"');
    expect(index).not.toContain("ia_publish_knowledge_article");
    expect(index.toLowerCase()).not.toContain("base64");
  });

  it("keeps dry-run before every mutation", () => {
    const dryRunGuard = index.indexOf("if (dryRun)");
    const upload = index.indexOf("await uploadArtifact(");
    const capture = index.indexOf("await captureArtifact(");
    expect(dryRunGuard).toBeGreaterThan(0);
    expect(upload).toBeGreaterThan(dryRunGuard);
    expect(capture).toBeGreaterThan(upload);
    expect(index).toContain("shouldAppendFailedFetchRun(dryRun, captureCommitted)");
  });

  it("captures, stages the integral section and returns counts in one transactional RPC", () => {
    expect(index).toContain('const CAPTURE_RPC = "ia_fiscal_capture_knowledge_source_v2"');
    expect(index).toMatch(/p_sections:\s*extractedText === null/);
    expect(index).toContain('section_key: "integral"');
    expect(index).not.toContain("await stageIntegralSection(");
    expect(index).toContain("capture.staged_sections");
    expect(index).toContain("capture.staged_chunks");
    expect(extraction).toContain("buildDeterministicChunks");
    expect(index).toContain(
      "assertCaptureStageIdentity(status, processingStatus, changeSetId, candidateVersionId)",
    );
    expect(core).toContain(
      "create or replace function public.ia_fiscal_capture_knowledge_source_v2(",
    );
    expect(core).toContain("defer-for-capture-v2");
    expect(core).toContain("Force every pooled session to recompile the Phase-1 capture body");
    expect(core).toContain("private.knowledge_staging_matches_payload(");
    expect(core).toContain("staged evidence does not exactly match the capture v2 payload");
  });

  it("keeps one failed fetch audit after rollback without conflicting after commit", () => {
    const committed = index.indexOf("onRpcCommitted();");
    const parsed = index.indexOf("return publicCaptureResult(data);");
    expect(committed).toBeGreaterThan(0);
    expect(parsed).toBeGreaterThan(committed);
    expect(index).toContain("shouldAppendFailedFetchRun(dryRun, captureCommitted)");
    expect(index).toContain("captureCommitted = true");
    expect(index).toContain("orphaned_storage_artifact");
    expect(index).toContain('disposition: "preserved_for_reconciliation"');
    expect(policy).toContain("return !dryRun && !captureCommitted");
  });

  it("keeps catalog endpoints raw and extracts only explicitly citable legal bodies", () => {
    expect(policy).toContain('content_mode: "catalog_only" | "legal_body"');
    expect(policy).toContain('endpoint_status: "active"');
    expect(index).toContain("shouldExtractCitableLegalBody(endpoint, artifact.mimeType)");
    expect(index).toContain("extraction = await extractLegalBodyText(artifact)");
    expect(index).toContain("content_mode: endpoint.content_mode");
    expect(index).toContain("citable_body: endpoint.citable_body");
    expect(policy).toMatch(
      /processingStatus === "requires_extraction"\s*&&\s*candidateVersionId !== null/,
    );
  });

  it("extracts HTML/PDF with explicit untrusted-PDF bounds and disables DOCX", () => {
    const extractionCall = index.indexOf("await extractLegalBodyText(artifact)");
    const upload = index.indexOf("await uploadArtifact(");
    const capture = index.indexOf("await captureArtifact(");

    expect(policy).toContain('throw new IngestPolicyError("source_extracted_text_too_large", 413)');
    expect(policy).not.toContain("normalized.slice(0, MAX_EXTRACTED_CHARACTERS)");
    expect(extractionCall).toBeGreaterThan(0);
    expect(upload).toBeGreaterThan(extractionCall);
    expect(capture).toBeGreaterThan(upload);
    expect(extraction).toContain('from "npm:unpdf@1.8.0"');
    expect(extraction).toContain("maxImageSize: MAX_PDF_IMAGE_PIXELS");
    expect(extraction).toContain("pdf.numPages > MAX_PDF_PAGES");
    expect(extraction).toContain('IngestPolicyError("source_pdf_open_failed", 422)');
    expect(extraction).toContain(
      'ExternalOcrPdfError("source_pdf_extraction_failed", pdf.numPages)',
    );
    expect(extraction).toContain(
      'ExternalOcrPdfError("source_pdf_text_missing", pdf.numPages)',
    );
    expect(extraction).toContain("isExternalOcrEligiblePdfFailure");
    expect(index).toContain('"external_ocr_page_limit_exceeded"');
    expect(index).toContain("!dryRun");
    expect(index).toContain('artifact.mimeType === "application/pdf"');
    expect(index).toContain("isExternalOcrEligiblePdfFailure(error)");
    expect(index).toContain("error.pageCount <= EXTERNAL_OCR_V1_MAX_PAGES");
    expect(index).toContain("? error.code");
    expect(index).toContain("extraction_blocker: extractionBlocker");
    expect(extraction).toContain("pdf.loadingTask.destroy()");
    expect(extraction).not.toContain("pdf.destroy()");
    expect(officialPdfSmoke).toContain('expectedOutcome: "extracted"');
    expect(officialPdfSmoke).toContain("expectedPages: 32");
    expect(officialPdfSmoke).toContain("LEI COMPLEMENTAR");
    expect(officialPdfSmoke).toContain('expectedOutcome: "blocked_missing_text"');
    expect(officialPdfSmoke).toContain('expectedSafeCode: "source_pdf_text_missing"');
    expect(officialPdfSmoke).toContain("observed instanceof IngestPolicyError");
    expect(officialPdfSmoke).toContain("observed.responseStatus !== 422");
    expect(policy).toContain('DOCX_DISABLED_CODE = "source_docx_disabled_edge_runtime"');
    expect(policy).toContain("item !== DOCX_MIME_TYPE");
    expect(policy).toContain("hasZipSignature(bytes)");
    expect(policy).toContain("throw new IngestPolicyError(DOCX_DISABLED_CODE, 415)");
    expect(extraction).not.toContain("mammoth");
    expect(extraction).not.toContain("docx");
    expect(extraction).not.toContain("Promise.race");
    expect(index).toContain("extraction_complete: extractedText !== null");
    expect(index).toContain("content_truncated: false");
    expect(index).toContain("extracted_char_count: extractedCharacterCount");
  });

  it("never evaluates or launches content from official documents", () => {
    expect(index).not.toMatch(/\beval\s*\(/);
    expect(index).not.toContain("new Function");
    expect(index).not.toContain("Deno.Command");
    expect(policy).toContain('redirect: "manual"');
    expect(policy).toContain("assertAllowedOfficialUrl(");
    expect(policy).toContain("hasPdfSignature(bytes)");
    expect(extraction).toContain("isEvalSupported: false");
  });
});
