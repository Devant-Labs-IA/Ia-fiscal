import { runtimeConfig } from "@/config/runtime";
import type {
  KnowledgeArticleEvidence,
  KnowledgeCandidateEvidence,
  KnowledgeCandidateInput,
  KnowledgeCandidateReviewDecision,
  KnowledgeCatalogCoverage,
  KnowledgeCitationEvidence,
  KnowledgeSearchCitation,
  KnowledgeSearchResult,
  KnowledgeOfficialSource,
  KnowledgeOperationsSnapshot,
  KnowledgeReviewerDirectory,
  KnowledgeReviewerEligibleStaff,
  KnowledgeReviewerGrant,
  KnowledgeReviewDecision,
  KnowledgeReviewQueueItem,
  KnowledgeSourceChangeEvidence,
  KnowledgeSourceChangeItemEvidence,
  KnowledgeSourceSectionEvidence,
  KnowledgeSourceChange,
  KnowledgeSourceEvidencePageRequest,
  LegalSourceReviewMetadata,
  LegalSourceReviewDecision,
} from "@/features/knowledge/knowledge-models";
import {
  KNOWLEDGE_EVIDENCE_CHANGE_ITEM_PAGE_SIZE,
  KNOWLEDGE_EVIDENCE_CONTENT_PAGE_SIZE,
  KNOWLEDGE_EVIDENCE_SECTION_PAGE_SIZE,
  KNOWLEDGE_MIN_ANSWER_CONFIDENCE,
} from "@/features/knowledge/knowledge-models";
import { formatDateTime } from "@/lib/format";
import {
  blockReasonSummary,
  divergenceTypeLabel,
  fiscalEventTypeLabel,
  fiscalStatusLabel,
  notificationPurposeLabel,
  parseBlockReasons,
  processingWorkerLabel,
  visibilityLabel,
  workerHealthStatus,
  workerStatusLabel,
} from "@/lib/fiscal-labels";
import { FISCAL_READ_TIMEOUT_MS } from "@/lib/query-policy";
import { getSupabaseClient } from "@/lib/supabase";
import { validateTaxpayerInput } from "@/lib/taxpayer-validation";
import {
  chatOperationalPriority,
  compareChatQueueItems,
  normalizeHandlingMode,
} from "@/services/chat-queue";
import type { FiscalService } from "@/services/fiscal-service";
import type {
  AuditEvent,
  ChatQueueItem,
  CreateTaxpayerInput,
  DashboardMetric,
  DashboardSummary,
  Debt,
  FiscalCase,
  NotificationCandidate,
  ProcessingHealthIndicator,
  ProductionBlocker,
  RiskLevel,
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
  MunicipalityMembershipStatus,
  MunicipalityUser,
  MunicipalityUserRole,
  NotificationRecipientReadModel,
  OperationalReport,
  PortalCaseReadModel,
  SearchResultItem,
  Taxpayer360Summary,
} from "@/types/read-models";

type Row = Record<string, unknown>;

type AssistedSafetyRpcResponse = {
  data: unknown;
  error: { code?: string; message?: string } | null;
};

type AssistedSafetyRpcClient = {
  rpc(
    functionName: "ia_get_assisted_operation_safety_status",
    args: { p_municipality_id: string },
  ): {
    abortSignal(signal: AbortSignal): Promise<AssistedSafetyRpcResponse>;
  };
};

type KnowledgeRpcResponse = {
  data: unknown;
  error: { code?: string; message?: string } | null;
};

type KnowledgeReadRpcClient = {
  rpc(
    functionName: string,
    args: Record<string, unknown>,
  ): {
    abortSignal(signal: AbortSignal): Promise<KnowledgeRpcResponse>;
  };
};

type KnowledgeWriteRpcClient = {
  rpc(functionName: string, args: Record<string, unknown>): Promise<KnowledgeRpcResponse>;
};

class FiscalDataError extends Error {
  constructor(readonly code: string) {
    super(`fiscal_data_error:${code}`);
    this.name = "FiscalDataError";
  }
}

function stringValue(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function identifierValue(value: unknown, fallback = ""): string {
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return fallback;
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

function objectValue(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function strictObject(value: unknown, code: string): Row {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new FiscalDataError(code);
  }
  return value as Row;
}

function strictArray(value: unknown, code: string): unknown[] {
  if (!Array.isArray(value)) throw new FiscalDataError(code);
  return value;
}

function strictString(value: unknown, code: string): string {
  if (typeof value !== "string" || !value.trim()) throw new FiscalDataError(code);
  return value;
}

function strictText(value: unknown, code: string): string {
  if (typeof value !== "string") throw new FiscalDataError(code);
  return value;
}

function strictNullableString(value: unknown, code: string): string | null {
  if (value === null) return null;
  if (typeof value !== "string") throw new FiscalDataError(code);
  return value || null;
}

function strictOptionalNullableString(value: unknown, code: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new FiscalDataError(code);
  return value || null;
}

function strictNumber(value: unknown, code: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new FiscalDataError(code);
  }
  return value;
}

function strictInteger(value: unknown, code: string): number {
  const parsed = strictNumber(value, code);
  if (!Number.isSafeInteger(parsed)) throw new FiscalDataError(code);
  return parsed;
}

function strictUnitInterval(value: unknown, code: string): number {
  const parsed = strictNumber(value, code);
  if (parsed > 1) throw new FiscalDataError(code);
  return parsed;
}

function strictNullableNumber(value: unknown, code: string): number | null {
  if (value === null) return null;
  return strictNumber(value, code);
}

function strictNullableInteger(value: unknown, code: string): number | null {
  if (value === null) return null;
  return strictInteger(value, code);
}

function strictBoolean(value: unknown, code: string): boolean {
  if (typeof value !== "boolean") throw new FiscalDataError(code);
  return value;
}

function isSecureHttpUrl(value: string | null): boolean {
  if (!value) return false;
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

function validatedIanaTimeZone(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    new Intl.DateTimeFormat("pt-BR", { timeZone: value }).format(new Date(0));
    return value;
  } catch {
    return null;
  }
}

function currentDateInSaoPaulo(): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function isCurrentLegalCitation(citation: KnowledgeSearchCitation): boolean {
  const today = currentDateInSaoPaulo();
  return Boolean(
    citation.publicationDate &&
    /^\d{4}-\d{2}-\d{2}$/.test(citation.publicationDate) &&
    citation.publicationDate <= today &&
    citation.validFrom &&
    /^\d{4}-\d{2}-\d{2}$/.test(citation.validFrom) &&
    citation.validFrom <= today &&
    (!citation.validUntil ||
      (/^\d{4}-\d{2}-\d{2}$/.test(citation.validUntil) && citation.validUntil >= today)),
  );
}

function strictStringArray(value: unknown, code: string): string[] {
  const values = strictArray(value, code);
  if (values.some((item) => typeof item !== "string")) throw new FiscalDataError(code);
  return values as string[];
}

function throwIfError(error: { code?: string; message?: string } | null): void {
  if (!error) return;
  const message = error.message?.toLocaleLowerCase("pt-BR") ?? "";
  const code = /abort|timeout|timed out/.test(message)
    ? "query_timeout"
    : error.code?.slice(0, 80) || "query_failed";
  throw new FiscalDataError(code);
}

function fiscalReadSignal(): AbortSignal {
  return AbortSignal.timeout(FISCAL_READ_TIMEOUT_MS);
}

function requireMunicipalityId(municipalityId: string): string {
  const normalized = municipalityId.trim();
  if (!normalized) throw new FiscalDataError("invalid_municipality_id");
  return normalized;
}

function requireTaxpayerId(taxpayerId: string): string {
  const normalized = taxpayerId.trim();
  if (!normalized) throw new FiscalDataError("invalid_taxpayer_id");
  return normalized;
}

function requireValidTaxpayerInput(
  input: CreateTaxpayerInput | UpdateTaxpayerInput,
): CreateTaxpayerInput {
  const validation = validateTaxpayerInput(input);
  if (!validation.valid) throw new FiscalDataError("invalid_taxpayer_input");
  return validation.data;
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
    ruleName: nullableString(row["rule_name"]),
    ruleDescription: nullableString(row["rule_description"]),
    ruleVersion:
      row["rule_version_number"] == null ? null : numberValue(row["rule_version_number"]),
    blockReasons: parseBlockReasons(row["block_reasons"]),
    hasCaseFinding: booleanValue(row["has_case_finding"]),
  };
}

