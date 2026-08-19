import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(resolve(process.cwd(), path), "utf8");
const migration = read(
  "supabase/migrations/20260819055931_governed_external_knowledge_ocr.sql",
);
const edge = read("supabase/functions/ia-fiscal-knowledge-ocr/index.ts");
const policy = read("supabase/functions/ia-fiscal-knowledge-ocr/policy.ts");
const oidc = read("supabase/functions/ia-fiscal-knowledge-ocr/oidc.ts");
const config = read("supabase/config.toml");
const workflow = read(".github/workflows/knowledge-ocr.yml");
const regression = read("supabase/tests/knowledge_ocr_regression.sql");

describe("governed external knowledge OCR contract", () => {
  it("authenticates immutable GitHub identity before creating a service client", () => {
    expect(policy).toContain(
      "repo:AlmoreContabilidade@296187202/Ia-fiscal@1320619695:environment:knowledge-ocr",
    );
    expect(policy).toContain('repositoryOwnerId: "296187202"');
    expect(policy).toContain('repositoryId: "1320619695"');
    expect(policy).toContain('runner_environment: "github-hosted"');
    expect(oidc).toContain('algorithms: ["RS256"]');
    const handler = edge.slice(edge.indexOf("Deno.serve"));
    expect(handler.indexOf("authenticateGithubOidc(request)")).toBeLessThan(
      handler.indexOf("serviceClient()"),
    );
    expect(config).toMatch(
      /\[functions\.ia-fiscal-knowledge-ocr\][\s\S]*?verify_jwt = false/,
    );
    expect(migration).toContain("OCR OIDC token replay detected");
    expect(migration).toContain("gate.workflow_commit_sha = p_context ->> 'workflow_sha'");
  });

  it("keeps GitHub free of Supabase service credentials", () => {
    expect(workflow).toContain("id-token: write");
    expect(workflow).not.toMatch(/SUPABASE_SERVICE_ROLE_KEY|service_role/i);
    expect(workflow).toContain(
      "https://qvgenxcrdrqyiyozxtdt.supabase.co/functions/v1/ia-fiscal-knowledge-ocr",
    );
  });

  it("queues only preserved official PDFs inside the v1 page cap", () => {
    expect(migration).toContain("artifact.extraction_status = 'requires_extraction'");
    expect(migration).toContain("artifact.mime_type = 'application/pdf'");
    expect(migration).toContain("extraction_page_count')::integer between 1 and 120");
    expect(migration).not.toContain("application/octet-stream");
    expect(migration).toContain("external_ocr_page_limit_exceeded");
  });

  it("makes evidence and Storage artifacts append-only, including TRUNCATE", () => {
    expect(migration).toContain("legal_ocr_job_pages_append_only");
    expect(migration).toContain("legal_ocr_results_append_only");
    expect(migration).toContain("legal_ocr_oidc_requests_no_truncate");
    expect(migration).toContain("legal_ocr_results_no_truncate");
    expect(migration).toContain("legal_ocr_storage_objects_truncate_guard");
    expect(migration).toContain("legal_ocr_storage_buckets_no_truncate");
    expect(migration).toContain("unrelated legal source artifact metadata is immutable");
    expect(migration).toContain("legal source artifact OCR evidence does not match result");
  });

  it("uses narrow service-only queue RPCs and the frozen finalize signature", () => {
    expect(migration).toMatch(
      /revoke all on function public\.ia_fiscal_finalize_knowledge_ocr_job\(\s*uuid, text, jsonb, text, text, text, text, bigint, text, jsonb, jsonb\s*\)[\s\S]*?grant execute on function public\.ia_fiscal_finalize_knowledge_ocr_job\([\s\S]*?\) to service_role/,
    );
    expect(migration).toMatch(
      /revoke all on private\.legal_ocr_jobs from public, anon, authenticated, service_role/,
    );
    expect(migration).toContain("for update of job skip locked");
    expect(migration).toContain("v_job.lease_started_at + interval '2 hours'");
  });

  it("double-validates source, page, quality and locked toolchain evidence", () => {
    expect(edge).toContain("verifyPageArtifacts");
    expect(edge).toContain("assertCompletionTextHashes");
    expect(edge).toContain("assertToolchain");
    expect(migration).toContain("OCR manifest root-of-trust evidence mismatch");
    expect(migration).toContain("OCR manifest metrics do not match server-derived evidence");
    expect(migration).toContain("OCR quality gate rejected coverage or confidence");
    expect(migration).toContain("page_coverage_bps between 9000 and 10000");
    expect(migration).toContain("mean_confidence_milli between 550 and 1000");
    expect(policy).toContain("export const MAX_TOTAL_CHARACTERS = 8_000_000");
  });

  it("finalizes atomically to under_review and never publishes", () => {
    const finalize = migration.slice(
      migration.indexOf("create or replace function public.ia_fiscal_finalize_knowledge_ocr_job"),
      migration.indexOf("alter function public.ia_get_knowledge_operations_snapshot"),
    );
    expect(finalize).toContain("'under_review'");
    expect(finalize).toContain("public.ia_fiscal_stage_knowledge_sections");
    expect(finalize).toContain("'publication_status', 'not_published'");
    expect(finalize).not.toMatch(/ia_publish_legal_source_version|status\s*=\s*'published'/);
  });

  it("avoids PostgreSQL reserved words in the deterministic chunk alias", () => {
    expect(migration).toContain("part(chunk_start)");
    expect(migration).toContain("part.chunk_start");
    expect(migration).toContain("bounded_chunks.chunk_start");
    expect(migration).not.toMatch(/part\s*\(\s*offset\s*\)/i);
  });

  it("parenthesizes CASE expressions inside PL/pgSQL IF conditions", () => {
    expect(migration).toContain("or not (case");
    expect(migration).toContain("or v_word_count <> (case");
    expect(migration).not.toMatch(/or\s+not\s+case\b/i);
    expect(migration).not.toMatch(/or\s+v_word_count\s+<>\s+case\b/i);
  });

  it("makes response-loss replay exact and idempotent", () => {
    expect(migration).toContain("completion_evidence_sha256");
    expect(migration).toContain("'status', 'already_completed'");
    expect(migration).toContain("completed OCR result does not match replay evidence");
    expect(migration).toContain("failure_lease_token_sha256");
    expect(migration).toContain("'replayed', true");
    expect(migration).toContain("cannot mutate the queue again");
  });

  it("exposes honest tenant/AAL2 OCR state without claiming auto-publication", () => {
    expect(migration).toContain("aal2 authentication required");
    expect(migration).toContain("'runtime_verified', v_runtime_verified");
    expect(migration).toContain("'blocked_page_limit', v_page_limit_blocked");
    expect(migration).toContain("'above_page_limit', 'manual_review_required'");
    expect(migration).toContain(
      "'has_attention', v_dead_letter > 0 or v_page_limit_blocked > 0",
    );
    expect(migration).toContain("'candidate_status', 'under_review'");
    expect(migration).toContain("'auto_publish', false");
  });

  it("ships a rollback-only SQL regression for the production gate", () => {
    expect(regression).toMatch(/^-- Transactional regression/);
    expect(regression).toContain("begin;");
    expect(regression).toContain("rollback;");
    expect(regression).toContain("OCR claim ran without both attested runtime gates");
    expect(regression).toContain("OCR queue crossed the 120-page or blocker boundary");
    expect(regression).toContain("raw official artifact metadata was mutable before OCR");
    expect(regression).toContain("OCR Storage artifact was mutable");
    expect(regression).toContain("legal candidate or publication");
  });
});
