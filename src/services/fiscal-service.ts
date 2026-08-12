import { isDemoMode } from "@/config/runtime";
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
  listPortalCases(municipalityId: string): Promise<PortalCaseReadModel[]>;
  listCaseMessages(municipalityId: string, caseId: string): Promise<CaseMessageReadModel[]>;
  getOperationalReport(municipalityId: string): Promise<OperationalReport>;
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
  listPortalCases: (municipalityId) => activeService().listPortalCases(municipalityId),
  listCaseMessages: (municipalityId, caseId) =>
    activeService().listCaseMessages(municipalityId, caseId),
  getOperationalReport: (municipalityId) => activeService().getOperationalReport(municipalityId),
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
  portal: (municipalityId: string) => ["municipality", municipalityId, "portal-cases"] as const,
  caseMessages: (municipalityId: string, caseId: string) =>
    ["municipality", municipalityId, "case-messages", caseId] as const,
  report: (municipalityId: string) =>
    ["municipality", municipalityId, "operational-report"] as const,
  municipalityUsers: (municipalityId: string) => ["municipality", municipalityId, "users"] as const,
};
