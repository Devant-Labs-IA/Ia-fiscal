// @vitest-environment jsdom

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Topbar } from "@/components/layout/Topbar";
import { SidebarProvider } from "@/components/ui/sidebar";

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
});
