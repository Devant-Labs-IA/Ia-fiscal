import { describe, expect, it } from "vitest";

import { fiscalKeys } from "@/services/fiscal-service";
import { mockFiscalService } from "@/services/mock-fiscal-service";

const MUNICIPALITY_ID = "demo-cordeiropolis";

describe("serviço fiscal demonstrativo", () => {
  it("preserva vínculos entre resumo, débitos e visão 360", async () => {
    const summaries = await mockFiscalService.listTaxpayerSummaries(MUNICIPALITY_ID);
    expect(summaries.length).toBeGreaterThan(0);

    const taxpayerId = summaries[0]!.taxpayerId;
    const debts = await mockFiscalService.listDebtPeriods(MUNICIPALITY_ID, taxpayerId);
    expect(debts.every((item) => item.taxpayerId === taxpayerId)).toBe(true);
  });

  it("limita a busca aos registros fictícios conhecidos", async () => {
    const summaries = await mockFiscalService.listTaxpayerSummaries(MUNICIPALITY_ID);
    const results = await mockFiscalService.searchFiscal(summaries[0]!.legalName, MUNICIPALITY_ID);
    expect(results[0]?.metadata["taxpayerId"]).toBe(summaries[0]!.taxpayerId);
  });

  it("não reutiliza dados fictícios em outro contexto municipal", async () => {
    await expect(mockFiscalService.listTaxpayerSummaries("demo-outro-municipio")).resolves.toEqual(
      [],
    );
    await expect(
      mockFiscalService.searchFiscal("Contribuinte", "demo-outro-municipio"),
    ).resolves.toEqual([]);
  });

  it("separa todas as chaves municipais e mantém apenas a saúde como global", () => {
    expect(fiscalKeys.dashboard("municipality-a")).not.toEqual(
      fiscalKeys.dashboard("municipality-b"),
    );
    expect(fiscalKeys.taxpayers("municipality-a")).not.toEqual(
      fiscalKeys.taxpayers("municipality-b"),
    );
    expect(fiscalKeys.debts("municipality-a", "taxpayer-1")).not.toEqual(
      fiscalKeys.debts("municipality-b", "taxpayer-1"),
    );
    expect(fiscalKeys.portal("municipality-a")).not.toEqual(fiscalKeys.portal("municipality-b"));
    expect(fiscalKeys.health).toEqual(["platform", "worker-health"]);
  });

  it("mantém escritas desabilitadas na demonstração", async () => {
    await expect(
      mockFiscalService.submitCaseQuestion("case-demo", "Pergunta válida", "request:demo-123"),
    ).rejects.toThrow("demo_write_disabled");
    await expect(
      mockFiscalService.claimCaseQuestion(
        "question-demo",
        "demo-cordeiropolis",
        "membership-demo",
        "human",
      ),
    ).rejects.toThrow("demo_write_disabled");
  });

  it("expõe a conversa fictícia somente para leitura", async () => {
    const queue = await mockFiscalService.listChatQueue(MUNICIPALITY_ID);
    const messages = await mockFiscalService.listCaseMessages(
      queue[0]!.municipalityId,
      queue[0]!.caseId,
    );
    expect(messages).toHaveLength(1);
    expect(messages[0]?.body).toBe(queue[0]?.lastMessage);
  });

  it("mantém toda entrega externa zerada", async () => {
    const report = await mockFiscalService.getOperationalReport(MUNICIPALITY_ID);
    expect(report.externalDeliveryCount).toBe(0);
  });

  it("rejeita leitura sem município explícito", () => {
    expect(() => mockFiscalService.listTaxpayerSummaries(" ")).toThrow("invalid_municipality_id");
  });
});
