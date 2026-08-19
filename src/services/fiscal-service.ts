import { isDemoMode } from "@/config/runtime";
import type {
  KnowledgeArticleEvidence,
  KnowledgeCandidateEvidence,
  KnowledgeCandidateInput,
  KnowledgeCandidateReviewDecision,
  KnowledgeOperationsSnapshot,
  KnowledgeReviewerDirectory,
  KnowledgeReviewDecision,
  KnowledgeSearchResult,
  KnowledgeSourceChangeEvidence,
  KnowledgeSourceEvidencePageRequest,
  LegalSourceReviewMetadata,
  LegalSourceReviewDecision,
} from "@/features/knowledge/knowledge-models";
import { mockFiscalService } from "@/services/mock-fiscal-service";
import { supabaseFiscalService } from "@/services/supabase-fiscal-service";
import type {
  AuditEvent,
  ChatQueueItem,
  CreateTaxpayerInput,
  DashboardSummary,
  FiscalCase,
  NotificationCandidate,
  ProcessingHealthIndicator,
  ProductionBlocker,
  Taxpayer,
  UpdateTaxpayerInput,
} from "@/types/fiscal";
import type {
  AssistedOperationSafetyStatus,
  CaseMessageReadModel,
  DebtPeriod,
  DivergenceReadModel,
  FiscalCaseReadModel,
  KnowledgeArticleReadModel,
  NotificationRecipientReadModel,
  MunicipalityMembershipStatus,
  MunicipalityUser,
  MunicipalityUserRole,
  OperationalReport,
  PortalCaseReadModel,
  SearchResultItem,
  Taxpayer360Summary,
} from "@/types/read-models";