function mapCase(row: Row): FiscalCaseReadModel {
  return {
    municipalityId: stringValue(row["municipality_id"]),
    caseId: stringValue(row["case_id"] ?? row["id"]),
    caseNumber: stringValue(row["case_number"], "—"),
    divergenceId: nullableString(row["divergence_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    taxpayerName: "Contribuinte protegido",
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

async function listTaxpayerSummaries(municipalityId: string): Promise<Taxpayer360Summary[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const { data, error } = await getSupabaseClient()
    .from("vw_taxpayer_360_summary")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .order("open_balance_total", { ascending: false })
    .limit(500)
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return (data as Row[] | null)?.map(mapSummary) ?? [];
}

async function createTaxpayer(municipalityId: string, input: CreateTaxpayerInput): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const data = requireValidTaxpayerInput(input);
  const result = await getSupabaseClient()
    .from("taxpayers")
    .insert({
      municipality_id: scopedMunicipalityId,
      municipal_registration: data.municipalRegistration,
      tax_id: data.taxId,
      legal_name: data.legalName,
      trade_name: data.tradeName || null,
      taxpayer_type: data.taxpayerType,
      status: "active",
      source_metadata: { origin: "manual_homologation" },
    })
    .select("id")
    .single();
  throwIfError(result.error);
  const taxpayerId = identifierValue(result.data?.id);
  if (!taxpayerId) throw new FiscalDataError("taxpayer_id_missing");
  return taxpayerId;
}

async function updateTaxpayer(
  municipalityId: string,
  taxpayerId: string,
  input: UpdateTaxpayerInput,
): Promise<void> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedTaxpayerId = requireTaxpayerId(taxpayerId);
  const data = requireValidTaxpayerInput(input);
  const result = await getSupabaseClient()
    .from("taxpayers")
    .update({
      municipal_registration: data.municipalRegistration,
      tax_id: data.taxId,
      legal_name: data.legalName,
      trade_name: data.tradeName || null,
      taxpayer_type: data.taxpayerType,
      updated_at: new Date().toISOString(),
    })
    .eq("municipality_id", scopedMunicipalityId)
    .eq("id", scopedTaxpayerId)
    .select("id")
    .single();
  throwIfError(result.error);
  if (identifierValue(result.data?.id) !== scopedTaxpayerId) {
    throw new FiscalDataError("taxpayer_not_found");
  }
}

async function archiveTaxpayer(municipalityId: string, taxpayerId: string): Promise<void> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedTaxpayerId = requireTaxpayerId(taxpayerId);
  const result = await getSupabaseClient()
    .from("taxpayers")
    .update({ status: "inactive", updated_at: new Date().toISOString() })
    .eq("municipality_id", scopedMunicipalityId)
    .eq("id", scopedTaxpayerId)
    .select("id")
    .single();
  throwIfError(result.error);
  if (identifierValue(result.data?.id) !== scopedTaxpayerId) {
    throw new FiscalDataError("taxpayer_not_found");
  }
}

async function listDebtPeriods(municipalityId: string, taxpayerId?: string): Promise<DebtPeriod[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  let query = getSupabaseClient()
    .from("vw_taxpayer_360_debts")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .order("competencia", { ascending: false })
    .limit(1000);
  if (taxpayerId) query = query.eq("taxpayer_id", taxpayerId);
  const { data, error } = await query.abortSignal(fiscalReadSignal());
  throwIfError(error);
  return (data as Row[] | null)?.map(mapDebt) ?? [];
}

async function listDivergences(
  municipalityId: string,
  taxpayerId?: string,
): Promise<DivergenceReadModel[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  let query = getSupabaseClient()
    .from("vw_taxpayer_360_divergences")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .order("as_of", { ascending: false })
    .limit(1000);
  if (taxpayerId) query = query.eq("taxpayer_id", taxpayerId);
  const { data, error } = await query.abortSignal(fiscalReadSignal());
  throwIfError(error);
  return (data as Row[] | null)?.map(mapDivergence) ?? [];
}

async function listFiscalCaseRows(
  municipalityId: string,
  taxpayerId?: string,
): Promise<FiscalCaseReadModel[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  let query = getSupabaseClient()
    .from("vw_taxpayer_360_cases")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .order("opened_at", { ascending: false })
    .limit(500);
  if (taxpayerId) query = query.eq("taxpayer_id", taxpayerId);
  const { data, error } = await query.abortSignal(fiscalReadSignal());
  throwIfError(error);
  return (data as Row[] | null)?.map(mapCase) ?? [];
}

async function listNotificationRecipients(
  municipalityId: string,
): Promise<NotificationRecipientReadModel[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const { data, error } = await getSupabaseClient()
    .from("vw_notification_recipient_candidates")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .order("priority", { ascending: true })
    .limit(1000)
    .abortSignal(fiscalReadSignal());
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

function mapKnowledgeCitation(value: unknown, code: string): KnowledgeCitationEvidence {
  const row = strictObject(value, code);
  return {
    citationId: strictString(row["citation_id"], code),
    citationLabel: strictString(row["citation_label"], code),
    quotedExcerpt: strictString(row["quoted_excerpt"], code),
    sourceId: strictString(row["source_id"], code),
    sourceTitle: strictString(row["source_title"], code),
    officialIdentifier: strictNullableString(row["official_identifier"], code),
    officialUrl: strictNullableString(row["official_url"], code),
    sourceVersionId: strictString(row["source_version_id"], code),
    sourceVersionNumber: strictInteger(row["source_version_number"], code),
    sourceVersionStatus: strictString(row["source_version_status"], code),
    sourceSha256: strictString(row["source_sha256"], code),
    publicationDate: strictNullableString(row["publication_date"], code),
    validFrom: strictNullableString(row["valid_from"], code),
    validUntil: strictNullableString(row["valid_until"], code),
    sectionId: strictString(row["section_id"], code),
    sectionKey: strictString(row["section_key"], code),
    sectionHeading: strictNullableString(row["section_heading"], code),
    sectionContentSha256: strictString(row["section_content_sha256"], code),
    isValid: strictBoolean(row["is_valid"], code),
    blockers: strictStringArray(row["blockers"], code),
  };
}

function strictKnowledgeCitations(value: unknown, code: string): KnowledgeCitationEvidence[] {
  return strictArray(value, code).map((citation) => mapKnowledgeCitation(citation, code));
}

async function listKnowledgeArticles(municipalityId: string): Promise<KnowledgeArticleReadModel[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const { data, error } = await getSupabaseClient()
    .from("vw_reusable_knowledge_articles")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .eq("is_test", false)
    .order("published_at", { ascending: false })
    .limit(200)
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((value) => {
    const row = strictObject(value, "knowledge_article_invalid");
    const returnedMunicipalityId = strictString(
      row["municipality_id"],
      "knowledge_article_invalid",
    );
    if (returnedMunicipalityId !== scopedMunicipalityId) {
      throw new FiscalDataError("knowledge_article_tenant_mismatch");
    }
    const citations = strictKnowledgeCitations(row["citations"], "knowledge_article_invalid");
    if (
      citations.length === 0 ||
      citations.some(
        (citation) =>
          !citation.isValid ||
          citation.blockers.length > 0 ||
          !isSecureHttpUrl(citation.officialUrl),
      )
    ) {
      throw new FiscalDataError("knowledge_article_evidence_unverified");
    }
    return {
      municipalityId: returnedMunicipalityId,
      articleId: strictString(row["article_id"], "knowledge_article_invalid"),
      revisionId: strictString(row["revision_id"], "knowledge_article_invalid"),
      intentKey: strictString(row["intent_key"], "knowledge_article_invalid"),
      semanticVersion: strictInteger(row["semantic_version"], "knowledge_article_invalid"),
      canonicalQuestion: strictString(row["canonical_question"], "knowledge_article_invalid"),
      taxScope: strictString(row["tax_scope"], "knowledge_article_invalid"),
      divergenceScope: strictString(row["divergence_scope"], "knowledge_article_invalid"),
      answerBody: strictString(row["answer_body"], "knowledge_article_invalid"),
      validFrom: strictNullableString(row["valid_from"], "knowledge_article_invalid"),
      validUntil: strictNullableString(row["valid_until"], "knowledge_article_invalid"),
      publishedAt: strictNullableString(row["published_at"], "knowledge_article_invalid"),
      isTest: strictBoolean(row["is_test"], "knowledge_article_invalid"),
      citations,
    };
  });
}

function mapKnowledgeSource(value: unknown): KnowledgeOfficialSource {
  const row = strictObject(value, "knowledge_source_invalid");
  return {
    sourceId: strictString(row["source_id"], "knowledge_source_invalid"),
    title: strictString(row["title"], "knowledge_source_invalid"),
    officialIdentifier: strictNullableString(
      row["official_identifier"],
      "knowledge_source_invalid",
    ),
    sourceType: strictString(row["source_type"], "knowledge_source_invalid"),
    taxScope: strictString(row["tax_scope"], "knowledge_source_invalid"),
    status: strictString(row["status"], "knowledge_source_invalid"),
    officialUrl: strictNullableString(row["official_url"], "knowledge_source_invalid"),
    trustTier: strictString(row["trust_tier"], "knowledge_source_invalid"),
    endpointStatus: strictString(row["endpoint_status"], "knowledge_source_invalid"),
    lastFetchStatus: strictString(row["last_fetch_status"], "knowledge_source_invalid"),
    lastCheckedAt: strictNullableString(row["last_checked_at"], "knowledge_source_invalid"),
    lastChangeDetectedAt: strictNullableString(
      row["last_change_detected_at"],
      "knowledge_source_invalid",
    ),
    lastErrorCode: strictNullableString(row["last_error_code"], "knowledge_source_invalid"),
    lastErrorDetail: strictNullableString(row["last_error_detail"], "knowledge_source_invalid"),
    latestVersionId: strictNullableString(row["latest_version_id"], "knowledge_source_invalid"),
    latestVersionNumber: strictNullableNumber(
      row["latest_version_number"],
      "knowledge_source_invalid",
    ),
    latestVersionStatus: strictNullableString(
      row["latest_version_status"],
      "knowledge_source_invalid",
    ),
    latestValidFrom: strictNullableString(row["latest_valid_from"], "knowledge_source_invalid"),
    latestValidUntil: strictNullableString(row["latest_valid_until"], "knowledge_source_invalid"),
    blockers: strictStringArray(row["blockers"], "knowledge_source_invalid"),
    canReview: strictBoolean(row["can_review"], "knowledge_source_invalid"),
    canPublish: strictBoolean(row["can_publish"], "knowledge_source_invalid"),
  };
}

function mapKnowledgeChange(value: unknown): KnowledgeSourceChange {
  const row = strictObject(value, "knowledge_change_invalid");
  return {
    changeSetId: strictString(row["change_set_id"], "knowledge_change_invalid"),
    sourceId: strictString(row["source_id"], "knowledge_change_invalid"),
    sourceTitle: strictString(row["source_title"], "knowledge_change_invalid"),
    changeType: strictString(row["change_type"], "knowledge_change_invalid"),
    status: strictString(row["status"], "knowledge_change_invalid"),
    detectedAt: strictNullableString(row["detected_at"], "knowledge_change_invalid"),
    fromSha256: strictNullableString(row["from_sha256"], "knowledge_change_invalid"),
    toSha256: strictString(row["to_sha256"], "knowledge_change_invalid"),
    candidateVersionId: strictNullableString(
      row["candidate_version_id"],
      "knowledge_change_invalid",
    ),
    candidateVersionNumber: strictNullableNumber(
      row["candidate_version_number"],
      "knowledge_change_invalid",
    ),
    candidateVersionStatus: strictNullableString(
      row["candidate_version_status"],
      "knowledge_change_invalid",
    ),
    candidateValidFrom: strictNullableString(
      row["candidate_valid_from"],
      "knowledge_change_invalid",
    ),
    candidateValidUntil: strictNullableString(
      row["candidate_valid_until"],
      "knowledge_change_invalid",
    ),
    officialUrl: strictNullableString(row["official_url"], "knowledge_change_invalid"),
    candidateContentPreview: strictNullableString(
      row["candidate_content_preview"],
      "knowledge_change_invalid",
    ),
    sectionCount: strictNullableNumber(row["section_count"], "knowledge_change_invalid"),
    diffSummary: strictNullableString(row["diff_summary"], "knowledge_change_invalid"),
    blockers: strictStringArray(row["blockers"], "knowledge_change_invalid"),
    canReview: strictBoolean(row["can_review"], "knowledge_change_invalid"),
    canPublish: strictBoolean(row["can_publish"], "knowledge_change_invalid"),
  };
}

function mapKnowledgeReview(value: unknown): KnowledgeReviewQueueItem {
  const row = strictObject(value, "knowledge_review_invalid");
  const queueKind = strictString(row["queue_kind"], "knowledge_review_invalid");
  if (
    queueKind !== "source_version" &&
    queueKind !== "knowledge_article" &&
    queueKind !== "learning_candidate"
  ) {
    throw new FiscalDataError("knowledge_review_invalid");
  }
  const item: KnowledgeReviewQueueItem = {
    queueKind,
    itemId: strictString(row["item_id"], "knowledge_review_invalid"),
    title: strictString(row["title"], "knowledge_review_invalid"),
    status: strictString(row["status"], "knowledge_review_invalid"),
    contentSha256: strictNullableString(row["content_sha256"], "knowledge_review_invalid"),
    submittedAt: strictNullableString(row["submitted_at"], "knowledge_review_invalid"),
    lastReviewedAt: strictNullableString(row["last_reviewed_at"], "knowledge_review_invalid"),
    blockers: strictStringArray(row["blockers"], "knowledge_review_invalid"),
    canReview: strictBoolean(row["can_review"], "knowledge_review_invalid"),
    canPublish: strictBoolean(row["can_publish"], "knowledge_review_invalid"),
    sourceId: strictNullableString(row["source_id"], "knowledge_review_invalid"),
    changeSetId: strictNullableString(row["change_set_id"], "knowledge_review_invalid"),
    candidateVersionId: strictNullableString(
      row["candidate_version_id"],
      "knowledge_review_invalid",
    ),
    candidateId: strictOptionalNullableString(row["candidate_id"], "knowledge_review_invalid"),
    question: strictOptionalNullableString(row["question"], "knowledge_review_invalid"),
    proposedAnswerPreview: strictOptionalNullableString(
      row["proposed_answer_preview"],
      "knowledge_review_invalid",
    ),
    articleId: strictNullableString(row["article_id"], "knowledge_review_invalid"),
    revisionId: strictNullableString(row["revision_id"], "knowledge_review_invalid"),
    revisionNumber: strictNullableNumber(row["revision_number"], "knowledge_review_invalid"),
    answerPreview: strictNullableString(row["answer_preview"], "knowledge_review_invalid"),
    citationCount: strictNullableNumber(row["citation_count"], "knowledge_review_invalid"),
    isTest:
      row["is_test"] === null ? null : strictBoolean(row["is_test"], "knowledge_review_invalid"),
    taxScope: strictNullableString(row["tax_scope"], "knowledge_review_invalid"),
    divergenceScope: strictNullableString(row["divergence_scope"], "knowledge_review_invalid"),
    validFrom: strictNullableString(row["valid_from"], "knowledge_review_invalid"),
    validUntil: strictNullableString(row["valid_until"], "knowledge_review_invalid"),
    officialUrl: strictNullableString(row["official_url"], "knowledge_review_invalid"),
    candidateContentPreview: strictNullableString(
      row["candidate_content_preview"],
      "knowledge_review_invalid",
    ),
    sectionCount: strictNullableNumber(row["section_count"], "knowledge_review_invalid"),
  };
  if (
    (queueKind === "source_version" &&
      (!item.changeSetId || !item.sourceId || !item.candidateVersionId)) ||
    (queueKind === "knowledge_article" && (!item.articleId || !item.revisionId)) ||
    (queueKind === "learning_candidate" &&
      (!item.candidateId || !item.question || !item.proposedAnswerPreview))
  ) {
    throw new FiscalDataError("knowledge_review_invalid");
  }
  return item;
}

function mapKnowledgeCatalogCoverage(value: unknown): KnowledgeCatalogCoverage {
  const code = "knowledge_coverage_invalid";
  const row = strictObject(value, code);
  const expected = strictNullableInteger(row["expected"], code);
  const discovered = strictInteger(row["discovered"], code);
  const identityVerified = strictInteger(row["identity_verified"], code);
  const extractionQueued = strictInteger(row["extraction_queued"], code);
  const reviewable = strictInteger(row["reviewable"], code);
  const published = strictInteger(row["published"], code);
  const corpusIntegral = strictBoolean(row["corpus_integral"], code);
  const upstreamStatus = strictString(row["upstream_status"], code);
  if (
    !new Set(["unverified", "available", "blocked_403", "blocked_502", "blocked_503"]).has(
      upstreamStatus,
    ) ||
    identityVerified > discovered ||
    extractionQueued > discovered ||
    reviewable > discovered ||
    published > discovered
  ) {
    throw new FiscalDataError(code);
  }
  const countsProveIntegral = expected !== null && discovered >= expected && published >= expected;
  if (corpusIntegral !== countsProveIntegral) throw new FiscalDataError(code);
  return {
    coverageKey: strictString(row["coverage_key"], code),
    title: strictString(row["title"], code),
    expected,
    discovered,
    identityVerified,
    extractionQueued,
    reviewable,
    published,
    corpusIntegral,
    upstreamStatus: upstreamStatus as KnowledgeCatalogCoverage["upstreamStatus"],
    blocker: strictNullableString(row["blocker"], code),
  };
}

function mapKnowledgeSnapshot(data: unknown, municipalityId: string): KnowledgeOperationsSnapshot {
  const root = strictObject(data, "knowledge_snapshot_invalid");
  if (root["verified"] !== true) throw new FiscalDataError("knowledge_snapshot_unverified");
  const municipality = strictObject(root["municipality"], "knowledge_snapshot_invalid");
  const returnedMunicipalityId = strictString(municipality["id"], "knowledge_snapshot_invalid");
  if (returnedMunicipalityId !== municipalityId) {
    throw new FiscalDataError("knowledge_snapshot_tenant_mismatch");
  }
  const capabilities = strictObject(root["capabilities"], "knowledge_snapshot_invalid");
  const summary = strictObject(root["summary"], "knowledge_snapshot_invalid");
  const health = strictObject(root["health"], "knowledge_snapshot_invalid");
  const schedule = strictObject(root["schedule"], "knowledge_snapshot_invalid");
  const ocr = strictObject(root["ocr"], "knowledge_ocr_status_invalid");
  const ocrJobs = strictObject(ocr["jobs"], "knowledge_ocr_status_invalid");
  const ocrLimits = strictObject(ocr["limits"], "knowledge_ocr_status_invalid");
  const reviewer = strictObject(root["reviewer"], "knowledge_snapshot_invalid");
  const coverage = strictArray(root["coverage"], "knowledge_coverage_invalid").map(
    mapKnowledgeCatalogCoverage,
  );
  const coverageLabel = strictString(root["coverage_label"], "knowledge_coverage_invalid");
  const corpusIntegral = strictBoolean(root["corpus_integral"], "knowledge_coverage_invalid");
  if (
    coverageLabel !== "Cobertura inicial governada" ||
    corpusIntegral !== (coverage.length > 0 && coverage.every((item) => item.corpusIntegral))
  ) {
    throw new FiscalDataError("knowledge_coverage_invalid");
  }
  const healthStatus = strictString(health["status"], "knowledge_snapshot_invalid");
  if (!new Set(["healthy", "attention", "blocked"]).has(healthStatus)) {
    throw new FiscalDataError("knowledge_snapshot_invalid");
  }
  const eligibleSections = strictInteger(
    summary["eligible_sections"],
    "knowledge_snapshot_invalid",
  );
  const indexedSections = strictInteger(summary["indexed_sections"], "knowledge_snapshot_invalid");
  const indexedChunks = strictInteger(summary["indexed_chunks"], "knowledge_snapshot_invalid");
  const pendingEmbeddings = strictInteger(
    summary["pending_embeddings"],
    "knowledge_snapshot_invalid",
  );
  const lastIndexedAt = strictNullableString(
    summary["last_indexed_at"],
    "knowledge_snapshot_invalid",
  );
  const scheduleEnabled = strictBoolean(schedule["enabled"], "knowledge_snapshot_invalid");
  const runtimeVerified = strictBoolean(schedule["runtime_verified"], "knowledge_snapshot_invalid");
  const timeZone = validatedIanaTimeZone(schedule["timezone"]);
  const nextRunAt = strictNullableString(schedule["next_run_at"], "knowledge_snapshot_invalid");
  const runtimeBlocker = strictOptionalNullableString(
    schedule["runtime_blocker"],
    "knowledge_snapshot_invalid",
  );
  const scheduleBlockers = [
    ...(runtimeVerified ? [] : [runtimeBlocker ?? "knowledge_runtime_not_verified"]),
    ...(timeZone ? [] : ["knowledge_schedule_timezone_not_verified"]),
    ...(scheduleEnabled && (!nextRunAt || Number.isNaN(Date.parse(nextRunAt)))
      ? ["knowledge_schedule_next_run_not_verified"]
      : []),
  ];
  const indexInconsistent = indexedSections > eligibleSections;
  const indexIncomplete = indexedSections < eligibleSections;
  const indexBlockers = indexInconsistent
    ? ["knowledge_index_inconsistent"]
    : eligibleSections === 0
      ? ["no_eligible_legal_sections"]
      : [
          ...(indexIncomplete ? ["knowledge_index_incomplete"] : []),
          ...(pendingEmbeddings > 0 ? ["knowledge_index_pending"] : []),
        ];
  const reviewerVerified = strictBoolean(reviewer["verified"], "knowledge_snapshot_invalid");
  const reviewerConfigured = strictBoolean(reviewer["configured"], "knowledge_snapshot_invalid");
  const reviewerBlockers = strictStringArray(reviewer["blockers"], "knowledge_snapshot_invalid");
  const ocrContractVersion = strictString(ocr["contract_version"], "knowledge_ocr_status_invalid");
  const ocrPolicyVersion = strictString(ocr["policy_version"], "knowledge_ocr_status_invalid");
  const ocrRuntimeVerified = strictBoolean(ocr["runtime_verified"], "knowledge_ocr_status_invalid");
  const ocrHasAttention = strictBoolean(ocr["has_attention"], "knowledge_ocr_status_invalid");
  const ocrRuntimeBlocker = strictOptionalNullableString(
    ocr["runtime_blocker"],
    "knowledge_ocr_status_invalid",
  );
  const ocrState = strictString(ocr["state"], "knowledge_ocr_status_invalid");
  const ocrCandidateStatus = strictString(ocr["candidate_status"], "knowledge_ocr_status_invalid");
  const ocrAutoPublish = strictBoolean(ocr["auto_publish"], "knowledge_ocr_status_invalid");
  const ocrAbovePageLimit = strictString(
    ocrLimits["above_page_limit"],
    "knowledge_ocr_status_invalid",
  );
  const ocrQueued = strictInteger(ocrJobs["queued"], "knowledge_ocr_status_invalid");
  const ocrProcessing = strictInteger(ocrJobs["processing"], "knowledge_ocr_status_invalid");
  const ocrCompleted = strictInteger(ocrJobs["completed"], "knowledge_ocr_status_invalid");
  const ocrDeadLetter = strictInteger(ocrJobs["dead_letter"], "knowledge_ocr_status_invalid");
  const ocrBlockedPageLimit = strictInteger(
    ocrJobs["blocked_page_limit"],
    "knowledge_ocr_status_invalid",
  );
  const ocrMaxPages = strictInteger(ocrLimits["max_pages"], "knowledge_ocr_status_invalid");
  const ocrMaxPageCharacters = strictInteger(
    ocrLimits["max_page_characters"],
    "knowledge_ocr_status_invalid",
  );
  const ocrMaxTotalCharacters = strictInteger(
    ocrLimits["max_total_characters"],
    "knowledge_ocr_status_invalid",
  );
  const expectedOcrState = !ocrRuntimeVerified
    ? "blocked"
    : ocrHasAttention
      ? "attention_required"
      : ocrProcessing > 0
        ? "processing"
        : ocrQueued > 0
          ? "queued"
          : "ready";
  const validOcrStates = new Set([
    "blocked",
    "processing",
    "queued",
    "attention_required",
    "ready",
  ]);
  if (
    ocrContractVersion !== "ia-fiscal-knowledge-ocr/v1" ||
    ocrPolicyVersion !== "ia-fiscal-knowledge-ocr-policy/v1" ||
    !validOcrStates.has(ocrState) ||
    ocrCandidateStatus !== "under_review" ||
    ocrAutoPublish !== false ||
    ocrAbovePageLimit !== "manual_review_required" ||
    ocrState !== expectedOcrState ||
    ocrHasAttention !== (ocrDeadLetter > 0 || ocrBlockedPageLimit > 0) ||
    (ocrRuntimeVerified
      ? ocrRuntimeBlocker !== null
      : ocrRuntimeBlocker !== "knowledge_ocr_runtime_not_verified") ||
    [ocrQueued, ocrProcessing, ocrCompleted, ocrDeadLetter, ocrBlockedPageLimit].some(
      (value) => value < 0,
    ) ||
    ocrMaxPages !== 120 ||
    ocrMaxPageCharacters !== 1_000_000 ||
    ocrMaxTotalCharacters !== 8_000_000
  ) {
    throw new FiscalDataError("knowledge_ocr_status_invalid");
  }
  return {
    verified: true,
    municipalityId: returnedMunicipalityId,
    municipalityName: strictString(municipality["name"], "knowledge_snapshot_invalid"),
    municipalitySlug: strictString(municipality["slug"], "knowledge_snapshot_invalid"),
    checkedAt: strictString(root["checked_at"], "knowledge_snapshot_invalid"),
    capabilities: {
      canView: strictBoolean(capabilities["can_view"], "knowledge_snapshot_invalid"),
      canSearch: strictBoolean(capabilities["can_search"], "knowledge_snapshot_invalid"),
      canSubmitCandidates: strictBoolean(
        capabilities["can_submit_candidates"],
        "knowledge_snapshot_invalid",
      ),
      canReviewCandidates: strictBoolean(
        capabilities["can_review_candidates"],
        "knowledge_snapshot_invalid",
      ),
      canReviewSourceVersions: strictBoolean(
        capabilities["can_review_source_versions"],
        "knowledge_snapshot_invalid",
      ),
      canReviewArticles: strictBoolean(
        capabilities["can_review_articles"],
        "knowledge_snapshot_invalid",
      ),
      canPublishSourceVersions: strictBoolean(
        capabilities["can_publish_source_versions"],
        "knowledge_snapshot_invalid",
      ),
      canPublishArticles: strictBoolean(
        capabilities["can_publish_articles"],
        "knowledge_snapshot_invalid",
      ),
    },
    summary: {
      officialSources: strictInteger(summary["official_sources"], "knowledge_snapshot_invalid"),
      totalSourceVersions: strictInteger(
        summary["total_source_versions"],
        "knowledge_snapshot_invalid",
      ),
      publishedSourceVersions: strictInteger(
        summary["published_source_versions"],
        "knowledge_snapshot_invalid",
      ),
      pendingSourceReviews: strictInteger(
        summary["pending_source_reviews"],
        "knowledge_snapshot_invalid",
      ),
      pendingSourceExtractions: strictInteger(
        summary["pending_source_extractions"],
        "knowledge_snapshot_invalid",
      ),
      pendingSourcePublications: strictInteger(
        summary["pending_source_publications"],
        "knowledge_snapshot_invalid",
      ),
      pendingArticleReviews: strictInteger(
        summary["pending_article_reviews"],
        "knowledge_snapshot_invalid",
      ),
      pendingCandidates: strictInteger(summary["pending_candidates"], "knowledge_snapshot_invalid"),
      pendingEmbeddings,
      eligibleSections,
      indexedSections,
      indexedChunks,
      lastIndexedAt,
      openChanges: strictInteger(summary["open_changes"], "knowledge_snapshot_invalid"),
      failedFetches24h: strictInteger(summary["failed_fetches_24h"], "knowledge_snapshot_invalid"),
    },
    sources: strictArray(root["sources"], "knowledge_snapshot_invalid").map(mapKnowledgeSource),
    changes: strictArray(root["changes"], "knowledge_snapshot_invalid").map(mapKnowledgeChange),
    reviews: strictArray(root["reviews"], "knowledge_snapshot_invalid").map(mapKnowledgeReview),
    health: {
      status: healthStatus as "healthy" | "attention" | "blocked",
      staleSources: strictInteger(health["stale_sources"], "knowledge_snapshot_invalid"),
      failedSources: strictInteger(health["failed_sources"], "knowledge_snapshot_invalid"),
      blockedSources: strictInteger(health["blocked_sources"], "knowledge_snapshot_invalid"),
      lastSuccessfulFetchAt: strictNullableString(
        health["last_successful_fetch_at"],
        "knowledge_snapshot_invalid",
      ),
      blockers: strictStringArray(health["blockers"], "knowledge_snapshot_invalid"),
    },
    schedule: {
      enabled: scheduleEnabled,
      cadenceLabel: strictString(schedule["cadence"], "knowledge_snapshot_invalid"),
      timeZone,
      nextRunAt,
      lastRunAt: strictNullableString(schedule["last_run_at"], "knowledge_snapshot_invalid"),
      lastRunStatus:
        strictOptionalNullableString(schedule["last_run_status"], "knowledge_snapshot_invalid") ??
        "never_run",
      runtimeVerified,
      blockers: [...new Set(scheduleBlockers)],
    },
    index: {
      status:
        indexInconsistent || eligibleSections === 0
          ? "blocked"
          : indexIncomplete || pendingEmbeddings > 0
            ? "attention"
            : "healthy",
      indexedSections,
      eligibleSections,
      embeddingModel: indexedChunks > 0 ? "gte-small" : null,
      lastIndexedAt,
      blockers: indexBlockers,
    },
    ocr: {
      contractVersion: ocrContractVersion,
      policyVersion: ocrPolicyVersion,
      runtimeVerified: ocrRuntimeVerified,
      hasAttention: ocrHasAttention,
      state: ocrState as "blocked" | "processing" | "queued" | "attention_required" | "ready",
      jobs: {
        queued: ocrQueued,
        processing: ocrProcessing,
        completed: ocrCompleted,
        deadLetter: ocrDeadLetter,
        blockedPageLimit: ocrBlockedPageLimit,
      },
      lastEventAt: strictNullableString(ocr["last_event_at"], "knowledge_ocr_status_invalid"),
      limits: {
        maxPages: ocrMaxPages,
        maxPageCharacters: ocrMaxPageCharacters,
        maxTotalCharacters: ocrMaxTotalCharacters,
        abovePageLimit: "manual_review_required",
      },
      candidateStatus: "under_review",
      autoPublish: false,
      blockers: [
        ...(ocrRuntimeVerified ? [] : [ocrRuntimeBlocker ?? "knowledge_ocr_runtime_not_verified"]),
        ...(ocrDeadLetter > 0 ? ["knowledge_ocr_jobs_failed"] : []),
        ...(ocrBlockedPageLimit > 0 ? ["knowledge_ocr_page_limit_exceeded"] : []),
      ],
    },
    reviewer: {
      verified: reviewerVerified,
      configured: reviewerConfigured,
      activeCount: strictInteger(reviewer["active_count"], "knowledge_snapshot_invalid"),
      currentUserCanReview: strictBoolean(
        reviewer["current_user_can_review"],
        "knowledge_snapshot_invalid",
      ),
      blockers: reviewerVerified
        ? reviewerBlockers
        : [...new Set([...reviewerBlockers, "reviewer_state_not_verified"])],
    },
    coverage,
    coverageLabel,
    corpusIntegral,
  };
}

function mapKnowledgeSearchCitation(value: unknown): KnowledgeSearchCitation {
  const code = "knowledge_search_invalid";
  const row = strictObject(value, code);
  return {
    citationId: `${strictString(row["source_version_id"], code)}:${strictString(row["legal_section_id"], code)}`,
    sourceTitle: strictString(row["source_title"], code),
    officialIdentifier: strictNullableString(row["official_identifier"], code),
    officialUrl: strictNullableString(row["official_url"], code),
    sourceVersionId: strictString(row["source_version_id"], code),
    sectionId: strictString(row["legal_section_id"], code),
    sectionKey: strictString(row["section_key"], code),
    sectionHeading: strictNullableString(row["heading"], code),
    citationLabel:
      strictNullableString(row["heading"], code) ?? strictString(row["section_key"], code),
    quotedExcerpt: strictString(row["excerpt"], code),
    publicationDate: strictNullableString(row["publication_date"], code),
    validFrom: strictNullableString(row["valid_from"], code),
    validUntil: strictNullableString(row["valid_until"], code),
    relevance: strictUnitInterval(row["score"], code),
    isValid: isSecureHttpUrl(strictNullableString(row["official_url"], code)),
    blockers: [],
  };
}

function mapKnowledgeSearchResult(
  payload: unknown,
  municipalityId: string,
  query: string,
): KnowledgeSearchResult {
  const code = "knowledge_search_invalid";
  const envelope = strictObject(payload, code);
  if (strictString(envelope["contract_version"], code) !== "knowledge-search-v1") {
    throw new FiscalDataError("knowledge_search_contract_mismatch");
  }
  const correlationId = strictString(envelope["correlation_id"], code);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      correlationId,
    )
  ) {
    throw new FiscalDataError("knowledge_search_correlation_invalid");
  }
  const row = strictObject(envelope["data"], code);
  if (row["verified"] !== true) throw new FiscalDataError("knowledge_search_unverified");
  const returnedMunicipalityId = strictString(row["municipality_id"], code);
  const returnedQuery = strictString(row["query"], code);
  if (returnedMunicipalityId !== municipalityId || returnedQuery !== query) {
    throw new FiscalDataError("knowledge_search_scope_mismatch");
  }

  const answered = strictBoolean(row["answered"], code);
  const answer = strictNullableString(row["answer"], code);
  const citations = strictArray(row["citations"], code).map(mapKnowledgeSearchCitation);
  const blockers = strictStringArray(row["blockers"], code);
  const confidence =
    row["confidence"] === null ? null : strictUnitInterval(row["confidence"], code);
  const hasVerifiableCitations =
    citations.length > 0 &&
    citations.every(
      (citation) =>
        citation.isValid &&
        citation.blockers.length === 0 &&
        citation.quotedExcerpt.trim().length > 0 &&
        isSecureHttpUrl(citation.officialUrl) &&
        isCurrentLegalCitation(citation),
    );
  if (
    answered &&
    (!answer?.trim() ||
      confidence === null ||
      confidence < KNOWLEDGE_MIN_ANSWER_CONFIDENCE ||
      !hasVerifiableCitations ||
      blockers.length > 0)
  ) {
    throw new FiscalDataError("knowledge_search_evidence_unverified");
  }
  if (!answered && answer !== null) {
    throw new FiscalDataError("knowledge_search_contract_mismatch");
  }

  return {
    verified: true,
    correlationId,
    municipalityId: returnedMunicipalityId,
    query: returnedQuery,
    answered,
    answer,
    confidence,
    retrievalMode: strictString(row["retrieval_mode"], code),
    searchedAt: strictString(row["searched_at"], code),
    citations,
    blockers,
  };
}

