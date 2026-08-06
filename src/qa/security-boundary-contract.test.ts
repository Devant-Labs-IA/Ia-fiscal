import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const projectRoot = process.cwd();
const migrationPath =
  "supabase/migrations/20260803234455_enforce_aal2_and_idempotent_question_claim.sql";
const operationalMigrationPath =
  "supabase/migrations/20260804002339_harden_batch_and_response_boundaries.sql";
const assignmentRoleMigrationPath =
  "supabase/migrations/20260804004659_revalidate_case_assignment_roles.sql";

function source(path: string): string {
  return readFileSync(resolve(projectRoot, path), "utf8");
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function functionDefinition(sql: string, signature: string): string {
  const start = sql.indexOf(`create or replace function ${signature}`);
  if (start < 0) throw new Error(`function_missing:${signature}`);
  const next = sql.indexOf("create or replace function ", start + signature.length);
  return sql.slice(start, next < 0 ? sql.length : next);
}

describe("contrato estático das fronteiras fiscais", () => {
  const migration = source(migrationPath);
  const operationalMigration = source(operationalMigrationPath);
  const assignmentRoleMigration = source(assignmentRoleMigrationPath);

  it("não converte administração técnica em vínculo fiscal municipal", () => {
    const roleHelper = functionDefinition(migration, "private.has_municipality_role(");
    expect(roleHelper).toContain("private.is_aal2()");
    expect(roleHelper).toContain("public.municipality_memberships");
    expect(roleHelper).not.toContain("private.is_platform_administrator()");

    const appShell = source("src/components/layout/AppShell.tsx");
    const appSidebar = source("src/components/layout/AppSidebar.tsx");
    const topbar = source("src/components/layout/Topbar.tsx");
    const authContext = source("src/auth/AuthContext.tsx");
    expect(authContext).toContain("platformAdmin: isPlatformAdmin");
    expect(appShell).toContain('auth.access?.role === "platform_admin"');
    expect(appShell).toContain('<Navigate to="/configuracoes" replace />');
    expect(appSidebar).toContain('item.url === "/configuracoes"');
    expect(topbar).toContain('auth.access?.role !== "platform_admin"');
  });

  it("exige AAL2 nos helpers de caso e na busca Edge", () => {
    for (const signature of [
      "private.current_municipality_membership_id(",
      "private.can_view_case_staff(",
      "private.can_review_case(",
      "private.can_access_case(",
    ]) {
      expect(functionDefinition(migration, signature)).toContain("private.is_aal2()");
    }

    const edge = source("supabase/functions/ia-fiscal-search/index.ts");
    expect(edge).toContain("supabase.auth.getClaims(token)");
    expect(edge).toContain("Authorization: authorization");
    expect(edge).not.toMatch(/^\s*authorization,\s*$/m);
    expect(edge).toContain('claimsData.claims.aal !== "aal2"');
    expect(edge).toContain('error: "aal2_required"');
  });

  it("preserva o replay do claim sem repetir efeitos", () => {
    const claim = functionDefinition(migration, "public.ia_claim_case_question(");
    const tenantGuard = claim.indexOf("cq.municipality_id = p_expected_municipality_id");
    const membershipGuard = claim.indexOf("v_membership_id <> p_expected_membership_id");
    const closedGuard = claim.indexOf("v_question.status in ('answered', 'closed')");
    const replayGuard = claim.indexOf("v_question.assigned_membership_id = v_membership_id");
    const update = claim.indexOf("update public.case_questions");
    const event = claim.indexOf("insert into public.case_events");

    expect(tenantGuard).toBeGreaterThan(0);
    expect(membershipGuard).toBeGreaterThan(tenantGuard);
    expect(closedGuard).toBeGreaterThan(membershipGuard);
    expect(replayGuard).toBeGreaterThan(closedGuard);
    expect(update).toBeGreaterThan(replayGuard);
    expect(event).toBeGreaterThan(update);

    const regression = source("supabase/tests/authorization_regression.sql");
    expect(regression).toContain("AAL1 fiscal crossed a regulated case boundary");
    expect(regression).toContain("technical platform admin inherited fiscal authority");
    expect(regression).toContain("cross-municipality claim context was accepted");
    expect(regression).toContain("terminal question status % was reclaimed");
    expect(regression).toContain("idempotent claim replay created another event");

    const evidence = JSON.parse(
      source("docs/qa/evidence/supabase-postapply-regression-2026-08-03.json"),
    ) as {
      migration_count: number;
      migrations: Array<{ path: string; sha256: string; deployment_status: string }>;
      regression_suites: Array<{ path: string; sha256: string; status: string }>;
    };
    expect(evidence.migration_count).toBe(36);
    expect(evidence.migrations).toHaveLength(3);
    for (const item of evidence.migrations) {
      expect(item.deployment_status).toMatch(/^applied/);
      expect(sha256(source(item.path))).toBe(item.sha256);
    }
    for (const suite of evidence.regression_suites) {
      expect(suite.status).toBe("pass");
      expect(sha256(source(suite.path))).toBe(suite.sha256);
    }
  });

  it("propaga o modo do lote e rejeita replay ambíguo", () => {
    const normalizeCounts = functionDefinition(
      operationalMigration,
      "private.normalize_case_opening_batch_counts(",
    );
    expect(normalizeCounts).toContain("new.requested_count");
    expect(normalizeCounts).not.toContain("new.selected_count");
    expect(normalizeCounts).toContain("old.status = 'processing'");

    const assignmentGuard = functionDefinition(
      operationalMigration,
      "private.validate_case_assignment_membership(",
    );
    expect(assignmentGuard).toContain("mm.status = 'active'");
    expect(assignmentGuard).toContain("mm.valid_from <= now()");
    expect(assignmentGuard).toContain("mm.valid_until is null or mm.valid_until > now()");
    expect(operationalMigration).toContain(
      "before insert or update of municipality_id, membership_id",
    );

    const createBatch = functionDefinition(
      operationalMigration,
      "public.ia_create_case_opening_batch(",
    );
    expect(operationalMigration).toContain("request_sha256 text");
    expect(createBatch).toContain("v_run.execution_mode");
    expect(createBatch).toContain("v_existing.request_sha256 is null");
    expect(createBatch).toContain("idempotency key owner mismatch");
    expect(createBatch).toContain("idempotency key payload mismatch");
    expect(createBatch).toContain("mm.valid_from <= now()");
    expect(createBatch).toContain("mm.valid_until is null or mm.valid_until > now()");
    expect(createBatch).toContain("pg_catalog.pg_advisory_xact_lock");

    const approveBatch = functionDefinition(
      operationalMigration,
      "public.ia_approve_case_opening_batch(",
    );
    expect(approveBatch).toContain("v_batch.execution_mode <> 'live'");
    expect(approveBatch).toContain("membership that is no longer valid");
    expect(approveBatch).toContain("homologation batches require the sandbox case-test workflow");
  });

  it("mantém respostas a participantes revogadas e fail-closed no banco", () => {
    expect(operationalMigration).toContain("sandbox_response_publication_enabled boolean");
    expect(operationalMigration).toContain("not null default false");

    const gate = functionDefinition(
      operationalMigration,
      "private.case_response_publication_allowed(",
    );
    expect(gate).toContain("p_execution_mode = 'homologation_test'");
    expect(gate).toContain("ps.sandbox_response_publication_enabled");

    const manual = functionDefinition(operationalMigration, "public.ia_publish_manual_response(");
    expect(manual).toContain("cm.case_id = v_question.case_id");
    expect(manual).toContain("v_existing_author_user_id is distinct from auth.uid()");
    expect(manual).toContain("v_existing_content_sha256 is distinct from v_content_sha256");
    expect(manual).toContain("pg_catalog.pg_advisory_xact_lock");

    expect(operationalMigration).toContain(
      "revoke all on function public.ia_publish_manual_response(uuid, text, text)\n  from public, anon, authenticated, service_role;",
    );
    expect(operationalMigration).toContain(
      "revoke all on function public.ia_publish_approved_response(uuid, text)\n  from public, anon, authenticated, service_role;",
    );
    expect(operationalMigration).not.toMatch(
      /grant execute on function public\.ia_publish_(manual|approved)_response/,
    );
  });

  it("revalida o papel da atribuição na aprovação e no worker", () => {
    const caseAssignment = functionDefinition(
      assignmentRoleMigration,
      "private.validate_case_assignment_membership(",
    );
    expect(caseAssignment).toContain("responsible_fiscal");
    expect(caseAssignment).toContain("fiscal_auditor");
    expect(caseAssignment).toContain("legal_reviewer");
    expect(caseAssignment).toContain("new.status <> 'active'");
    expect(caseAssignment).toContain("for share");
    expect(caseAssignment).toContain("supervisor assignment requires a supervisor membership");
    expect(assignmentRoleMigration).toContain(
      "before insert or update of municipality_id, membership_id, assignment_role, status",
    );

    const batchItem = functionDefinition(
      assignmentRoleMigration,
      "private.validate_batch_item_assigned_membership(",
    );
    expect(batchItem).toContain("v_membership_role is distinct from 'fiscal_auditor'");
    expect(batchItem).toContain("new.status in ('selected', 'approved', 'revalidating')");
    expect(batchItem).toContain("v_divergence_status is distinct from 'pending_revalidation'");
    expect(batchItem).toContain("for update");
    expect(batchItem).toContain("for share");
    expect(assignmentRoleMigration).toContain(
      "before insert or update of municipality_id, divergence_id, assigned_membership_id, status",
    );
    expect(assignmentRoleMigration).toContain(
      "create unique index case_opening_batch_items_active_divergence_uq",
    );
    expect(assignmentRoleMigration).not.toContain(
      "create unique index if not exists case_opening_batch_items_active_divergence_uq",
    );

    const batchApproval = functionDefinition(
      assignmentRoleMigration,
      "private.validate_batch_processing_assignments(",
    );
    expect(batchApproval).toContain("mm.role <> 'fiscal_auditor'");
    expect(batchApproval).toContain("bi.status in ('selected', 'approved', 'revalidating')");
    expect(batchApproval).toContain("for update of d");
    expect(batchApproval).toContain("for share of mm");
    expect(assignmentRoleMigration).toContain(
      "before update of status, execution_mode\n  on public.case_opening_batches",
    );

    const claim = functionDefinition(assignmentRoleMigration, "public.ia_claim_case_question(");
    expect(claim).toContain("when v_membership_role = 'fiscal_auditor' then 'responsible_fiscal'");
    expect(claim).toContain("else 'reviewer'");
  });
});
