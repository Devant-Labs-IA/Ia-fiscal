export type KnowledgeReviewDecision = "approved" | "rejected" | "revision_requested";
export type KnowledgeCandidateReviewDecision = "approved" | "rejected";
export type LegalSourceReviewDecision = "approved" | "rejected" | "changes_requested";

export const KNOWLEDGE_EVIDENCE_CONTENT_PAGE_SIZE = 20_000;
export const KNOWLEDGE_EVIDENCE_SECTION_PAGE_SIZE = 25;
export const KNOWLEDGE_EVIDENCE_CHANGE_ITEM_PAGE_SIZE = 25;
export const KNOWLEDGE_MIN_ANSWER_CONFIDENCE = 0.35;

export interface KnowledgeSourceEvidencePageRequest {
  contentOffset: number;
  sectionOffset: number;
  changeItemOffset: number;
}

export interface LegalSourceReviewMetadata {
  publicationDate: string | null;
  validFrom: string | null;
  validUntil: string | null;
}

export interface KnowledgeCitationEvidence {
  citationId: string;
  citationLabel: string;
  quotedExcerpt: string;
  sourceId: string;
  sourceTitle: string;
  officialIdentifier: string | null;
  officialUrl: string | null;
  sourceVersionId: string;
  sourceVersionNumber: number;
  sourceVersionStatus: string;
  sourceSha256: string;
  publicationDate: string | null;
  validFrom: string | null;
  validUntil: string | null;
  sectionId: string;
  sectionKey: string;
  sectionHeading: string | null;
  sectionContentSha256: string;
  isValid: boolean;
  blockers: string[];
}

export interface KnowledgeArticleEvidence {
  verified: boolean;
  municipalityId: string;
  articleId: string;
  revisionId: string;
  contentSha256: string;
  canonicalQuestion: string;
  answerBody: string;
  answerLength: number;
  citationCount: number;
  citations: KnowledgeCitationEvidence[];
  evidenceComplete: boolean;
  blockers: string[];
}

export interface KnowledgeSourceChangeItemEvidence {
  ordinal: number;
  itemKind: string;
  itemPath: string;
  beforeSha256: string | null;
  afterSha256: string | null;
  beforeExcerpt: string | null;
  afterExcerpt: string | null;
  summary: string;
}

export interface KnowledgeSourceSectionEvidence {
  sectionId: string;
  sectionKey: string;
  heading: string | null;
  ordinal: number;
  contentPreview: string;
  contentTotalChars: number;
  contentSha256: string;
  chunkCount: number;
}

export interface KnowledgeSourceChangeEvidence {
  verified: boolean;
  municipalityId: string;
  changeSetId: string;
  changeType: string;
  status: string;
  sourceId: string;
  sourceTitle: string;
  officialIdentifier: string | null;
  officialUrl: string | null;
  requestedUrl: string | null;
  capturedUrl: string | null;
  observedAt: string | null;
  rawContentSha256: string | null;
  fromSha256: string | null;
  toSha256: string;
  diffSha256: string;
  artifactId: string | null;
  artifactMimeType: string | null;
  artifactByteSize: number | null;
  candidateVersionId: string;
  candidateVersionNumber: number;
  candidateVersionStatus: string;
  contentSha256: string;
  contentText: string;
  contentOffset: number;
  contentLimit: number;
  contentTotalChars: number;
  contentHasMore: boolean;
  diffSummary: string;
  publicationDate: string | null;
  validFrom: string | null;
  validUntil: string | null;
  sectionOffset: number;
  sectionLimit: number;
  sectionTotal: number;
  sectionHasMore: boolean;
  sections: KnowledgeSourceSectionEvidence[];
  changeItems: KnowledgeSourceChangeItemEvidence[];
  changeItemOffset: number;
  changeItemLimit: number;
  changeItemTotal: number;
  changeItemsHasMore: boolean;
  changeItemsFullSha256: string;
  evidenceComplete: boolean;
  blockers: string[];
}

export interface KnowledgeOperationsCapabilities {
  canView: boolean;
  canSearch: boolean;
  canSubmitCandidates: boolean;
  canReviewCandidates: boolean;
  canReviewSourceVersions: boolean;
  canReviewArticles: boolean;
  canPublishSourceVersions: boolean;
  canPublishArticles: boolean;
}

