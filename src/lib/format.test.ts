import { describe, expect, it } from "vitest";

import { formatCnpj, maskCnpj } from "@/lib/format";

describe("identificadores fiscais", () => {
  it("formata CNPJ sem alterar os dígitos", () => {
    expect(formatCnpj("12345678000190")).toBe("12.345.678/0001-90");
  });

  it("mascara o miolo do CNPJ para exposição reduzida", () => {
    const masked = maskCnpj("12345678000190");
    expect(masked).toContain("***");
    expect(masked).not.toContain("3456780001");
  });
});
