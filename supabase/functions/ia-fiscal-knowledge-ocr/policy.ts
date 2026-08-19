export const OCR_CONTRACT_VERSION = "ia-fiscal-knowledge-ocr/v1";
export const OCR_MANIFEST_VERSION = "ia-fiscal-knowledge-ocr-manifest/v1";
export const OCR_PAGE_VERSION = "ia-fiscal-knowledge-ocr-page/v1";
export const OCR_BUCKET = "legal-ocr-artifacts";
export const SOURCE_BUCKET = "legal-source-artifacts";
export const SOURCE_URL_TTL_SECONDS = 180;
export const MAX_PART_BYTES = 5 * 1024 * 1024;
export const MAX_MANIFEST_BYTES = MAX_PART_BYTES;
export const MAX_PAGES = 120;
export const MAX_PAGE_CHARACTERS = 1_000_000;
// V1 is intentionally bounded below the Edge memory ceiling. Raising this
// requires a production-size runtime smoke and a new attested contract.
export const MAX_TOTAL_CHARACTERS = 8_000_000;
export const CONTENT_PAGE_SEPARATOR = "\n\f\n";

export const GITHUB_OIDC_POLICY = Object.freeze({
  issuer: "https://token.actions.githubusercontent.com",
  jwksUrl: "https://token.actions.githubusercontent.com/.well-known/jwks",
  audience: "ia-fiscal-knowledge-ocr-qvgenxcrdrqyiyozxtdt",
  repository: "AlmoreContabilidade/Ia-fiscal",
  repositoryOwner: "AlmoreContabilidade",
  repositoryOwnerId: "296187202",
  repositoryId: "1320619695",
  ref: "refs/heads/main",
  environment: "knowledge-ocr",
  workflowRef:
    "AlmoreContabilidade/Ia-fiscal/.github/workflows/knowledge-ocr.yml@refs/heads/main",
  subject:
    "repo:AlmoreContabilidade@296187202/Ia-fiscal@1320619695:environment:knowledge-ocr",
  allowedEvents: new Set(["schedule", "workflow_dispatch"]),
});

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const SHA1_PATTERN = /^[a-f0-9]{40}$/;
const SAFE_CODE_PATTERN = /^[a-z0-9][a-z0-9_.:-]{1,119}$/;

export type JsonRecord = Record<string, unknown>;
export type OcrAction = "claim" | "heartbeat" | "upload-part" | "complete" | "fail";
export type DbOcrAction = "claim" | "heartbeat" | "upload_part" | "complete" | "fail";

export type GithubOidcIdentity = {
  audience: string;
  repository: string;
  repositoryOwner: string;
  repositoryOwnerId: string;
  repositoryId: string;
  ref: string;
  environment: string;
  workflowRef: string;
  workflowSha: string;
  subject: string;
  jti: string;
  runId: string;
  runAttempt: number;
  expiresAt: number;
};

export type OidcContext = {
  action: DbOcrAction;
  audience: string;
  repository: string;
  repository_owner: string;
  repository_owner_id: string;
  repository_id: string;
  runner_environment: "github-hosted";
  ref: string;
  environment: string;
  workflow_ref: string;
  workflow_sha: string;
  subject_sha256: string;
  jti_sha256: string;
  run_id: string;
  run_attempt: number;
  expires_at: string;
};

export type UploadPartRequest = {
  jobId: string;
  leaseToken: string;
  partKind: "page" | "manifest";
  partNumber: number;
  sha256: string;
  contentType: "application/json";
  bytes: Uint8Array;
};

export type CompletionPage = {
  page_number: number;
  content_text: string;
  text_sha256: string;
  confidence_milli: number | null;
  confidence_samples: number;
  character_count: number;
  utf8_bytes: number;
  word_count: number;
  storage_path: string;
  artifact_sha256: string;
  artifact_byte_size: number;
};

export type CompletionPageReference = Pick<
  CompletionPage,
  "page_number" | "storage_path" | "artifact_sha256" | "artifact_byte_size"
>;

export class OcrPolicyError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
  ) {
    super(code);
    this.name = "OcrPolicyError";
  }
}

