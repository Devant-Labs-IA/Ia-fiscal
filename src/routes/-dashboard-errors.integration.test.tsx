// @vitest-environment jsdom

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, render, screen } from "@testing-library/react";
import { Suspense } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { Route } from "@/routes/index";

const mocks = vi.hoisted(() => ({
  rejected: vi.fn(() => Promise.reject(new Error("read_failed"))),
}));

vi.mock("@/auth/AuthContext", () => ({
  useAuth: () => ({ access: { municipalityId: "municipality-1" } }),
}));

vi.mock("@/services/fiscal-service", () => ({
  fiscalKeys: {
    dashboard: (municipalityId: string) => ["municipality", municipalityId, "dashboard"],
    cases: (municipalityId: string) => ["municipality", municipalityId, "cases"],
    chat: (municipalityId: string) => ["municipality", municipalityId, "chat"],
    notifications: (municipalityId: string) => ["municipality", municipalityId, "notifications"],
    health: ["platform", "worker-health"],
    blockers: (municipalityId: string) => ["municipality", municipalityId, "blockers"],
    events: (municipalityId: string) => ["municipality", municipalityId, "events"],
  },
  fiscalService: {
    getDashboardSummary: mocks.rejected,
    listFiscalCases: mocks.rejected,
    listChatQueue: mocks.rejected,
    listNotificationCandidates: mocks.rejected,
    listProcessingHealth: mocks.rejected,
    listProductionBlockers: mocks.rejected,
    listAuditEvents: mocks.rejected,
  },
}));

afterEach(() => cleanup());

describe("erros independentes do dashboard", () => {
  it("não apresenta falha de consulta como lista vazia", async () => {
    const Page = Route.options.component;
    if (!Page) throw new Error("dashboard route component is required");
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });

    await act(async () => {
      render(
        <QueryClientProvider client={queryClient}>
          <Suspense fallback={<p>Carregando dashboard…</p>}>
            <Page />
          </Suspense>
        </QueryClientProvider>,
      );
    });

    expect(
      await screen.findByText(
        "Não foi possível carregar os indicadores. Tente novamente.",
        {},
        { timeout: 3_000 },
      ),
    ).toBeTruthy();
    expect(screen.getByText("Não foi possível carregar os casos prioritários.")).toBeTruthy();
    expect(screen.getByText("Não foi possível carregar a fila de atendimento.")).toBeTruthy();
    expect(
      screen.getByText("Não foi possível carregar os candidatos de notificação."),
    ).toBeTruthy();
    expect(screen.getByText("Não foi possível consultar a saúde do processamento.")).toBeTruthy();
    expect(screen.getByText("Não foi possível carregar os bloqueios de produção.")).toBeTruthy();
    expect(screen.getByText("Não foi possível carregar a atividade recente.")).toBeTruthy();
    expect(screen.getByText("Contagem indisponível. Nenhum envio foi liberado.")).toBeTruthy();
    expect(screen.getByText("contagem indisponível")).toBeTruthy();
  });
});
