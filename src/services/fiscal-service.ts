import { isDemoMode } from "@/config/runtime";
import { mockFiscalService } from "@/services/mock-fiscal-service";
import { supabaseFiscalService } from "@/services/supabase-fiscal-service";
import type {
  AuditEvent,
  ChatQueueItem,
  DashboardSummary,
  FiscalCase,
  NotificationCandidate,
  ProcessingHealthIndicator,
  ProductionBlocker,
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

export interface FiscalService {
  getDashboardSummary(): Promise<DashboardSummary>;
  listFiscalCases(): Promise<FiscalCase[]>;
  listChatQueue(): Promise<ChatQueueItem[]>;
  listNotificationCandidates(): Promise<NotificationCandidate[]>;
  listProcessingHealth(): Promise<ProcessingHealthIndicator[]>;
  listProductionBlockers(): Promise<ProductionBlocker[]>;
  listAuditEvents(): Promise<AuditEvent[]>;
  listTaxpayers(): Promise<Taxpayer[]>;
  listTaxpayerSummaries(): Promise<Taxpayer360Summary[]>;
  listDebtPeriods(taxpayerId?: string): Promise<DebtPeriod[]>;
  listDivergences(taxpayerId?: string): Promise<DivergenceReadModel[]>;
  listFiscalCaseRows(taxpayerId?: string): Promise<FiscalCaseReadModel[]>;
  listNotificationRecipients(): Promise<NotificationRecipientReadModel[]>;
  listKnowledgeArticles(): Promise<KnowledgeArticleReadModel[]>;
  listPortalCases(): Promise<PortalCaseReadModel[]>;
  getOperationalReport(): Promise<OperationalReport>;
  submitCaseQuestion(caseId: string, body: string, clientRequestId: string): Promise<string>;
  searchFiscal(query: string, municipalityId: string): Promise<SearchResultItem[]>;
}

function activeService(): FiscalService {
  return isDemoMode() ? mockFiscalService : supabaseFiscalService;
}

export const fiscalService: FiscalService = {
  getDashboardSummary: () => activeService().getDashboardSummary(),
  listFiscalCases: () => activeService().listFiscalCases(),
  listChatQueue: () => activeService().listChatQueue(),
  listNotificationCandidates: () => activeService().listNotificationCandidates(),
  listProcessingHealth: () => activeService().listProcessingHealth(),
  listProductionBlockers: () => activeService().listProductionBlockers(),
  listAuditEvents: () => activeService().listAuditEvents(),
  listTaxpayers: () => activeService().listTaxpayers(),
  listTaxpayerSummaries: () => activeService().listTaxpayerSummaries(),
  listDebtPeriods: (taxpayerId) => activeService().listDebtPeriods(taxpayerId),
  listDivergences: (taxpayerId) => activeService().listDivergences(taxpayerId),
  listFiscalCaseRows: (taxpayerId) => activeService().listFiscalCaseRows(taxpayerId),
  listNotificationRecipients: () => activeService().listNotificationRecipients(),
  listKnowledgeArticles: () => activeService().listKnowledgeArticles(),
  listPortalCases: () => activeService().listPortalCases(),
  getOperationalReport: () => activeService().getOperationalReport(),
  submitCaseQuestion: (caseId, body, clientRequestId) =>
    activeService().submitCaseQuestion(caseId, body, clientRequestId),
  searchFiscal: (query, municipalityId) => activeService().searchFiscal(query, municipalityId),
};

/** Chaves estáveis de cache do TanStack Query. */
export const fiscalKeys = {
  dashboard: ["dashboard", "summary"] as const,
  cases: ["dashboard", "cases"] as const,
  chat: ["dashboard", "chat"] as const,
  notifications: ["dashboard", "notifications"] as const,
  health: ["dashboard", "health"] as const,
  blockers: ["dashboard", "blockers"] as const,
  events: ["dashboard", "events"] as const,
  taxpayers: ["taxpayers"] as const,
  debts: (taxpayerId?: string) => ["debts", taxpayerId ?? "all"] as const,
  divergences: (taxpayerId?: string) => ["divergences", taxpayerId ?? "all"] as const,
  caseRows: (taxpayerId?: string) => ["case-rows", taxpayerId ?? "all"] as const,
  recipients: ["notification-recipients"] as const,
  knowledge: ["knowledge"] as const,
  portal: ["portal-cases"] as const,
  report: ["operational-report"] as const,
};