export interface FiscalService {
  getDashboardSummary(municipalityId: string): Promise<DashboardSummary>;
  listFiscalCases(municipalityId: string): Promise<FiscalCase[]>;
  listChatQueue(municipalityId: string): Promise<ChatQueueItem[]>;
  listNotificationCandidates(municipalityId: string): Promise<NotificationCandidate[]>;
  listProcessingHealth(): Promise<ProcessingHealthIndicator[]>;
  listProductionBlockers(municipalityId: string): Promise<ProductionBlocker[]>;
  listAuditEvents(municipalityId: string): Promise<AuditEvent[]>;
  listTaxpayers(municipalityId: string): Promise<Taxpayer[]>;
  listTaxpayerSummaries(municipalityId: string): Promise<Taxpayer360Summary[]>;
  createTaxpayer(municipalityId: string, input: CreateTaxpayerInput): Promise<string>;
  updateTaxpayer(
    municipalityId: string,
    taxpayerId: string,
    input: UpdateTaxpayerInput,
  ): Promise<void>;
  archiveTaxpayer(municipalityId: string, taxpayerId: string): Promise<void>;
  listDebtPeriods(municipalityId: string, taxpayerId?: string): Promise<DebtPeriod[]>;
  listDivergences(municipalityId: string, taxpayerId?: string): Promise<DivergenceReadModel[]>;
  listFiscalCaseRows(municipalityId: string, taxpayerId?: string): Promise<FiscalCaseReadModel[]>;
  listNotificationRecipients(municipalityId: string): Promise<NotificationRecipientReadModel[]>;
  listKnowledgeArticles(municipalityId: string): Promise<KnowledgeArticleReadModel[]>;
  getKnowledgeOperationsSnapshot(municipalityId: string): Promise<KnowledgeOperationsSnapshot>;
  listKnowledgeReviewerCapabilities(municipalityId: string): Promise<KnowledgeReviewerDirectory>;
  grantKnowledgeReviewerCapability(
    municipalityId: string,
    targetMembershipId: string,
    validUntil: string | null,
    reason: string,
    confirmation: string,
  ): Promise<string>;
  revokeKnowledgeReviewerCapability(
    grantId: string,
    reason: string,
    confirmation: string,
  ): Promise<void>;
  searchLegalKnowledge(municipalityId: string, query: string): Promise<KnowledgeSearchResult>;
  submitKnowledgeCandidate(municipalityId: string, input: KnowledgeCandidateInput): Promise<string>;
  getKnowledgeCandidateEvidence(
    municipalityId: string,
    candidateId: string,
  ): Promise<KnowledgeCandidateEvidence>;
  reviewKnowledgeCandidate(
    municipalityId: string,
    candidateId: string,
    decision: KnowledgeCandidateReviewDecision,
    notes: string,
    confirmation: string,
  ): Promise<string>;
  getKnowledgeArticleEvidence(
    municipalityId: string,
    articleId: string,
    revisionId: string,
  ): Promise<KnowledgeArticleEvidence>;
  getLegalSourceChangeEvidence(
    municipalityId: string,
    changeSetId: string,
    page?: KnowledgeSourceEvidencePageRequest,
  ): Promise<KnowledgeSourceChangeEvidence>;
  reviewLegalSourceChange(
    municipalityId: string,
    changeSetId: string,
    decision: LegalSourceReviewDecision,
    notes: string,
    confirmation: string,
    metadata: LegalSourceReviewMetadata,
  ): Promise<string>;
  publishLegalSourceVersion(
    municipalityId: string,
    sourceVersionId: string,
    confirmation: string,
  ): Promise<void>;
  reviewKnowledgeArticle(
    municipalityId: string,
    articleId: string,
    revisionId: string,
    decision: KnowledgeReviewDecision,
    notes: string,
    confirmation: string,
  ): Promise<string>;
  publishKnowledgeArticle(
    municipalityId: string,
    articleId: string,
    confirmation: string,
  ): Promise<void>;
  listPortalCases(municipalityId: string): Promise<PortalCaseReadModel[]>;
  listCaseMessages(municipalityId: string, caseId: string): Promise<CaseMessageReadModel[]>;
  getOperationalReport(municipalityId: string): Promise<OperationalReport>;
  getAssistedOperationSafetyStatus(municipalityId: string): Promise<AssistedOperationSafetyStatus>;
  listMunicipalityUsers(municipalityId: string): Promise<MunicipalityUser[]>;
  addExistingMunicipalityUser(
    municipalityId: string,
    email: string,
    role: MunicipalityUserRole,
  ): Promise<string>;
  updateMunicipalityMembership(
    municipalityId: string,
    membershipId: string,
    role: MunicipalityUserRole,
    status: MunicipalityMembershipStatus,
  ): Promise<string>;
  claimCaseQuestion(
    questionId: string,
    municipalityId: string,
    membershipId: string,
    handlingMode: "human" | "ai_assist",
  ): Promise<string>;
  submitCaseQuestion(caseId: string, body: string, clientRequestId: string): Promise<string>;
  searchFiscal(query: string, municipalityId: string): Promise<SearchResultItem[]>;
}

function activeService(): FiscalService {
  return isDemoMode() ? mockFiscalService : supabaseFiscalService;
}