async function searchLegalKnowledge(
  municipalityId: string,
  rawQuery: string,
): Promise<KnowledgeSearchResult> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const query = rawQuery.trim();
  if (query.length < 5 || query.length > 500) {
    throw new FiscalDataError("invalid_knowledge_search_query");
  }
  const { data, error } = await getSupabaseClient().functions.invoke("ia-fiscal-knowledge-search", {
    body: { municipality_id: scopedMunicipalityId, query, limit: 8 },
    signal: fiscalReadSignal(),
  });
  throwIfError(error);
  return mapKnowledgeSearchResult(data, scopedMunicipalityId, query);
}

async function submitKnowledgeCandidate(
  municipalityId: string,
  input: KnowledgeCandidateInput,
): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const question = input.question.trim();
  const proposedAnswer = input.proposedAnswer.trim();
  const citationSectionIds = [
    ...new Set(input.citationSectionIds.map((value) => value.trim())),
  ].filter(Boolean);
  if (question.length < 5 || question.length > 1_000) {
    throw new FiscalDataError("invalid_knowledge_candidate_question");
  }
  if (proposedAnswer.length < 20 || proposedAnswer.length > 8_000) {
    throw new FiscalDataError("invalid_knowledge_candidate_answer");
  }
  if (citationSectionIds.length === 0 || citationSectionIds.length > 20) {
    throw new FiscalDataError("knowledge_candidate_citation_required");
  }
  if (input.confirmation !== "ENVIAR PARA REVISÃO") {
    throw new FiscalDataError("knowledge_candidate_confirmation_required");
  }
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { data, error } = await client.rpc("ia_submit_knowledge_candidate", {
    p_municipality_id: scopedMunicipalityId,
    p_question: question,
    p_proposed_answer: proposedAnswer,
    p_citation_section_ids: citationSectionIds,
    p_confirmation: input.confirmation,
  });
  throwIfError(error);
  return strictString(data, "knowledge_candidate_id_missing");
}

