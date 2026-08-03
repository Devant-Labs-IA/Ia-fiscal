export type StaffRole =
  "platform_admin" | "municipal_admin" | "supervisor" | "fiscal_auditor" | "legal_reviewer";

export type PortalRole = "taxpayer" | "accountant";
export type AppRole = StaffRole | PortalRole;

export interface AccessContext {
  role: AppRole;
  municipalityId: string;
  municipalityLabel: string;
  membershipId?: string;
  taxpayerId?: string;
  accountingFirmId?: string;
}

export interface Taxpayer360Summary {
  municipalityId: string;
  taxpayerId: string;
  municipalRegistration: string;
  taxId: string;
  legalName: string;
  tradeName: string;
  taxpayerType: string;
  taxpayerStatus: string;
  debtPeriodCount: number;
  overduePeriodCount: number;
  incompleteDebtPeriodCount: number;
  openBalanceTotal: number;
  oldestOpenDueOn: string | null;
  divergenceCount: number;
  activeDivergenceCount: number;
  blockedDivergenceCount: number;
  divergenceAmountTotal: number;
  caseCount: number;
  activeCaseCount: number;
  blockedCalculationCount: number;
  contactCount: number;
  verifiedContactCount: number;
  responsibleCount: number;
  deliveryReadyResponsibleCount: number;
  waitingQuestionCount: number;
  operationalAttentionLevel: string;
  primaryActionLabel: string | null;
  primaryActionReason: string | null;
  primaryActionPriority: string | null;
  primaryActionDueAt: string | null;
}

export interface DebtPeriod {
  municipalityId: string;
  taxpayerId: string;
  competence: string;
  assessedAmount: number;
  overdueAmount: number;
  paidAmount: number;
  derivedCreditsAmount: number;
  openBalance: number;
  incompleteAmount: number;
  futureAmount: number;
  firstDueOn: string | null;
  lastDueOn: string | null;
  status: string;
  eligible: boolean;
  ruleVersion: string;
  asOf: string | null;
}

export interface DivergenceReadModel {
  municipalityId: string;
  divergenceId: string;
  taxpayerId: string;
  taxId: string;
  taxpayerName: string;
  divergenceType: string;
  periodStart: string;
  periodEnd: string;
  differenceAmount: number;
  priorityScore: number | null;
  status: string;
  executionMode: string;
  ruleCode: string;
  ruleVersion: number | null;
  blockReasons: string[];
  hasCaseFinding: boolean;
}

export interface FiscalCaseReadModel {
  municipalityId: string;
  caseId: string;
  caseNumber: string;
  divergenceId: string | null;
  taxpayerId: string;
  taxpayerName: string;
  status: string;
  confidentiality: string;
  executionMode: string;
  openedAt: string;
  updatedAt: string | null;
  explanationTitle: string | null;
  explanationSummary: string | null;
  legalBasisSummary: string | null;
  legalReviewRequired: boolean;
  waitingQuestionCount: number;
}

export interface NotificationRecipientReadModel {
  municipalityId: string;
  taxpayerId: string;
  candidateId: string;
  proposedFor: string;
  recipientType: string;
  maskedEmail: string;
  candidateStatus: string;
  deliveryBlockReason: string;
  priority: number;
  readyPendingExternalAuthorization: boolean;
  safeForDelivery: boolean;
  externalDeliveryAuthorized: boolean;
  createdAt: string;
}

export interface KnowledgeArticleReadModel {
  municipalityId: string;
  articleId: string;
  intentKey: string;
  semanticVersion: number;
  canonicalQuestion: string;
  taxScope: string;
  divergenceScope: string;
  answerBody: string;
  validFrom: string | null;
  validUntil: string | null;
  publishedAt: string | null;
  isTest: boolean;
}

export interface PortalCaseReadModel {
  municipalityId: string;
  caseId: string;
  caseNumber: string;
  taxpayerId: string;
  taxpayerName: string;
  caseStatus: string;
  executionMode: string;
  explanationStatus: string;
  title: string;
  summary: string;
  divergenceSummary: Record<string, unknown>;
  legalBasisSummary: string;
  citations: unknown[];
  officialSystemUrl: string | null;
  portalPath: string | null;
  legalReviewRequired: boolean;
  threadId: string | null;
  threadStatus: string | null;
}

export interface CaseMessageReadModel {
  id: string;
  caseId: string;
  body: string;
  senderType: string;
  sourceType: string;
  status: string;
  visibility: string;
  createdAt: string;
  publishedAt: string | null;
}

export interface OperationalReport {
  taxpayerCount: number;
  overduePeriodCount: number;
  openBalanceTotal: number;
  activeDivergenceCount: number;
  divergenceAmountTotal: number;
  activeCaseCount: number;
  blockedCalculationCount: number;
  waitingQuestionCount: number;
  recipientCandidateCount: number;
  deliveryReadyCount: number;
  externalDeliveryCount: number;
}

export interface SearchResultItem {
  resultType: string;
  title: string;
  subtitle: string;
  route: string | null;
  metadata: Record<string, unknown>;
}
