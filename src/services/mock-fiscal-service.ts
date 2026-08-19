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
import type { KnowledgeOperationsSnapshot } from "@/features/knowledge/knowledge-models";
import { validateTaxpayerInput } from "@/lib/taxpayer-validation";
import type { FiscalService } from "@/services/fiscal-service";
import type { CreateTaxpayerInput, Taxpayer, UpdateTaxpayerInput } from "@/types/fiscal";
import type {
  AssistedOperationSafetyStatus,
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
let demoTaxpayerSequence = summaries.length;

function requireDemoWriteMunicipality(municipalityId: string): void {
  if (!hasDemoMunicipality(municipalityId)) {
    throw new Error("write_not_available_for_municipality");
  }
}

function requireValidTaxpayerInput(
  input: CreateTaxpayerInput | UpdateTaxpayerInput,
): CreateTaxpayerInput {
  const validation = validateTaxpayerInput(input);
  if (!validation.valid) throw new Error("invalid_taxpayer_input");
  return validation.data;
}

function taxpayerFromSummary(item: Taxpayer360Summary): Taxpayer {
  return {
    id: item.taxpayerId,
    name: item.legalName,
    cnpj: item.taxId,
    tradeName: item.tradeName,
    segment: item.taxpayerType,
    city: "Cordeirópolis/SP",
    registrationStatus:
      item.taxpayerStatus === "active" || item.taxpayerStatus === "ativo" ? "ativo" : "suspenso",
    monitoredSince: item.oldestOpenDueOn ?? new Date().toISOString(),
  };
}

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
  ruleName: "Regra de demonstração",
  ruleDescription: "Regra fictícia usada somente para validar a interface na operação assistida.",
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
    revisionId: "demo-knowledge-revision-1",
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
    citations: [
      {
        citationId: "demo-citation-1",
        citationLabel: "Demonstração — artigo 1º",
        quotedExcerpt:
          "Trecho fictício usado apenas para demonstrar a apresentação de uma citação oficial.",
        sourceId: "demo-source-1",
        sourceTitle: "Código Tributário Municipal",
        officialIdentifier: "Lei Complementar nº 399/2024",
        officialUrl: "https://cordeiropolis.sp.gov.br/",
        sourceVersionId: "demo-source-version-1",
        sourceVersionNumber: 1,
        sourceVersionStatus: "published",
        sourceSha256: "0".repeat(64),
        publicationDate: "2024-12-20",
        validFrom: "2025-01-01",
        validUntil: null,
        sectionId: "demo-section-1",
        sectionKey: "artigo_1",
        sectionHeading: "Artigo 1º",
        sectionContentSha256: "1".repeat(64),
        isValid: true,
        blockers: [],
      },
    ],
  },
];