export function isRecord(value: unknown): value is JsonRecord {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export function isSha256(value: unknown): value is string {
  return typeof value === "string" && SHA256_PATTERN.test(value);
}

export async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  const digestInput = new Uint8Array(bytes.byteLength);
  digestInput.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", digestInput.buffer);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function requiredString(record: JsonRecord, key: string, maxLength: number): string {
  const value = record[key];
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    throw new OcrPolicyError("ocr_request_invalid", 400);
  }
  return value;
}

function requiredInteger(
  record: JsonRecord,
  key: string,
  minimum: number,
  maximum: number,
): number {
  const value = record[key];
  if (!Number.isSafeInteger(value) || (value as number) < minimum || (value as number) > maximum) {
    throw new OcrPolicyError("ocr_request_invalid", 400);
  }
  return value as number;
}

export function parseEnvelope(value: unknown): { action: OcrAction; body: JsonRecord } {
  if (!isRecord(value) || value.contract_version !== OCR_CONTRACT_VERSION) {
    throw new OcrPolicyError("ocr_contract_version_invalid", 400);
  }
  const action = value.action;
  if (
    action !== "claim" &&
    action !== "heartbeat" &&
    action !== "upload-part" &&
    action !== "complete" &&
    action !== "fail"
  ) {
    throw new OcrPolicyError("ocr_action_invalid", 400);
  }
  return { action, body: value };
}

export function dbAction(action: OcrAction): DbOcrAction {
  return action === "upload-part" ? "upload_part" : action;
}

export function parseLease(record: JsonRecord): { jobId: string; leaseToken: string } {
  const jobId = requiredString(record, "job_id", 64);
  const leaseToken = requiredString(record, "lease_token", 128);
  if (!isUuid(jobId) || !SHA256_PATTERN.test(leaseToken)) {
    throw new OcrPolicyError("ocr_lease_invalid", 400);
  }
  return { jobId, leaseToken };
}

function decodeBase64(value: string, maximumBytes: number): Uint8Array {
  if (
    value.length === 0 ||
    value.length > Math.ceil(maximumBytes / 3) * 4 + 4 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)
  ) {
    throw new OcrPolicyError("ocr_part_encoding_invalid", 400);
  }
  let binary: string;
  try {
    binary = atob(value);
  } catch {
    throw new OcrPolicyError("ocr_part_encoding_invalid", 400);
  }
  if (binary.length > maximumBytes) {
    throw new OcrPolicyError("ocr_part_too_large", 413);
  }
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export async function parseUploadPart(record: JsonRecord): Promise<UploadPartRequest> {
  const { jobId, leaseToken } = parseLease(record);
  const partKind = requiredString(record, "part_kind", 16);
  if (partKind !== "page" && partKind !== "manifest") {
    throw new OcrPolicyError("ocr_part_kind_invalid", 400);
  }
  const partNumber = requiredInteger(record, "part_number", 1, MAX_PAGES + 1);
  const sha256 = requiredString(record, "sha256", 64);
  const contentType = requiredString(record, "content_type", 64);
  const bodyBase64 = requiredString(
    record,
    "body_base64",
    Math.ceil(MAX_PART_BYTES / 3) * 4 + 4,
  );
  if (!isSha256(sha256) || contentType !== "application/json") {
    throw new OcrPolicyError("ocr_part_metadata_invalid", 400);
  }
  const bytes = decodeBase64(bodyBase64, MAX_PART_BYTES);
  if ((await sha256Hex(bytes)) !== sha256) {
    throw new OcrPolicyError("ocr_part_hash_mismatch", 422);
  }
  let decoded: unknown;
  try {
    decoded = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new OcrPolicyError("ocr_part_json_invalid", 422);
  }
  if (!isRecord(decoded)) throw new OcrPolicyError("ocr_part_json_invalid", 422);
  if (
    (partKind === "page" &&
      (decoded.schema_version !== OCR_PAGE_VERSION || decoded.page_number !== partNumber)) ||
    (partKind === "manifest" && decoded.schema_version !== OCR_MANIFEST_VERSION)
  ) {
    throw new OcrPolicyError("ocr_part_schema_invalid", 422);
  }
  return {
    jobId,
    leaseToken,
    partKind,
    partNumber,
    sha256,
    contentType: "application/json",
    bytes,
  };
}

