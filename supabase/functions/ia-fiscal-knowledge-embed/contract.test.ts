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

  it("uses only the pinned built-in embedding model and governed job RPCs", () => {
    expect(source).toContain("new Supabase.ai.Session(EMBEDDING_MODEL)");
    expect(source).toContain('mean_pool: true');
    expect(source).toContain('normalize: true');
    expect(source).toContain('"ia_fiscal_claim_legal_embedding_jobs"');
    expect(source).toContain('"ia_fiscal_complete_legal_embedding_job"');
    expect(source).toContain('"ia_fiscal_fail_legal_embedding_job"');
    expect(source).not.toContain("content: job.content_text");
    expect(source).not.toContain("console.log(job.content_text");
  });
});