const knowledgeOperationsSnapshot: KnowledgeOperationsSnapshot = {
  verified: true,
  municipalityId: DEMO_MUNICIPALITY_ID,
  municipalityName: "Cordeirópolis",
  municipalitySlug: "cordeiropolis-sp",
  checkedAt: dashboardSummary.referenceDate,
  capabilities: {
    canView: true,
    canSearch: true,
    canSubmitCandidates: false,
    canReviewCandidates: false,
    canReviewSourceVersions: false,
    canReviewArticles: false,
    canPublishSourceVersions: false,
    canPublishArticles: false,
  },
  summary: {
    officialSources: 1,
    totalSourceVersions: 1,
    publishedSourceVersions: 0,
    pendingSourceReviews: 1,
    pendingSourceExtractions: 1,
    pendingSourcePublications: 0,
    pendingArticleReviews: 0,
    pendingCandidates: 0,
    pendingEmbeddings: 0,
    eligibleSections: 1,
    indexedSections: 1,
    indexedChunks: 1,
    lastIndexedAt: dashboardSummary.referenceDate,
    openChanges: 1,
    failedFetches24h: 0,
  },
  sources: [
    {
      sourceId: "demo-source-1",
      title: "Código Tributário Municipal",
      officialIdentifier: "Lei Complementar nº 399/2024",
      sourceType: "law",
      taxScope: "ISSQN",
      status: "under_review",
      officialUrl: "https://cordeiropolis.sp.gov.br/",
      trustTier: "official_primary",
      endpointStatus: "available",
      lastFetchStatus: "success",
      lastCheckedAt: dashboardSummary.referenceDate,
      lastChangeDetectedAt: dashboardSummary.referenceDate,
      lastErrorCode: null,
      lastErrorDetail: null,
      latestVersionId: "demo-source-version-1",
      latestVersionNumber: 1,
      latestVersionStatus: "under_review",
      latestValidFrom: "2025-01-01",
      latestValidUntil: null,
      blockers: ["source_review_required"],
      canReview: false,
      canPublish: false,
    },
  ],
  changes: [
    {
      changeSetId: "demo-change-1",
      sourceId: "demo-source-1",
      sourceTitle: "Código Tributário Municipal",
      changeType: "first_version",
      status: "pending_review",
      detectedAt: dashboardSummary.referenceDate,
      fromSha256: null,
      toSha256: "demo-content-hash",
      candidateVersionId: "demo-source-version-1",
      candidateVersionNumber: 1,
      candidateVersionStatus: "under_review",
      candidateValidFrom: "2025-01-01",
      candidateValidUntil: null,
      officialUrl: "https://cordeiropolis.sp.gov.br/",
      candidateContentPreview:
        "Art. 1º Esta lei institui as normas tributárias aplicáveis ao Município de Cordeirópolis.",
      sectionCount: 1,
      diffSummary: "Primeira versão oficial identificada para revisão.",
      blockers: ["source_review_required"],
      canReview: false,
      canPublish: false,
    },
  ],
  reviews: [],
  health: {
    status: "attention",
    staleSources: 0,
    failedSources: 0,
    blockedSources: 1,
    lastSuccessfulFetchAt: dashboardSummary.referenceDate,
    blockers: ["source_review_required"],
  },
  schedule: {
    enabled: false,
    cadenceLabel: "Todos os dias às 03h00",
    timeZone: "America/Sao_Paulo",
    nextRunAt: null,
    lastRunAt: dashboardSummary.referenceDate,
    lastRunStatus: "completed_unchanged",
    runtimeVerified: false,
    blockers: ["demo_runtime_simulated"],
  },
  index: {
    status: "attention",
    indexedSections: 1,
    eligibleSections: 1,
    embeddingModel: "Modelo semântico oficial",
    lastIndexedAt: dashboardSummary.referenceDate,
    blockers: [],
  },
  ocr: {
    contractVersion: "ia-fiscal-knowledge-ocr/v1",
    policyVersion: "ia-fiscal-knowledge-ocr-policy/v1",
    runtimeVerified: false,
    hasAttention: false,
    state: "blocked",
    jobs: {
      queued: 0,
      processing: 0,
      completed: 0,
      deadLetter: 0,
      blockedPageLimit: 0,
    },
    lastEventAt: null,
    limits: {
      maxPages: 120,
      maxPageCharacters: 1_000_000,
      maxTotalCharacters: 8_000_000,
      abovePageLimit: "manual_review_required",
    },
    candidateStatus: "under_review",
    autoPublish: false,
    blockers: ["knowledge_ocr_runtime_not_verified"],
  },
  reviewer: {
    verified: false,
    configured: false,
    activeCount: 0,
    currentUserCanReview: false,
    blockers: ["reviewer_state_not_verified"],
  },
  coverage: [],
  coverageLabel: "Cobertura inicial governada",
  corpusIntegral: false,
};

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
  const scopedSummaries = visible
    ? summaries.filter((item) => item.taxpayerStatus !== "inactive")
    : [];
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

