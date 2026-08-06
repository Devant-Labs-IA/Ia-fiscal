import {
  auditEvents,
  chatQueue,
  dashboardSummary,
  debts,
  fiscalCases,
  notificationCandidates,
  processingHealth,
  productionBlockers,
  taxpayers,
} from "@/data/mocks";
import type { FiscalService } from "@/services/fiscal-service";
import type {
  CaseMessageReadModel,
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

const LATENCY_MS = 180;
const DEMO_MUNICIPALITY_ID = "demo-cordeiropolis";

function resolve<T>(value: T): Promise<T> {
  return new Promise((done) => setTimeout(() => done(value), LATENCY_MS));
}

function hasDemoMunicipality(municipalityId: string): boolean {
  if (!municipalityId.trim()) throw new Error("invalid_municipality_id");
  return municipalityId === DEMO_MUNICIPALITY_ID;
}

function summaryFromTaxpayer(index: number): Taxpayer360Summary {
  const taxpayer = taxpayers[index]!;
  const taxpayerDebts = debts.filter((debt) => debt.taxpayerId === taxpayer.id);
  const taxpayerCases = fiscalCases.filter((item) => item.taxpayer.id === taxpayer.id);
  const openBalance = taxpayerDebts.reduce((total, debt) => total + debt.amount, 0);
  return {
    municipalityId: DEMO_MUNICIPALITY_ID,
    taxpayerId: taxpayer.id,
    municipalRegistration: `HML-${String(index + 1).padStart(5, "0")}`,
    taxId: taxpayer.cnpj,
    legalName: taxpayer.name,
    tradeName: taxpayer.tradeName,
    taxpayerType: taxpayer.segment,
    taxpayerStatus: taxpayer.registrationStatus,
    debtPeriodCount: taxpayerDebts.length,
    overduePeriodCount: taxpayerDebts.filter((debt) => debt.status === "vencido").length,
    incompleteDebtPeriodCount: 0,
    openBalanceTotal: openBalance,
    oldestOpenDueOn: taxpayerDebts[0]?.dueDate ?? null,
    divergenceCount: taxpayerCases.length,
    activeDivergenceCount: taxpayerCases.filter((item) => item.status !== "concluido").length,
    blockedDivergenceCount: 0,
    divergenceAmountTotal: taxpayerCases.reduce((total, item) => total + item.amount, 0),
    caseCount: taxpayerCases.length,
    activeCaseCount: taxpayerCases.filter((item) => item.status !== "concluido").length,
    blockedCalculationCount: index === 0 ? 2 : 0,
    contactCount: 1,
    verifiedContactCount: 0,
    responsibleCount: 1,
    deliveryReadyResponsibleCount: 0,
    waitingQuestionCount: chatQueue.some((item) => item.cnpj === taxpayer.cnpj) ? 1 : 0,
    operationalAttentionLevel: openBalance > 0 ? "attention" : "normal",
    primaryActionLabel: openBalance > 0 ? "Analisar saldo municipal em aberto" : null,
    primaryActionReason: openBalance > 0 ? "Competência com saldo em aberto" : null,
    primaryActionPriority: openBalance > 0 ? "attention" : null,
    primaryActionDueAt: null,
  };
}

const summaries = taxpayers.map((_, index) => summaryFromTaxpayer(index));

const debtPeriods: DebtPeriod[] = debts.map((debt) => ({
  municipalityId: DEMO_MUNICIPALITY_ID,
  taxpayerId: debt.taxpayerId,
  competence: debt.competences[0] ?? "",
  assessedAmount: debt.amount,
  overdueAmount: debt.status === "vencido" ? debt.amount : 0,
  paidAmount: 0,
  derivedCreditsAmount: 0,
  openBalance: debt.amount,
  incompleteAmount: 0,
  futureAmount: debt.status === "a_vencer" ? debt.amount : 0,
  firstDueOn: debt.dueDate,
  lastDueOn: debt.dueDate,
  status: debt.status,
  eligible: debt.status === "vencido",
  ruleVersion: "demo-only",
  asOf: dashboardSummary.referenceDate,
}));

const divergences: DivergenceReadModel[] = fiscalCases.map((item, index) => ({
  municipalityId: DEMO_MUNICIPALITY_ID,
  divergenceId: `demo-divergence-${index + 1}`,
  taxpayerId: item.taxpayer.id,
  taxId: item.taxpayer.cnpj,
  taxpayerName: item.taxpayer.name,
  divergenceType: item.divergenceType,
  periodStart: item.debt.dueDate,
  periodEnd: item.debt.dueDate,
  differenceAmount: item.amount,
  priorityScore: null,
  status: item.status,
  executionMode: "sandbox",
  ruleCode: "demo-only",
  ruleVersion: 1,
  blockReasons: [],
  hasCaseFinding: true,
}));

const caseRows: FiscalCaseReadModel[] = fiscalCases.map((item, index) => ({
  municipalityId: DEMO_MUNICIPALITY_ID,
  caseId: item.id,
  caseNumber: `HML-${item.id.toUpperCase()}`,
  divergenceId: `demo-divergence-${index + 1}`,
  taxpayerId: item.taxpayer.id,
  taxpayerName: item.taxpayer.name,
  status: item.status,
  confidentiality: "internal",
  executionMode: "sandbox",
  openedAt: dashboardSummary.referenceDate,
  updatedAt: dashboardSummary.referenceDate,
  explanationTitle: item.divergenceType,
  explanationSummary: item.divergenceDetail,
  legalBasisSummary: item.legalBasis.join(" · "),
  legalReviewRequired: true,
  waitingQuestionCount: 0,
}));

const recipientRows: NotificationRecipientReadModel[] = notificationCandidates.map((item) => ({
  municipalityId: DEMO_MUNICIPALITY_ID,
  taxpayerId: item.id,
  candidateId: item.id,
  proposedFor: "initial_notice",
  recipientType: "taxpayer",
  maskedEmail: item.contact,
  candidateStatus: item.status,
  deliveryBlockReason: item.blockedReason,
  priority: 100,
  readyPendingExternalAuthorization: false,
  safeForDelivery: false,
  externalDeliveryAuthorized: false,
  createdAt: dashboardSummary.referenceDate,
}));

const knowledgeRows: KnowledgeArticleReadModel[] = [
  {
    municipalityId: DEMO_MUNICIPALITY_ID,
    articleId: "demo-knowledge-1",
    intentKey: "consulta_debito",
    semanticVersion: 1,
    canonicalQuestion: "Como consultar a composição de um débito municipal?",
    taxScope: "ISSQN",
    divergenceScope: "conta_corrente",
    answerBody:
      "A composição deve ser consultada no ambiente autenticado. Esta resposta fictícia não produz ciência, prazo ou efeito fiscal.",
    validFrom: "2026-01-01T00:00:00-03:00",
    validUntil: null,
    publishedAt: dashboardSummary.referenceDate,
    isTest: true,
  },
];

const portalRows: PortalCaseReadModel[] = caseRows.slice(0, 2).map((item) => ({
  municipalityId: item.municipalityId,
  caseId: item.caseId,
  caseNumber: item.caseNumber,
  taxpayerId: item.taxpayerId,
  taxpayerName: item.taxpayerName,
  caseStatus: item.status,
  executionMode: "sandbox",
  explanationStatus: "prepared",
  title: item.explanationTitle ?? "Conferência fiscal",
  summary: item.explanationSummary ?? "",
  divergenceSummary: {},
  legalBasisSummary: item.legalBasisSummary ?? "",
  citations: [],
  officialSystemUrl: "https://araras.sigissweb.com/",
  portalPath: `/portal?case=${item.caseId}`,
  legalReviewRequired: true,
  threadId: null,
  threadStatus: null,
}));

function report(municipalityId: string): OperationalReport {
  const visible = hasDemoMunicipality(municipalityId);
  const scopedSummaries = visible ? summaries : [];
  const scopedDebts = visible ? debtPeriods : [];
  const scopedDivergences = visible ? divergences : [];
  const scopedCases = visible ? caseRows : [];
  const scopedQueue = visible ? chatQueue : [];
  return {
    taxpayerCount: scopedSummaries.length,
    overduePeriodCount: scopedDebts.filter((item) => item.status === "vencido").length,
    openBalanceTotal: scopedDebts.reduce((total, item) => total + item.openBalance, 0),
    activeDivergenceCount: scopedDivergences.length,
    divergenceAmountTotal: scopedDivergences.reduce(
      (total, item) => total + item.differenceAmount,
      0,
    ),
    activeCaseCount: scopedCases.length,
    blockedCalculationCount: visible ? 24 : 0,
    waitingQuestionCount: scopedQueue.length,
    recipientCandidateCount: visible ? 86 : 0,
    deliveryReadyCount: 0,
    externalDeliveryCount: 0,
  };
}

export const mockFiscalService: FiscalService = {
  getDashboardSummary: (municipalityId) =>
    resolve(
      hasDemoMunicipality(municipalityId) ? dashboardSummary : { ...dashboardSummary, metrics: [] },
    ),
  listFiscalCases: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? fiscalCases : []),
  listChatQueue: (municipalityId) =>
    resolve(
      hasDemoMunicipality(municipalityId)
        ? chatQueue.filter((item) => item.municipalityId === municipalityId)
        : [],
    ),
  listNotificationCandidates: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? notificationCandidates : []),
  listProcessingHealth: () => resolve(processingHealth),
  listProductionBlockers: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? productionBlockers : []),
  listAuditEvents: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? auditEvents : []),
  listTaxpayers: (municipalityId) => resolve(hasDemoMunicipality(municipalityId) ? taxpayers : []),
  listTaxpayerSummaries: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? summaries : []),
  listDebtPeriods: (municipalityId, taxpayerId) =>
    resolve(
      hasDemoMunicipality(municipalityId)
        ? taxpayerId
          ? debtPeriods.filter((item) => item.taxpayerId === taxpayerId)
          : debtPeriods
        : [],
    ),
  listDivergences: (municipalityId, taxpayerId) =>
    resolve(
      hasDemoMunicipality(municipalityId)
        ? taxpayerId
          ? divergences.filter((item) => item.taxpayerId === taxpayerId)
          : divergences
        : [],
    ),
  listFiscalCaseRows: (municipalityId, taxpayerId) =>
    resolve(
      hasDemoMunicipality(municipalityId)
        ? taxpayerId
          ? caseRows.filter((item) => item.taxpayerId === taxpayerId)
          : caseRows
        : [],
    ),
  listNotificationRecipients: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? recipientRows : []),
  listKnowledgeArticles: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? knowledgeRows : []),
  listPortalCases: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? portalRows : []),
  listCaseMessages: (municipalityId, caseId) => {
    if (!hasDemoMunicipality(municipalityId)) return resolve([]);
    const item = chatQueue.find(
      (question) => question.municipalityId === municipalityId && question.caseId === caseId,
    );
    const messages: CaseMessageReadModel[] = item
      ? [
          {
            id: `demo-message:${item.id}`,
            caseId,
            body: item.lastMessage,
            senderType: "taxpayer",
            sourceType: "portal",
            status: "published",
            visibility: "participants",
            createdAt: item.waitingSince,
            publishedAt: item.waitingSince,
          },
        ]
      : [];
    return resolve(messages);
  },
  getOperationalReport: (municipalityId) => resolve(report(municipalityId)),
  async claimCaseQuestion() {
    throw new Error("demo_write_disabled");
  },
  async submitCaseQuestion() {
    throw new Error("demo_write_disabled");
  },
  searchFiscal(query, municipalityId) {
    if (!hasDemoMunicipality(municipalityId)) return resolve([]);
    const normalized = query.toLocaleLowerCase("pt-BR");
    const results: SearchResultItem[] = summaries
      .filter(
        (item) =>
          item.legalName.toLocaleLowerCase("pt-BR").includes(normalized) ||
          item.taxId.includes(query.replace(/\D/g, "")),
      )
      .map((item) => ({
        resultType: "taxpayer",
        title: item.legalName,
        subtitle: item.municipalRegistration,
        route: `/contribuintes/${item.taxpayerId}`,
        metadata: { taxpayerId: item.taxpayerId },
      }));
    return resolve(results);
  },
};