function mapKnowledgeCandidateCitation(value: unknown): KnowledgeSearchCitation {
  const code = "knowledge_candidate_evidence_invalid";
  const row = strictObject(value, code);
  const officialUrl = strictNullableString(row["official_url"], code);
  const sourceVersionId = strictString(row["source_version_id"], code);
  const sectionId = strictString(row["legal_section_id"], code);
  const sectionKey = strictString(row["section_key"], code);
  const heading = strictNullableString(row["heading"], code);
  const serverValid = strictBoolean(row["is_valid"], code);
  return {
    citationId: `${sourceVersionId}:${sectionId}`,
    sourceTitle: strictString(row["source_title"], code),
    officialIdentifier: strictNullableString(row["official_identifier"], code),
    officialUrl,
    sourceVersionId,
    sectionId,
    sectionKey,
    sectionHeading: heading,
    citationLabel: heading ?? sectionKey,
    quotedExcerpt: strictString(row["excerpt"], code),
    publicationDate: strictNullableString(row["publication_date"], code),
    validFrom: strictNullableString(row["valid_from"], code),
    validUntil: strictNullableString(row["valid_until"], code),
    relevance: strictUnitInterval(row["score"], code),
    isValid: serverValid && isSecureHttpUrl(officialUrl),
    blockers: strictStringArray(row["blockers"], code),
  };
}