function assistedOperationSafetyStatus(municipalityId: string): AssistedOperationSafetyStatus {
  hasDemoMunicipality(municipalityId);
  return {
    verified: true,
    externalDeliveryBlocked: true,
    masterLock: true,
    externalEmailEnabled: false,
    openEmailChannel: false,
    automaticNoticeEnabled: false,
    pendingExternalJobs: 0,
    checkedAt: dashboardSummary.referenceDate,
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
  listTaxpayers: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? summaries.map(taxpayerFromSummary) : []),
  listTaxpayerSummaries: (municipalityId) =>
    resolve(hasDemoMunicipality(municipalityId) ? summaries : []),
  createTaxpayer(municipalityId, input) {
    requireDemoWriteMunicipality(municipalityId);
    const data = requireValidTaxpayerInput(input);
    demoTaxpayerSequence += 1;
    const taxpayerId = `demo-taxpayer-${demoTaxpayerSequence}`;
    summaries.push({
      municipalityId,
      taxpayerId,
      municipalRegistration: data.municipalRegistration,
      taxId: data.taxId,
      legalName: data.legalName,
      tradeName: data.tradeName,
      taxpayerType: data.taxpayerType,
      taxpayerStatus: "active",
      debtPeriodCount: 0,
      overduePeriodCount: 0,
      incompleteDebtPeriodCount: 0,
      openBalanceTotal: 0,
      oldestOpenDueOn: null,
      divergenceCount: 0,
      activeDivergenceCount: 0,
      blockedDivergenceCount: 0,
      divergenceAmountTotal: 0,
      caseCount: 0,
      activeCaseCount: 0,
      blockedCalculationCount: 0,
      contactCount: 0,
      verifiedContactCount: 0,
      responsibleCount: 0,
      deliveryReadyResponsibleCount: 0,
      waitingQuestionCount: 0,
      operationalAttentionLevel: "normal",
      primaryActionLabel: null,
      primaryActionReason: null,
      primaryActionPriority: null,
      primaryActionDueAt: null,
    });
    return resolve(taxpayerId);
  },
  updateTaxpayer(municipalityId, taxpayerId, input) {
    requireDemoWriteMunicipality(municipalityId);
    const data = requireValidTaxpayerInput(input);
    const index = summaries.findIndex(
      (item) => item.municipalityId === municipalityId && item.taxpayerId === taxpayerId,
    );
    if (index < 0) throw new Error("taxpayer_not_found");
    summaries[index] = {
      ...summaries[index]!,
      municipalRegistration: data.municipalRegistration,
      taxId: data.taxId,
      legalName: data.legalName,
      tradeName: data.tradeName,
      taxpayerType: data.taxpayerType,
    };
    return resolve(undefined);
  },
  archiveTaxpayer(municipalityId, taxpayerId) {
    requireDemoWriteMunicipality(municipalityId);
    const index = summaries.findIndex(
      (item) => item.municipalityId === municipalityId && item.taxpayerId === taxpayerId,
    );
    if (index < 0) throw new Error("taxpayer_not_found");
    summaries[index] = { ...summaries[index]!, taxpayerStatus: "inactive" };
    return resolve(undefined);
  },
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
  getKnowledgeOperationsSnapshot: (municipalityId) => {
    if (!hasDemoMunicipality(municipalityId)) throw new Error("invalid_municipality_id");
    return resolve(knowledgeOperationsSnapshot);
  },
  async listKnowledgeReviewerCapabilities() {
    throw new Error("demo_reviewer_directory_unavailable");
  },
  async grantKnowledgeReviewerCapability() {
    throw new Error("demo_write_disabled");
  },
  async revokeKnowledgeReviewerCapability() {
    throw new Error("demo_write_disabled");
  },
  async searchLegalKnowledge(municipalityId, query) {
    if (!hasDemoMunicipality(municipalityId)) throw new Error("invalid_municipality_id");
    const normalized = query.trim();
    if (normalized.length < 5 || normalized.length > 500) {
      throw new Error("invalid_knowledge_search_query");
    }
    return resolve({
      verified: true,
      correlationId: "00000000-0000-4000-8000-000000000001",
      municipalityId,
      query: normalized,
      answered: true,
      answer:
        "O recolhimento deve observar o prazo definido na legislação municipal vigente. Confira o dispositivo oficial antes de aplicar a orientação ao caso concreto.",
      confidence: 0.91,
      retrievalMode: "hybrid",
      searchedAt: dashboardSummary.referenceDate,
      citations: [
        {
          citationId: "demo-search-citation-1",
          sourceId: "demo-source-1",
          sourceTitle: "Código Tributário Municipal",
          officialIdentifier: "Lei Complementar nº 399/2024",
          officialUrl: "https://cordeiropolis.sp.gov.br/",
          sourceVersionId: "demo-source-version-1",
          sectionId: "demo-section-1",
          sectionKey: "artigo_1",
          sectionHeading: "Artigo 1º",
          citationLabel: "Art. 1º",
          quotedExcerpt:
            "Esta lei institui as normas tributárias aplicáveis ao Município de Cordeirópolis.",
          publicationDate: "2024-12-20",
          validFrom: "2025-01-01",
          validUntil: null,
          relevance: 0.91,
          isValid: true,
          blockers: [],
        },
      ],
      blockers: [],
    });
  },
  async submitKnowledgeCandidate() {
    throw new Error("demo_write_disabled");
  },
  async getKnowledgeCandidateEvidence() {
    throw new Error("demo_evidence_unavailable");
  },
  async reviewKnowledgeCandidate() {
    throw new Error("demo_write_disabled");
  },
  async getKnowledgeArticleEvidence() {
    throw new Error("demo_evidence_unavailable");
  },
  async getLegalSourceChangeEvidence() {
    throw new Error("demo_evidence_unavailable");
  },
  async reviewLegalSourceChange() {
    throw new Error("demo_write_disabled");
  },
  async publishLegalSourceVersion() {
    throw new Error("demo_write_disabled");
  },
  async reviewKnowledgeArticle() {
    throw new Error("demo_write_disabled");
  },
  async publishKnowledgeArticle() {
    throw new Error("demo_write_disabled");
  },
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
  getAssistedOperationSafetyStatus: (municipalityId) =>
    resolve(assistedOperationSafetyStatus(municipalityId)),
  listMunicipalityUsers: () => resolve([]),
  async addExistingMunicipalityUser() {
    throw new Error("demo_write_disabled");
  },
  async updateMunicipalityMembership() {
    throw new Error("demo_write_disabled");
  },
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
