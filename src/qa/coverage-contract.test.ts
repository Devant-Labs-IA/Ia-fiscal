import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

interface CoverageMatrix {
  responsive_contract: {
    mobile_breakpoint_px: number;
    viewports: Array<{
      id: string;
      class: "mobile" | "tablet" | "desktop";
      width: number;
      height: number;
      expected_navigation: "mobile_drawer" | "desktop_sidebar";
    }>;
  };
  roles: string[];
  routes: Array<{
    route_template: string;
    sample_path: string;
    allowed_roles: string[];
    denied_roles: string[];
    required_states: string[];
    critical_interactions: string[];
    claim_roles?: string[];
  }>;
  accessibility_checks: Array<{
    id: string;
    execution: "static" | "browser_pending";
  }>;
  execution: {
    remote_browser_used: boolean;
    planned_route_viewport_cases: number;
  };
}

interface QaLedger {
  system: { version: string };
  run: {
    inventory_complete: boolean;
    clean_critical_passes: number;
    full_regression_after_last_change: boolean;
  };
  scope: { roles: string[]; viewports: string[]; areas: string[] };
  items: Array<{
    id: string;
    area: string;
    required: boolean;
    critical: boolean;
    status: "pass" | "fail" | "blocked" | "not_run" | "na";
    expected_roles: string[];
    tested_roles: string[];
    expected_viewports: string[];
    tested_viewports: string[];
    evidence: string[];
    defects: string[];
  }>;
  defects: Array<{ id: string }>;
}

const projectRoot = process.cwd();

function source(path: string): string {
  return readFileSync(resolve(projectRoot, path), "utf8");
}

function json<T>(path: string): T {
  return JSON.parse(source(path)) as T;
}

function generatedRouteTemplates(): string[] {
  const routeTree = source("src/routeTree.gen.ts");
  const interfaceBody = routeTree.match(
    /export interface FileRoutesByFullPath \{(?<body>[\s\S]*?)\n\}/,
  )?.groups?.["body"];
  if (!interfaceBody) throw new Error("file_routes_interface_missing");
  return [...interfaceBody.matchAll(/^\s+'([^']+)':/gm)].map((match) => match[1]!).sort();
}

const matrix = json<CoverageMatrix>("docs/qa/coverage-matrix-current.json");
const ledger = json<QaLedger>("docs/qa/ledger-current.json");