export interface KnowledgeOperationsSummary {
  officialSources: number;
  totalSourceVersions: number;
  publishedSourceVersions: number;
  pendingSourceReviews: number;
  pendingSourceExtractions: number;
  pendingSourcePublications: number;
  pendingArticleReviews: number;
  pendingCandidates: number;
  pendingEmbeddings: number;
  eligibleSections: number;
  indexedSections: number;
  indexedChunks: number;
  lastIndexedAt: string | null;
  openChanges: number;
  failedFetches24h: number;
}

export interface KnowledgeScheduleStatus {
  enabled: boolean;
  cadenceLabel: string;
  timeZone: string | null;
  nextRunAt: string | null;
  lastRunAt: string | null;
  lastRunStatus: string;
  runtimeVerified: boolean;
  blockers: string[];
}

export interface KnowledgeReviewerStatus {
  verified: boolean;
  configured: boolean;
  activeCount: number;
  currentUserCanReview: boolean;
  blockers: string[];
}

export interface KnowledgeReviewerGrant {
  grantId: string;
  membershipId: string;
  role: string;
  status: string;
  validFrom: string;
  validUntil: string | null;
  isCurrent: boolean;
}

export interface KnowledgeReviewerEligibleStaff {
  membershipId: string;
  role: string;
  alreadyConfigured: boolean;
}

export interface KnowledgeReviewerDirectory {
  verified: boolean;
  municipalityId: string;
  activeGrants: KnowledgeReviewerGrant[];
  eligibleStaff: KnowledgeReviewerEligibleStaff[];
  piiExposed: false;
  checkedAt: string;
}

export interface KnowledgeIndexStatus {
  status: "healthy" | "attention" | "blocked" | "unknown";
  indexedSections: number;
  eligibleSections: number;
  canonicalRetrieval: "lexical_portuguese";
  lexicalLanguage: "pt-BR";
  lexicalFullContent: true;
  semanticStatus: "unsupported_language";
  semanticUsableChunks: 0;
  semanticHistoricalChunks: number;
  embeddingModel: string | null;
  lastIndexedAt: string | null;
  blockers: string[];
}

export interface KnowledgeOcrStatus {
  contractVersion: "ia-fiscal-knowledge-ocr/v1";
  policyVersion: "ia-fiscal-knowledge-ocr-policy/v1";
  runtimeVerified: boolean;
  hasAttention: boolean;
  state: "blocked" | "processing" | "queued" | "attention_required" | "ready";
  jobs: {
    queued: number;
    processing: number;
    completed: number;
    deadLetter: number;
    blockedPageLimit: number;
  };
  lastEventAt: string | null;
  limits: {
    maxPages: number;
    maxPageCharacters: number;
    maxTotalCharacters: number;
    abovePageLimit: "manual_review_required";
  };
  candidateStatus: "under_review";
  autoPublish: false;
  blockers: string[];
}

export type KnowledgeCoverageUpstreamStatus =
  "unverified" | "available" | "blocked_403" | "blocked_502" | "blocked_503";

export interface KnowledgeCatalogCoverage {
  coverageKey: string;
  title: string;
  expected: number | null;
  discovered: number;
  identityVerified: number;
  extractionQueued: number;
  reviewable: number;
  published: number;
  corpusIntegral: boolean;
  upstreamStatus: KnowledgeCoverageUpstreamStatus;
  blocker: string | null;
}

export interface KnowledgeOfficialSource {
  sourceId: string;
  title: string;
  officialIdentifier: string | null;
  sourceType: string;
  taxScope: string;
  status: string;
  officialUrl: string | null;
  trustTier: string;
  endpointStatus: string;
  lastFetchStatus: string;
  lastCheckedAt: string | null;
  lastChangeDetectedAt: string | null;
  lastErrorCode: string | null;
  lastErrorDetail: string | null;
  latestVersionId: string | null;
  latestVersionNumber: number | null;
  latestVersionStatus: string | null;
  latestValidFrom: string | null;
  latestValidUntil: string | null;
  blockers: string[];
  canReview: boolean;
  canPublish: boolean;
}