export const fiscalService: FiscalService = {
  getDashboardSummary: (municipalityId) => activeService().getDashboardSummary(municipalityId),
  listFiscalCases: (municipalityId) => activeService().listFiscalCases(municipalityId),
  listChatQueue: (municipalityId) => activeService().listChatQueue(municipalityId),
  listNotificationCandidates: (municipalityId) =>
    activeService().listNotificationCandidates(municipalityId),
  listProcessingHealth: () => activeService().listProcessingHealth(),
  listProductionBlockers: (municipalityId) =>
    activeService().listProductionBlockers(municipalityId),
  listAuditEvents: (municipalityId) => activeService().listAuditEvents(municipalityId),
  listTaxpayers: (municipalityId) => activeService().listTaxpayers(municipalityId),
  listTaxpayerSummaries: (municipalityId) => activeService().listTaxpayerSummaries(municipalityId),
  createTaxpayer: (municipalityId, input) => activeService().createTaxpayer(municipalityId, input),
  updateTaxpayer: (municipalityId, taxpayerId, input) =>
    activeService().updateTaxpayer(municipalityId, taxpayerId, input),
  archiveTaxpayer: (municipalityId, taxpayerId) =>
    activeService().archiveTaxpayer(municipalityId, taxpayerId),
  listDebtPeriods: (municipalityId, taxpayerId) =>
    activeService().listDebtPeriods(municipalityId, taxpayerId),
  listDivergences: (municipalityId, taxpayerId) =>
    activeService().listDivergences(municipalityId, taxpayerId),
  listFiscalCaseRows: (municipalityId, taxpayerId) =>
    activeService().listFiscalCaseRows(municipalityId, taxpayerId),
  listNotificationRecipients: (municipalityId) =>
    activeService().listNotificationRecipients(municipalityId),
  listKnowledgeArticles: (municipalityId) => activeService().listKnowledgeArticles(municipalityId),
  getKnowledgeOperationsSnapshot: (municipalityId) =>
    activeService().getKnowledgeOperationsSnapshot(municipalityId),
  listKnowledgeReviewerCapabilities: (municipalityId) =>
    activeService().listKnowledgeReviewerCapabilities(municipalityId),
  grantKnowledgeReviewerCapability: (
    municipalityId,
    targetMembershipId,
    validUntil,
    reason,
    confirmation,
  ) =>
    activeService().grantKnowledgeReviewerCapability(
      municipalityId,
      targetMembershipId,
      validUntil,
      reason,
      confirmation,
    ),
  revokeKnowledgeReviewerCapability: (grantId, reason, confirmation) =>
    activeService().revokeKnowledgeReviewerCapability(grantId, reason, confirmation),
  searchLegalKnowledge: (municipalityId, query) =>
    activeService().searchLegalKnowledge(municipalityId, query),
  submitKnowledgeCandidate: (municipalityId, input) =>
    activeService().submitKnowledgeCandidate(municipalityId, input),
  getKnowledgeCandidateEvidence: (municipalityId, candidateId) =>
    activeService().getKnowledgeCandidateEvidence(municipalityId, candidateId),
  reviewKnowledgeCandidate: (municipalityId, candidateId, decision, notes, confirmation) =>
    activeService().reviewKnowledgeCandidate(
      municipalityId,
      candidateId,
      decision,
      notes,
      confirmation,
    ),
  getKnowledgeArticleEvidence: (municipalityId, articleId, revisionId) =>
    activeService().getKnowledgeArticleEvidence(municipalityId, articleId, revisionId),
  getLegalSourceChangeEvidence: (municipalityId, changeSetId, page) =>
    activeService().getLegalSourceChangeEvidence(municipalityId, changeSetId, page),
  reviewLegalSourceChange: (municipalityId, changeSetId, decision, notes, confirmation, metadata) =>
    activeService().reviewLegalSourceChange(
      municipalityId,
      changeSetId,
      decision,
      notes,
      confirmation,
      metadata,
    ),
  publishLegalSourceVersion: (municipalityId, sourceVersionId, confirmation) =>
    activeService().publishLegalSourceVersion(municipalityId, sourceVersionId, confirmation),
  reviewKnowledgeArticle: (municipalityId, articleId, revisionId, decision, notes, confirmation) =>
    activeService().reviewKnowledgeArticle(
      municipalityId,
      articleId,
      revisionId,
      decision,
      notes,
      confirmation,
    ),
  publishKnowledgeArticle: (municipalityId, articleId, confirmation) =>
    activeService().publishKnowledgeArticle(municipalityId, articleId, confirmation),
  listPortalCases: (municipalityId) => activeService().listPortalCases(municipalityId),
  listCaseMessages: (municipalityId, caseId) =>
    activeService().listCaseMessages(municipalityId, caseId),
  getOperationalReport: (municipalityId) => activeService().getOperationalReport(municipalityId),
  getAssistedOperationSafetyStatus: (municipalityId) =>
    activeService().getAssistedOperationSafetyStatus(municipalityId),
  listMunicipalityUsers: (municipalityId) => activeService().listMunicipalityUsers(municipalityId),
  addExistingMunicipalityUser: (municipalityId, email, role) =>
    activeService().addExistingMunicipalityUser(municipalityId, email, role),
  updateMunicipalityMembership: (municipalityId, membershipId, role, status) =>
    activeService().updateMunicipalityMembership(municipalityId, membershipId, role, status),
  claimCaseQuestion: (questionId, municipalityId, membershipId, handlingMode) =>
    activeService().claimCaseQuestion(questionId, municipalityId, membershipId, handlingMode),
  submitCaseQuestion: (caseId, body, clientRequestId) =>
    activeService().submitCaseQuestion(caseId, body, clientRequestId),
  searchFiscal: (query, municipalityId) => activeService().searchFiscal(query, municipalityId),
};

