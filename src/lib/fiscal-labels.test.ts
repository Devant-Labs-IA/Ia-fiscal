import { describe, expect, it } from "vitest";

import {
  blockReasonLabel,
  blockReasonSummary,
  debtClassificationRuleDetails,
  debtClassificationRuleLabel,
  divergenceTypeDetails,
  environmentLabel,
  fiscalEventTypeLabel,
  fiscalOperationalReasonLabel,
  fiscalRulePresentation,
  fiscalRuleDetails,
  fiscalStatusLabel,
  knowledgeDivergenceScopeLabel,
  knowledgeIntentLabel,
  knowledgeTaxScopeLabel,
  notificationChannelLabel,
  notificationPurposeLabel,
  operationalFieldLabel,
  parseBlockReasons,
  processingWorkerLabel,
  taxpayerTypeLabel,
  visibilityLabel,
  workerHealthStatus,
  workerStatusLabel,
} from "@/lib/fiscal-labels";

describe("catálogo fiscal em português", () => {
  it("traduz os termos observados na operação assistida", () => {
    expect(divergenceTypeDetails("Current Account Balance")).toEqual({
      label: "Saldo da conta corrente municipal",
      description: "Compara os valores lançados, pagos e ainda em aberto no período.",
    });
    expect(divergenceTypeDetails("Saldo da conta corrente municipal").label).toBe(
      "Saldo da conta corrente municipal",
    );
    expect(fiscalStatusLabel("Pending Revalidation")).toBe("Aguardando nova conferência");
    expect(blockReasonLabel("Unverification")).toBe("Contato ainda não verificado");
    expect(blockReasonSummary('{"code":"Unverification"}')).toBe("Contato ainda não verificado");
    expect(fiscalStatusLabel("blocked_unverified")).toBe("Bloqueado por validação pendente");
    expect(fiscalStatusLabel("converted")).toBe("Convertida em procedimento fiscal");
    expect(fiscalStatusLabel("eligible_after_verification")).toBe("Apto após validação");
    expect(fiscalStatusLabel("expired")).toBe("Cadastro substituído ou expirado");
    expect(environmentLabel("assisted_operation")).toBe("Operação assistida");
    expect(environmentLabel("homologation")).toBe("Operação assistida");
    expect(taxpayerTypeLabel("company")).toBe("Pessoa jurídica");
    expect(taxpayerTypeLabel("individual")).toBe("Pessoa física");
  });

  it("explica a regra e sua versão sem expor o código interno", () => {
    expect(fiscalRuleDetails("CURRENT_ACCOUNT_BALANCE_HOMOLOGATION_V1", 1)).toEqual({
      label: "Conferência do saldo da conta corrente — versão 1",
      description:
        "Compara lançamentos, pagamentos e saldo em aberto; requer conferência da equipe fiscal.",
    });
    expect(debtClassificationRuleLabel("current-account-maturity-v3")).toBe(
      "Classificação de vencimentos da conta corrente — versão 3",
    );
    expect(debtClassificationRuleDetails("current-account-maturity-v3").description).toBe(
      "Classifica cada competência conforme o vencimento e o saldo que permanece em aberto.",
    );
    expect(
      fiscalRulePresentation(
        "current-account-balance-homologation-v1",
        1,
        "current-account-balance-homologation-v1",
        null,
      ),
    ).toEqual({
      label: "Conferência do saldo da conta corrente — versão 1",
      description:
        "Compara lançamentos, pagamentos e saldo em aberto; requer conferência da equipe fiscal.",
    });
  });

  it("explica motivos operacionais sem expor códigos internos", () => {
    expect(fiscalOperationalReasonLabel("no_current_approved_exact_knowledge")).toBe(
      "Ainda não existe uma resposta aprovada na base de conhecimento para este questionamento.",
    );
  });

  it("traduz status do worker e metadados dos eventos", () => {
    expect(workerStatusLabel("healthy")).toBe("Operacional");
    expect(workerHealthStatus("unhealthy")).toBe("critico");
    expect(fiscalEventTypeLabel("case_question_claimed")).toBe(
      "Atendimento assumido pela equipe fiscal",
    );
    expect(visibilityLabel("participants")).toBe("participantes do procedimento");
    expect(processingWorkerLabel("worker_sandbox")).toBe("Processador da operação assistida");
    expect(processingWorkerLabel("unknown_processor_v2")).toBe("Processador fiscal interno");
  });

  it("traduz finalidade, campos e temas da base de conhecimento", () => {
    expect(notificationPurposeLabel("initial_inspection_alert")).toBe(
      "Aviso inicial para conferência fiscal",
    );
    expect(notificationChannelLabel("whatsapp")).toBe("WhatsApp");
    expect(operationalFieldLabel("location")).toBe("Localização");
    expect(operationalFieldLabel("contact_number")).toBe("Número de contato");
    expect(operationalFieldLabel("state_key")).toBe("Identificador da situação");
    expect(operationalFieldLabel("unknown_backend_key")).toBe("Informação operacional");
    expect(knowledgeTaxScopeLabel("fiscal_case_answer")).toBe("Resposta de procedimento fiscal");
    expect(knowledgeDivergenceScopeLabel("current_account_balance")).toBe(
      "Saldo da conta corrente municipal",
    );
    expect(knowledgeIntentLabel("why-overdue-iss-may-trigger-inspection")).toBe(
      "Fiscalização relacionada a débito de ISS vencido",
    );
    expect(knowledgeIntentLabel("qa-a3c59f9d55420b12ee14")).toBe("Pergunta fiscal revisada");
  });

  it("nunca devolve identificadores técnicos observados como rótulo visível", () => {
    const visibleLabels = [
      fiscalStatusLabel("blocked_unverified"),
      notificationPurposeLabel("initial_inspection_alert"),
      divergenceTypeDetails("current_account_balance").label,
      debtClassificationRuleLabel("current-account-maturity-v3"),
      blockReasonLabel("superseded_contact_or_relationship"),
      operationalFieldLabel("unknown_backend_key"),
      knowledgeIntentLabel("qa-a3c59f9d55420b12ee14"),
      environmentLabel("homologation"),
    ];

    for (const label of visibleLabels) {
      expect(label).not.toMatch(
        /_|blocked-unverified|initial-inspection|current-account|homologation/i,
      );
    }
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
    expect(blockReasonLabel("superseded_contact_or_relationship")).toBe(
      "Contato ou vínculo substituído por cadastro mais recente",
    );
  });
});