function mapKnowledgeCandidateEvidence(
  data: unknown,
  municipalityId: string,
  candidateId: string,
): KnowledgeCandidateEvidence {
  const code = "knowledge_candidate_evidence_invalid";
  const row = strictObject(data, code);
  if (row["verified"] !== true) {
    throw new FiscalDataError("knowledge_candidate_evidence_unverified");
  }
  const returnedMunicipalityId = strictString(row["municipality_id"], code);
  const returnedCandidateId = strictString(row["candidate_id"], code);
  if (returnedMunicipalityId !== municipalityId || returnedCandidateId !== candidateId) {
    throw new FiscalDataError("knowledge_candidate_evidence_scope_mismatch");
  }
  const canPublish = strictBoolean(row["can_publish"], code);
  if (canPublish) throw new FiscalDataError("knowledge_candidate_publication_forbidden");
  return {
    verified: true,
    checkedAt: strictString(row["checked_at"], code),
    municipalityId: returnedMunicipalityId,
    candidateId: returnedCandidateId,
    question: strictString(row["question"], code),
    proposedAnswer: strictString(row["proposed_answer"], code),
    contentSha256: strictString(row["content_sha256"], code),
    status: strictString(row["status"], code),
    submittedAt: strictString(row["submitted_at"], code),
    reviewedAt: strictNullableString(row["reviewed_at"], code),
    citations: strictArray(row["citations"], code).map(mapKnowledgeCandidateCitation),
    evidenceComplete: strictBoolean(row["evidence_complete"], code),
    blockers: strictStringArray(row["blockers"], code),
    canReview: strictBoolean(row["can_review"], code),
    canPublish: false,
  };
}

async function getKnowledgeCandidateEvidence(
  municipalityId: string,
  candidateId: string,
): Promise<KnowledgeCandidateEvidence> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedCandidateId = requireKnowledgeIdentifier(candidateId, "invalid_candidate_id");
  const client = getSupabaseClient() as unknown as KnowledgeReadRpcClient;
  const { data, error } = await client
    .rpc("ia_get_knowledge_candidate_evidence", {
      p_municipality_id: scopedMunicipalityId,
      p_candidate_id: scopedCandidateId,
    })
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return mapKnowledgeCandidateEvidence(data, scopedMunicipalityId, scopedCandidateId);
}

async function reviewKnowledgeCandidate(
  municipalityId: string,
  candidateId: string,
  decision: KnowledgeCandidateReviewDecision,
  notes: string,
  confirmation: string,
): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedCandidateId = requireKnowledgeIdentifier(candidateId, "invalid_candidate_id");
  if (decision !== "approved" && decision !== "rejected") {
    throw new FiscalDataError("invalid_candidate_review_decision");
  }
  const normalizedNotes = notes.trim();
  if (normalizedNotes.length > 4_000 || (decision === "rejected" && normalizedNotes.length < 10)) {
    throw new FiscalDataError("invalid_candidate_review_notes");
  }
  if (confirmation !== "REVISAR CANDIDATO") {
    throw new FiscalDataError("candidate_review_confirmation_required");
  }
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { data, error } = await client.rpc("ia_review_knowledge_candidate", {
    p_expected_municipality_id: scopedMunicipalityId,
    p_candidate_id: scopedCandidateId,
    p_decision: decision,
    p_notes: normalizedNotes || null,
    p_confirmation: confirmation,
  });
  throwIfError(error);
  return strictString(data, "knowledge_candidate_review_id_missing");
}

function mapKnowledgeArticleEvidence(
  data: unknown,
  municipalityId: string,
  articleId: string,
  revisionId: string,
): KnowledgeArticleEvidence {
  const row = strictObject(data, "knowledge_article_evidence_invalid");
  if (row["verified"] !== true) {
    throw new FiscalDataError("knowledge_article_evidence_unverified");
  }
  const returnedMunicipalityId = strictString(
    row["municipality_id"],
    "knowledge_article_evidence_invalid",
  );
  const returnedArticleId = strictString(row["article_id"], "knowledge_article_evidence_invalid");
  const returnedRevisionId = strictString(row["revision_id"], "knowledge_article_evidence_invalid");
  if (
    returnedMunicipalityId !== municipalityId ||
    returnedArticleId !== articleId ||
    returnedRevisionId !== revisionId
  ) {
    throw new FiscalDataError("knowledge_article_evidence_tenant_mismatch");
  }
  const answerBody = strictString(row["answer_body"], "knowledge_article_evidence_invalid");
  const answerLength = strictInteger(row["answer_length"], "knowledge_article_evidence_invalid");
  const citations = strictKnowledgeCitations(
    row["citations"],
    "knowledge_article_evidence_invalid",
  );
  const citationCount = strictInteger(row["citation_count"], "knowledge_article_evidence_invalid");
  if (Array.from(answerBody).length !== answerLength || citations.length !== citationCount) {
    throw new FiscalDataError("knowledge_article_evidence_incomplete");
  }
  return {
    verified: true,
    municipalityId: returnedMunicipalityId,
    articleId: returnedArticleId,
    revisionId: returnedRevisionId,
    contentSha256: strictString(row["content_sha256"], "knowledge_article_evidence_invalid"),
    canonicalQuestion: strictString(
      row["canonical_question"],
      "knowledge_article_evidence_invalid",
    ),
    answerBody,
    answerLength,
    citationCount,
    citations,
    evidenceComplete: strictBoolean(row["evidence_complete"], "knowledge_article_evidence_invalid"),
    blockers: strictStringArray(row["blockers"], "knowledge_article_evidence_invalid"),
  };
}

function mapKnowledgeSourceSection(value: unknown): KnowledgeSourceSectionEvidence {
  const code = "knowledge_source_evidence_invalid";
  const row = strictObject(value, code);
  return {
    sectionId: strictString(row["section_id"], code),
    sectionKey: strictString(row["section_key"], code),
    heading: strictNullableString(row["heading"], code),
    ordinal: strictInteger(row["ordinal"], code),
    contentPreview: strictString(row["content_preview"], code),
    contentTotalChars: strictInteger(row["content_total_chars"], code),
    contentSha256: strictString(row["content_sha256"], code),
    chunkCount: strictInteger(row["chunk_count"], code),
  };
}

function mapKnowledgeSourceChangeItem(value: unknown): KnowledgeSourceChangeItemEvidence {
  const code = "knowledge_source_evidence_invalid";
  const row = strictObject(value, code);
  return {
    ordinal: strictInteger(row["ordinal"], code),
    itemKind: strictString(row["item_kind"], code),
    itemPath: strictString(row["item_path"], code),
    beforeSha256: strictNullableString(row["before_sha256"], code),
    afterSha256: strictNullableString(row["after_sha256"], code),
    beforeExcerpt: strictNullableString(row["before_excerpt"], code),
    afterExcerpt: strictNullableString(row["after_excerpt"], code),
    summary: strictString(row["summary"], code),
  };
}

