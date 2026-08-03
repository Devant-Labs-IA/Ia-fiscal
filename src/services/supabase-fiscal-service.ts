import { runtimeConfig } from "@/config/runtime";
import { getSupabaseClient } from "@/lib/supabase";
import type { FiscalService } from "@/services/fiscal-service";
import type {
  AuditEvent,
  ChatQueueItem,
  DashboardMetric,
  DashboardSummary,
  Debt,
  FiscalCase,
  NotificationCandidate,
  ProcessingHealthIndicator,
  ProductionBlocker,
  RiskLevel,
  Taxpayer,
} from "@/types/fiscal";
import type {
  DebtPeriod,
  DivergenceReadModel,
  FiscalCaseReadModel,
  KnowledgeArticleReadModel,
  NotificationRecipientReadModel,
  OperationalReport,
  PortalCaseReadModel,
  SearchResultItem,
  Taxpayer360Summary,
} from "@/types/read-models";

type Row = Record<string, unknown>;

class FiscalDataError extends Error {
  constructor(readonly code: string) {
    super(`fiscal_data_error:${code}`);
    this.name = "FiscalDataError";
  }
}

function stringValue(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function numberValue(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function booleanValue(value: unknown): boolean {
  return value === true;
}

function stringArray(value: unknown): string[] {
  if (Array.isArray(value)) return value.filter((item): item is string => typeof item === "string");
  return [];
}

function objectValue(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function throwIfError(error: { code?: string } | null): void {
  if (error) throw new FiscalDataError(error.code?.slice(0, 80) || "query_failed");
}

function statusToRisk(status: string, waitingQuestionCount = 0): RiskLevel {
  // Operational priority only. This must never be presented as a legal risk conclusion.
  if (waitingQuestionCount > 0) return "alto";
  if (["awaiting_fiscal", "review_pending"].includes(status)) return "alto";
  if (["blocked", "pending_revalidation"].includes(status)) return "medio";
  return "baixo";
}

function mapSummary(row: Row): Taxpayer360Summary {
  return {
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    municipalRegistration: stringValue(row["municipal_registration"], "—"),
    taxId: stringValue(row["tax_id"]),
    legalName: stringValue(row["legal_name"], "Contribuinte sem nome"),
    tradeName: stringValue(row["trade_name"]),
    taxpayerType: stringValue(row["taxpayer_type"], "não classificado"),
    taxpayerStatus: stringValue(row["taxpayer_status"], "unknown"),
    debtPeriodCount: numberValue(row["debt_period_count"]),
    overduePeriodCount: numberValue(row["overdue_period_count"]),
    incompleteDebtPeriodCount: numberValue(row["incomplete_debt_period_count"]),
    openBalanceTotal: numberValue(row["open_balance_total"]),
    oldestOpenDueOn: nullableString(row["oldest_open_due_on"]),
    divergenceCount: numberValue(row["divergence_count"]),
    activeDivergenceCount: numberValue(row["active_divergence_count"]),
    blockedDivergenceCount: numberValue(row["blocked_divergence_count"]),
    divergenceAmountTotal: numberValue(row["divergence_amount_total"]),
    caseCount: numberValue(row["case_count"]),
    activeCaseCount: numberValue(row["active_case_count"]),
    blockedCalculationCount: numberValue(row["blocked_calculation_count"]),
    contactCount: numberValue(row["contact_count"]),
    verifiedContactCount: numberValue(row["verified_contact_count"]),
    responsibleCount: numberValue(row["responsible_count"]),
    deliveryReadyResponsibleCount: numberValue(row["delivery_ready_responsible_count"]),
    waitingQuestionCount: numberValue(row["waiting_question_count"]),
    operationalAttentionLevel: stringValue(row["operational_attention_level"], "normal"),
    primaryActionLabel: nullableString(row["primary_action_label"]),
    primaryActionReason: nullableString(row["primary_action_reason"]),
    primaryActionPriority: nullableString(row["primary_action_priority"]),
    primaryActionDueAt: nullableString(row["primary_action_due_at"]),
  };
}

function mapDebt(row: Row): DebtPeriod {
  return {
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    competence: stringValue(row["competencia"]),
    assessedAmount: numberValue(row["valor_emitido"]),
    overdueAmount: numberValue(row["valor_vencido"]),
    paidAmount: numberValue(row["valor_pago"]),
    derivedCreditsAmount: numberValue(row["applied_credits_derived"]),
    openBalance: numberValue(row["saldo_em_aberto"]),
    incompleteAmount: numberValue(row["valor_sem_vencimento"]),
    futureAmount: numberValue(row["valor_a_vencer"]),
    firstDueOn: nullableString(row["primeiro_vencimento"]),
    lastDueOn: nullableString(row["ultimo_vencimento"]),
    status: stringValue(row["status"], "unknown"),
    eligible: booleanValue(row["elegivel"]),
    ruleVersion: stringValue(row["regra_versao"], "unknown"),
    asOf: nullableString(row["data_base"]),
  };
}

function mapDivergence(row: Row): DivergenceReadModel {
  return {
    municipalityId: stringValue(row["municipality_id"]),
    divergenceId: stringValue(row["divergence_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    taxId: stringValue(row["tax_id"]),
    taxpayerName: stringValue(row["legal_name"], "Contribuinte sem nome"),
    divergenceType: stringValue(row["divergence_type"], "não classificada"),
    periodStart: stringValue(row["period_start"]),
    periodEnd: stringValue(row["period_end"]),
    differenceAmount: numberValue(row["difference_amount"]),
    priorityScore: row["priority_score"] == null ? null : numberValue(row["priority_score"]),
    status: stringValue(row["status"], "unknown"),
    executionMode: stringValue(row["execution_mode"], "sandbox"),
    ruleCode: stringValue(row["rule_code"], "unknown"),
    ruleVersion:
      row["rule_version_number"] == null ? null : numberValue(row["rule_version_number"]),
    blockReasons: stringArray(row["block_reasons"]),
    hasCaseFinding: booleanValue(row["has_case_finding"]),
  };
}

function mapCase(row: Row): FiscalCaseReadModel {
  return {
    municipalityId: stringValue(row["municipality_id"]),
    caseId: stringValue(row["case_id"] ?? row["id"]),
    caseNumber: stringValue(row["case_number"], "—"),
    taxpayerId: stringValue(row["taxpayer_id"]),
    taxpayerName: stringValue(row["taxpayer_name"] ?? row["legal_name"], "Contribuinte sem nome"),
    status: stringValue(row["status"] ?? row["case_status"], "unknown"),
    confidentiality: stringValue(row["confidentiality"], "internal"),
    executionMode: stringValue(row["execution_mode"], "sandbox"),
    openedAt: stringValue(row["opened_at"]),
    updatedAt: nullableString(row["updated_at"]),
    explanationTitle: nullableString(row["current_explanation_title"]),
    explanationSummary: nullableString(row["current_explanation_summary"]),
    legalBasisSummary: nullableString(row["legal_basis_summary"]),
    legalReviewRequired: booleanValue(row["legal_review_required"]),
    waitingQuestionCount: numberValue(row["waiting_question_count"]),
  };
}

async function listTaxpayerSummaries(): Promise<Taxpayer360Summary[]> {
  const { data, error } = await getSupabaseClient()
    .from("vw_taxpayer_360_summary")
    .select("*")
    .order("open_balance_total", { ascending: false })
    .limit(500);
  throwIfError(error);
  return (data as Row[] | null)?.map(mapSummary) ?? [];
}

async function listDebtPeriods(taxpayerId?: string): Promise<DebtPeriod[]> {
  let query = getSupabaseClient()
    .from("vw_taxpayer_360_debts")
    .select("*")
    .order("competencia", { ascending: false })
    .limit(1000);
  if (taxpayerId) query = query.eq("taxpayer_id", taxpayerId);
  const { data, error } = await query;
  throwIfError(error);
  return (data as Row[] | null)?.map(mapDebt) ?? [];
}

async function listDivergences(taxpayerId?: string): Promise<DivergenceReadModel[]> {
  let query = getSupabaseClient()
    .from("vw_taxpayer_360_divergences")
    .select("*")
    .order("as_of", { ascending: false })
    .limit(1000);
  if (taxpayerId) query = query.eq("taxpayer_id", taxpayerId);
  const { data, error } = await query;
  throwIfError(error);
  return (data as Row[] | null)?.map(mapDivergence) ?? [];
}

async function listFiscalCaseRows(taxpayerId?: string): Promise<FiscalCaseReadModel[]> {
  let query = getSupabaseClient()
    .from("vw_taxpayer_360_cases")
    .select("*")
    .order("opened_at", { ascending: false })
    .limit(500);
  if (taxpayerId) query = query.eq("taxpayer_id", taxpayerId);
  const { data, error } = await query;
  throwIfError(error);
  return (data as Row[] | null)?.map(mapCase) ?? [];
}

async function listNotificationRecipients(): Promise<NotificationRecipientReadModel[]> {
  const { data, error } = await getSupabaseClient()
    .from("vw_notification_recipient_candidates")
    .select("*")
    .order("priority", { ascending: true })
    .limit(1000);
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((row) => ({
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    candidateId: stringValue(row["candidate_id"]),
    proposedFor: stringValue(row["proposed_for"]),
    recipientType: stringValue(row["recipient_type"]),
    maskedEmail: stringValue(row["masked_email"], "***"),
    candidateStatus: stringValue(row["candidate_status"], "unknown"),
    deliveryBlockReason: stringValue(row["delivery_block_reason"], "Validação pendente"),
    priority: numberValue(row["priority"]),
    readyPendingExternalAuthorization: booleanValue(row["ready_pending_external_authorization"]),
    safeForDelivery: booleanValue(row["safe_for_delivery"]),
    externalDeliveryAuthorized: booleanValue(row["external_delivery_authorized"]),
    createdAt: stringValue(row["created_at"]),
  }));
}

async function listKnowledgeArticles(): Promise<KnowledgeArticleReadModel[]> {
  const { data, error } = await getSupabaseClient()
    .from("vw_reusable_knowledge_articles")
    .select("*")
    .order("published_at", { ascending: false })
    .limit(200);
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((row) => ({
    municipalityId: stringValue(row["municipality_id"]),
    articleId: stringValue(row["article_id"]),
    intentKey: stringValue(row["intent_key"]),
    semanticVersion: numberValue(row["semantic_version"]),
    canonicalQuestion: stringValue(row["canonical_question"]),
    taxScope: stringValue(row["tax_scope"]),
    divergenceScope: stringValue(row["divergence_scope"]),
    answerBody: stringValue(row["answer_body"]),
    validFrom: nullableString(row["valid_from"]),
    validUntil: nullableString(row["valid_until"]),
    publishedAt: nullableString(row["published_at"]),
    isTest: booleanValue(row["is_test"]),
  }));
}

async function listPortalCases(): Promise<PortalCaseReadModel[]> {
  const { data, error } = await getSupabaseClient()
    .from("vw_case_portal_home")
    .select("*")
    .order("prepared_at", { ascending: false })
    .limit(200);
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((row) => ({
    municipalityId: stringValue(row["municipality_id"]),
    caseId: stringValue(row["case_id"]),
    caseNumber: stringValue(row["case_number"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    taxpayerName: stringValue(row["taxpayer_name"]),
    caseStatus: stringValue(row["case_status"]),
    executionMode: stringValue(row["execution_mode"], "sandbox"),
    explanationStatus: stringValue(row["explanation_status"]),
    title: stringValue(row["title"]),
    summary: stringValue(row["summary"]),
    divergenceSummary: objectValue(row["divergence_summary"]),
    legalBasisSummary: stringValue(row["legal_basis_summary"]),
    citations: Array.isArray(row["citations_snapshot"]) ? row["citations_snapshot"] : [],
    officialSystemUrl: nullableString(row["official_system_url"]),
    portalPath: nullableString(row["portal_path"]),
    legalReviewRequired: booleanValue(row["legal_review_required"]),
    threadId: nullableString(row["thread_id"]),
    threadStatus: nullableString(row["thread_status"]),
  }));
}

async function getOperationalReport(): Promise<OperationalReport> {
  const [taxpayers, recipients] = await Promise.all([
    listTaxpayerSummaries(),
    listNotificationRecipients(),
  ]);
  return {
    taxpayerCount: taxpayers.length,
    overduePeriodCount: taxpayers.reduce((total, item) => total + item.overduePeriodCount, 0),
    openBalanceTotal: taxpayers.reduce((total, item) => total + item.openBalanceTotal, 0),
    activeDivergenceCount: taxpayers.reduce((total, item) => total + item.activeDivergenceCount, 0),
    divergenceAmountTotal: taxpayers.reduce((total, item) => total + item.divergenceAmountTotal, 0),
    activeCaseCount: taxpayers.reduce((total, item) => total + item.activeCaseCount, 0),
    blockedCalculationCount: taxpayers.reduce(
      (total, item) => total + item.blockedCalculationCount,
      0,
    ),
    waitingQuestionCount: taxpayers.reduce((total, item) => total + item.waitingQuestionCount, 0),
    recipientCandidateCount: recipients.length,
    deliveryReadyCount: recipients.filter((item) => item.safeForDelivery).length,
    externalDeliveryCount: recipients.filter((item) => item.externalDeliveryAuthorized).length,
  };
}

function dashboardMetrics(report: OperationalReport): DashboardMetric[] {
  return [
    {
      id: "contribuintes",
      label: "Contribuintes monitorados",
      value: report.taxpayerCount.toLocaleString("pt-BR"),
      context: "Registros visíveis para o perfil e município atuais",
      tone: "neutro",
      icon: "contribuintes",
      route: "/contribuintes",
    },
    {
      id: "debitos",
      label: "Competências com saldo vencido",
      value: report.overduePeriodCount.toLocaleString("pt-BR"),
      context: "Somente vencimentos classificados por regra governada",
      tone: report.overduePeriodCount > 0 ? "atencao" : "positivo",
      icon: "debitos",
      route: "/debitos",
    },
    {
      id: "fiscalizacoes",
      label: "Processos ativos visíveis",
      value: report.activeCaseCount.toLocaleString("pt-BR"),
      context: "Casos sigilosos dependem de atribuição ativa",
      tone: "neutro",
      icon: "fiscalizacoes",
      route: "/fiscalizacoes",
    },
    {
      id: "notificacoes",
      label: "Candidatos de destinatário",
      value: report.recipientCandidateCount.toLocaleString("pt-BR"),
      context: `${report.deliveryReadyCount} aptos após validação; envio externo bloqueado`,
      tone: "atencao",
      icon: "notificacoes",
      route: "/notificacoes",
    },
    {
      id: "atendimento",
      label: "Perguntas aguardando",
      value: report.waitingQuestionCount.toLocaleString("pt-BR"),
      context: "Fila do ambiente autenticado",
      tone: report.waitingQuestionCount > 0 ? "atencao" : "positivo",
      icon: "atendimento",
      route: "/atendimento",
    },
    {
      id: "calculos",
      label: "Cálculos bloqueados",
      value: report.blockedCalculationCount.toLocaleString("pt-BR"),
      context: "Dados insuficientes impedem resultado conclusivo",
      tone: report.blockedCalculationCount > 0 ? "critico" : "positivo",
      icon: "calculos",
      route: "/relatorios",
    },
  ];
}

async function listFiscalCasesLegacy(): Promise<FiscalCase[]> {
  const [cases, summaries, debtPeriods] = await Promise.all([
    listFiscalCaseRows(),
    listTaxpayerSummaries(),
    listDebtPeriods(),
  ]);
  const byTaxpayer = new Map(summaries.map((item) => [item.taxpayerId, item]));
  return cases.map((item) => {
    const summary = byTaxpayer.get(item.taxpayerId);
    const period = debtPeriods.find((debt) => debt.taxpayerId === item.taxpayerId);
    const taxpayer: Taxpayer = {
      id: item.taxpayerId,
      name: item.taxpayerName,
      cnpj: summary?.taxId ?? "",
      tradeName: summary?.tradeName ?? "",
      segment: summary?.taxpayerType ?? "não classificado",
      city: runtimeConfig.municipalityLabel,
      registrationStatus: summary?.taxpayerStatus === "active" ? "ativo" : "suspenso",
      monitoredSince: item.openedAt,
    };
    const debt: Debt = {
      id: `debt:${item.caseId}`,
      taxpayerId: item.taxpayerId,
      tax: "ISSQN — conferência municipal",
      competences: period?.competence ? [period.competence] : [],
      amount: period?.openBalance ?? 0,
      dueDate: period?.firstDueOn ?? item.openedAt,
      status: period?.status === "em_aberto" ? "vencido" : "em_discussao",
    };
    return {
      id: item.caseId,
      taxpayer,
      divergenceType: item.explanationTitle ?? "Conferência fiscal",
      divergenceDetail: item.explanationSummary ?? "Detalhes disponíveis no dossiê autenticado.",
      amount: debt.amount,
      competences: debt.competences,
      risk: statusToRisk(item.status, item.waitingQuestionCount),
      assignee: "Atribuição governada",
      status:
        item.status === "closed"
          ? "concluido"
          : item.status === "awaiting_fiscal"
            ? "aguardando_documento"
            : "em_analise",
      legalBasis: item.legalBasisSummary ? [item.legalBasisSummary] : [],
      debt,
    };
  });
}

async function listChatQueue(): Promise<ChatQueueItem[]> {
  const { data, error } = await getSupabaseClient()
    .from("vw_fiscal_chat_inbox")
    .select("*")
    .order("priority", { ascending: false })
    .order("created_at", { ascending: true })
    .limit(200);
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((row) => ({
    id: stringValue(row["question_id"]),
    taxpayerName: stringValue(row["taxpayer_name"]),
    cnpj: "identificador protegido",
    lastMessage: stringValue(row["question_preview"]),
    waitingSince: stringValue(row["created_at"]),
    waitingLabel: nullableString(row["sla_due_at"]) ? "SLA registrado" : "sem SLA configurado",
    origin: "portal do contribuinte",
    priority: statusToRisk(stringValue(row["status"]), numberValue(row["priority"])),
    suggestedReply: "Nova resposta exige revisão humana ou conhecimento publicado vigente.",
  }));
}

async function listProcessingHealth(): Promise<ProcessingHealthIndicator[]> {
  const { data, error } = await getSupabaseClient().from("api_worker_health").select("*").limit(50);
  throwIfError(error);
  if (!data?.length) {
    return [
      {
        id: "worker-not-observed",
        label: "Worker sandbox",
        status: "pausado",
        detail: "Nenhuma execução observável foi registrada",
        metric: "homologação bloqueada",
      },
    ];
  }
  return (data as Row[]).map((row) => ({
    id: stringValue(row["worker_name"]),
    label: stringValue(row["worker_name"]),
    status: stringValue(row["status"]) === "healthy" ? "operacional" : "atencao",
    detail: `Pendentes: ${numberValue(row["pending_jobs"])} · dead letter: ${numberValue(row["dead_letter_jobs"])}`,
    metric: nullableString(row["last_success_at"]) ?? "sem sucesso registrado",
  }));
}

async function listAuditEvents(): Promise<AuditEvent[]> {
  const { data, error } = await getSupabaseClient()
    .from("case_events")
    .select("id, event_type, occurred_at, visibility")
    .order("occurred_at", { ascending: false })
    .limit(20);
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((row) => ({
    id: stringValue(row["id"]),
    type: "escalonamento",
    title: stringValue(row["event_type"], "Evento do processo"),
    description: `Evento auditável com visibilidade ${stringValue(row["visibility"], "restrita")}.`,
    occurredAt: stringValue(row["occurred_at"]),
    actor: "Identidade registrada na trilha de auditoria",
  }));
}

async function searchFiscal(query: string, municipalityId: string): Promise<SearchResultItem[]> {
  const normalized = query.trim();
  if (normalized.length < 2 || normalized.length > 500) {
    throw new FiscalDataError("invalid_search_length");
  }
  const { data, error } = await getSupabaseClient().functions.invoke("ia-fiscal-search", {
    body: { municipality_id: municipalityId, query: normalized, limit: 30, offset: 0 },
  });
  if (error) throw new FiscalDataError("search_failed");
  const envelope = objectValue(data);
  const payload = objectValue(envelope["data"] ?? envelope);
  const intent = stringValue(payload["intent"], "unsupported");
  const rows = Array.isArray(payload["rows"]) ? (payload["rows"] as Row[]) : [];
  return rows.map((row) => {
    const taxpayerId = stringValue(row["taxpayer_id"]);
    const caseId = stringValue(row["case_id"]);
    const title = stringValue(row["legal_name"] ?? row["case_number"], "Resultado fiscal");
    return {
      resultType: intent,
      title,
      subtitle: stringValue(
        row["masked_tax_id"] ?? row["divergence_type"] ?? row["status"],
        "Resultado governado",
      ),
      route: taxpayerId ? `/contribuintes/${taxpayerId}` : caseId ? "/fiscalizacoes" : null,
      metadata: row,
    };
  });
}

export const supabaseFiscalService: FiscalService = {
  async getDashboardSummary(): Promise<DashboardSummary> {
    const report = await getOperationalReport();
    return {
      environmentLabel: "Homologação — nenhum envio externo autorizado",
      greeting: "Painel do Fiscal",
      operationalSummary:
        "Prioridade operacional não representa risco jurídico, lançamento ou conclusão fiscal.",
      referenceDate: new Date().toISOString(),
      metrics: dashboardMetrics(report),
    };
  },
  listFiscalCases: listFiscalCasesLegacy,
  listChatQueue,
  async listNotificationCandidates(): Promise<NotificationCandidate[]> {
    const recipients = await listNotificationRecipients();
    return recipients.slice(0, 20).map((item) => ({
      id: item.candidateId,
      taxpayerName: "Contribuinte protegido",
      cnpj: "identificador protegido",
      channel: "e-mail",
      contact: item.maskedEmail,
      contactValidated: item.readyPendingExternalAuthorization,
      templateName: item.proposedFor || "Aviso inicial de cortesia",
      status: item.safeForDelivery ? "preparado" : "bloqueado",
      blockedReason: item.deliveryBlockReason,
      draftMessage: "Conteúdo disponível apenas após seleção de template governado.",
    }));
  },
  listProcessingHealth,
  async listProductionBlockers(): Promise<ProductionBlocker[]> {
    const report = await getOperationalReport();
    return [
      {
        id: "contacts",
        title: "Validação de destinatários",
        description: `${report.recipientCandidateCount - report.deliveryReadyCount} candidato(s) ainda bloqueado(s).`,
        done:
          report.recipientCandidateCount > 0 &&
          report.deliveryReadyCount === report.recipientCandidateCount,
        owner: "Cadastro + Fazenda",
      },
      {
        id: "calculations",
        title: "Dados obrigatórios dos cálculos",
        description: `${report.blockedCalculationCount} cálculo(s) bloqueado(s) por dados insuficientes.`,
        done: report.blockedCalculationCount === 0,
        owner: "Fazenda",
      },
      {
        id: "external-delivery",
        title: "Envio externo",
        description: "Permanece deliberadamente desabilitado no ambiente de homologação.",
        done: false,
        owner: "Chefia fiscal + Procuradoria",
      },
    ];
  },
  listAuditEvents,
  async listTaxpayers(): Promise<Taxpayer[]> {
    const rows = await listTaxpayerSummaries();
    return rows.map((row) => ({
      id: row.taxpayerId,
      name: row.legalName,
      cnpj: row.taxId,
      tradeName: row.tradeName,
      segment: row.taxpayerType,
      city: runtimeConfig.municipalityLabel,
      registrationStatus: row.taxpayerStatus === "active" ? "ativo" : "suspenso",
      monitoredSince: row.oldestOpenDueOn ?? new Date().toISOString(),
    }));
  },
  listTaxpayerSummaries,
  listDebtPeriods,
  listDivergences,
  listFiscalCaseRows,
  listNotificationRecipients,
  listKnowledgeArticles,
  listPortalCases,
  getOperationalReport,
  async submitCaseQuestion(caseId, body, clientRequestId): Promise<string> {
    const normalizedBody = body.trim();
    if (normalizedBody.length < 5 || normalizedBody.length > 4000) {
      throw new FiscalDataError("invalid_question_length");
    }
    if (!/^[a-zA-Z0-9:_-]{8,120}$/.test(clientRequestId)) {
      throw new FiscalDataError("invalid_client_request_id");
    }
    const { data, error } = await getSupabaseClient().rpc("ia_submit_case_question", {
      p_case_id: caseId,
      p_body: normalizedBody,
      p_client_request_id: clientRequestId,
    });
    throwIfError(error);
    return stringValue(data, clientRequestId);
  },
  searchFiscal,
};
