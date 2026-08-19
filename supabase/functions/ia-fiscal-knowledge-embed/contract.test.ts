import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const source = readFileSync(resolve(process.cwd(), "supabase/functions/ia-fiscal-knowledge-embed/index.ts"), "utf8");
const config = readFileSync(resolve(process.cwd(), "supabase/config.toml"), "utf8");

describe("knowledge embedding Edge contract", () => {
  it("uses Vault scheduler anti-replay with gateway JWT disabled", () => {
    expect(config).toMatch(
      /\[functions\.ia-fiscal-knowledge-embed\]\s*(?:#[^\n]*\s*)*verify_jwt\s*=\s*false/,
    );
    expect(source).toContain('assertKnowledgeSchedulerRequest(request, client, "embed")');
    expect(source).not.toContain("SUPABASE_ANON_KEY");
  });

  it("preserves the authenticated HTTP contract as a retired-model no-op", () => {
    expect(source).toContain('event: "knowledge_embedding_retired_noop"');
    expect(source).toContain('status: "retired_noop"');
    expect(source).toContain('semantic_status: "unsupported_language"');
    expect(source).toContain("claimed: 0");
    expect(source).toContain("completed: 0");
    expect(source).toContain("failed: 0");
  });

  it("cannot call Supabase AI or mutate a retired embedding job", () => {
    expect(source).not.toContain("Supabase.ai");
    expect(source).not.toContain("session.run");
    expect(source).not.toContain("ia_fiscal_claim_legal_embedding_jobs");
    expect(source).not.toContain("ia_fiscal_complete_legal_embedding_job");
    expect(source).not.toContain("ia_fiscal_fail_legal_embedding_job");
    expect(source).not.toMatch(/embedding_generation|p_embedding|mean_pool|normalize:/);
  });
});