function mapKnowledgeSourceEvidencePage(
  data: unknown,
  municipalityId: string,
  changeSetId: string,
): KnowledgeSourceChangeEvidence {
  const code = "knowledge_source_evidence_invalid";
  const row = strictObject(data, code);
  if (row["verified"] !== true) throw new FiscalDataError("knowledge_source_evidence_unverified");
  const returnedMunicipalityId = strictString(row["municipality_id"], code);
  const returnedChangeSetId = strictString(row["change_set_id"], code);
  if (returnedMunicipalityId !== municipalityId || returnedChangeSetId !== changeSetId) {
    throw new FiscalDataError("knowledge_source_evidence_tenant_mismatch");
  }
  return {
    verified: true,
    municipalityId: returnedMunicipalityId,
    changeSetId: returnedChangeSetId,
    changeType: strictString(row["change_type"], code),
    status: strictString(row["status"], code),
    sourceId: strictString(row["source_id"], code),
    sourceTitle: strictString(row["source_title"], code),
    officialIdentifier: strictNullableString(row["official_identifier"], code),
    officialUrl: strictNullableString(row["official_url"], code),
    requestedUrl: strictNullableString(row["requested_url"], code),
    capturedUrl: strictNullableString(row["captured_url"], code),
    observedAt: strictNullableString(row["observed_at"], code),
    rawContentSha256: strictNullableString(row["raw_content_sha256"], code),
    fromSha256: strictNullableString(row["from_sha256"], code),
    toSha256: strictString(row["to_sha256"], code),
    diffSha256: strictString(row["diff_sha256"], code),
    artifactId: strictNullableString(row["artifact_id"], code),
    artifactMimeType: strictNullableString(row["artifact_mime_type"], code),
    artifactByteSize: strictNullableNumber(row["artifact_byte_size"], code),
    candidateVersionId: strictString(row["candidate_version_id"], code),
    candidateVersionNumber: strictInteger(row["candidate_version_number"], code),
    candidateVersionStatus: strictString(row["candidate_version_status"], code),
    contentSha256: strictString(row["content_sha256"], code),
    contentText: strictText(row["content_text"], code),
    contentOffset: strictInteger(row["content_offset"], code),
    contentLimit: strictInteger(row["content_limit"], code),
    contentTotalChars: strictInteger(row["content_total_chars"], code),
    contentHasMore: strictBoolean(row["content_has_more"], code),
    diffSummary: strictString(row["diff_summary"], code),
    publicationDate: strictNullableString(row["publication_date"], code),
    validFrom: strictNullableString(row["valid_from"], code),
    validUntil: strictNullableString(row["valid_until"], code),
    sectionOffset: strictInteger(row["section_offset"], code),
    sectionLimit: strictInteger(row["section_limit"], code),
    sectionTotal: strictInteger(row["section_total"], code),
    sectionHasMore: strictBoolean(row["section_has_more"], code),
    sections: strictArray(row["sections"], code).map(mapKnowledgeSourceSection),
    changeItems: strictArray(row["change_items"], code).map(mapKnowledgeSourceChangeItem),
    changeItemOffset: strictInteger(row["change_item_offset"], code),
    changeItemLimit: strictInteger(row["change_item_limit"], code),
    changeItemTotal: strictInteger(row["change_item_total"], code),
    changeItemsHasMore: strictBoolean(row["change_items_has_more"], code),
    changeItemsFullSha256: strictString(row["change_items_full_sha256"], code),
    evidenceComplete: strictBoolean(row["evidence_complete"], code),
    blockers: strictStringArray(row["blockers"], code),
  };
}

async function getKnowledgeOperationsSnapshot(
  municipalityId: string,
): Promise<KnowledgeOperationsSnapshot> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const client = getSupabaseClient() as unknown as KnowledgeReadRpcClient;
  const { data, error } = await client
    .rpc("ia_get_knowledge_operations_snapshot", { p_municipality_id: scopedMunicipalityId })
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return mapKnowledgeSnapshot(data, scopedMunicipalityId);
}

function mapKnowledgeReviewerGrant(value: unknown): KnowledgeReviewerGrant {
  const code = "knowledge_reviewer_directory_invalid";
  const row = strictObject(value, code);
  return {
    grantId: strictString(row["grant_id"], code),
    membershipId: strictString(row["membership_id"], code),
    role: strictString(row["role"], code),
    status: strictString(row["status"], code),
    validFrom: strictString(row["valid_from"], code),
    validUntil: strictNullableString(row["valid_until"], code),
    isCurrent: strictBoolean(row["is_current"], code),
  };
}

function mapKnowledgeReviewerEligibleStaff(value: unknown): KnowledgeReviewerEligibleStaff {
  const code = "knowledge_reviewer_directory_invalid";
  const row = strictObject(value, code);
  return {
    membershipId: strictString(row["membership_id"], code),
    role: strictString(row["role"], code),
    alreadyConfigured: strictBoolean(row["already_configured"], code),
  };
}

function mapKnowledgeReviewerDirectory(
  data: unknown,
  municipalityId: string,
): KnowledgeReviewerDirectory {
  const code = "knowledge_reviewer_directory_invalid";
  const row = strictObject(data, code);
  if (row["verified"] !== true || row["pii_exposed"] !== false) {
    throw new FiscalDataError(code);
  }
  const returnedMunicipalityId = strictString(row["municipality_id"], code);
  if (returnedMunicipalityId !== municipalityId) {
    throw new FiscalDataError("knowledge_reviewer_directory_tenant_mismatch");
  }
  return {
    verified: true,
    municipalityId: returnedMunicipalityId,
    activeGrants: strictArray(row["active_grants"], code).map(mapKnowledgeReviewerGrant),
    eligibleStaff: strictArray(row["eligible_staff"], code).map(mapKnowledgeReviewerEligibleStaff),
    piiExposed: false,
    checkedAt: strictString(row["checked_at"], code),
  };
}

async function listKnowledgeReviewerCapabilities(
  municipalityId: string,
): Promise<KnowledgeReviewerDirectory> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const client = getSupabaseClient() as unknown as KnowledgeReadRpcClient;
  const { data, error } = await client
    .rpc("ia_list_legal_reviewer_capabilities", {
      p_municipality_id: scopedMunicipalityId,
    })
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return mapKnowledgeReviewerDirectory(data, scopedMunicipalityId);
}

function normalizedReviewerReason(value: string): string {
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1_000) {
    throw new FiscalDataError("invalid_knowledge_reviewer_reason");
  }
  return normalized;
}

async function grantKnowledgeReviewerCapability(
  municipalityId: string,
  targetMembershipId: string,
  validUntil: string | null,
  reason: string,
  confirmation: string,
): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedMembershipId = requireKnowledgeIdentifier(
    targetMembershipId,
    "invalid_membership_id",
  );
  if (confirmation !== "CONFIRMAR REVISOR JURIDICO") {
    throw new FiscalDataError("knowledge_reviewer_confirmation_required");
  }
  if (validUntil !== null && Number.isNaN(Date.parse(validUntil))) {
    throw new FiscalDataError("invalid_knowledge_reviewer_validity");
  }
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { data, error } = await client.rpc("ia_grant_legal_reviewer_capability", {
    p_municipality_id: scopedMunicipalityId,
    p_target_membership_id: scopedMembershipId,
    p_valid_until: validUntil,
    p_reason: normalizedReviewerReason(reason),
    p_confirmation: confirmation,
  });
  throwIfError(error);
  return strictString(data, "knowledge_reviewer_grant_id_missing");
}

async function revokeKnowledgeReviewerCapability(
  grantId: string,
  reason: string,
  confirmation: string,
): Promise<void> {
  const scopedGrantId = requireKnowledgeIdentifier(grantId, "invalid_knowledge_reviewer_grant_id");
  if (confirmation !== "REVOGAR REVISOR JURIDICO") {
    throw new FiscalDataError("knowledge_reviewer_revocation_confirmation_required");
  }
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { error } = await client.rpc("ia_revoke_legal_reviewer_capability", {
    p_grant_id: scopedGrantId,
    p_reason: normalizedReviewerReason(reason),
    p_confirmation: confirmation,
  });
  throwIfError(error);
}

async function getKnowledgeArticleEvidence(
  municipalityId: string,
  articleId: string,
  revisionId: string,
): Promise<KnowledgeArticleEvidence> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedArticleId = requireKnowledgeIdentifier(articleId, "invalid_article_id");
  const scopedRevisionId = requireKnowledgeIdentifier(revisionId, "invalid_revision_id");
  const client = getSupabaseClient() as unknown as KnowledgeReadRpcClient;
  const { data, error } = await client
    .rpc("ia_get_knowledge_article_evidence", {
      p_municipality_id: scopedMunicipalityId,
      p_article_id: scopedArticleId,
      p_revision_id: scopedRevisionId,
    })
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return mapKnowledgeArticleEvidence(data, scopedMunicipalityId, scopedArticleId, scopedRevisionId);
}

async function getLegalSourceChangeEvidence(
  municipalityId: string,
  changeSetId: string,
  requestedPage: KnowledgeSourceEvidencePageRequest = {
    contentOffset: 0,
    sectionOffset: 0,
    changeItemOffset: 0,
  },
): Promise<KnowledgeSourceChangeEvidence> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedChangeSetId = requireKnowledgeIdentifier(changeSetId, "invalid_change_set_id");
  const contentOffset = strictInteger(
    requestedPage.contentOffset,
    "invalid_knowledge_evidence_page",
  );
  const sectionOffset = strictInteger(
    requestedPage.sectionOffset,
    "invalid_knowledge_evidence_page",
  );
  const changeItemOffset = strictInteger(
    requestedPage.changeItemOffset,
    "invalid_knowledge_evidence_page",
  );
  const client = getSupabaseClient() as unknown as KnowledgeReadRpcClient;
  const { data, error } = await client
    .rpc("ia_get_legal_source_change_evidence", {
      p_municipality_id: scopedMunicipalityId,
      p_change_set_id: scopedChangeSetId,
      p_content_offset: contentOffset,
      p_content_limit: KNOWLEDGE_EVIDENCE_CONTENT_PAGE_SIZE,
      p_section_offset: sectionOffset,
      p_section_limit: KNOWLEDGE_EVIDENCE_SECTION_PAGE_SIZE,
      p_change_item_offset: changeItemOffset,
      p_change_item_limit: KNOWLEDGE_EVIDENCE_CHANGE_ITEM_PAGE_SIZE,
    })
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  const page = mapKnowledgeSourceEvidencePage(data, scopedMunicipalityId, scopedChangeSetId);
  const expectedContentLength = Math.min(
    page.contentLimit,
    Math.max(page.contentTotalChars - page.contentOffset, 0),
  );
  const expectedSectionLength = Math.min(
    page.sectionLimit,
    Math.max(page.sectionTotal - page.sectionOffset, 0),
  );
  const expectedChangeItemLength = Math.min(
    page.changeItemLimit,
    Math.max(page.changeItemTotal - page.changeItemOffset, 0),
  );
  if (
    page.contentOffset !== contentOffset ||
    page.sectionOffset !== sectionOffset ||
    page.changeItemOffset !== changeItemOffset ||
    page.contentLimit !== KNOWLEDGE_EVIDENCE_CONTENT_PAGE_SIZE ||
    page.sectionLimit !== KNOWLEDGE_EVIDENCE_SECTION_PAGE_SIZE ||
    page.changeItemLimit !== KNOWLEDGE_EVIDENCE_CHANGE_ITEM_PAGE_SIZE ||
    Array.from(page.contentText).length !== expectedContentLength ||
    page.sections.length !== expectedSectionLength ||
    page.changeItems.length !== expectedChangeItemLength ||
    page.contentHasMore !== page.contentOffset + page.contentLimit < page.contentTotalChars ||
    page.sectionHasMore !== page.sectionOffset + page.sectionLimit < page.sectionTotal ||
    page.changeItemsHasMore !==
      page.changeItemOffset + page.changeItemLimit < page.changeItemTotal ||
    new Set(page.sections.map((section) => section.sectionId)).size !== page.sections.length ||
    new Set(page.changeItems.map((item) => item.ordinal)).size !== page.changeItems.length
  ) {
    throw new FiscalDataError("knowledge_source_evidence_page_mismatch");
  }
  return page;
}

