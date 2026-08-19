import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const read = (path: string) => readFileSync(resolve(process.cwd(), path), "utf8");
const core = read("supabase/migrations/20260819040404_knowledge_phase2_core.sql");
const catalog = read("supabase/migrations/20260819042149_knowledge_phase2_catalog_coverage.sql");
const activation = read("supabase/release/activate_knowledge_phase2_schedule.sql");
const postgresRuntimeFixes = [
  read("supabase/migrations/20260819041131_fix_knowledge_embedding_claim_event_alias.sql"),
  read("supabase/migrations/20260819041252_fix_knowledge_embedding_claim_event_returning.sql"),
  read("supabase/migrations/20260819041525_fix_knowledge_halfvec_operator_schema.sql"),
];
const rawCaptureIdentityFix = read(
  "supabase/migrations/20260819063856_fix_capture_v2_raw_ocr_identity.sql",
);
const regression = read("supabase/tests/knowledge_phase2_regression.sql");
const config = read("supabase/config.toml");
const searchEdge = read("supabase/functions/ia-fiscal-knowledge-search/index.ts");
const ingestEdge = read("supabase/functions/ia-fiscal-knowledge-ingest/index.ts");
const ingestPolicy = read("supabase/functions/ia-fiscal-knowledge-ingest/policy.ts");
const ingestExtraction = read("supabase/functions/ia-fiscal-knowledge-ingest/extraction.ts");

