import { describe, expect, it } from "vitest";

import { mockFiscalService } from "@/services/mock-fiscal-service";

describe("serviço fiscal demonstrativo", () => {
  it("preserva vínculos entre resumo, débitos e visão 360", async () => {
    const summaries = await mockFiscalService.listTaxpayerSummaries();
    expect(summaries.length).toBeGreaterThan(0);

    const taxpayerId = summaries[0]!.taxpayerId;
    const debts = await mockFiscalService.listDebtPeriods(taxpayerId);
    expect(debts.every((item) => item.taxpayerId === taxpayerId)).toBe(true);
  });

  it("limita a busca aos registros fictícios conhecidos", async () => {
    const summaries = await mockFiscalService.listTaxpayerSummaries();
    const results = await mockFiscalService.searchFiscal(summaries[0]!.legalName, "demo");
    expect(results[0]?.metadata["taxpayerId"]).toBe(summaries[0]!.taxpayerId);
  });

  it("mantém escritas desabilitadas na demonstração", async () => {
    await expect(
      mockFiscalService.submitCaseQuestion("case-demo", "Pergunta válida", "request:demo-123"),
    ).rejects.toThrow("demo_write_disabled");
  });

  it("mantém toda entrega externa zerada", async () => {
    const report = await mockFiscalService.getOperationalReport();
    expect(report.externalDeliveryCount).toBe(0);
  });
});
