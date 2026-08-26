import { describe, expect, it } from "vitest";

import {
  buildDefaultHomologationEmailBody,
  extractTaxpayerIdFromPath,
  homologationEmailBlockers,
} from "@/lib/homologation-policy";

describe("homologation email policy", () => {
  it("accepts the approved internal-test template", () => {
    expect(
      homologationEmailBlockers(
        "Aviso informativo para conferência no CIGIS",
        buildDefaultHomologationEmailBody(),
      ),
    ).toEqual([]);
  });

  it.each([
    ["Acesse https://exemplo.test para consultar.", "links"],
    ["Existe um valor de R$ 1.000,00 para conferência.", "valores"],
    ["Consulte o anexo enviado para análise.", "anexos"],
  ])("blocks prohibited content: %s", (body, expected) => {
    expect(homologationEmailBlockers("Aviso de conferência", body).join(" ")).toContain(expected);
  });

  it("extracts the taxpayer context from the 360 route", () => {
    expect(extractTaxpayerIdFromPath("/contribuintes/abc-123")).toBe("abc-123");
    expect(extractTaxpayerIdFromPath("/debitos")).toBeNull();
  });
});
