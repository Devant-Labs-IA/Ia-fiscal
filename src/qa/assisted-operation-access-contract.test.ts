import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  "supabase/migrations/20260813144225_restrict_assisted_safety_status_to_staff.sql",
  "utf8",
).toLocaleLowerCase("en-US");

describe("diagnóstico da operação assistida", () => {
  it("exige AAL2 e vínculo interno real no município", () => {
    expect(migration).toContain("not private.is_aal2()");
    expect(migration).toContain("private.has_municipality_role(p_municipality_id, null)");
    expect(migration).not.toContain("taxpayer_user_links");
    expect(migration).not.toContain("accountant_user_links");
  });

  it("mantém a função sem execução pública ou anônima", () => {
    expect(migration).toContain(
      "revoke all on function public.ia_get_assisted_operation_safety_status(uuid)",
    );
    expect(migration).toContain("from public, anon, authenticated, service_role");
    expect(migration).toContain("grant execute on function");
    expect(migration).toContain("to authenticated");
  });
});