describe("Segundo Cérebro phase 2 database contract", () => {
  it("keeps raw official evidence pre-candidate until governed extraction", () => {
    expect(rawCaptureIdentityFix).toContain(
      "Raw catalog/PDF captures legitimately create an auditable change set",
    );
    expect(rawCaptureIdentityFix).toContain(
      "elsif v_change_set_id is not null and v_candidate_version_id is null",
    );
    expect(regression).toContain(
      "raw capture did not preserve its governed pre-extraction identity",
    );
  });

  it("keeps the legal reviewer capability narrow and leaves global role helpers untouched", () => {
    expect(core).not.toMatch(
      /create\s+or\s+replace\s+function\s+private\.(?:has_municipality_role|current_municipality_membership_id)/i,
    );
    expect(core).toContain("private.current_legal_reviewer_membership_id");
    expect(core).toContain(
      "v_target.role not in ('municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer')",
    );
    expect(core).not.toContain("'support_readonly') then");
    expect(core).toContain("self-grant of legal reviewer capability is prohibited");
  });

  it("uses tenant-explicit mutation overloads and revokes their legacy signatures", () => {
    expect(core).toContain("p_expected_municipality_id uuid");
    expect(core).toContain("tenant-bound legal change not found");
    expect(core).toContain("tenant-bound legal version not found");
    expect(core).toContain("tenant-bound knowledge article not found");
    expect(core).toContain("tenant-bound learning candidate not found");
    expect(core).toMatch(
      /revoke all on function public\.ia_review_knowledge_candidate\(uuid, text, text, text\)[\s\S]*grant execute on function public\.ia_review_knowledge_candidate\(uuid, uuid, text, text, text\)/,
    );
    expect(core).toContain("p_confirmation <> 'ENVIAR PARA REVISÃO'");
    expect(core.match(/v_invalid_count integer;/g)).toHaveLength(1);
  });

  it("protects reviewer administration and paginated evidence with explicit ACLs", () => {
    expect(core).toMatch(
      /revoke all on function public\.ia_list_legal_reviewer_capabilities\(uuid\)[\s\S]*grant execute on function public\.ia_list_legal_reviewer_capabilities\(uuid\)\s+to authenticated/,
    );
    expect(core).toMatch(
      /revoke all on function public\.ia_get_legal_source_change_evidence\(\s*uuid, uuid, integer, integer, integer, integer, integer, integer\s*\)[\s\S]*grant execute on function public\.ia_get_legal_source_change_evidence\(\s*uuid, uuid, integer, integer, integer, integer, integer, integer\s*\) to authenticated/,
    );
    expect(core).not.toMatch(
      /grant execute on function public\.ia_get_legal_source_change_evidence\(\s*uuid, uuid, integer, integer, integer, integer\s*\) to authenticated/,
    );
    expect(core).toContain("change_items_full_sha256");
    expect(core).toContain("legal_reviewer_capability_events_once_uq");
    expect(core).toContain("private.expire_legal_reviewer_capabilities");
    expect(core).toContain("'system'");
    expect(core).toMatch(
      /revoke all on function private\.expire_legal_reviewer_capabilities\(integer, uuid, uuid\)/,
    );
    expect(regression).toContain("expired grant did not emit exactly one append-only event");
    expect(regression).toContain("elapsed grant was not materialized before regrant");
  });

  it("gates initial snapshots and schedules on the attested runtime", () => {
    expect(core).toContain("private.knowledge_runtime_is_verified()");
    expect(core).toContain("'last_run_status', coalesce(setting.last_run_status, 'never_run')");
    expect(core).toContain("'runtime_blocker'");
    expect(core).toContain("'timezone', setting.timezone");
    expect(core).not.toContain("cron.schedule(");
    expect(core).toContain("knowledge_runtime_current_gates");
    expect(core).toContain("current_knowledge_runtime_gate_id()");
    expect(core).toContain("ingest_release_fingerprint");
    expect(core).toContain("embed_release_fingerprint");
    expect(core).toContain("search_release_fingerprint");
    expect(core).toContain("ia_fiscal_revoke_knowledge_runtime_gate");
    expect(activation).toContain("if not private.knowledge_runtime_is_verified() then");
    expect(activation).toContain("phase2_activation_backfill");
    expect(activation).toContain("on conflict (");
    expect(activation).toContain("cron.schedule(");
    expect(activation).toContain("municipality.slug in ('cordeiropolis-sp', 'araras-sp')");
    expect(activation).toContain("('cordeiropolis-sp'::text, 'active'::text)");
    expect(activation).toContain("('araras-sp'::text, 'homologation'::text)");
    expect(activation).toContain("'municipality_status', target.status");
    expect(activation).toContain("'scope', 'internal_knowledge_refresh_only'");
    expect(activation).toContain("count(distinct event.municipality_id)");
    expect(activation).toContain(
      "release activation event did not retain municipality readiness status",
    );
    expect(activation).toContain("endpoint.content_mode = 'legal_body'");
    expect(activation).toContain("endpoint.content_mode = 'catalog_only'");
    expect(activation).toContain("phase2_release_enabled_official_refresh");
    expect(activation).toContain("'client_communication_enabled', false");
    expect(activation).toContain("private.current_knowledge_runtime_gate_id() as id");
    expect(activation).toContain(
      "a non-target municipality already has knowledge automation enabled",
    );
    expect(activation).toContain("join target on target.id = chunk.municipality_id");
    expect(core).toContain("knowledge_schedule_activation_events");
    expect(core).toContain("p_confirmation <> (case when p_enabled");
    expect(core).not.toContain("p_confirmation <> case when p_enabled");
  });

  it("leases scheduler work fairly and limits indexed coverage to eligible law", () => {
    expect(core).toContain("knowledge_scheduler_dispatch_events");
    expect(core).toContain("net._http_response");
    expect(core).toContain("ia_fiscal_reconcile_knowledge_scheduler_dispatches");
    expect(core).toContain(
      "lease_expires_at timestamptz not null default (now() + interval '2 minutes')",
    );
    expect(core).toContain("max(dispatch.created_at) as pending_dispatch_at");
    expect(core).toContain("max(fetch_run.completed_at) as last_completed_fetch_at");
    expect(core).toContain("pending_dispatch.pending_dispatch_at is null");
    expect(core).toContain("'retry_scheduled'");
    expect(core).toContain("'circuit_opened'");
    expect(core).toContain("scheduler_embed_batch_partial_failure");
    expect(core).toContain("partition by job.municipality_id");
    expect(core).toMatch(
      /events as \([\s\S]*insert into private\.legal_embedding_job_events as claimed_event[\s\S]*returning claimed_event\.job_id/,
    );
    expect(core).not.toMatch(/returning job_id\b/);
    expect(core).toContain("legal_embedding_claim_cursors");
    expect(core).toContain("last_municipality_id");
    expect(core).toContain("tenant_wrap");
    expect(core).toMatch(
      /ia_fiscal_claim_legal_embedding_jobs[\s\S]*lock_current_knowledge_runtime_gate_id\(\)[\s\S]*join private\.knowledge_automation_settings setting[\s\S]*setting\.enabled/,
    );
    expect(core).toMatch(
      /ia_fiscal_dispatch_due_knowledge_work[\s\S]*lock_current_knowledge_runtime_gate_id\(\)[\s\S]*ia_fiscal_reconcile_knowledge_scheduler_dispatches/,
    );
    expect(core).toMatch(
      /ia_fiscal_hybrid_search_legal_knowledge[\s\S]*lock_current_knowledge_runtime_gate_id\(\)/,
    );
    expect(core).toContain("'status', 'runtime_not_verified'");
    expect(core).toContain("+ endpoint.poll_interval <= now()");
    expect(core).toContain("for update skip locked");
    expect(
      core.match(/recent_failure\.status in \('failed', 'blocked'\)/g)?.length,
    ).toBeGreaterThanOrEqual(1);
    expect(core).toMatch(
      /'indexed_sections'[\s\S]*private\.legal_source_version_is_current_citable/,
    );
    expect(core).toMatch(
      /with eligible as materialized[\s\S]*private\.legal_source_version_is_current_citable/,
    );
    expect(regression).toContain("pg_net response was not reconciled into one retry event");
    expect(regression).toContain("HTTP 207 embed response bypassed retry and breaker accounting");
    expect(regression).toContain("disabled third tenant advanced in the embedding queue");
    expect(core).toMatch(
      /legal_source_version_is_current_citable[\s\S]*legal_source_artifact_versions[\s\S]*join storage\.objects object[\s\S]*fetch_run\.status = 'completed_changed'/,
    );
    expect(core).not.toMatch(/legal_source_fetch_runs\s+fetch\b/);
    expect(regression).toContain("legacy published version without artifact became citable");
    expect(regression).toContain("hybrid search ran with a revoked runtime gate");
    expect(regression).toContain("hybrid search ran with an expired runtime gate");
    expect(core.match(/not private\.legal_source_version_is_current_citable\(/g)).toHaveLength(2);
    expect(regression).toContain(
      "article review accepted a legacy citation without artifact evidence",
    );
    expect(regression).toContain(
      "article publication accepted a legacy citation without artifact evidence",
    );
  });

  it("releases an answer only above the calibrated absolute relevance boundary", () => {
    expect(core).toContain("v_min_confidence constant double precision := 0.35");
    expect(core.match(/OPERATOR\(extensions\.<=>\)/g)).toHaveLength(3);
    expect(core).not.toMatch(/embedding\s*<=>/);
    expect(core).toContain("private.knowledge_retrieval_confidence");
    expect(core).toContain("v_confidence >= v_min_confidence");
    expect(core).toContain("jsonb_build_array('insufficient_relevance')");
    expect(regression).toContain("low-relevance retrieval crossed the answer boundary");
  });

  it("audits successful searches by correlation code without logging query text or legal excerpts", () => {
    expect(searchEdge).toContain('event: "knowledge_search_succeeded"');
    expect(searchEdge).toContain("correlation_id: correlationId");
    expect(searchEdge).toContain("municipality_id: input.municipalityId");
    expect(searchEdge).toContain("citation_count: citationCount");
    expect(searchEdge).toContain("duration_ms:");
    const successLog =
      searchEdge.match(
        /console\.info\(JSON\.stringify\(\{\s*event: "knowledge_search_succeeded",[\s\S]*?\}\)\);/,
      )?.[0] ?? "";
    expect(successLog).not.toMatch(/(?:query|excerpt|answer):/);
  });

  it("ships a transactional runtime regression for the high-risk contracts", () => {
    expect(regression).toContain("rollback;");
    expect(regression).toContain("narrow capability aliased has_municipality_role");
    expect(regression).toContain("scheduler repeated an endpoint or starved the second batch");
    expect(regression).toContain("change-item evidence pagination/hash contract failed");
    expect(regression).toContain("canonical dedupe depended on authority spelling");
    expect(regression).toContain("an unvalidated discovery displaced the last-known-good body");
    expect(regression).toContain("real 503 fetch did not update catalog health");
    expect(regression).toContain("search answered from non-published evidence");
    expect(regression).toContain("artifact retry was not exactly idempotent");
    expect(regression).toContain("correlation replay changed the atomic capture response");
    expect(regression).toContain("rollback/failure audit left partial or duplicate evidence");
    expect(regression).toMatch(
      /\$atomic_capture\$;\s*reset role;\s*do \$atomic_capture_assertions\$/,
    );
    expect(regression).toMatch(
      /do \$legacy_uncaptured_fixture\$[\s\S]*session_replication_role = replica[\s\S]*insert into public\.legal_source_versions[\s\S]*insert into public\.legal_sections[\s\S]*insert into private\.legal_chunks[\s\S]*session_replication_role = origin/,
    );
  });

  it("keeps private inspections outside restricted role blocks", () => {
    let restrictedRole: string | null = null;
    const violations: string[] = [];

    regression.split("\n").forEach((line, index) => {
      const roleMatch = line.match(/^set local role (authenticated|service_role);$/);
      if (roleMatch) restrictedRole = roleMatch[1];
      if (/^reset role;$/.test(line)) restrictedRole = null;
      if (restrictedRole && /\bprivate\./.test(line)) {
        violations.push(`${index + 1}:${restrictedRole}:${line.trim()}`);
      }
    });

    expect(violations).toEqual([]);
  });

  it("initializes every regression-scoped setting before its first read", () => {
    const settingNames = [...regression.matchAll(/current_setting\('(qa\.[^']+)'\)/g)].map(
      (match) => match[1],
    );

    for (const settingName of new Set(settingNames)) {
      const firstRead = regression.indexOf(`current_setting('${settingName}')`);
      const escapedSettingName = settingName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const firstWrite = regression.search(
        new RegExp(`set_config\\s*\\(\\s*'${escapedSettingName}'`),
      );

      expect(firstWrite, `${settingName} is never initialized`).toBeGreaterThanOrEqual(0);
      expect(firstWrite, `${settingName} is read before initialization`).toBeLessThan(firstRead);
    }
  });

  it("captures and stages exactly once through the atomic service-only v2 RPC", () => {
    expect(ingestEdge).toContain('const CAPTURE_RPC = "ia_fiscal_capture_knowledge_source_v2"');
    expect(ingestEdge).not.toContain("await stageIntegralSection(");
    expect(core).toContain("defer-for-capture-v2");
    expect(core).toContain("private.knowledge_staging_matches_payload");
    expect(core).toMatch(
      /revoke all on function public\.ia_fiscal_capture_knowledge_source_v2\([\s\S]*?\) from public, anon, authenticated, service_role;[\s\S]*?grant execute on function public\.ia_fiscal_capture_knowledge_source_v2\([\s\S]*?\) to service_role;/,
    );
    expect(core).toMatch(
      /revoke all on function public\.ia_fiscal_stage_knowledge_sections_legacy_impl\(uuid, jsonb\)[\s\S]*?from public, anon, authenticated, service_role;/,
    );
    expect(core).toMatch(
      /revoke all on function public\.ia_fiscal_capture_knowledge_source\([\s\S]*?\) from public, anon, authenticated, service_role;/,
    );
    expect(ingestEdge.indexOf("return publicCaptureResult(data);")).toBeGreaterThan(
      ingestEdge.indexOf("onRpcCommitted();"),
    );
    expect(ingestEdge).toContain("shouldAppendFailedFetchRun(dryRun, captureCommitted)");
    expect(ingestEdge).toContain("captureCommitted = true");
    expect(ingestEdge).toContain("orphaned_storage_artifact");
    expect(ingestPolicy).toContain("return !dryRun && !captureCommitted");
  });

  it("disables DOCX before parsing because Edge workers cannot terminate parser work", () => {
    expect(ingestPolicy).toContain('DOCX_DISABLED_CODE = "source_docx_disabled_edge_runtime"');
    expect(ingestPolicy).toContain("item !== DOCX_MIME_TYPE");
    expect(ingestPolicy).toContain('await response.body?.cancel("source_mime_rejected")');
    expect(ingestPolicy).toContain("hasZipSignature(bytes)");
    expect(ingestExtraction).not.toContain("mammoth");
    expect(ingestExtraction).not.toContain("docx");
    expect(ingestExtraction).not.toContain("Promise.race");
  });

  it("crawls paginated fiscal catalogs without claiming premature integral coverage", () => {
    expect(catalog).toContain("legal_catalog_coverage_candidates");
    expect(catalog).toContain("canonical_legal_key");
    expect(catalog).toContain("legal_source_canonical_identities");
    expect(catalog).toContain("legal_source_relationship_candidates");
    expect(catalog).toContain("'relationships_queued'");
    expect(catalog).toContain(":canonical-law:");
    expect(catalog).toContain("newly discovered");
    expect(catalog).toContain("count(candidate.id) = coverage.expected_document_count");
    expect(catalog).toContain("legal_source_version_is_current_citable");
    expect(
      catalog.match(/private\.legal_version_has_complete_evidence/g)?.length,
    ).toBeGreaterThanOrEqual(1);
    expect(
      catalog.match(/private\.legal_source_version_is_current_citable/g)?.length,
    ).toBeGreaterThanOrEqual(2);
    expect(catalog).toContain("'Cobertura inicial governada'");
    expect(catalog).toContain("'corpus_integral'");
    expect(catalog).toContain("Classificacao=752&Modulo=8&Pagina=1");
    expect(catalog).toContain("Classificacao=951&Modulo=8&Pagina=1");
    expect(catalog).toContain("Classificacao=1228&Modulo=8&Pagina=1");
    expect(catalog).toContain("Classificacao=424&Modulo=8&Pagina=1");
    expect(catalog).toContain("large_or_legacy_attachment_extractor_required");
  });

  it("keeps the last-known-good body active and queues cutovers fail-closed", () => {
    expect(catalog).toContain("legal_source_endpoints_one_active_legal_body_uq");
    expect(catalog).toContain("legal_source_endpoints_one_active_ficha_uq");
    expect(catalog).toContain("validated_cutover_required");
    expect(catalog).toContain("'safe_cutover_pending'");
    expect(catalog).toContain("pg_advisory_xact_lock");
    expect(catalog).toContain("legal_body_endpoint_cutovers");
    expect(catalog).toContain("relation_discovery_active");
    expect(catalog).toContain("endpoint.parser_hint = 'siscam_document'");
    expect(regression).toContain("canonical Siscam ficha activation was ambiguous");
    expect(regression).toContain("last_known_good_before_validated_cutover");
  });

  it("keeps PostgreSQL runtime follow-ups executable instead of escaping line breaks", () => {
    for (const migration of postgresRuntimeFixes) {
      expect(migration).not.toContain("\\n\\ncreate or replace function");
      expect(migration).toMatch(/^--[^\n]+\n\ncreate or replace function/m);
    }
  });

  it("derives catalog health from the latest persisted fetch instead of static seeds", () => {
    expect(catalog).toContain("refresh_legal_catalog_coverage_health");
    expect(catalog).toContain("last_fetch_run_sequence");
    expect(catalog).toContain("when new.http_status = 403 then 'blocked_403'");
    expect(catalog).toContain("when new.http_status = 502 then 'blocked_502'");
    expect(catalog).toContain("when new.http_status = 503 then 'blocked_503'");
    expect(catalog).toContain(
      "when new.status in ('completed_unchanged', 'completed_changed') then 'available'",
    );
  });

  it("uses custom scheduler auth only where gateway JWT is intentionally disabled", () => {
    expect(config).toMatch(
      /\[functions\.ia-fiscal-knowledge-ingest\][\s\S]*?verify_jwt\s*=\s*false/,
    );
    expect(config).toMatch(
      /\[functions\.ia-fiscal-knowledge-embed\][\s\S]*?verify_jwt\s*=\s*false/,
    );
    expect(config).toMatch(
      /\[functions\.ia-fiscal-knowledge-search\][\s\S]*?verify_jwt\s*=\s*true/,
    );
    expect(core).toContain("knowledge_scheduler_nonces");
    expect(core).not.toMatch(/service[_-]?role.{0,20}[=:].{0,80}[A-Za-z0-9_-]{20}/i);
  });
});