describe("contrato executável de cobertura QA", () => {
  it("mantém a matriz em paridade com as onze rotas geradas", () => {
    const matrixRoutes = matrix.routes.map((route) => route.route_template).sort();
    expect(matrixRoutes).toHaveLength(11);
    expect(matrixRoutes).toEqual(generatedRouteTemplates());

    const dynamicRoute = matrix.routes.find(
      (route) => route.route_template === "/contribuintes/$taxpayerId",
    );
    expect(dynamicRoute?.sample_path).toBe("/contribuintes/tp-1");
    expect(dynamicRoute?.sample_path).not.toContain("$");
  });

  it("define casos mobile, limite 767/768, tablet e desktop", () => {
    const breakpointSource = source("src/hooks/use-mobile.tsx");
    const sourceBreakpoint = Number(
      breakpointSource.match(/MOBILE_BREAKPOINT\s*=\s*(\d+)/)?.[1] ?? Number.NaN,
    );
    expect(sourceBreakpoint).toBe(matrix.responsive_contract.mobile_breakpoint_px);

    const byId = new Map(
      matrix.responsive_contract.viewports.map((viewport) => [viewport.id, viewport]),
    );
    expect(byId.get("mobile")?.width).toBeLessThan(sourceBreakpoint);
    expect(byId.get("mobile_boundary")?.width).toBe(sourceBreakpoint - 1);
    expect(byId.get("mobile_boundary")?.expected_navigation).toBe("mobile_drawer");
    expect(byId.get("tablet")?.width).toBe(sourceBreakpoint);
    expect(byId.get("tablet")?.expected_navigation).toBe("desktop_sidebar");
    expect(byId.get("desktop")?.width).toBeGreaterThan(sourceBreakpoint);
    expect(new Set(matrix.responsive_contract.viewports.map((viewport) => viewport.class))).toEqual(
      new Set(["mobile", "tablet", "desktop"]),
    );
    expect(matrix.execution.planned_route_viewport_cases).toBe(
      matrix.routes.length * matrix.responsive_contract.viewports.length,
    );
    expect(matrix.execution.remote_browser_used).toBe(false);
  });

  it("declara cada papel em decisões de acesso por rota", () => {
    const declaredRoles = new Set(matrix.roles);
    for (const route of matrix.routes) {
      expect(route.required_states.length).toBeGreaterThan(0);
      expect(route.critical_interactions.length).toBeGreaterThan(0);
      const decidedRoles = new Set([...route.allowed_roles, ...route.denied_roles]);
      expect(decidedRoles).toEqual(declaredRoles);
    }
  });

  it("mantém um único landmark main no shell autenticado", () => {
    const appShell = source("src/components/layout/AppShell.tsx");
    const sidebarSource = source("src/components/ui/sidebar.tsx");
    const sidebarInset = sidebarSource.match(
      /const SidebarInset[\s\S]*?SidebarInset\.displayName = "SidebarInset";/,
    )?.[0];
    if (!sidebarInset) throw new Error("sidebar_inset_missing");

    const mainCount =
      (appShell.match(/<main\b/g) ?? []).length + (sidebarInset.match(/<main\b/g) ?? []).length;
    expect(mainCount).toBe(1);
  });

  it("preserva idioma, foco visível e fechamento acessível no menu mobile", () => {
    expect(source("src/routes/__root.tsx")).toContain('<html lang="pt-BR">');
    expect(source("src/styles.css")).toMatch(/:focus-visible\s*\{/);

    const sidebarSource = source("src/components/ui/sidebar.tsx");
    const sheetSource = source("src/components/ui/sheet.tsx");
    const mobileBranch = sidebarSource.match(
      /if \(isMobile\) \{[\s\S]*?\n\s*return \([\s\S]*?\n\s*\);\n\s*\}/,
    )?.[0];
    if (!mobileBranch) throw new Error("mobile_sidebar_branch_missing");
    expect(mobileBranch).not.toContain("[&>button]:hidden");
    expect(sheetSource).toContain("size-11");
    expect(sheetSource).toContain('<span className="sr-only">Fechar</span>');

    const atendimento = matrix.routes.find((route) => route.route_template === "/atendimento");
    expect(atendimento?.required_states).toEqual(
      expect.arrayContaining(["mutation_pending", "mutation_error", "mutation_success"]),
    );
    expect(atendimento?.critical_interactions).toEqual(
      expect.arrayContaining(["claim_question", "open_protected_conversation"]),
    );
    expect(atendimento?.claim_roles).toEqual(["supervisor", "fiscal_auditor", "legal_reviewer"]);
    expect(atendimento?.claim_roles).not.toContain("municipal_admin");
  });

  it("mantém o ledger atual consistente sem mascarar gates pendentes", () => {
    expect(ledger.system.version).not.toMatch(/GitHub remote empty|32 migrations|98630ba/i);
    expect(ledger.run.inventory_complete).toBe(false);
    expect(ledger.run.clean_critical_passes).toBe(0);
    expect(ledger.run.full_regression_after_last_change).toBe(false);

    const itemIds = ledger.items.map((item) => item.id);
    expect(new Set(itemIds).size).toBe(itemIds.length);
    expect(itemIds).toEqual(
      expect.arrayContaining([
        "UI-ROUTE-INVENTORY-CURRENT-001",
        "UI-RESPONSIVE-CONTRACT-001",
        "A11Y-SOURCE-CONTRACT-001",
        "UI-MOCK-SMOKE-001",
        "A11Y-BROWSER-001",
      ]),
    );

    const defectIds = new Set(ledger.defects.map((defect) => defect.id));
    for (const item of ledger.items) {
      expect(ledger.scope.areas).toContain(item.area);
      if (["pass", "fail", "blocked"].includes(item.status)) {
        expect(item.evidence.length).toBeGreaterThan(0);
      }
      if (item.status === "fail") {
        expect(item.defects.length).toBeGreaterThan(0);
        for (const defect of item.defects) expect(defectIds).toContain(defect);
      }
      expect(item.tested_roles.every((role) => item.expected_roles.includes(role))).toBe(true);
      expect(
        item.tested_viewports.every((viewport) => item.expected_viewports.includes(viewport)),
      ).toBe(true);
    }

    const referencedRoles = new Set(ledger.items.flatMap((item) => item.expected_roles));
    const referencedViewports = new Set(ledger.items.flatMap((item) => item.expected_viewports));
    expect(referencedRoles).toEqual(new Set(ledger.scope.roles));
    expect(referencedViewports).toEqual(new Set(ledger.scope.viewports));
    expect(ledger.items.some((item) => item.critical && item.status !== "pass")).toBe(true);
  });
});
