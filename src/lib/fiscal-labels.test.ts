import { describe, expect, it } from "vitest";

import {
  blockReasonLabel,
  blockReasonSummary,
  divergenceTypeDetails,
  fiscalRuleDetails,
  fiscalStatusLabel,
  parseBlockReasons,
} from "@/lib/fiscal-labels";

describe("catálogo fiscal em português", () => {
  it("traduz os termos observados na homologação", () => {
    expect(divergenceTypeDetails("Current Account Balance")).toEqual({
      label: "Saldo da conta corrente municipal",
      description: "Compara os valores lançados, pagos e ainda em aberto no período.",
    });
    expect(fiscalStatusLabel("Pending Revalidation")).toBe("Aguardando nova conferência");
    expect(blockReasonLabel("Unverification")).toBe("Contato ainda não verificado");
    expect(blockReasonSummary('{"code":"Unverification"}')).toBe("Contato ainda não verificado");
  });

  it("explica a regra e sua versão sem expor o código interno", () => {
    expect(fiscalRuleDetails("CURRENT_ACCOUNT_BALANCE_HOMOLOGATION_V1", 1)).toEqual({
      label: "Conferência do saldo da conta corrente — versão 1",
      description: "Regra de homologação que compara lançamentos, pagamentos e saldo em aberto.",
    });
  });
});

describe("motivos de bloqueio estruturados", () => {
  it("lê arrays, JSON serializado e objetos sem renderizar JSON cru", () => {
    expect(parseBlockReasons('[{"code":"unverification"},{"reason":"missing_email"}]')).toEqual([
      "unverification",
      "missing_email",
    ]);
    expect(
      parseBlockReasons({ reasons: ["pending_revalidation", "pending_revalidation"] }),
    ).toEqual(["pending_revalidation"]);
    expect(parseBlockReasons("{unverification,missing_verified_contact}")).toEqual([
      "unverification",
      "missing_verified_contact",
    ]);
  });
});