import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(resolve(process.cwd(), path), "utf8");
const migrationNames = readdirSync(resolve(process.cwd(), "supabase/migrations")).filter((name) =>
  name.endsWith("_make_portuguese_lexical_search_canonical.sql"),
);
if (migrationNames.length !== 1) {
  throw new Error(`expected one canonical PT-BR lexical migration, found ${migrationNames.length}`);
}
const [migrationName] = migrationNames;
const migration = read(`supabase/migrations/${migrationName}`);
const searchEdge = read("supabase/functions/ia-fiscal-knowledge-search/index.ts");
const embedEdge = read("supabase/functions/ia-fiscal-knowledge-embed/index.ts");
const searchPolicy = read("supabase/functions/ia-fiscal-knowledge-search/policy.ts");
const activation = read("supabase/release/activate_knowledge_phase2_schedule.sql");
const rollback = read("supabase/release/rollback_portuguese_lexical_search.sql");
const regression = read("supabase/tests/knowledge_lexical_ptbr_regression.sql");
const excerptBody = migration.slice(
  migration.indexOf("create or replace function private.portuguese_lexical_literal_excerpt("),
  migration.indexOf("alter function public.ia_fiscal_hybrid_search_legal_knowledge("),
);
const searchBody = migration.slice(
  migration.indexOf("create or replace function public.ia_fiscal_hybrid_search_legal_knowledge("),
  migration.indexOf("alter function private.ia_fiscal_dispatch_due_knowledge_work(integer)"),
);
const dispatcherBody = migration.slice(
  migration.indexOf("create or replace function private.ia_fiscal_dispatch_due_knowledge_work("),
  migration.indexOf("alter function public.ia_get_knowledge_operations_snapshot(uuid)"),
);
const snapshotBody = migration.slice(
  migration.indexOf("create or replace function public.ia_get_knowledge_operations_snapshot("),
);

