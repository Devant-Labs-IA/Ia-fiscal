// @vitest-environment jsdom

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Route } from "@/routes/configuracoes";

const mocks = vi.hoisted(() => ({
  auth: {
    access: {
      role: "municipal_admin",
      municipalityId: "municipality-1",
      municipalityLabel: "Araras/SP",
    },
    municipalityContexts: [
      {
        id: "municipality-1",
        label: "Araras/SP",
        name: "Araras",
        stateCode: "SP",
        ibgeCode: "3503307",
      },
    ],
    demo: false,
    user: { id: "admin-1" },
  },
  listUsers: vi.fn(),
  addUser: vi.fn(),
  updateMembership: vi.fn(),
  getSafetyStatus: vi.fn(),
}));

vi.mock("@/auth/AuthContext", () => ({ useAuth: () => mocks.auth }));
vi.mock("@/services/fiscal-service", () => ({
  fiscalKeys: {
    municipalityUsers: (municipalityId: string) => ["municipality", municipalityId, "users"],
    externalDeliverySafety: (municipalityId: string) => [
      "municipality",
      municipalityId,
      "external-delivery-safety",
    ],
  },
  fiscalService: {
    listMunicipalityUsers: mocks.listUsers,
    addExistingMunicipalityUser: mocks.addUser,
    updateMunicipalityMembership: mocks.updateMembership,
    getAssistedOperationSafetyStatus: mocks.getSafetyStatus,
  },
}));

beforeEach(() => {
  mocks.auth.access.role = "municipal_admin";
  mocks.listUsers.mockReset().mockResolvedValue([
    {
      membershipId: "membership-1",
      userId: "user-1",
      fullName: "Fiscal de Homologação",
      email: "fiscal@prefeitura.gov.br",
      role: "fiscal_auditor",
      status: "active",
      validFrom: "2026-08-01T10:00:00Z",
      validUntil: null,
      lastSeenAt: null,
    },
  ]);
  mocks.getSafetyStatus.mockReset().mockResolvedValue({
    verified: true,
    externalDeliveryBlocked: true,
    masterLock: true,
    externalEmailEnabled: false,
    openEmailChannel: false,
    automaticNoticeEnabled: false,
    pendingExternalJobs: 0,
    checkedAt: "2026-08-13T12:00:00Z",
  });
});

afterEach(() => cleanup());

async function renderPage() {
  const Page = Route.options.component;
  if (!Page) throw new Error("configuracoes route component is required");
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  await act(async () => {
    render(
      <QueryClientProvider client={queryClient}>
        <Page />
      </QueryClientProvider>,
    );
  });
}

describe("configurações administrativas", () => {
  it("exibe diretório municipal em português sem detalhes técnicos do backend", async () => {
    await renderPage();

    expect(
      await screen.findByText("Fiscal de Homologação", undefined, { timeout: 3_000 }),
    ).toBeTruthy();
    expect(screen.getByText("fiscal@prefeitura.gov.br")).toBeTruthy();
    expect(screen.getByText(/Esta ação não cria conta, não envia convite/)).toBeTruthy();
    expect(screen.queryByText("Backend")).toBeNull();
    expect(screen.getAllByText(/operação assistida/i).length).toBeGreaterThan(0);
    expect(await screen.findByText("Envios externos bloqueados com segurança")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Preparar envios externos" }));
    expect(await screen.findByText("Preparação segura de envios externos")).toBeTruthy();
    expect(screen.getByText(/não desbloqueia, agenda, autoriza ou envia/)).toBeTruthy();
    expect(mocks.listUsers).toHaveBeenCalledWith("municipality-1");
    expect(mocks.getSafetyStatus).toHaveBeenCalledWith("municipality-1");
  });

  it("bloqueia a página para quem não é administrador municipal", async () => {
    mocks.auth.access.role = "supervisor";
    await renderPage();

    expect(screen.getByText("Acesso administrativo necessário")).toBeTruthy();
    expect(screen.queryByText("Adicionar conta existente")).toBeNull();
    expect(mocks.listUsers).not.toHaveBeenCalled();
  });
});