function requireKnowledgeIdentifier(value: string, code: string): string {
  const normalized = value.trim();
  if (!normalized) throw new FiscalDataError(code);
  return normalized;
}

function normalizedReviewNotes(value: string): string | null {
  const normalized = value.trim();
  if (normalized.length > 4_000) throw new FiscalDataError("knowledge_review_notes_too_long");
  return normalized || null;
}

function normalizedOptionalDate(value: string | null): string | null {
  if (value === null || value === "") return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) {
    throw new FiscalDataError("invalid_knowledge_date");
  }
  return value;
}

async function reviewLegalSourceChange(
  municipalityId: string,
  changeSetId: string,
  decision: LegalSourceReviewDecision,
  notes: string,
  confirmation: string,
  metadata: LegalSourceReviewMetadata,
): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedChangeSetId = requireKnowledgeIdentifier(changeSetId, "invalid_change_set_id");
  if (!new Set(["approved", "rejected", "changes_requested"]).has(decision)) {
    throw new FiscalDataError("invalid_source_review_decision");
  }
  if (confirmation !== "REVISAR") throw new FiscalDataError("review_confirmation_required");
  const publicationDate = normalizedOptionalDate(metadata.publicationDate);
  const validFrom = normalizedOptionalDate(metadata.validFrom);
  const validUntil = normalizedOptionalDate(metadata.validUntil);
  if (validFrom && validUntil && validUntil < validFrom) {
    throw new FiscalDataError("invalid_knowledge_validity");
  }
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { data, error } = await client.rpc("ia_review_legal_source_change", {
    p_expected_municipality_id: scopedMunicipalityId,
    p_change_set_id: scopedChangeSetId,
    p_decision: decision,
    p_review_notes: normalizedReviewNotes(notes),
    p_confirmation: confirmation,
    p_publication_date: publicationDate,
    p_valid_from: validFrom,
    p_valid_until: validUntil,
  });
  throwIfError(error);
  return strictString(data, "source_review_id_missing");
}

async function publishLegalSourceVersion(
  municipalityId: string,
  sourceVersionId: string,
  confirmation: string,
): Promise<void> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedVersionId = requireKnowledgeIdentifier(sourceVersionId, "invalid_source_version_id");
  if (confirmation !== "PUBLICAR") {
    throw new FiscalDataError("publication_confirmation_required");
  }
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { error } = await client.rpc("ia_publish_legal_source_version", {
    p_expected_municipality_id: scopedMunicipalityId,
    p_source_version_id: scopedVersionId,
    p_confirmation: confirmation,
  });
  throwIfError(error);
}

async function reviewKnowledgeArticle(
  municipalityId: string,
  articleId: string,
  revisionId: string,
  decision: KnowledgeReviewDecision,
  notes: string,
  confirmation: string,
): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedArticleId = requireKnowledgeIdentifier(articleId, "invalid_article_id");
  const scopedRevisionId = requireKnowledgeIdentifier(revisionId, "invalid_revision_id");
  if (!new Set(["approved", "rejected", "revision_requested"]).has(decision)) {
    throw new FiscalDataError("invalid_knowledge_review_decision");
  }
  if (confirmation !== "REVISAR") throw new FiscalDataError("review_confirmation_required");
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { data, error } = await client.rpc("ia_review_knowledge_article", {
    p_expected_municipality_id: scopedMunicipalityId,
    p_article_id: scopedArticleId,
    p_revision_id: scopedRevisionId,
    p_decision: decision,
    p_notes: normalizedReviewNotes(notes),
    p_confirmation: confirmation,
  });
  throwIfError(error);
  return strictString(data, "knowledge_review_id_missing");
}

async function publishKnowledgeArticle(
  municipalityId: string,
  articleId: string,
  confirmation: string,
): Promise<void> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const scopedArticleId = requireKnowledgeIdentifier(articleId, "invalid_article_id");
  if (confirmation !== "PUBLICAR") {
    throw new FiscalDataError("publication_confirmation_required");
  }
  const client = getSupabaseClient() as unknown as KnowledgeWriteRpcClient;
  const { error } = await client.rpc("ia_publish_knowledge_article", {
    p_expected_municipality_id: scopedMunicipalityId,
    p_article_id: scopedArticleId,
    p_confirmation: confirmation,
  });
  throwIfError(error);
}

async function listPortalCases(municipalityId: string): Promise<PortalCaseReadModel[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const { data, error } = await getSupabaseClient()
    .from("vw_case_portal_home")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .order("prepared_at", { ascending: false })
    .limit(200)
    .abortSignal(fiscalReadSignal());
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

async function listCaseMessages(
  municipalityId: string,
  caseId: string,
): Promise<CaseMessageReadModel[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  if (!caseId) return [];
  const { data, error } = await getSupabaseClient()
    .from("case_messages")
    .select(
      "id, case_id, body, sender_type, source_type, status, visibility, created_at, published_at",
    )
    .eq("municipality_id", scopedMunicipalityId)
    .eq("case_id", caseId)
    .order("created_at", { ascending: false })
    .limit(200)
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return ((data as Row[] | null) ?? []).reverse().map((row) => ({
    id: stringValue(row["id"]),
    caseId: stringValue(row["case_id"]),
    body: stringValue(row["body"]),
    senderType: stringValue(row["sender_type"], "unknown"),
    sourceType: stringValue(row["source_type"], "manual"),
    status: stringValue(row["status"], "unknown"),
    visibility: stringValue(row["visibility"], "restricted"),
    createdAt: stringValue(row["created_at"]),
    publishedAt: nullableString(row["published_at"]),
  }));
}

const operationalReportInFlight = new Map<string, Promise<OperationalReport>>();

async function loadOperationalReport(municipalityId: string): Promise<OperationalReport> {
  const { data, error } = await getSupabaseClient()
    .rpc("ia_operational_report", { p_municipality_id: municipalityId })
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  const report = objectValue(data);
  return {
    taxpayerCount: numberValue(report["taxpayer_count"]),
    overduePeriodCount: numberValue(report["overdue_period_count"]),
    openBalanceTotal: numberValue(report["open_balance_total"]),
    activeDivergenceCount: numberValue(report["active_divergence_count"]),
    divergenceAmountTotal: numberValue(report["divergence_amount_total"]),
    activeCaseCount: numberValue(report["active_case_count"]),
    blockedCalculationCount: numberValue(report["blocked_calculation_count"]),
    waitingQuestionCount: numberValue(report["waiting_question_count"]),
    recipientCandidateCount: numberValue(report["recipient_candidate_count"]),
    deliveryReadyCount: numberValue(report["delivery_ready_count"]),
    externalDeliveryCount: numberValue(report["external_delivery_count"]),
  };
}

function getOperationalReport(municipalityId: string): Promise<OperationalReport> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const current = operationalReportInFlight.get(scopedMunicipalityId);
  if (current) return current;

  const request = loadOperationalReport(scopedMunicipalityId).finally(() => {
    if (operationalReportInFlight.get(scopedMunicipalityId) === request) {
      operationalReportInFlight.delete(scopedMunicipalityId);
    }
  });
  operationalReportInFlight.set(scopedMunicipalityId, request);
  return request;
}

function requiredBoolean(row: Row, key: string): boolean {
  const value = row[key];
  if (typeof value !== "boolean") throw new FiscalDataError("safety_status_invalid");
  return value;
}

function requiredNonNegativeNumber(row: Row, key: string): number {
  const value = row[key];
  const parsed =
    typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new FiscalDataError("safety_status_invalid");
  }
  return parsed;
}

function mapAssistedOperationSafetyStatus(value: unknown): AssistedOperationSafetyStatus {
  const row = objectValue(value);
  if (Object.keys(row).length === 0) throw new FiscalDataError("safety_status_invalid");
  const checkedAtValue = row["checked_at"];
  if (checkedAtValue != null && typeof checkedAtValue !== "string") {
    throw new FiscalDataError("safety_status_invalid");
  }
  return {
    verified: requiredBoolean(row, "verified"),
    externalDeliveryBlocked: requiredBoolean(row, "external_delivery_blocked"),
    masterLock: requiredBoolean(row, "master_lock"),
    externalEmailEnabled: requiredBoolean(row, "external_email_enabled"),
    openEmailChannel: requiredBoolean(row, "open_email_channel"),
    automaticNoticeEnabled: requiredBoolean(row, "automatic_notice_enabled"),
    pendingExternalJobs: requiredNonNegativeNumber(row, "pending_external_jobs"),
    checkedAt: checkedAtValue ?? null,
  };
}

async function getAssistedOperationSafetyStatus(
  municipalityId: string,
): Promise<AssistedOperationSafetyStatus> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  // A função já existe no banco, mas ainda não consta no tipo gerado local.
  // O cast fica restrito a esta RPC de leitura para não afrouxar o cliente inteiro.
  const safetyClient = getSupabaseClient() as unknown as AssistedSafetyRpcClient;
  const { data, error } = await safetyClient
    .rpc("ia_get_assisted_operation_safety_status", {
      p_municipality_id: scopedMunicipalityId,
    })
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return mapAssistedOperationSafetyStatus(data);
}

async function listMunicipalityUsers(municipalityId: string): Promise<MunicipalityUser[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const { data, error } = await getSupabaseClient().rpc("ia_list_municipality_users", {
    p_municipality_id: scopedMunicipalityId,
  });
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((row) => ({
    membershipId: stringValue(row["membership_id"]),
    userId: stringValue(row["user_id"]),
    fullName: stringValue(row["full_name"], "Usuário sem nome"),
    email: stringValue(row["email"]),
    role: stringValue(row["role"], "support_readonly") as MunicipalityUserRole,
    status: stringValue(row["status"], "revoked") as MunicipalityMembershipStatus,
    validFrom: stringValue(row["valid_from"]),
    validUntil: nullableString(row["valid_until"]),
    lastSeenAt: nullableString(row["last_seen_at"]),
  }));
}

async function addExistingMunicipalityUser(
  municipalityId: string,
  email: string,
  role: MunicipalityUserRole,
): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const normalizedEmail = email.trim().toLocaleLowerCase("pt-BR");
  if (!normalizedEmail) throw new FiscalDataError("invalid_user_email");
  const { data, error } = await getSupabaseClient().rpc("ia_add_existing_municipality_user", {
    p_municipality_id: scopedMunicipalityId,
    p_email: normalizedEmail,
    p_role: role,
  });
  throwIfError(error);
  const membershipId = stringValue(data);
  if (!membershipId) throw new FiscalDataError("membership_id_missing");
  return membershipId;
}