describe("canonical Portuguese lexical legal search", () => {
  it("requires a quiescent retired-model runtime before cutover", () => {
    expect(migration).toContain("revoke the current knowledge runtime gate before lexical cutover");
    expect(migration).toContain(
      "disable every knowledge automation setting before lexical cutover",
    );
    expect(migration).toContain("wait for every retired semantic lease before lexical cutover");
    expect(migration).toContain("wait for every retired semantic dispatch before lexical cutover");
  });

  it("never calls an embedding or generative model in the search path", () => {
    expect(searchEdge).toContain("p_query_embedding: null");
    expect(searchEdge).not.toContain("Supabase.ai.Session");
    expect(searchEdge).not.toContain("session.run");
    expect(searchEdge).not.toMatch(/openai|anthropic|generateText/i);
    expect(searchBody).not.toContain("private.legal_embeddings");
    expect(searchBody).not.toContain("OPERATOR(extensions.<=>)");
  });

  it("uses the same accent normalization and Portuguese configuration on both sides", () => {
    expect(migration).toContain("private.normalize_portuguese_lexical_text(content_text)");
    expect(searchBody).toContain("private.normalize_portuguese_lexical_text(v_query)");
    expect(searchBody).toContain("pg_catalog.websearch_to_tsquery(");
    expect(searchBody).toContain("pg_catalog.querytree(v_tsquery)");
    expect(searchBody).toContain("query must contain positive searchable Portuguese terms");
    expect(searchBody).toContain("'pg_catalog.portuguese'::pg_catalog.regconfig");
    expect(searchBody).toContain(") @@ v_presence_tsquery");
    expect(searchBody).toContain("windowed.window_vector @@ v_tsquery");
    expect(searchBody).toContain("pg_catalog.ts_rank_cd(");
  });

  it("uses the integral GIN only for presence before bounded-window ranking", () => {
    expect(migration).toMatch(
      /create index legal_sections_search_portuguese_idx[\s\S]*using gin[\s\S]*normalize_portuguese_lexical_text\(content_text\)/,
    );
    expect(searchBody).toContain("with lexical_candidates as materialized");
    expect(searchBody).toContain("current_candidates as materialized");
    expect(searchBody).toContain("window_vectors as materialized");
    expect(searchBody).toContain("window_matches as materialized");
    expect(searchBody).toContain("best_windows as materialized");
    expect(searchBody).toContain("ranked_windows as materialized");
    expect(searchBody).toContain("from public.legal_sections section");
    expect(searchBody).toContain("where section.municipality_id = p_municipality_id");
    expect(searchBody.indexOf(") @@ v_presence_tsquery")).toBeGreaterThanOrEqual(0);
    expect(searchBody.indexOf(") @@ v_presence_tsquery")).toBeLessThan(
      searchBody.indexOf("cross join lateral pg_catalog.generate_series("),
    );
    expect(searchBody.indexOf("private.legal_source_version_is_current_citable(")).toBeLessThan(
      searchBody.indexOf("cross join lateral pg_catalog.generate_series("),
    );
    expect(searchBody.indexOf("limit v_limit")).toBeLessThan(
      searchBody.indexOf("from private.legal_source_artifact_versions mapping"),
    );
    expect(searchBody).not.toContain("limit 100");
  });

  it("rejects OR and NOT before candidate discovery", () => {
    const candidateDiscovery = searchBody.indexOf("with lexical_candidates as materialized");
    expect(searchBody).toContain("position('|' in v_parsed_query) > 0");
    expect(searchBody).toContain("position('!' in v_parsed_query) > 0");
    expect(searchBody).toContain(
      "OR queries are not supported by the calibrated Portuguese lexical release",
    );
    expect(searchBody).toContain(
      "NOT queries are not supported by the calibrated Portuguese lexical release",
    );
    expect(searchBody.indexOf("OR queries are not supported")).toBeLessThan(candidateDiscovery);
    expect(searchBody.indexOf("NOT queries are not supported")).toBeLessThan(candidateDiscovery);
    expect(regression).toContain("imposto OR taxa");
    expect(regression).toContain("OR quasar OR nebulosa OR asteroide");
    expect(regression).toContain("imposto -servicos");
    expect(regression).toContain("v_adversarial_lexeme_count <> 12");
  });

  it("ranks every 12k/6k literal window without trusting saturated section positions", () => {
    expect(searchBody).toContain("pg_catalog.generate_series(");
    expect(searchBody).toContain("candidate.content_text from window_start.start_char for 12000");
    expect(searchBody).toContain("6000");
    expect(searchBody).toContain("v_presence_tsquery := pg_catalog.regexp_replace(");
    expect(searchBody).toContain("'(<->|<[0-9]+>)'");
    expect(searchBody.indexOf("pg_catalog.ts_rank_cd(")).toBeGreaterThan(
      searchBody.indexOf("window_matches as materialized"),
    );
    expect(regression).toContain("repeat('termo ', 17000)");
    expect(regression).toContain("bounded windows did not neutralize the 16383-position inflation");
    expect(regression).toContain("presence/window split did not recover a deep phrase");
  });

  it("maps the best cover to a literal excerpt whose full query remains in the answer", () => {
    expect(searchBody).toContain("private.portuguese_lexical_literal_excerpt(");
    expect(searchBody).toContain("ranked.window_content_text");
    expect(searchBody).toContain("ranked.content_text");
    expect(searchBody).toContain(") >= v_min_confidence");
    expect(excerptBody).toContain("MaxWords=80");
    expect(excerptBody).toContain("MaxFragments=1");
    expect(excerptBody).toContain("v_plain_fragment");
    expect(excerptBody).toContain("v_fragment_start");
    expect(excerptBody).toContain("p_require_answer_cover");
    expect(excerptBody).toContain("position(v_window_text in v_official_text) = 0");
    expect(excerptBody).toContain("position(v_excerpt in v_official_text) = 0");
    expect(excerptBody).toContain("substring(v_window_text from v_excerpt_start for 2000)");
    expect(excerptBody).toContain(
      "private.normalize_portuguese_lexical_text(left(v_excerpt, 1500))",
    );
    expect(regression).toContain("'imposto ' ||");
    expect(regression).toContain("repeat('administracao ', 300)");
    expect(regression).toContain("'and_cover', 'imposto servicos'");
    expect(regression).toContain("'phrase_cover', '\"imposto servicos\"'");
    expect(regression).toContain("answer used an isolated early lexeme instead of the best");
    expect(regression).toContain("weak citation fixture unexpectedly crossed the answer boundary");
    expect(regression).toContain("weak distant citation did not remain literal and non-answering");
    expect(regression).toContain("position(v_excerpt in v_deep_phrase_document) = 0");
    expect(regression).toContain("position('imposto sobre serviços' in v_answer) = 0");
  });

  it("searches only an integral artifact-backed section, never inferred chunk coverage", () => {
    expect(searchBody).toContain("section.content_sha256 = version.content_sha256");
    expect(searchBody).toContain("section.content_text = version.content_text");
    expect(searchBody).toContain("private.legal_source_version_is_current_citable(");
    expect(searchBody).toContain("from private.legal_source_artifact_versions mapping");
    expect(searchBody).toContain("artifact.extraction_status = 'completed'");
    expect(searchBody).toContain("artifact.metadata ->> 'content_truncated' = 'false'");
    expect(searchBody).toContain("fetch_run.status = 'completed_changed'");
    expect(searchBody).not.toContain("private.legal_chunks");
    expect(snapshotBody).toContain("count(distinct version.id)::integer");
    expect(snapshotBody).toContain("section.content_sha256 = version.content_sha256");
    expect(snapshotBody).toContain("section.content_text = version.content_text");
    expect(snapshotBody).toContain("index_state.indisvalid and index_state.indisready");
    expect(snapshotBody).toContain("'lexical_full_content', v_lexical_full_content");
  });

  it("reports the unsupported semantic layer without deleting historical evidence", () => {
    expect(migration).toContain("'semantic_status', 'unsupported_language'");
    expect(migration).toContain("'semantic_usable_chunks', 0");
    expect(migration).toContain("'semantic_historical_chunks'");
    expect(migration).toContain("'lexical_full_content', v_lexical_full_content");
    expect(migration).toContain(
      "multilingual_model_with_explicit_token_contract_and_new_release_gate",
    );
    expect(migration).not.toMatch(/delete\s+from\s+private\.legal_embeddings/i);
    expect(migration).not.toMatch(/update\s+private\.legal_embeddings/i);
    expect(migration).not.toMatch(/update\s+public\.legal_source_versions/i);
    expect(migration).not.toMatch(/insert\s+into\s+public\.legal_source_versions/i);
    expect(migration).not.toMatch(/status\s*=\s*'published'/i);
  });

  it("terminalizes old jobs with compensating state and preserves old functions revoked", () => {
    expect(migration).toContain("job.status in ('queued', 'processing', 'failed', 'dead_letter')");
    expect(migration).toContain("'semantic_model_language_unsupported'");
    expect(migration).toContain("'previous_status', previous.previous_status");
    expect(migration).toContain("'previous_safe_error_code', previous.previous_safe_error_code");
    for (const preservedFunction of [
      "private.enqueue_legal_embedding_job_pre_lexical_ptbr()",
      "public.ia_fiscal_claim_legal_embedding_jobs_pre_lexical_ptbr(integer)",
      "public.ia_fiscal_hybrid_search_legal_knowledge_pre_lexical_ptbr(",
      "private.ia_fiscal_dispatch_due_knowledge_work_pre_lexical_ptbr(integer)",
      "public.ia_get_knowledge_operations_snapshot_pre_lexical_ptbr(uuid)",
    ]) {
      expect(migration).toContain(`revoke all on function ${preservedFunction}`);
    }
    expect(migration).toContain("if not private.is_service_role() then");
    expect(migration).toContain("private.lock_current_knowledge_runtime_gate_id()");
    expect(migration).toMatch(
      /create or replace function public\.ia_fiscal_claim_legal_embedding_jobs[\s\S]*future multilingual model[\s\S]*return;/i,
    );
    expect(rollback).toContain("no knowledge automation setting may be enabled");
    expect(rollback).toContain("revoke the current knowledge runtime gate before lexical rollback");
    expect(rollback).toContain("previous_status");
    expect(rollback).toContain("semantic_retirement_rollback_processing_requeued");
    expect(rollback).toContain("_pre_lexical_ptbr");
  });

  it("keeps activation, scheduler and Edge embedding paths inert", () => {
    expect(activation).not.toMatch(/insert\s+into\s+private\.legal_embedding_jobs/i);
    expect(activation).not.toContain("phase2_activation_backfill");
    expect(dispatcherBody).not.toContain("private.legal_embedding_jobs");
    expect(dispatcherBody).not.toContain("/functions/v1/ia-fiscal-knowledge-embed");
    expect(dispatcherBody).not.toMatch(/scope\s*=\s*'embed'|'embed'\s*,/);
    expect(dispatcherBody).toContain("'embedding_dispatch', false");
    expect(embedEdge).toContain('event: "knowledge_embedding_retired_noop"');
    expect(embedEdge).not.toContain("Supabase.ai");
    expect(embedEdge).not.toContain("ia_fiscal_claim_legal_embedding_jobs");
    expect(embedEdge).not.toContain("ia_fiscal_complete_legal_embedding_job");
    expect(embedEdge).not.toContain("ia_fiscal_fail_legal_embedding_job");
  });

  it("calibrates a compact PT-BR cover above and a weak cover below the answer gate", () => {
    expect(migration).toContain("private.knowledge_portuguese_lexical_confidence(");
    expect(searchBody).toContain("v_min_confidence constant double precision := 0.35");
    expect(searchBody).toContain("v_confidence >= v_min_confidence");
    expect(regression).toContain("strong PT-BR match did not clear the answer boundary");
    expect(regression).toContain("weak PT-BR match crossed the answer boundary");
  });

  it("keeps the public envelope compatible while disclosing the canonical mode", () => {
    expect(searchPolicy).toContain('SEARCH_CONTRACT_VERSION = "knowledge-search-v1"');
    expect(searchBody).toContain("'retrieval_mode', 'lexical_portuguese'");
    expect(searchBody).toContain("'lexical_language', 'pt-BR'");
    expect(searchBody).toContain("'semantic_status', 'unsupported_language'");
    expect(searchBody).toContain("'citations', v_citations");
  });
});
