import { describe, expect, it } from "vitest";

import { maskTaxpayerTaxId, validateTaxpayerInput } from "@/lib/taxpayer-validation";

describe("validação de cadastro de contribuinte", () => {
  it("normaliza um CNPJ válido no contrato da aplicação", () => {
    const result = validateTaxpayerInput({
      municipalRegistration: " 12345 ",
      taxId: "12.345.678/0001-90",
      legalName: " Empresa de Teste Ltda. ",
      tradeName: " Teste ",
      taxpayerType: "company",
    });

    expect(result.valid).toBe(true);
    expect(result.data).toMatchObject({
      municipalRegistration: "12345",
      taxId: "12345678000190",
      legalName: "Empresa de Teste Ltda.",
      tradeName: "Teste",
    });
  });

  it.each(["123", "123456789012", "1234567890123", "123456789012345"])(
    "recusa CPF/CNPJ com quantidade incorreta de dígitos: %s",
    (taxId) => {
      const result = validateTaxpayerInput({
        municipalRegistration: "12345",
        taxId,
        legalName: "Contribuinte Teste",
        tradeName: "",
        taxpayerType: "individual",
      });

      expect(result.valid).toBe(false);
      expect(result.errors.taxId).toContain("11 dígitos ou CNPJ com 14 dígitos");
    },
  );

  it("exige inscrição municipal e razão social", () => {
    const result = validateTaxpayerInput({
      municipalRegistration: " ",
      taxId: "12345678901",
      legalName: " ",
      tradeName: "",
      taxpayerType: "individual",
    });

    expect(result.errors.municipalRegistration).toBeTruthy();
    expect(result.errors.legalName).toBeTruthy();
  });

  it("mascara CPF e CNPJ sem expor o documento completo", () => {
    expect(maskTaxpayerTaxId("12345678901")).toBe("123.***.***-01");
    expect(maskTaxpayerTaxId("12345678000190")).toBe("12.345.***/****-90");
  });
});
