import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const projectRoot = process.cwd();
const migrationPath =
  "supabase/migrations/20260803014627_enforce_aal2_and_idempotent_question_claim.sql";

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

  it("não converte administração técnica em vínculo fiscal municipal", () => {
    const roleHelper = functionDefinition(migration, "private.has_municipality_role(");
    expect(roleHelper).toContain("private.is_aal2()");
    expect(roleHelper).toContain("public.municipality_memberships");
    expect(roleHelper).not.toContain("private.is_platform_administrator()");

    const appShell = source("src/components/layout/AppShell.tsx");
    const appSidebar = source("src/components/layout/AppSidebar.tsx");
    const topbar = source("src/components/layout/Topbar.tsx");
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
      source("docs/qa/evidence/supabase-authorization-regression-2026-08-03.json"),
    ) as {
      migration: { path: string; sha256: string; deployment_status: string };
      regression_suite: { path: string; sha256: string };
    };
    expect(evidence.migration.deployment_status).toBe("validated_not_applied");
    expect(sha256(source(evidence.migration.path))).toBe(evidence.migration.sha256);
    expect(sha256(source(evidence.regression_suite.path))).toBe(evidence.regression_suite.sha256);
  });
});