export function buildPartStoragePath(
  jobId: string,
  attempt: number,
  partKind: "page" | "manifest",
  partNumber: number,
  sha256: string,
): string {
  if (!isUuid(jobId) || !Number.isInteger(attempt) || attempt < 1 || !isSha256(sha256)) {
    throw new OcrPolicyError("ocr_storage_identity_invalid", 500);
  }
  if (partKind === "manifest") {
    return `jobs/${jobId}/attempt-${attempt}/manifest-${sha256}.json`;
  }
  return `jobs/${jobId}/attempt-${attempt}/page-${String(partNumber).padStart(4, "0")}-${sha256}.json`;
}

export function parseCompletionPageReferences(
  value: unknown,
  jobId: string,
  attempt: number,
): CompletionPageReference[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_PAGES) {
    throw new OcrPolicyError("ocr_pages_invalid", 400);
  }
  return value.map((entry, index) => {
    if (!isRecord(entry) || !isRecord(entry.artifact)) {
      throw new OcrPolicyError("ocr_page_invalid", 400);
    }
    const pageNumber = requiredInteger(entry, "page_number", 1, MAX_PAGES);
    if (pageNumber !== index + 1) throw new OcrPolicyError("ocr_page_sequence_invalid", 422);
    // Completion deliberately contains references only. Text and confidence
    // are derived from the immutable page artifact inside the trusted Edge.
    if (Object.keys(entry).some((key) => !["page_number", "artifact"].includes(key))) {
      throw new OcrPolicyError("ocr_page_reference_invalid", 422);
    }
    if (
      Object.keys(entry.artifact).length !== 3 ||
      Object.keys(entry.artifact).some(
        (key) => !["storage_ref", "sha256", "byte_size"].includes(key),
      )
    ) {
      throw new OcrPolicyError("ocr_page_reference_invalid", 422);
    }
    const storagePath = requiredString(entry.artifact, "storage_ref", 1_024);
    const artifactSha256 = requiredString(entry.artifact, "sha256", 64);
    const artifactBytes = requiredInteger(entry.artifact, "byte_size", 2, MAX_PART_BYTES);
    const expectedPath = buildPartStoragePath(
      jobId,
      attempt,
      "page",
      pageNumber,
      artifactSha256,
    );
    if (!isSha256(artifactSha256) || storagePath !== expectedPath) {
      throw new OcrPolicyError("ocr_page_artifact_invalid", 422);
    }
    return {
      page_number: pageNumber,
      storage_path: storagePath,
      artifact_sha256: artifactSha256,
      artifact_byte_size: artifactBytes,
    };
  });
}

export async function assertCompletionTextHashes(pages: CompletionPage[]): Promise<string> {
  let totalCharacters = 0;
  for (const page of pages) {
    totalCharacters += page.character_count;
    if (totalCharacters + (pages.length - 1) * CONTENT_PAGE_SEPARATOR.length > MAX_TOTAL_CHARACTERS) {
      throw new OcrPolicyError("ocr_total_characters_exceeded", 413);
    }
    if ((await sha256Hex(page.content_text)) !== page.text_sha256) {
      throw new OcrPolicyError("ocr_page_text_hash_mismatch", 422);
    }
  }
  const content = pages.map((page) => page.content_text).join(CONTENT_PAGE_SEPARATOR);
  return sha256Hex(content);
}

export function unicodeCharacterCount(value: string): number {
  return Array.from(value).length;
}

export function pythonRound(value: number): number {
  const floor = Math.floor(value);
  const remainder = value - floor;
  if (remainder < 0.5) return floor;
  if (remainder > 0.5) return floor + 1;
  return floor % 2 === 0 ? floor : floor + 1;
}

