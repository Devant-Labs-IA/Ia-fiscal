// @vitest-environment jsdom

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { Suspense } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Route } from "@/routes/atendimento";

const mocks = vi.hoisted(() => ({
  auth: {
    demo: false,
    access: {
      role: "fiscal_auditor",
      municipalityId: "municipality-1",
      municipalityLabel: "Município",
      membershipId: "membership-1",
    },
  },
  listChatQueue: vi.fn(),
  listCaseMessages: vi.fn(),
  claimCaseQuestion: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("@/auth/AuthContext", () => ({ useAuth: () => mocks.auth }));

vi.mock("@/services/fiscal-service", () => ({
  fiscalKeys: {
    chat: (municipalityId: string) => ["municipality", municipalityId, "chat"],
    events: (municipalityId: string) => ["municipality", municipalityId, "events"],
    caseMessages: (municipalityId: string, caseId: string) => [
      "municipality",
      municipalityId,
      "case-messages",
      caseId,
    ],
  },
  fiscalService: {
    listChatQueue: mocks.listChatQueue,
    listCaseMessages: mocks.listCaseMessages,
    claimCaseQuestion: mocks.claimCaseQuestion,
  },
}));

vi.mock("sonner", () => ({
  toast: { success: mocks.toastSuccess, error: mocks.toastError },
}));

const QUEUE_ITEM = {
  id: "question-1",
  municipalityId: "municipality-1",
  caseId: "case-1",
  caseNumber: "FIS-001",
  taxpayerName: "Contribuinte Teste",
  cnpj: "identificador protegido",
  lastMessage: "Como conferir o valor?",
  waitingSince: "2026-08-02T10:00:00-03:00",
  waitingLabel: "SLA registrado",
  slaDueAt: "2026-08-02T12:00:00-03:00",
  status: "submitted",
  handlingMode: "unassigned",
  assignedMembershipId: null,
  claimedAt: null,
  origin: "portal do contribuinte",
  priority: "alto",
  suggestedReply: "Sem resposta automática.",
};

async function renderQueue() {
  const Page = Route.options.component;
  if (!Page) throw new Error("atendimento route component is required");
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  await act(async () => {
    render(
      <QueryClientProvider client={queryClient}>
        <Suspense fallback={<p>Carregando atendimento…</p>}>
          <Page />
        </Suspense>
      </QueryClientProvider>,
    );
  });
  return queryClient;
}

beforeEach(() => {
  mocks.auth.demo = false;
  mocks.auth.access.role = "fiscal_auditor";
  mocks.auth.access.membershipId = "membership-1";
  mocks.listChatQueue.mockReset().mockResolvedValue([QUEUE_ITEM]);
  mocks.listCaseMessages.mockReset().mockResolvedValue([]);
  mocks.claimCaseQuestion.mockReset();
  mocks.toastSuccess.mockReset();
  mocks.toastError.mockReset();
});

afterEach(() => cleanup());

describe("atribuição supervisionada de atendimento", () => {
  it("registra um único claim enquanto a operação está pendente", async () => {
    let resolveClaim: ((membershipId: string) => void) | undefined;
    mocks.claimCaseQuestion.mockImplementation(
      () =>
        new Promise<string>((resolve) => {
          resolveClaim = resolve;
        }),
    );
    await renderQueue();

    const claimButton = await screen.findByRole("button", { name: "Assumir atendimento" });
    fireEvent.click(claimButton);
    await waitFor(() => expect(mocks.claimCaseQuestion).toHaveBeenCalledTimes(1));
    expect(mocks.claimCaseQuestion).toHaveBeenCalledWith(
      "question-1",
      "municipality-1",
      "membership-1",
      "human",
    );

    const pendingButton = screen.getByRole("button", { name: "Assumindo…" });
    expect((pendingButton as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(pendingButton);
    expect(mocks.claimCaseQuestion).toHaveBeenCalledTimes(1);

    await act(async () => resolveClaim?.("membership-1"));
    await waitFor(() => expect(mocks.toastSuccess).toHaveBeenCalledTimes(1));
    expect(mocks.toastError).not.toHaveBeenCalled();
  });

  it("não oferece claim no modo demonstrativo", async () => {
    mocks.auth.demo = true;
    await renderQueue();

    expect(await screen.findByText("Atribuição indisponível para este perfil")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Assumir atendimento" })).toBeNull();
    expect(mocks.claimCaseQuestion).not.toHaveBeenCalled();
  });

  it("não comunica sucesso quando o banco recusa a atribuição", async () => {
    mocks.claimCaseQuestion.mockRejectedValue(new Error("question already claimed"));
    await renderQueue();

    fireEvent.click(await screen.findByRole("button", { name: "Assumir atendimento" }));
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(mocks.listChatQueue.mock.calls.length).toBeGreaterThan(1));
    expect(mocks.toastSuccess).not.toHaveBeenCalled();
  });

  it("apresenta estado encerrado antes da atribuição preservada", async () => {
    mocks.listChatQueue.mockResolvedValue([
      {
        ...QUEUE_ITEM,
        status: "closed",
        assignedMembershipId: "membership-1",
      },
    ]);
    await renderQueue();

    expect(await screen.findByText("Atendimento encerrado")).toBeTruthy();
    expect(screen.queryByText("Assumido por você")).toBeNull();
    expect(screen.queryByRole("button", { name: "Assumir atendimento" })).toBeNull();
  });
});
