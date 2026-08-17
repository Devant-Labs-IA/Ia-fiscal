import { describe, expect, it } from "vitest";

import {
  onboardingKeyForRole,
  onboardingStepsForRole,
  type OnboardingCapability,
} from "@/config/onboarding";
import type { AppRole } from "@/types/read-models";

describe("roteiros de primeiro acesso", () => {
  it("explica o fluxo fiscal e diferencia as capacidades reais", () => {
    const steps = onboardingStepsForRole("fiscal_auditor");
    const capabilities = new Set<OnboardingCapability>(steps.map((step) => step.capability));
    const content = steps.map((step) => `${step.title} ${step.summary}`).join(" ");

    expect(capabilities).toEqual(new Set(["available", "simulation", "blocked", "guidance"]));
    expect(content).toContain("Visão Fiscal 360");
    expect(content).toContain("Perguntas registradas pelo contribuinte no portal");
    expect(content).toContain("não envia, agenda ou autoriza e-mail");
    expect(content).toContain("não permite redigir, revisar ou publicar uma resposta");
  });

  it("mantém roteiros e chaves independentes por perfil", () => {
    const roles: AppRole[] = [
      "platform_admin",
      "municipal_admin",
      "supervisor",
      "fiscal_auditor",
      "legal_reviewer",
      "support_readonly",
      "taxpayer",
      "accountant",
    ];

    expect(new Set(roles.map(onboardingKeyForRole)).size).toBe(roles.length);
    roles.forEach((role) => expect(onboardingStepsForRole(role).length).toBeGreaterThan(1));
    expect(onboardingStepsForRole("municipal_admin").some((step) => step.id === "settings")).toBe(
      true,
    );
    expect(
      onboardingStepsForRole("municipal_admin").some((step) => step.id === "service-read-only"),
    ).toBe(true);
    expect(
      onboardingStepsForRole("support_readonly").some((step) => step.id === "service-read-only"),
    ).toBe(true);
    expect(onboardingStepsForRole("supervisor").some((step) => step.id === "service")).toBe(true);
    expect(onboardingStepsForRole("taxpayer").some((step) => step.id === "debts")).toBe(false);
  });
});
