import { describe, expect, it } from "vitest";

import { deriveExternalDeliverySafetyPresentation } from "@/lib/external-delivery-readiness";
import type { AssistedOperationSafetyStatus } from "@/types/read-models";

const safelyBlocked: AssistedOperationSafetyStatus = {
  verified: true,
  externalDeliveryBlocked: true,
  masterLock: true,
  externalEmailEnabled: false,
  openEmailChannel: false,
  automaticNoticeEnabled: false,
  pendingExternalJobs: 0,
  checkedAt: "2026-08-13T12:00:00Z",
};

describe("apresentação da prontidão de comunicação externa", () => {
  it("confirma somente o estado seguro de bloqueio", () => {
    const presentation = deriveExternalDeliverySafetyPresentation(safelyBlocked, "success");

    expect(presentation.state).toBe("blocked");
    expect(presentation.title).toBe("Envios externos bloqueados com segurança");
    expect(presentation.checklist).toHaveLength(5);
    expect(presentation.checklist.every((item) => item.state === "confirmed")).toBe(true);
  });

  it("exige revisão quando qualquer proteção está aberta", () => {
    const presentation = deriveExternalDeliverySafetyPresentation(
      {
        ...safelyBlocked,
        externalDeliveryBlocked: false,
        openEmailChannel: true,
      },
      "success",
    );

    expect(presentation.state).toBe("attention");
    expect(presentation.checklist.find((item) => item.id === "email-channel")?.state).toBe(
      "attention",
    );
  });

  it.each([
    [undefined, "error" as const],
    [{ ...safelyBlocked, verified: false }, "success" as const],
  ])("falha de forma fechada quando o estado não é confiável", (status, queryState) => {
    const presentation = deriveExternalDeliverySafetyPresentation(status, queryState);

    expect(presentation.state).toBe("unverified");
    expect(presentation.title).toBe("Estado não verificado");
    expect(presentation.checklist.every((item) => item.state === "unknown")).toBe(true);
  });

  it("não apresenta resultado enquanto a consulta está em andamento", () => {
    const presentation = deriveExternalDeliverySafetyPresentation(undefined, "loading");

    expect(presentation.state).toBe("checking");
    expect(presentation.checklist.every((item) => item.state === "unknown")).toBe(true);
  });
});
