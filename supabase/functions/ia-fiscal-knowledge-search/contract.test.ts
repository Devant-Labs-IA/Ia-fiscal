import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const source = readFileSync(resolve(process.cwd(), "supabase/functions/ia-fiscal-knowledge-search/index.ts"), "utf8");
const migration = readFileSync(resolve(process.cwd(), "supabase/migrations/20260819040404_knowledge_phase2_core.sql"), "utf8");
const config = readFileSync(resolve(process.cwd(), "supabase/config.toml"), "utf8");

describe("knowledge search Edge contract", () => {
  it("preserves user JWT, AAL2 and gateway verification", () => {
    expect(config).toMatch(
      /\[functions\.ia-fiscal-knowledge-search\]\s*(?:#[^\n]*\s*)*verify_jwt\s*=\s*true/,
    );
    expect(source).toContain("Authorization: authorization");
    expect(source).toContain('claimsData.claims.aal !== "aal2"');
    expect(source).not.toContain("SUPABASE_SERVICE_ROLE_KEY");
  });

  it("uses gte-small hybrid retrieval and lexical fallback without generative answers", () => {
    expect(source).toContain("new Supabase.ai.Session(SEARCH_EMBEDDING_MODEL)");
    expect(source).toContain('queryEmbedding = null');
    expect(source).toContain('"ia_fiscal_hybrid_search_legal_knowledge"');
    expect(source).not.toMatch(/openai|anthropic|generateText/i);
    expect(migration).toContain("with eligible as materialized");
    expect(migration).toContain("chunk.municipality_id = p_municipality_id");
    expect(migration).toContain("version.status = 'published'");
  });

  it("keeps the correlation envelope and emits a metadata-only success audit", () => {
    expect(source).toContain("correlation_id: correlationId");
    expect(source).toContain('event: "knowledge_search_succeeded"');
    const successLog = source.match(
      /console\.info\(JSON\.stringify\(\{\s*event: "knowledge_search_succeeded",[\s\S]*?\}\)\);/,
    )?.[0] ?? "";
    expect(successLog).toContain("municipality_id: input.municipalityId");
    expect(successLog).toContain("citation_count: citationCount");
    expect(successLog).not.toMatch(/(?:query|excerpt|answer):/);
  });
});