/** Chaves estáveis de cache do TanStack Query. */
export const fiscalKeys = {
  dashboard: (municipalityId: string) =>
    ["municipality", municipalityId, "dashboard", "summary"] as const,
  cases: (municipalityId: string) =>
    ["municipality", municipalityId, "dashboard", "cases"] as const,
  chat: (municipalityId: string) => ["municipality", municipalityId, "dashboard", "chat"] as const,
  notifications: (municipalityId: string) =>
    ["municipality", municipalityId, "dashboard", "notifications"] as const,
  health: ["platform", "worker-health"] as const,
  blockers: (municipalityId: string) =>
    ["municipality", municipalityId, "dashboard", "blockers"] as const,
  events: (municipalityId: string) =>
    ["municipality", municipalityId, "dashboard", "events"] as const,
  taxpayers: (municipalityId: string) => ["municipality", municipalityId, "taxpayers"] as const,
  debts: (municipalityId: string, taxpayerId?: string) =>
    ["municipality", municipalityId, "debts", taxpayerId ?? "all"] as const,
  divergences: (municipalityId: string, taxpayerId?: string) =>
    ["municipality", municipalityId, "divergences", taxpayerId ?? "all"] as const,
  caseRows: (municipalityId: string, taxpayerId?: string) =>
    ["municipality", municipalityId, "case-rows", taxpayerId ?? "all"] as const,
  recipients: (municipalityId: string) =>
    ["municipality", municipalityId, "notification-recipients"] as const,
  knowledge: (municipalityId: string) => ["municipality", municipalityId, "knowledge"] as const,
  knowledgeOperations: (municipalityId: string) =>
    ["municipality", municipalityId, "knowledge", "operations"] as const,
  knowledgeReviewers: (municipalityId: string) =>
    ["municipality", municipalityId, "knowledge", "reviewers"] as const,
  knowledgeSearch: (municipalityId: string, query: string) =>
    ["municipality", municipalityId, "knowledge", "search", query] as const,
  knowledgeArticleEvidence: (municipalityId: string, articleId: string, revisionId: string) =>
    [
      "municipality",
      municipalityId,
      "knowledge",
      "article-evidence",
      articleId,
      revisionId,
    ] as const,
  legalSourceChangeEvidence: (municipalityId: string, changeSetId: string) =>
    ["municipality", municipalityId, "knowledge", "source-evidence", changeSetId] as const,
  knowledgeCandidateEvidence: (municipalityId: string, candidateId: string) =>
    ["municipality", municipalityId, "knowledge", "candidate-evidence", candidateId] as const,
  portal: (municipalityId: string) => ["municipality", municipalityId, "portal-cases"] as const,
  caseMessages: (municipalityId: string, caseId: string) =>
    ["municipality", municipalityId, "case-messages", caseId] as const,
  report: (municipalityId: string) =>
    ["municipality", municipalityId, "operational-report"] as const,
  externalDeliverySafety: (municipalityId: string) =>
    ["municipality", municipalityId, "external-delivery-safety"] as const,
  municipalityUsers: (municipalityId: string) => ["municipality", municipalityId, "users"] as const,
};