export interface KnowledgeSourceChange {
  changeSetId: string;
  sourceId: string;
  sourceTitle: string;
  changeType: string;
  status: string;
  detectedAt: string | null;
  fromSha256: string | null;
  toSha256: string;
  candidateVersionId: string | null;
  candidateVersionNumber: number | null;
  candidateVersionStatus: string | null;
  candidateValidFrom: string | null;
  candidateValidUntil: string | null;
  officialUrl: string | null;
  candidateContentPreview: string | null;
  sectionCount: number | null;
  diffSummary: string | null;
  blockers: string[];
  canReview: boolean;
  canPublish: boolean;
}

export type KnowledgeReviewQueueKind =
  "source_version" | "knowledge_article" | "learning_candidate";

export interface KnowledgeReviewQueueItem {
  queueKind: KnowledgeReviewQueueKind;
  itemId: string;
  title: string;
  status: string;
  contentSha256: string | null;
  submittedAt: string | null;
  lastReviewedAt: string | null;
  blockers: string[];
  canReview: boolean;
  canPublish: boolean;
  sourceId: string | null;
  changeSetId: string | null;
  candidateVersionId: string | null;
  candidateId: string | null;
  question: string | null;
  proposedAnswerPreview: string | null;
  articleId: string | null;
  revisionId: string | null;
  revisionNumber: number | null;
  answerPreview: string | null;
  citationCount: number | null;
  isTest: boolean | null;
  taxScope: string | null;
  divergenceScope: string | null;
  validFrom: string | null;
  validUntil: string | null;
  officialUrl: string | null;
  candidateContentPreview: string | null;
  sectionCount: number | null;
}

export interface KnowledgeHealthStatus {
  status: "healthy" | "attention" | "blocked" | "unknown";
  staleSources: number;
  failedSources: number;
  blockedSources: number;
  lastSuccessfulFetchAt: string | null;
  blockers: string[];
}

export interface KnowledgeSearchCitation {
  citationId: string;
  sourceTitle: string;
  officialIdentifier: string | null;
  officialUrl: string | null;
  sourceVersionId: string;
  sectionId: string;
  sectionKey: string;
  sectionHeading: string | null;
  citationLabel: string;
  quotedExcerpt: string;
  publicationDate: string | null;
  validFrom: string | null;
  validUntil: string | null;
  relevance: number;
  isValid: boolean;
  blockers: string[];
}

export interface KnowledgeSearchResult {
  verified: boolean;
  correlationId: string;
  municipalityId: string;
  query: string;
  answered: boolean;
  answer: string | null;
  confidence: number | null;
  retrievalMode: "lexical_portuguese";
  lexicalLanguage: "pt-BR";
  semanticStatus: "unsupported_language";
  searchedAt: string;
  citations: KnowledgeSearchCitation[];
  blockers: string[];
}

export interface KnowledgeCandidateInput {
  question: string;
  proposedAnswer: string;
  citationSectionIds: string[];
  confirmation: "ENVIAR PARA REVISÃO";
}

export interface KnowledgeCandidateEvidence {
  verified: boolean;
  checkedAt: string;
  municipalityId: string;
  candidateId: string;
  question: string;
  proposedAnswer: string;
  contentSha256: string;
  status: string;
  submittedAt: string;
  reviewedAt: string | null;
  citations: KnowledgeSearchCitation[];
  evidenceComplete: boolean;
  blockers: string[];
  canReview: boolean;
  canPublish: false;
}

export interface KnowledgeOperationsSnapshot {
  verified: boolean;
  municipalityId: string;
  municipalityName: string;
  municipalitySlug: string;
  checkedAt: string;
  capabilities: KnowledgeOperationsCapabilities;
  summary: KnowledgeOperationsSummary;
  sources: KnowledgeOfficialSource[];
  changes: KnowledgeSourceChange[];
  reviews: KnowledgeReviewQueueItem[];
  health: KnowledgeHealthStatus;
  schedule: KnowledgeScheduleStatus;
  index: KnowledgeIndexStatus;
  ocr: KnowledgeOcrStatus;
  reviewer: KnowledgeReviewerStatus;
  coverage: KnowledgeCatalogCoverage[];
  coverageLabel: string;
  corpusIntegral: boolean;
}
