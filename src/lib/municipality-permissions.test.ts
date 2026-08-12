import { describe, expect, it } from "vitest";

import { canManageMunicipalTaxpayers } from "@/lib/municipality-permissions";

describe("permissão municipal do cadastro de contribuintes", () => {
  it.each(["municipal_admin", "supervisor"])("permite o papel municipal %s", (role) => {
    expect(canManageMunicipalTaxpayers(role)).toBe(true);
  });

  it.each(["platform_admin", "fiscal_auditor", "legal_reviewer", "support_readonly", null])(
    "nega CRUD sem papel municipal autorizado: %s",
    (role) => {
      expect(canManageMunicipalTaxpayers(role)).toBe(false);
    },
  );
});
