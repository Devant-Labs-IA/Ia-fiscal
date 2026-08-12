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
    limit: vi.fn(),
    abortSignal: vi.fn().mockResolvedValue({ data, error: null }),
  };
  chain.select.mockReturnValue(chain);
  chain.eq.mockReturnValue(chain);
  chain.in.mockReturnValue(chain);
  chain.order.mockReturnValue(chain);
  chain.limit.mockReturnValue(chain);
  return chain;
}

function rpcChain(data: unknown) {
  return {
    abortSignal: vi.fn().mockResolvedValue({ data, error: null }),
  };
}

beforeEach(() => {
  mocks.from.mockReset();
  mocks.rpc.mockReset();
});

describe("contrato Supabase do atendimento", () => {
  it("consulta o relatório operacional agregado por município", async () => {
    const chain = rpcChain({ taxpayer_count: 3, open_balance_total: "151.40" });
    mocks.rpc.mockReturnValue(chain);

    await expect(
      supabaseFiscalService.getOperationalReport("municipality-1"),
    ).resolves.toMatchObject({
      taxpayerCount: 3,
      openBalanceTotal: 151.4,
    });
    expect(mocks.rpc).toHaveBeenCalledWith("ia_operational_report", {
      p_municipality_id: "municipality-1",
    });
    expect(chain.abortSignal).toHaveBeenCalledTimes(1);
  });

  it("compartilha o relatório enquanto a mesma consulta municipal está em andamento", async () => {
    let release: ((value: { data: unknown; error: null }) => void) | undefined;
    const pending = new Promise<{ data: unknown; error: null }>((resolve) => {
      release = resolve;
    });
    mocks.rpc.mockReturnValue({ abortSignal: vi.fn(() => pending) });

    const first = supabaseFiscalService.getOperationalReport("municipality-dedup");
    const second = supabaseFiscalService.getOperationalReport("municipality-dedup");

    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    release?.({ data: { taxpayer_count: 2 }, error: null });
    await expect(Promise.all([first, second])).resolves.toEqual([
      expect.objectContaining({ taxpayerCount: 2 }),
      expect.objectContaining({ taxpayerCount: 2 }),
    ]);
  });

  it("mapeia regra explicativa e motivos de bloqueio em JSON", async () => {
    const chain = readChain([
      {
        municipality_id: "municipality-1",
        divergence_id: "divergence-1",
        rule_code: "CURRENT_ACCOUNT_BALANCE_HOMOLOGATION_V1",
        rule_name: "Conferência do saldo da conta corrente",
        rule_description: "Compara lançamentos, pagamentos e saldo em aberto.",
        block_reasons: '[{"code":"unverification"}]',
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.listDivergences("municipality-1")).resolves.toEqual([
      expect.objectContaining({
        ruleName: "Conferência do saldo da conta corrente",
        ruleDescription: "Compara lançamentos, pagamentos e saldo em aberto.",
        blockReasons: ["unverification"],
      }),
    ]);
  });

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

  it("apresenta o status do worker em português", async () => {
    const chain = readChain([
      {
        worker_name: "divergence-worker",
        status: "unhealthy",
        pending_jobs: 4,
        dead_letter_jobs: 2,
        last_success_at: "2026-08-11T15:30:00Z",
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.listProcessingHealth()).resolves.toEqual([
      expect.objectContaining({
        label: "Processador de divergências fiscais",
        status: "critico",
        detail: "Situação: Crítico · Pendentes: 4 · Falhas definitivas: 2",
        metric: expect.stringMatching(/^Último processamento: 11\/08\/2026/),
      }),
    ]);
  });

  it("traduz o tipo e a visibilidade dos eventos", async () => {
    const chain = readChain([
      {
        id: 10,
        event_type: "case_question_claimed",
        visibility: "staff",
        occurred_at: "2026-08-11T12:00:00Z",
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.listAuditEvents("municipality-1")).resolves.toEqual([
      expect.objectContaining({
        title: "Atendimento assumido pela equipe fiscal",
        description: "Evento auditável visível para equipe fiscal.",
      }),
    ]);
  });

  it("normaliza finalidade e bloqueio das notificações do dashboard", async () => {
    const chain = readChain([
      {
        municipality_id: "municipality-1",
        candidate_id: "candidate-1",
        proposed_for: "initial_notice",
        candidate_status: "blocked_unverified",
        delivery_block_reason: "relationship_unverified;external_delivery_not_authorized",
        safe_for_delivery: false,
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(
      supabaseFiscalService.listNotificationCandidates("municipality-1"),
    ).resolves.toEqual([
      expect.objectContaining({
        templateName: "Aviso inicial de conferência",
        blockedReason:
          "Vínculo com o contribuinte ainda não verificado · Envio externo não autorizado",
      }),
    ]);
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