export function assertGithubOidcClaims(
  payload: JsonRecord,
  protectedHeader: JsonRecord,
  nowSeconds = Math.floor(Date.now() / 1_000),
): GithubOidcIdentity {
  const aud = payload.aud;
  const exp = payload.exp;
  const iat = payload.iat;
  const nbf = payload.nbf;
  const runAttempt = Number(payload.run_attempt);
  if (
    protectedHeader.alg !== "RS256" ||
    (protectedHeader.typ !== undefined && protectedHeader.typ !== "JWT") ||
    aud !== GITHUB_OIDC_POLICY.audience ||
    payload.iss !== GITHUB_OIDC_POLICY.issuer ||
    payload.repository !== GITHUB_OIDC_POLICY.repository ||
    payload.repository_owner !== GITHUB_OIDC_POLICY.repositoryOwner ||
    payload.repository_owner_id !== GITHUB_OIDC_POLICY.repositoryOwnerId ||
    payload.repository_id !== GITHUB_OIDC_POLICY.repositoryId ||
    payload.ref !== GITHUB_OIDC_POLICY.ref ||
    payload.ref_type !== "branch" ||
    payload.environment !== GITHUB_OIDC_POLICY.environment ||
    payload.workflow_ref !== GITHUB_OIDC_POLICY.workflowRef ||
    payload.sub !== GITHUB_OIDC_POLICY.subject ||
    payload.repository_visibility !== "private" ||
    payload.runner_environment !== "github-hosted" ||
    typeof payload.workflow_sha !== "string" ||
    !SHA1_PATTERN.test(payload.workflow_sha) ||
    typeof payload.jti !== "string" ||
    payload.jti.length < 8 ||
    payload.jti.length > 256 ||
    typeof payload.run_id !== "string" ||
    !/^[1-9][0-9]{0,19}$/.test(payload.run_id) ||
    !Number.isSafeInteger(runAttempt) ||
    runAttempt < 1 ||
    runAttempt > 1_000 ||
    typeof payload.event_name !== "string" ||
    !GITHUB_OIDC_POLICY.allowedEvents.has(payload.event_name) ||
    typeof exp !== "number" ||
    typeof iat !== "number" ||
    typeof nbf !== "number" ||
    exp <= nowSeconds - 30 ||
    exp > nowSeconds + 600 ||
    iat > nowSeconds + 30 ||
    exp - iat > 600 ||
    nbf > nowSeconds + 30
  ) {
    throw new OcrPolicyError("github_oidc_claims_rejected", 403);
  }
  return {
    audience: GITHUB_OIDC_POLICY.audience,
    repository: GITHUB_OIDC_POLICY.repository,
    repositoryOwner: GITHUB_OIDC_POLICY.repositoryOwner,
    repositoryOwnerId: GITHUB_OIDC_POLICY.repositoryOwnerId,
    repositoryId: GITHUB_OIDC_POLICY.repositoryId,
    ref: GITHUB_OIDC_POLICY.ref,
    environment: GITHUB_OIDC_POLICY.environment,
    workflowRef: GITHUB_OIDC_POLICY.workflowRef,
    workflowSha: payload.workflow_sha,
    subject: GITHUB_OIDC_POLICY.subject,
    jti: payload.jti,
    runId: payload.run_id,
    runAttempt,
    expiresAt: exp,
  };
}

export async function buildOidcContext(
  identity: GithubOidcIdentity,
  action: OcrAction,
): Promise<OidcContext> {
  return {
    action: dbAction(action),
    audience: identity.audience,
    repository: identity.repository,
    repository_owner: identity.repositoryOwner,
    repository_owner_id: identity.repositoryOwnerId,
    repository_id: identity.repositoryId,
    runner_environment: "github-hosted",
    ref: identity.ref,
    environment: identity.environment,
    workflow_ref: identity.workflowRef,
    workflow_sha: identity.workflowSha,
    subject_sha256: await sha256Hex(identity.subject),
    jti_sha256: await sha256Hex(identity.jti),
    run_id: identity.runId,
    run_attempt: identity.runAttempt,
    expires_at: new Date(identity.expiresAt * 1_000).toISOString(),
  };
}

export function parseFailure(record: JsonRecord): {
  jobId: string;
  leaseToken: string;
  errorCode: string;
  errorDetail: string | null;
  retryable: boolean;
} {
  const { jobId, leaseToken } = parseLease(record);
  const errorCode = requiredString(record, "error_code", 120).toLowerCase();
  if (!SAFE_CODE_PATTERN.test(errorCode) || typeof record.retryable !== "boolean") {
    throw new OcrPolicyError("ocr_failure_invalid", 400);
  }
  const detail = record.error_detail;
  if (detail !== undefined && detail !== null && (typeof detail !== "string" || detail.length > 1_000)) {
    throw new OcrPolicyError("ocr_failure_invalid", 400);
  }
  return {
    jobId,
    leaseToken,
    errorCode,
    errorDetail: typeof detail === "string" && detail.trim() ? detail.trim() : null,
    retryable: record.retryable,
  };
}
