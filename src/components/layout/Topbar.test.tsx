// @vitest-environment jsdom

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Topbar } from "@/components/layout/Topbar";
import { SidebarProvider } from "@/components/ui/sidebar";

const serviceMocks = vi.hoisted(() => ({ searchFiscal: vi.fn() }));

vi.mock("@/services/fiscal-service", () => ({
  fiscalService: { searchFiscal: serviceMocks.searchFiscal },
}));

vi.mock("@/auth/AuthContext", () => ({
  useAuth: () => ({
    access: {
      role: "fiscal_auditor",
      municipalityId: "municipality-1",
      municipalityLabel: "Cordeirópolis/SP",
      platformAdmin: false,
    },
    municipalityContexts: [],
    user: { email: "fiscal@prefeitura.gov.br", user_metadata: {} },
    demo: false,
    signOut: vi.fn(),
  }),
}));

beforeEach(() => {
  serviceMocks.searchFiscal.mockReset();
  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  });
});

afterEach(() => cleanup());

describe("ajuda na barra superior", () => {
  it("reabre o treinamento e descreve corretamente o bloqueio externo", () => {
    const openTutorial = vi.fn();
    render(
      <SidebarProvider>
        <Topbar onOpenTutorial={openTutorial} />
      </SidebarProvider>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Abrir treinamento de uso do sistema" }));
    expect(openTutorial).toHaveBeenCalledOnce();
    expect(screen.getByRole("button", { name: "Comunicações externas bloqueadas" })).toBeTruthy();
  });

  it("anuncia carregamento e quantidade de resultados da busca global", async () => {
    let finishSearch: ((value: unknown[]) => void) | undefined;
    serviceMocks.searchFiscal.mockReturnValue(
      new Promise((resolve) => {
        finishSearch = resolve;
      }),
    );
    render(
      <SidebarProvider>
        <Topbar />
      </SidebarProvider>,
    );

    const input = screen.getByLabelText("Buscar contribuinte, CNPJ ou processo");
    fireEvent.change(input, { target: { value: "Empresa" } });
    fireEvent.submit(input.closest("form")!);

    expect(screen.getByRole("status").textContent).toContain("Busca em andamento");
    expect(input.getAttribute("aria-busy")).toBe("true");
    finishSearch?.([
      {
        resultType: "taxpayer",
        title: "Empresa Municipal",
        subtitle: "Cadastro autorizado",
        route: "/contribuintes/1",
        metadata: {},
      },
    ]);

    expect(await screen.findByText("Busca concluída. 1 resultado autorizado.")).toBeTruthy();
    expect(input.getAttribute("aria-controls")).toBe("resultados-busca-global");
    expect(input.getAttribute("aria-expanded")).toBe("true");
  });
});
