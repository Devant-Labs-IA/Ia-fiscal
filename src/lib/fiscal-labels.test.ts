import { describe, expect, it } from "vitest";

import {
  blockReasonLabel,
  blockReasonSummary,
  debtClassificationRuleLabel,
  divergenceTypeDetails,
  environmentLabel,
  fiscalEventTypeLabel,
  fiscalRuleDetails,
  fiscalStatusLabel,
  parseBlockReasons,
  processingWorkerLabel,
  taxpayerTypeLabel,
  visibilityLabel,
  workerHealthStatus,
  workerStatusLabel,
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
    expect(fiscalStatusLabel("blocked_unverified")).toBe("Bloqueado por validação pendente");
    expect(environmentLabel("homologation")).toBe("Homologação");
    expect(taxpayerTypeLabel("company")).toBe("Pessoa jurídica");
    expect(taxpayerTypeLabel("individual")).toBe("Pessoa física");
  });

  it("explica a regra e sua versão sem expor o código interno", () => {
    expect(fiscalRuleDetails("CURRENT_ACCOUNT_BALANCE_HOMOLOGATION_V1", 1)).toEqual({
      label: "Conferência do saldo da conta corrente — versão 1",
      description: "Regra de homologação que compara lançamentos, pagamentos e saldo em aberto.",
    });
    expect(debtClassificationRuleLabel("current-account-maturity-v3")).toBe(
      "Classificação de vencimentos da conta corrente — versão 3",
    );
  });

  it("traduz status do worker e metadados dos eventos", () => {
    expect(workerStatusLabel("healthy")).toBe("Operacional");
    expect(workerHealthStatus("unhealthy")).toBe("critico");
    expect(fiscalEventTypeLabel("case_question_claimed")).toBe(
      "Atendimento assumido pela equipe fiscal",
    );
    expect(visibilityLabel("participants")).toBe("participantes do procedimento");
    expect(processingWorkerLabel("worker_sandbox")).toBe("Processador do ambiente de homologação");
    expect(processingWorkerLabel("unknown_processor_v2")).toBe("Processador fiscal interno");
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
    expect(blockReasonSummary("relationship_unverified;external_delivery_not_authorized")).toBe(
      "Vínculo com o contribuinte ainda não verificado · Envio externo não autorizado",
    );
  });
});
