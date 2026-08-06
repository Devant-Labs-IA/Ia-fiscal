import { beforeEach, describe, expect, it, vi } from "vitest";

import { supabaseFiscalService } from "@/services/supabase-fiscal-service";

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
}));

vi.mock("@/lib/supabase", () => ({
  getSupabaseClient: () => ({ from: mocks.from, rpc: mocks.rpc }),
}));

function readChain(data: Record<string, unknown>[]) {
  const chain = {
    select: vi.fn(),
    eq: vi.fn(),
    in: vi.fn(),
    order: vi.fn(),
    limit: vi.fn().mockResolvedValue({ data, error: null }),
  };
  chain.select.mockReturnValue(chain);
  chain.eq.mockReturnValue(chain);
  chain.in.mockReturnValue(chain);
  chain.order.mockReturnValue(chain);
  return chain;
}

beforeEach(() => {
  mocks.from.mockReset();
  mocks.rpc.mockReset();
});

describe("contrato Supabase do atendimento", () => {
  it.each([
    [
      "resumos de contribuinte",
      "vw_taxpayer_360_summary",
      () => supabaseFiscalService.listTaxpayerSummaries("municipality-1"),
    ],
    [
      "períodos de débito",
      "vw_taxpayer_360_debts",
      () => supabaseFiscalService.listDebtPeriods("municipality-1"),
    ],
    [
      "divergências",
      "vw_taxpayer_360_divergences",
      () => supabaseFiscalService.listDivergences("municipality-1"),
    ],
    [
      "casos fiscais",
      "vw_taxpayer_360_cases",
      () => supabaseFiscalService.listFiscalCaseRows("municipality-1"),
    ],
    [
      "destinatários",
      "vw_notification_recipient_candidates",
      () => supabaseFiscalService.listNotificationRecipients("municipality-1"),
    ],
    [
      "conhecimento",
      "vw_reusable_knowledge_articles",
      () => supabaseFiscalService.listKnowledgeArticles("municipality-1"),
    ],
    [
      "portal",
      "vw_case_portal_home",
      () => supabaseFiscalService.listPortalCases("municipality-1"),
    ],
    ["eventos", "case_events", () => supabaseFiscalService.listAuditEvents("municipality-1")],
  ])("fixa municipality_id em %s", async (_label, table, run) => {
    const chain = readChain([]);
    mocks.from.mockReturnValue(chain);

    await run();

    expect(mocks.from).toHaveBeenCalledWith(table);
    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
  });

  it("mantém a saúde do worker como leitura global sem coluna municipal", async () => {
    const chain = readChain([]);
    mocks.from.mockReturnValue(chain);

    await supabaseFiscalService.listProcessingHealth();

    expect(mocks.from).toHaveBeenCalledWith("api_worker_health");
    expect(chain.eq).not.toHaveBeenCalled();
  });

  it("rejeita leitura municipal sem contexto explícito", async () => {
    await expect(supabaseFiscalService.listTaxpayerSummaries(" ")).rejects.toThrow(
      "invalid_municipality_id",
    );
    expect(mocks.from).not.toHaveBeenCalled();
  });

  it("mapeia a fila com vínculo de caso e prioridade operacional pelo SLA", async () => {
    const chain = readChain([
      {
        question_id: "question-1",
        municipality_id: "municipality-1",
        case_id: "case-1",
        case_number: "FIS-001",
        taxpayer_name: "Contribuinte protegido",
        question_preview: "Pergunta",
        created_at: "2026-08-01T10:00:00-03:00",
        sla_due_at: "2020-01-01T00:00:00Z",
        status: "submitted",
        handling_mode: null,
        assigned_membership_id: null,
        claimed_at: null,
      },
    ]);
    mocks.from.mockReturnValue(chain);

    const result = await supabaseFiscalService.listChatQueue("municipality-1");

    expect(mocks.from).toHaveBeenCalledWith("vw_fiscal_chat_inbox");
    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(chain.in).toHaveBeenCalledWith("status", ["waiting", "claimed"]);
    expect(chain.order).toHaveBeenCalledWith("operational_priority", { ascending: false });
    expect(chain.order).toHaveBeenCalledWith("sla_due_at", {
      ascending: true,
      nullsFirst: false,
    });
    expect(result[0]).toMatchObject({
      id: "question-1",
      municipalityId: "municipality-1",
      caseId: "case-1",
      caseNumber: "FIS-001",
      priority: "critico",
      handlingMode: "unassigned",
      assignedMembershipId: null,
    });
  });

  it("consulta somente a conversa do caso solicitado", async () => {
    const chain = readChain([
      {
        id: "message-newest",
        case_id: "case-1",
        body: "Mensagem mais recente",
        sender_type: "fiscal",
        source_type: "manual",
        status: "published",
        visibility: "participants",
        created_at: "2026-08-01T11:00:00-03:00",
        published_at: "2026-08-01T11:00:00-03:00",
      },
      {
        id: "message-1",
        case_id: "case-1",
        body: "Mensagem autorizada",
        sender_type: "taxpayer",
        source_type: "portal",
        status: "published",
        visibility: "participants",
        created_at: "2026-08-01T10:00:00-03:00",
        published_at: "2026-08-01T10:00:00-03:00",
      },
    ]);
    mocks.from.mockReturnValue(chain);

    const result = await supabaseFiscalService.listCaseMessages("municipality-1", "case-1");

    expect(mocks.from).toHaveBeenCalledWith("case_messages");
    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(chain.eq).toHaveBeenCalledWith("case_id", "case-1");
    expect(chain.order).toHaveBeenCalledWith("created_at", { ascending: false });
    expect(result.map((message) => message.body)).toEqual([
      "Mensagem autorizada",
      "Mensagem mais recente",
    ]);
  });

  it("chama somente a RPC de atribuição humana e exige membership no retorno", async () => {
    mocks.rpc.mockResolvedValue({ data: "membership-1", error: null });

    await expect(
      supabaseFiscalService.claimCaseQuestion(
        "question-1",
        "municipality-1",
        "membership-1",
        "human",
      ),
    ).resolves.toBe("membership-1");
    expect(mocks.rpc).toHaveBeenCalledWith("ia_claim_case_question", {
      p_question_id: "question-1",
      p_expected_municipality_id: "municipality-1",
      p_expected_membership_id: "membership-1",
      p_handling_mode: "human",
    });
  });
});