async function updateMunicipalityMembership(
  municipalityId: string,
  membershipId: string,
  role: MunicipalityUserRole,
  status: MunicipalityMembershipStatus,
): Promise<string> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  if (!membershipId.trim()) throw new FiscalDataError("invalid_membership_id");
  const { data, error } = await getSupabaseClient().rpc("ia_update_municipality_membership", {
    p_municipality_id: scopedMunicipalityId,
    p_membership_id: membershipId,
    p_role: role,
    p_status: status,
  });
  throwIfError(error);
  const updatedMembershipId = stringValue(data);
  if (!updatedMembershipId) throw new FiscalDataError("membership_id_missing");
  return updatedMembershipId;
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

async function listFiscalCasesLegacy(municipalityId: string): Promise<FiscalCase[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const [cases, summaries, divergences] = await Promise.all([
    listFiscalCaseRows(scopedMunicipalityId),
    listTaxpayerSummaries(scopedMunicipalityId),
    listDivergences(scopedMunicipalityId),
  ]);
  const byTaxpayer = new Map(summaries.map((item) => [item.taxpayerId, item]));
  const byDivergence = new Map(divergences.map((item) => [item.divergenceId, item]));
  return cases.map((item) => {
    const summary = byTaxpayer.get(item.taxpayerId);
    const divergence = item.divergenceId ? byDivergence.get(item.divergenceId) : undefined;
    const divergencePeriods = divergence
      ? [...new Set([divergence.periodStart, divergence.periodEnd].filter(Boolean))]
      : [];
    const taxpayer: Taxpayer = {
      id: item.taxpayerId,
      name: summary?.legalName ?? item.taxpayerName,
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
      competences: divergencePeriods,
      amount: divergence?.differenceAmount ?? 0,
      dueDate: divergence?.periodEnd ?? item.openedAt,
      status: "em_discussao",
    };
    return {
      id: item.caseId,
      taxpayer,
      divergenceType:
        item.explanationTitle ??
        (divergence ? divergenceTypeLabel(divergence.divergenceType) : "Conferência fiscal"),
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

async function listChatQueue(municipalityId: string): Promise<ChatQueueItem[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const { data, error } = await getSupabaseClient()
    .from("vw_fiscal_chat_inbox")
    .select("*")
    .eq("municipality_id", scopedMunicipalityId)
    .in("status", ["waiting", "claimed"])
    .order("operational_priority", { ascending: false })
    .order("sla_due_at", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: true })
    .limit(200)
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return ((data as Row[] | null) ?? [])
    .map((row) => {
      const status = stringValue(row["status"], "submitted");
      const slaDueAt = nullableString(row["sla_due_at"]);
      return {
        id: stringValue(row["question_id"]),
        municipalityId: stringValue(row["municipality_id"]),
        caseId: stringValue(row["case_id"]),
        caseNumber: stringValue(row["case_number"], "Processo protegido"),
        taxpayerName: stringValue(row["taxpayer_name"]),
        cnpj: "identificador protegido",
        lastMessage: stringValue(row["question_preview"]),
        waitingSince: stringValue(row["created_at"]),
        waitingLabel: slaDueAt
          ? "Prazo de atendimento registrado"
          : "Prazo de atendimento não configurado",
        slaDueAt,
        status,
        handlingMode: normalizeHandlingMode(row["handling_mode"]),
        assignedMembershipId: nullableString(row["assigned_membership_id"]),
        claimedAt: nullableString(row["claimed_at"]),
        origin: "portal do contribuinte" as const,
        priority: chatOperationalPriority(status, slaDueAt),
        suggestedReply:
          "Nenhuma resposta automática foi gerada. Consulte a conversa e as fontes governadas antes de redigir qualquer orientação.",
      };
    })
    .sort(compareChatQueueItems);
}

async function listProcessingHealth(): Promise<ProcessingHealthIndicator[]> {
  const { data, error } = await getSupabaseClient()
    .from("api_worker_health")
    .select("*")
    .limit(50)
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  if (!data?.length) {
    return [
      {
        id: "worker-not-observed",
        label: "Processador da operação assistida",
        status: "pausado",
        detail: "Nenhuma execução observável foi registrada",
        metric: "envios externos bloqueados",
      },
    ];
  }
  return (data as Row[]).map((row) => {
    const status = stringValue(row["status"], "unknown");
    const workerName = stringValue(row["worker_name"]);
    const lastSuccessAt = nullableString(row["last_success_at"]);
    const lastSuccessTime = lastSuccessAt ? Date.parse(lastSuccessAt) : Number.NaN;
    return {
      id: workerName,
      label: processingWorkerLabel(workerName),
      status: workerHealthStatus(status),
      detail: `Situação: ${workerStatusLabel(status)} · Pendentes: ${numberValue(row["pending_jobs"])} · Falhas definitivas: ${numberValue(row["dead_letter_jobs"])}`,
      metric: Number.isFinite(lastSuccessTime)
        ? `Último processamento: ${formatDateTime(lastSuccessAt!)}`
        : "Nenhum processamento concluído",
    };
  });
}

async function listAuditEvents(municipalityId: string): Promise<AuditEvent[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const { data, error } = await getSupabaseClient()
    .from("case_events")
    .select("id, event_type, occurred_at, visibility")
    .eq("municipality_id", scopedMunicipalityId)
    .order("occurred_at", { ascending: false })
    .limit(20)
    .abortSignal(fiscalReadSignal());
  throwIfError(error);
  return ((data as Row[] | null) ?? []).map((row) => ({
    id: identifierValue(row["id"]),
    type: "escalonamento",
    title: fiscalEventTypeLabel(stringValue(row["event_type"])),
    description: `Evento auditável visível para ${visibilityLabel(stringValue(row["visibility"]))}.`,
    occurredAt: stringValue(row["occurred_at"]),
    actor: "Identidade registrada na trilha de auditoria",
  }));
}

async function searchFiscal(query: string, municipalityId: string): Promise<SearchResultItem[]> {
  const scopedMunicipalityId = requireMunicipalityId(municipalityId);
  const normalized = query.trim();
  if (normalized.length < 2 || normalized.length > 500) {
    throw new FiscalDataError("invalid_search_length");
  }
  const { data, error } = await getSupabaseClient().functions.invoke("ia-fiscal-search", {
    body: { municipality_id: scopedMunicipalityId, query: normalized, limit: 30, offset: 0 },
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
    const maskedTaxId = nullableString(row["masked_tax_id"]);
    const divergenceType = nullableString(row["divergence_type"]);
    const status = nullableString(row["status"]);
    return {
      resultType: intent,
      title,
      subtitle:
        maskedTaxId ??
        (divergenceType ? divergenceTypeLabel(divergenceType) : null) ??
        (status ? fiscalStatusLabel(status) : null) ??
        "Resultado fiscal conferido",
      route: taxpayerId ? `/contribuintes/${taxpayerId}` : caseId ? "/fiscalizacoes" : null,
      metadata: row,
    };
  });
}

export const supabaseFiscalService: FiscalService = {
  async getDashboardSummary(municipalityId): Promise<DashboardSummary> {
    const report = await getOperationalReport(municipalityId);
    return {
      environmentLabel: "Operação assistida — envios externos bloqueados",
      greeting: "Painel do Fiscal",
      operationalSummary:
        "Prioridade operacional não representa risco jurídico, lançamento ou conclusão fiscal.",
      referenceDate: new Date().toISOString(),
      metrics: dashboardMetrics(report),
    };
  },
  listFiscalCases: listFiscalCasesLegacy,
  listChatQueue,
  async listNotificationCandidates(municipalityId): Promise<NotificationCandidate[]> {
    const [recipients, summaries] = await Promise.all([
      listNotificationRecipients(municipalityId),
      listTaxpayerSummaries(municipalityId),
    ]);
    const summariesByTaxpayer = new Map(summaries.map((item) => [item.taxpayerId, item]));

    return recipients.slice(0, 20).map((item) => {
      const taxpayer = summariesByTaxpayer.get(item.taxpayerId);
      return {
        id: item.candidateId,
        taxpayerName: taxpayer?.legalName ?? "Cadastro do contribuinte não disponível",
        cnpj: taxpayer?.taxId || taxpayer?.municipalRegistration || "Inscrição não disponível",
        channel: "e-mail",
        contact: item.maskedEmail,
        contactValidated: item.readyPendingExternalAuthorization,
        templateName: notificationPurposeLabel(item.proposedFor),
        status: item.safeForDelivery ? "preparado" : "bloqueado",
        blockedReason: blockReasonSummary(item.deliveryBlockReason),
        draftMessage: "Conteúdo disponível apenas após seleção de template governado.",
      };
    });
  },
  listProcessingHealth,
  async listProductionBlockers(municipalityId): Promise<ProductionBlocker[]> {
    const report = await getOperationalReport(municipalityId);
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
        description: "Permanece deliberadamente bloqueado durante a operação assistida.",
        done: false,
        owner: "Chefia fiscal + Procuradoria",
      },
    ];
  },
  listAuditEvents,
  async listTaxpayers(municipalityId): Promise<Taxpayer[]> {
    const rows = await listTaxpayerSummaries(municipalityId);
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
  createTaxpayer,
  updateTaxpayer,
  archiveTaxpayer,
  listDebtPeriods,
  listDivergences,
  listFiscalCaseRows,
  listNotificationRecipients,
  listKnowledgeArticles,
  getKnowledgeOperationsSnapshot,
  listKnowledgeReviewerCapabilities,
  grantKnowledgeReviewerCapability,
  revokeKnowledgeReviewerCapability,
  searchLegalKnowledge,
  submitKnowledgeCandidate,
  getKnowledgeCandidateEvidence,
  reviewKnowledgeCandidate,
  getKnowledgeArticleEvidence,
  getLegalSourceChangeEvidence,
  reviewLegalSourceChange,
  publishLegalSourceVersion,
  reviewKnowledgeArticle,
  publishKnowledgeArticle,
  listPortalCases,
  listCaseMessages,
  getOperationalReport,
  getAssistedOperationSafetyStatus,
  listMunicipalityUsers,
  addExistingMunicipalityUser,
  updateMunicipalityMembership,
  async claimCaseQuestion(questionId, municipalityId, membershipId, handlingMode): Promise<string> {
    if (!questionId) throw new FiscalDataError("invalid_question_id");
    if (!municipalityId) throw new FiscalDataError("invalid_municipality_id");
    if (!membershipId) throw new FiscalDataError("invalid_membership_id");
    if (handlingMode !== "human" && handlingMode !== "ai_assist") {
      throw new FiscalDataError("invalid_handling_mode");
    }
    const { data, error } = await getSupabaseClient().rpc("ia_claim_case_question", {
      p_question_id: questionId,
      p_expected_municipality_id: municipalityId,
      p_expected_membership_id: membershipId,
      p_handling_mode: handlingMode,
    });
    throwIfError(error);
    const returnedMembershipId = stringValue(data);
    if (!returnedMembershipId) throw new FiscalDataError("claim_membership_missing");
    return returnedMembershipId;
  },
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
