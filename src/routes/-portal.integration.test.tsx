// @vitest-environment jsdom

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { Suspense } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Route } from "@/routes/portal";

const mocks = vi.hoisted(() => ({
  listPortalCases: vi.fn(),
  submitCaseQuestion: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("@/auth/AuthContext", () => ({
  useAuth: () => ({
    access: {
      role: "taxpayer",
      municipalityId: "municipality-1",
      municipalityLabel: "Município",
      taxpayerId: "taxpayer-1",
    },
  }),
}));

vi.mock("@/services/fiscal-service", () => ({
  fiscalKeys: {
    portal: (municipalityId: string) => ["municipality", municipalityId, "portal-cases"],
  },
  fiscalService: {
    listPortalCases: mocks.listPortalCases,
    submitCaseQuestion: mocks.submitCaseQuestion,
  },
}));

vi.mock("sonner", () => ({
  toast: { success: mocks.toastSuccess, error: mocks.toastError },
}));

const PORTAL_CASE = {
  municipalityId: "municipality-1",
  caseId: "case-1",
  caseNumber: "FIS-001",
  taxpayerId: "taxpayer-1",
  taxpayerName: "Contribuinte Teste",
  caseStatus: "open",
  executionMode: "sandbox",
  explanationStatus: "draft",
  title: "Caso de teste",
  summary: "Resumo",
  divergenceSummary: {},
  legalBasisSummary: "",
  citations: [],
  officialSystemUrl: null,
  portalPath: null,
  legalReviewRequired: false,
  threadId: null,
  threadStatus: null,
};

async function renderPortal() {
  const PortalPage = Route.options.component;
  if (!PortalPage) throw new Error("portal route component is required");
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  await act(async () => {
    render(
      <QueryClientProvider client={queryClient}>
        <Suspense fallback={<p>Carregando portal…</p>}>
          <PortalPage />
        </Suspense>
      </QueryClientProvider>,
    );
  });
  return queryClient;
}

async function openConfirmation(body = "Qual é o fundamento deste lançamento?") {
  const textarea = await screen.findByPlaceholderText(
    "Descreva sua dúvida sem incluir senhas ou dados bancários.",
  );
  fireEvent.change(textarea, { target: { value: body } });
  fireEvent.click(screen.getByRole("button", { name: "Revisar e registrar pergunta" }));
  return screen.findByRole("button", { name: "Confirmar registro" });
}

beforeEach(() => {
  mocks.listPortalCases.mockReset().mockResolvedValue([PORTAL_CASE]);
  mocks.submitCaseQuestion.mockReset();
  mocks.toastSuccess.mockReset();
  mocks.toastError.mockReset();
});

afterEach(() => cleanup());

describe("envio idempotente no portal", () => {
  it("consulta somente o contexto municipal autenticado", async () => {
    await renderPortal();
    await waitFor(() => expect(mocks.listPortalCases).toHaveBeenCalledWith("municipality-1"));
  });

  it("desabilita a confirmação durante pending e bloqueia um segundo disparo", async () => {
    let resolveSubmission: ((questionId: string) => void) | undefined;
    mocks.submitCaseQuestion.mockImplementation(
      () =>
        new Promise<string>((resolve) => {
          resolveSubmission = resolve;
        }),
    );
    await renderPortal();
    const confirm = await openConfirmation();

    fireEvent.click(confirm);
    await waitFor(() => expect(mocks.submitCaseQuestion).toHaveBeenCalledTimes(1));
    const pendingButton = await screen.findByRole("button", { name: "Registrando…" });
    expect((pendingButton as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(pendingButton);
    expect(mocks.submitCaseQuestion).toHaveBeenCalledTimes(1);

    await act(async () => resolveSubmission?.("question-1"));
    await waitFor(() => expect(mocks.toastSuccess).toHaveBeenCalledTimes(1));
  });

  it("reutiliza a request key após erro e troca a chave quando o conteúdo muda", async () => {
    mocks.submitCaseQuestion
      .mockRejectedValueOnce(new Error("network_error"))
      .mockResolvedValueOnce("question-1")
      .mockResolvedValueOnce("question-2");
    await renderPortal();
    const firstConfirm = await openConfirmation("Pergunta original para retry");

    fireEvent.click(firstConfirm);
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledTimes(1));
    fireEvent.click(await screen.findByRole("button", { name: "Confirmar registro" }));
    await waitFor(() => expect(mocks.submitCaseQuestion).toHaveBeenCalledTimes(2));

    const firstKey = String(mocks.submitCaseQuestion.mock.calls[0]?.[2]);
    const retryKey = String(mocks.submitCaseQuestion.mock.calls[1]?.[2]);
    expect(retryKey).toBe(firstKey);

    await waitFor(() =>
      expect(screen.queryByRole("button", { name: "Confirmar registro" })).toBeNull(),
    );
    const secondConfirm = await openConfirmation("Pergunta alterada após o primeiro envio");
    fireEvent.click(secondConfirm);
    await waitFor(() => expect(mocks.submitCaseQuestion).toHaveBeenCalledTimes(3));

    const changedContentKey = String(mocks.submitCaseQuestion.mock.calls[2]?.[2]);
    expect(changedContentKey).not.toBe(firstKey);
  });
});
