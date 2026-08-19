import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const source = readFileSync(resolve(process.cwd(), "supabase/functions/ia-fiscal-knowledge-search/index.ts"), "utf8");
const migrationNames = readdirSync(resolve(process.cwd(), "supabase/migrations")).filter((name) =>
  name.endsWith("_make_portuguese_lexical_search_canonical.sql")
);
if (migrationNames.length !== 1) {
  throw new Error(`expected one canonical PT-BR lexical migration, found ${migrationNames.length}`);
}
const [migrationName] = migrationNames;
const migration = readFileSync(
  resolve(process.cwd(), "supabase/migrations", migrationName),
  "utf8",
);
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

  it("uses complete PT-BR lexical retrieval without any model inference", () => {
    expect(source).not.toContain("Supabase.ai.Session");
    expect(source).not.toContain("session.run");
    expect(source).toContain("p_query_embedding: null");
    expect(source).toContain('"ia_fiscal_hybrid_search_legal_knowledge"');
    expect(source).not.toMatch(/openai|anthropic|generateText/i);
    expect(migration).toContain("with lexical_candidates as materialized");
    expect(migration).toContain("section.municipality_id = p_municipality_id");
    expect(migration).toContain("section.content_sha256 = version.content_sha256");
    expect(migration).toContain("section.content_text = version.content_text");
    expect(migration).toContain("private.legal_source_version_is_current_citable(");
    expect(migration).toContain(") @@ v_presence_tsquery");
    expect(migration).toContain("windowed.window_vector @@ v_tsquery");
    expect(migration).toContain("window_vectors as materialized");
    expect(migration).toContain("candidate.content_text from window_start.start_char for 12000");
    expect(migration).toContain("private.portuguese_lexical_literal_excerpt(");
    expect(migration).toContain("'retrieval_mode', 'lexical_portuguese'");
    expect(migration).toContain("'semantic_status', 'unsupported_language'");
    expect(migration).not.toContain("join private.legal_embeddings embedding\n+      on embedding.municipality_id = chunk.municipality_id");
  });

  it("normalizes PT-BR accents and preserves stemming and compound-query semantics", () => {
    expect(migration).toContain("private.normalize_portuguese_lexical_text(content_text)");
    expect(migration).toContain("private.normalize_portuguese_lexical_text(v_query)");
    expect(migration).toContain("pg_catalog.websearch_to_tsquery(");
    expect(migration).toContain("'pg_catalog.portuguese'::pg_catalog.regconfig");
    expect(migration).toContain("pg_catalog.ts_rank_cd(");
  });

  it("fails closed for unsupported boolean semantics before retrieval", () => {
    expect(migration).toContain("position('|' in v_parsed_query) > 0");
    expect(migration).toContain("position('!' in v_parsed_query) > 0");
    expect(migration).toContain("OR queries are not supported");
    expect(migration).toContain("NOT queries are not supported");
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
