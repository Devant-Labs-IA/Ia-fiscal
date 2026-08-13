// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { OnboardingGate } from "@/components/onboarding/OnboardingGate";
import { ONBOARDING_VERSION } from "@/config/onboarding";

const mocks = vi.hoisted(() => ({
  load: vi.fn(),
  save: vi.fn(),
}));

vi.mock("@/services/onboarding-service", async (importOriginal) => {
  const original = await importOriginal<typeof import("@/services/onboarding-service")>();
  return {
    ...original,
    onboardingService: {
      load: mocks.load,
      save: mocks.save,
    },
  };
});

beforeEach(() => {
  mocks.load.mockReset().mockResolvedValue(null);
  mocks.save.mockReset().mockImplementation(async (input) => ({
    userId: input.userId,
    onboardingKey: `first-access:${input.role}`,
    onboardingVersion: ONBOARDING_VERSION,
    currentStep: input.currentStep,
    completedAt: input.completed ? "2026-08-13T12:00:00Z" : null,
    updatedAt: "2026-08-13T12:00:00Z",
  }));
});

afterEach(() => cleanup());

function renderGate(role: "platform_admin" | "fiscal_auditor" = "platform_admin") {
  const signOut = vi.fn();
  render(
    <OnboardingGate userId="user-1" role={role} onSignOut={signOut}>
      {({ openTutorial }) => (
        <button type="button" onClick={openTutorial}>
          Ajuda
        </button>
      )}
    </OnboardingGate>,
  );
  return { signOut };
}

describe("bloqueio de primeiro acesso", () => {
  it("mantém um modal acessível durante o carregamento e bloqueia Escape", async () => {
    let resolveLoad: ((value: null) => void) | undefined;
    mocks.load.mockReturnValue(
      new Promise<null>((resolve) => {
        resolveLoad = resolve;
      }),
    );
    renderGate();

    expect(screen.getByText("Preparando seu treinamento")).toBeTruthy();
    const loadingDialog = screen.getByRole("dialog");
    expect(loadingDialog).toBeTruthy();
    expect(loadingDialog.contains(document.activeElement)).toBe(true);
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.getByRole("dialog")).toBeTruthy();

    await act(async () => resolveLoad?.(null));
    expect(
      await screen.findByText("Acompanhe a plataforma sem assumir a função fiscal"),
    ).toBeTruthy();
    expect(screen.getByRole("dialog").className).toContain("max-h-[calc(100dvh-1rem)]");
    expect(document.querySelector(".overflow-y-auto")).toBeTruthy();
  });

  it("mantém a falha de carregamento em um modal ativo e não dispensável", async () => {
    mocks.load.mockRejectedValue(new Error("indisponível"));
    renderGate();

    expect(await screen.findByText("O treinamento não pôde ser carregado")).toBeTruthy();
    const errorDialog = screen.getByRole("dialog");
    expect(errorDialog.contains(document.activeElement)).toBe(true);
    expect(screen.queryByRole("button", { name: "Fechar" })).toBeNull();

    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Tentar novamente" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Encerrar sessão" })).toBeTruthy();
  });

  it("não permite dispensar o tutorial inicial e salva a conclusão", async () => {
    renderGate();
    expect(
      await screen.findByText("Acompanhe a plataforma sem assumir a função fiscal"),
    ).toBeTruthy();

    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(screen.getByText("Encerrar sessão")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Próxima etapa" }));
    expect(await screen.findByText("Fluxo da administração da plataforma")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Concluir treinamento" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(mocks.save).toHaveBeenLastCalledWith(
      expect.objectContaining({ completed: true, role: "platform_admin" }),
    );
  });

  it("não abre automaticamente quando a versão atual já foi concluída e permite refazer", async () => {
    mocks.load.mockResolvedValue({
      userId: "user-1",
      onboardingKey: "first-access:platform_admin",
      onboardingVersion: ONBOARDING_VERSION,
      currentStep: 2,
      completedAt: "2026-08-13T12:00:00Z",
      updatedAt: "2026-08-13T12:00:00Z",
    });
    renderGate();

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    fireEvent.click(screen.getByRole("button", { name: "Ajuda" }));
    expect(await screen.findByRole("dialog")).toBeTruthy();
    expect(screen.getByText("Fechar treinamento")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Próxima etapa" }));
    expect(mocks.save).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Concluir treinamento" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(mocks.save).toHaveBeenCalledTimes(1);
    expect(mocks.save).toHaveBeenCalledWith(
      expect.objectContaining({ completed: true, role: "platform_admin" }),
    );
    expect(mocks.save).not.toHaveBeenCalledWith(expect.objectContaining({ completed: false }));
  });

  it("retoma a etapa persistida da versão atual", async () => {
    mocks.load.mockResolvedValue({
      userId: "user-1",
      onboardingKey: "first-access:fiscal_auditor",
      onboardingVersion: ONBOARDING_VERSION,
      currentStep: 5,
      completedAt: null,
      updatedAt: "2026-08-13T12:00:00Z",
    });
    renderGate("fiscal_auditor");

    expect(await screen.findByText("Valide a prévia sem enviar ao cliente")).toBeTruthy();
    expect(screen.getByText("Etapa 6 de 12")).toBeTruthy();
  });

  it("reinicia obrigatoriamente quando a versão do treinamento muda", async () => {
    mocks.load.mockResolvedValue({
      userId: "user-1",
      onboardingKey: "first-access:platform_admin",
      onboardingVersion: 99,
      currentStep: 2,
      completedAt: "2026-08-13T12:00:00Z",
      updatedAt: "2026-08-13T12:00:00Z",
    });
    renderGate();

    expect(
      await screen.findByText("Acompanhe a plataforma sem assumir a função fiscal"),
    ).toBeTruthy();
    expect(screen.getByText("Etapa 1 de 2")).toBeTruthy();
    expect(screen.getByText("Encerrar sessão")).toBeTruthy();
  });
});
