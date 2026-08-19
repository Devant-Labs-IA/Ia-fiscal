import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { authenticateGithubOidc } from "./oidc.ts";
import {
  assertCompletionTextHashes,
  buildOidcContext,
  buildPartStoragePath,
  isRecord,
  isSha256,
  isUuid,
  MAX_MANIFEST_BYTES,
  MAX_PAGE_CHARACTERS,
  MAX_PAGES,
  MAX_PART_BYTES,
  MAX_TOTAL_CHARACTERS,
  OCR_BUCKET,
  OCR_CONTRACT_VERSION,
  OCR_MANIFEST_VERSION,
  OCR_PAGE_VERSION,
  OcrPolicyError,
  parseCompletionPageReferences,
  parseEnvelope,
  parseFailure,
  parseLease,
  parseUploadPart,
  pythonRound,
  sha256Hex,
  SOURCE_BUCKET,
  SOURCE_URL_TTL_SECONDS,
  type CompletionPage,
  type CompletionPageReference,
  type GithubOidcIdentity,
  type JsonRecord,
  type OcrAction,
  type OidcContext,
  unicodeCharacterCount,
} from "./policy.ts";

const SERVICE_NAME = "ia-fiscal-knowledge-ocr";
const CLAIM_RPC = "ia_fiscal_claim_knowledge_ocr_job";
const HEARTBEAT_RPC = "ia_fiscal_heartbeat_knowledge_ocr_job";
const FINALIZE_RPC = "ia_fiscal_finalize_knowledge_ocr_job";
const FAIL_RPC = "ia_fiscal_fail_knowledge_ocr_job";
const MAX_REQUEST_BYTES = 8 * 1024 * 1024;
const OCR_POLICY_VERSION = "ia-fiscal-knowledge-ocr-policy/v1";
const TOOLCHAIN_LOCK_SHA256 =
  "6bb5c3a93dad84e38ea05cedb47e1aeee13c8a22899f0cb9f693e114e5e5cd60";
const MIN_PAGE_COVERAGE_BPS = 9_000;
const MIN_MEAN_CONFIDENCE_MILLI = 550;

type QualityEvidence = {
  page_count: number;
  pages_with_text: number;
  page_coverage_bps: number;
  mean_confidence_milli: number;
  minimum_confidence_milli: number;
  confidence_page_samples: number;
  total_characters: number;
  total_utf8_bytes: number;
  total_words: number;
};

type ManifestEvidence = QualityEvidence & {
  policy_version: string;
  toolchain_lock_sha256: string;
  source_sha256: string;
  source_byte_size: number;
  normalized_sha256: string;
  normalized_byte_size: number;
  language: "por";
  dpi: 300;
  toolchain: JsonRecord;
};

function json(status: number, body: JsonRecord): Response {
  return new Response(JSON.stringify({ contract_version: OCR_CONTRACT_VERSION, ...body }), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
    },
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new OcrPolicyError("ocr_configuration_missing", 503);
  return value;
}

function serviceClient(): SupabaseClient {
  return createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "x-ia-ocr-contract": OCR_CONTRACT_VERSION } },
  });
}

async function readJson(request: Request): Promise<unknown> {
  if (request.headers.get("content-type")?.split(";", 1)[0]?.trim() !== "application/json") {
    throw new OcrPolicyError("ocr_content_type_invalid", 415);
  }
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_REQUEST_BYTES) {
    throw new OcrPolicyError("ocr_request_too_large", 413);
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_REQUEST_BYTES) {
    throw new OcrPolicyError("ocr_request_too_large", 413);
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new OcrPolicyError("ocr_json_invalid", 400);
  }
}

function rpcError(code: string): OcrPolicyError {
  return new OcrPolicyError(code, 409);
}

async function oidcContext(identity: GithubOidcIdentity, action: OcrAction): Promise<OidcContext> {
  return buildOidcContext(identity, action);
}

async function claim(
  supabase: SupabaseClient,
  identity: GithubOidcIdentity,
): Promise<Response> {
  const { data, error } = await supabase.rpc(CLAIM_RPC, {
    p_oidc_context: await oidcContext(identity, "claim"),
    p_lease_seconds: 600,
  });
  if (error || !isRecord(data) || data.contract_version !== OCR_CONTRACT_VERSION) {
    throw rpcError("ocr_claim_failed");
  }
  if (data.status === "empty") return json(200, { status: "empty" });
  if (
    data.status !== "claimed" ||
    !isRecord(data.job) ||
    !isRecord(data.source) ||
    !isRecord(data.limits)
  ) {
    throw rpcError("ocr_claim_contract_invalid");
  }
  const sourceBucket = data.source.storage_bucket;
  const sourcePath = data.source.storage_path;
  if (
    sourceBucket !== SOURCE_BUCKET ||
    typeof sourcePath !== "string" ||
    sourcePath.length < 1 ||
    sourcePath.length > 1_024 ||
    sourcePath.startsWith("/") ||
    sourcePath.split("/").includes("..") ||
    !isSha256(data.source.sha256) ||
    !Number.isSafeInteger(data.source.byte_size) ||
    (data.source.byte_size as number) < 1 ||
    data.source.mime_type !== "application/pdf"
  ) {
    throw rpcError("ocr_claim_contract_invalid");
  }
  if (
    data.limits.max_pages !== MAX_PAGES ||
    data.limits.max_page_characters !== MAX_PAGE_CHARACTERS ||
    data.limits.max_total_characters !== MAX_TOTAL_CHARACTERS ||
    data.limits.max_part_bytes !== MAX_PART_BYTES ||
    data.limits.source_url_ttl_seconds !== SOURCE_URL_TTL_SECONDS
  ) {
    throw rpcError("ocr_claim_limits_invalid");
  }
  const { data: signed, error: signedError } = await supabase.storage
    .from(SOURCE_BUCKET)
    .createSignedUrl(sourcePath, SOURCE_URL_TTL_SECONDS, { download: "official-source.pdf" });
  if (signedError || !signed?.signedUrl) {
    throw new OcrPolicyError("ocr_source_signing_failed", 503);
  }
  const publicSource = { ...data.source };
  delete publicSource.storage_bucket;
  delete publicSource.storage_path;
  publicSource.url = signed.signedUrl;
  return json(200, {
    status: "claimed",
    job: data.job,
    source: publicSource,
    limits: data.limits,
  });
}

async function heartbeat(
  supabase: SupabaseClient,
  identity: GithubOidcIdentity,
  body: JsonRecord,
): Promise<Response> {
  const lease = parseLease(body);
  const { data, error } = await supabase.rpc(HEARTBEAT_RPC, {
    p_job_id: lease.jobId,
    p_lease_token: lease.leaseToken,
    p_oidc_context: await oidcContext(identity, "heartbeat"),
    p_usage: "heartbeat",
    p_extend_seconds: 600,
  });
  if (error || !isRecord(data)) throw rpcError("ocr_heartbeat_failed");
  return json(200, data);
}

function duplicateStorageError(error: unknown): boolean {
  if (!isRecord(error)) return false;
  const status = String(error.statusCode ?? error.status ?? "");
  const message = typeof error.message === "string" ? error.message.toLowerCase() : "";
  return status === "409" || message.includes("already exists");
}

async function uploadPart(
  supabase: SupabaseClient,
  identity: GithubOidcIdentity,
  body: JsonRecord,
): Promise<Response> {
  const part = await parseUploadPart(body);
  const { data: lease, error: leaseError } = await supabase.rpc(HEARTBEAT_RPC, {
    p_job_id: part.jobId,
    p_lease_token: part.leaseToken,
    p_oidc_context: await oidcContext(identity, "upload-part"),
    p_usage: "upload_part",
    p_extend_seconds: 600,
  });
  if (
    leaseError ||
    !isRecord(lease) ||
    !Number.isSafeInteger(lease.attempt) ||
    (lease.attempt as number) < 1
  ) {
    throw rpcError("ocr_upload_lease_failed");
  }
  const attempt = lease.attempt as number;
  const storagePath = buildPartStoragePath(
    part.jobId,
    attempt,
    part.partKind,
    part.partNumber,
    part.sha256,
  );
  const decoded = JSON.parse(new TextDecoder().decode(part.bytes)) as JsonRecord;
  if (
    (part.partKind === "manifest" &&
      (decoded.job_id !== part.jobId || decoded.attempt !== attempt)) ||
    (part.partKind === "page" && decoded.page_number !== part.partNumber)
  ) {
    throw new OcrPolicyError("ocr_part_job_identity_mismatch", 422);
  }

  const blobBytes = new Uint8Array(part.bytes.byteLength);
  blobBytes.set(part.bytes);
  const { error } = await supabase.storage
    .from(OCR_BUCKET)
    .upload(storagePath, new Blob([blobBytes], { type: "application/json" }), {
      contentType: "application/json",
      cacheControl: "31536000",
      upsert: false,
      metadata: {
        sha256: part.sha256,
        job_id: part.jobId,
        attempt,
        part_kind: part.partKind,
        part_number: part.partNumber,
      },
    });
  const duplicate = duplicateStorageError(error);
  if (error && !duplicate) throw new OcrPolicyError("ocr_part_storage_failed", 503);
  if (duplicate) {
    await downloadImmutableJson(
      supabase,
      storagePath,
      part.sha256,
      part.bytes.byteLength,
      MAX_PART_BYTES,
    );
  }
  return json(duplicate ? 200 : 201, {
    status: duplicate ? "already_present" : "created",
    storage_ref: storagePath,
    sha256: part.sha256,
    byte_size: part.bytes.byteLength,
  });
}

async function downloadImmutableJson(
  supabase: SupabaseClient,
  storagePath: string,
  expectedSha256: string,
  expectedBytes: number,
  maximumBytes: number,
): Promise<{ bytes: Uint8Array; value: JsonRecord }> {
  if (
    !isSha256(expectedSha256) ||
    !Number.isSafeInteger(expectedBytes) ||
    expectedBytes < 2 ||
    expectedBytes > maximumBytes
  ) {
    throw new OcrPolicyError("ocr_artifact_reference_invalid", 422);
  }
  const { data, error } = await supabase.storage.from(OCR_BUCKET).download(storagePath);
  if (error || !data) throw new OcrPolicyError("ocr_artifact_read_failed", 503);
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.byteLength !== expectedBytes || bytes.byteLength > maximumBytes) {
    throw new OcrPolicyError("ocr_artifact_size_mismatch", 422);
  }
  if ((await sha256Hex(bytes)) !== expectedSha256) {
    throw new OcrPolicyError("ocr_artifact_hash_mismatch", 422);
  }
  try {
    const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (!isRecord(value)) throw new Error("not_object");
    return { bytes, value };
  } catch {
    throw new OcrPolicyError("ocr_artifact_json_invalid", 422);
  }
}

function manifestAttempt(storagePath: string, jobId: string, sha256: string): number {
  const match = storagePath.match(
    new RegExp(`^jobs/${jobId}/attempt-([1-9][0-9]*)/manifest-${sha256}\\.json$`),
  );
  if (!match) throw new OcrPolicyError("ocr_manifest_reference_invalid", 422);
  const attempt = Number(match[1]);
  if (!Number.isSafeInteger(attempt) || attempt < 1 || attempt > 10) {
    throw new OcrPolicyError("ocr_manifest_reference_invalid", 422);
  }
  return attempt;
}

function nonNegativeInteger(value: unknown, maximum: number): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= maximum;
}

function positiveInteger(value: unknown, maximum: number): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 1 && (value as number) <= maximum;
}

function wordCount(value: string): number {
  const trimmed = value.trim();
  return trimmed ? trimmed.split(/\s+/u).length : 0;
}

function exactKeys(value: JsonRecord, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length && actual.every((key, index) => key === wanted[index]);
}

function qualityEvidence(pages: CompletionPage[]): QualityEvidence {
  const pagesWithText = pages.filter((page) => page.character_count > 0).length;
  const confidences = pages
    .map((page) => page.confidence_milli)
    .filter((value): value is number => value !== null);
  const evidence: QualityEvidence = {
    page_count: pages.length,
    pages_with_text: pagesWithText,
    page_coverage_bps: pythonRound((pagesWithText * 10_000) / pages.length),
    mean_confidence_milli: confidences.length
      ? pythonRound(confidences.reduce((sum, value) => sum + value, 0) / confidences.length)
      : 0,
    minimum_confidence_milli: confidences.length ? Math.min(...confidences) : 0,
    confidence_page_samples: confidences.length,
    total_characters: pages.reduce((sum, page) => sum + page.character_count, 0),
    total_utf8_bytes: pages.reduce((sum, page) => sum + page.utf8_bytes, 0),
    total_words: pages.reduce((sum, page) => sum + page.word_count, 0),
  };
  if (
    evidence.page_coverage_bps < MIN_PAGE_COVERAGE_BPS ||
    evidence.mean_confidence_milli < MIN_MEAN_CONFIDENCE_MILLI ||
    evidence.confidence_page_samples < evidence.pages_with_text
  ) {
    throw new OcrPolicyError("ocr_quality_gate_failed", 422);
  }
  return evidence;
}

function assertToolchain(tools: JsonRecord, engineVersion: string): JsonRecord {
  const expectedPackages: Record<string, string> = {
    bubblewrap: "0.9.0-1ubuntu0.1",
    "poppler-utils": "24.02.0-1ubuntu9.9",
    qpdf: "11.9.0-1.1ubuntu0.1",
    "tesseract-ocr": "5.3.4-1build5",
    "tesseract-ocr-por": "1:4.1.0-2",
    unrtf: "0.21.10-clean-1",
  };
  const versions: Record<string, string> = {
    bubblewrap: "0.9.0",
    qpdf: "11.9.0",
    pdfinfo: "24.02.0",
    pdftoppm: "24.02.0",
    tesseract: "5.3.4",
    unrtf: "0.21.10",
    python: "3.12.11",
  };
  if (
    !exactKeys(tools, [
      "bubblewrap",
      "qpdf",
      "pdfinfo",
      "pdftoppm",
      "tesseract",
      "unrtf",
      "python",
      "packages",
      "tesseract_por",
    ])
  ) {
    throw new OcrPolicyError("ocr_toolchain_invalid", 422);
  }
  for (const [name, version] of Object.entries(versions)) {
    const binary = tools[name];
    if (
      !isRecord(binary) ||
      binary.canonical_version !== version ||
      typeof binary.version !== "string" ||
      binary.version.length < 1 ||
      binary.version.length > 160 ||
      !isSha256(binary.binary_sha256) ||
      !positiveInteger(binary.binary_bytes, 256 * 1024 * 1024)
    ) {
      throw new OcrPolicyError("ocr_toolchain_invalid", 422);
    }
  }
  const packages = tools.packages;
  if (engineVersion !== versions.tesseract || !isRecord(packages)) {
    throw new OcrPolicyError("ocr_toolchain_invalid", 422);
  }
  if (
    !exactKeys(packages, Object.keys(expectedPackages)) ||
    Object.entries(expectedPackages).some(([name, version]) => packages[name] !== version)
  ) {
    throw new OcrPolicyError("ocr_toolchain_invalid", 422);
  }
  if (
    !isRecord(tools.tesseract_por) ||
    !isSha256(tools.tesseract_por.traineddata_sha256) ||
    !positiveInteger(tools.tesseract_por.traineddata_bytes, 256 * 1024 * 1024)
  ) {
    throw new OcrPolicyError("ocr_toolchain_invalid", 422);
  }
  return tools;
}

function assertManifest(
  manifest: JsonRecord,
  jobId: string,
  attempt: number,
  engineVersion: string,
  contentSha256: string,
  pages: CompletionPage[],
  quality: QualityEvidence,
): ManifestEvidence {
  const metrics = manifest.metrics;
  if (
    !exactKeys(manifest, [
      "schema_version",
      "contract_version",
      "policy_version",
      "toolchain_lock_sha256",
      "job_id",
      "attempt",
      "source",
      "ocr",
      "auxiliary_sources",
      "metrics",
    ]) ||
    manifest.schema_version !== OCR_MANIFEST_VERSION ||
    manifest.contract_version !== OCR_CONTRACT_VERSION ||
    manifest.policy_version !== OCR_POLICY_VERSION ||
    manifest.toolchain_lock_sha256 !== TOOLCHAIN_LOCK_SHA256 ||
    manifest.job_id !== jobId ||
    manifest.attempt !== attempt ||
    !Array.isArray(manifest.auxiliary_sources) ||
    manifest.auxiliary_sources.length !== 0 ||
    !isRecord(manifest.ocr) ||
    !exactKeys(manifest.ocr, [
      "language",
      "dpi",
      "content_page_separator",
      "content_sha256",
      "tools",
      "pages",
    ]) ||
    manifest.ocr.language !== "por" ||
    manifest.ocr.dpi !== 300 ||
    manifest.ocr.content_page_separator !== "\n\f\n" ||
    manifest.ocr.content_sha256 !== contentSha256 ||
    !Array.isArray(manifest.ocr.pages) ||
    manifest.ocr.pages.length !== pages.length ||
    !isRecord(manifest.ocr.tools) ||
    !isRecord(manifest.source) ||
    !exactKeys(manifest.source, [
      "sha256",
      "bytes",
      "normalized_sha256",
      "normalized_bytes",
      "page_count",
    ]) ||
    !isSha256(manifest.source.sha256) ||
    !positiveInteger(manifest.source.bytes, 512 * 1024 * 1024) ||
    !isSha256(manifest.source.normalized_sha256) ||
    !positiveInteger(manifest.source.normalized_bytes, 512 * 1024 * 1024) ||
    manifest.source.page_count !== pages.length ||
    !isRecord(metrics) ||
    metrics.requested_pages !== pages.length ||
    metrics.processed_pages !== pages.length
  ) {
    throw new OcrPolicyError("ocr_manifest_contract_invalid", 422);
  }
  const toolchain = assertToolchain(manifest.ocr.tools, engineVersion);
  for (let index = 0; index < pages.length; index += 1) {
    const evidence = manifest.ocr.pages[index];
    const page = pages[index];
    if (
      !isRecord(evidence) ||
      !exactKeys(evidence, [
        "page_number",
        "text_sha256",
        "confidence_milli",
        "confidence_samples",
        "character_count",
        "utf8_bytes",
        "word_count",
        "has_text",
        "artifact_sha256",
      ]) ||
      evidence.page_number !== page.page_number ||
      evidence.text_sha256 !== page.text_sha256 ||
      evidence.artifact_sha256 !== page.artifact_sha256 ||
      evidence.confidence_milli !== page.confidence_milli ||
      evidence.confidence_samples !== page.confidence_samples ||
      evidence.character_count !== page.character_count ||
      evidence.utf8_bytes !== page.utf8_bytes ||
      evidence.word_count !== page.word_count ||
      evidence.has_text !== (page.character_count > 0)
    ) {
      throw new OcrPolicyError("ocr_manifest_page_mismatch", 422);
    }
  }
  const expectedMetrics: JsonRecord = {
    requested_pages: quality.page_count,
    processed_pages: quality.page_count,
    pages_with_text: quality.pages_with_text,
    page_coverage_bps: quality.page_coverage_bps,
    mean_confidence_milli: quality.mean_confidence_milli,
    minimum_confidence_milli: quality.minimum_confidence_milli,
    confidence_page_samples: quality.confidence_page_samples,
    total_characters: quality.total_characters,
    total_utf8_bytes: quality.total_utf8_bytes,
    total_words: quality.total_words,
  };
  if (
    !exactKeys(metrics, Object.keys(expectedMetrics)) ||
    Object.entries(expectedMetrics).some(([key, value]) => metrics[key] !== value)
  ) {
    throw new OcrPolicyError("ocr_manifest_metrics_mismatch", 422);
  }
  return {
    ...quality,
    policy_version: OCR_POLICY_VERSION,
    toolchain_lock_sha256: TOOLCHAIN_LOCK_SHA256,
    source_sha256: manifest.source.sha256,
    source_byte_size: manifest.source.bytes,
    normalized_sha256: manifest.source.normalized_sha256,
    normalized_byte_size: manifest.source.normalized_bytes,
    language: "por",
    dpi: 300,
    toolchain,
  };
}

async function verifyPageArtifacts(
  supabase: SupabaseClient,
  references: CompletionPageReference[],
): Promise<CompletionPage[]> {
  const pages: CompletionPage[] = [];
  for (let start = 0; start < references.length; start += 8) {
    const batch = references.slice(start, start + 8);
    const verified = await Promise.all(
      batch.map(async (reference): Promise<CompletionPage> => {
        const { value } = await downloadImmutableJson(
          supabase,
          reference.storage_path,
          reference.artifact_sha256,
          reference.artifact_byte_size,
          MAX_PART_BYTES,
        );
        const text = value.text;
        const confidenceMilli = value.confidence_milli;
        const confidenceSamples = value.confidence_samples;
        const characterCount = typeof text === "string" ? unicodeCharacterCount(text) : -1;
        const utf8Bytes = typeof text === "string" ? new TextEncoder().encode(text).byteLength : -1;
        const words = typeof text === "string" ? wordCount(text) : -1;
        if (
          !exactKeys(value, [
            "schema_version",
            "page_number",
            "text",
            "text_sha256",
            "confidence_milli",
            "confidence_samples",
            "character_count",
            "utf8_bytes",
            "word_count",
          ]) ||
          value.schema_version !== OCR_PAGE_VERSION ||
          value.page_number !== reference.page_number ||
          typeof text !== "string" ||
          characterCount > 1_000_000 ||
          !isSha256(value.text_sha256) ||
          (await sha256Hex(text)) !== value.text_sha256 ||
          !nonNegativeInteger(confidenceSamples, 100_000_000) ||
          !(
            confidenceMilli === null ||
            (nonNegativeInteger(confidenceMilli, 1_000) && confidenceSamples > 0)
          ) ||
          (confidenceSamples === 0 && confidenceMilli !== null) ||
          (characterCount > 0 && (confidenceMilli === null || confidenceSamples === 0)) ||
          (characterCount === 0 && (confidenceMilli !== null || confidenceSamples !== 0)) ||
          value.character_count !== characterCount ||
          value.utf8_bytes !== utf8Bytes ||
          value.word_count !== words
        ) {
          throw new OcrPolicyError("ocr_page_artifact_mismatch", 422);
        }
        return {
          ...reference,
          content_text: text,
          text_sha256: value.text_sha256,
          confidence_milli: confidenceMilli,
          confidence_samples: confidenceSamples,
          character_count: characterCount,
          utf8_bytes: utf8Bytes,
          word_count: words,
        };
      }),
    );
    pages.push(...verified);
  }
  return pages;
}

async function complete(
  supabase: SupabaseClient,
  identity: GithubOidcIdentity,
  body: JsonRecord,
): Promise<Response> {
  const { jobId, leaseToken } = parseLease(body);
  if (!isRecord(body.engine) || !isRecord(body.manifest)) {
    throw new OcrPolicyError("ocr_completion_invalid", 400);
  }
  const engineName = body.engine.name;
  const engineVersion = body.engine.version;
  const manifestPath = body.manifest.storage_ref;
  const manifestSha256 = body.manifest.sha256;
  const manifestByteSize = body.manifest.byte_size;
  const expectedContentSha256 = body.content_sha256;
  if (
    engineName !== "tesseract" ||
    typeof engineVersion !== "string" ||
    !/^[A-Za-z0-9][A-Za-z0-9_.+-]{0,79}$/.test(engineVersion) ||
    typeof manifestPath !== "string" ||
    manifestPath.length > 1_024 ||
    !isSha256(manifestSha256) ||
    !Number.isSafeInteger(manifestByteSize) ||
    !isSha256(expectedContentSha256)
  ) {
    throw new OcrPolicyError("ocr_completion_invalid", 400);
  }
  const attempt = manifestAttempt(manifestPath, jobId, manifestSha256);
  const pageReferences = parseCompletionPageReferences(body.pages, jobId, attempt);
  const pages = await verifyPageArtifacts(supabase, pageReferences);
  const actualContentSha256 = await assertCompletionTextHashes(pages);
  if (actualContentSha256 !== expectedContentSha256) {
    throw new OcrPolicyError("ocr_content_hash_mismatch", 422);
  }
  const { value: manifest } = await downloadImmutableJson(
    supabase,
    manifestPath,
    manifestSha256,
    manifestByteSize as number,
    MAX_MANIFEST_BYTES,
  );
  const quality = qualityEvidence(pages);
  const manifestEvidence = assertManifest(
    manifest,
    jobId,
    attempt,
    engineVersion,
    expectedContentSha256,
    pages,
    quality,
  );

  const { data, error } = await supabase.rpc(FINALIZE_RPC, {
    p_job_id: jobId,
    p_lease_token: leaseToken,
    p_oidc_context: await oidcContext(identity, "complete"),
    p_engine_name: engineName,
    p_engine_version: engineVersion,
    p_manifest_path: manifestPath,
    p_manifest_sha256: manifestSha256,
    p_manifest_byte_size: manifestByteSize,
    p_expected_content_sha256: expectedContentSha256,
    p_manifest_evidence: manifestEvidence,
    p_pages: pages,
  });
  if (
    error ||
    !isRecord(data) ||
    !["under_review", "already_completed"].includes(String(data.status)) ||
    data.publication_status !== "not_published"
  ) {
    throw rpcError("ocr_finalization_failed");
  }
  return json(data.status === "already_completed" ? 200 : 201, data);
}

async function fail(
  supabase: SupabaseClient,
  identity: GithubOidcIdentity,
  body: JsonRecord,
): Promise<Response> {
  const failure = parseFailure(body);
  const { data, error } = await supabase.rpc(FAIL_RPC, {
    p_job_id: failure.jobId,
    p_lease_token: failure.leaseToken,
    p_oidc_context: await oidcContext(identity, "fail"),
    p_error_code: failure.errorCode,
    p_error_detail: failure.errorDetail,
    p_retryable: failure.retryable,
  });
  if (error || !isRecord(data)) throw rpcError("ocr_failure_record_failed");
  return json(200, data);
}

function safeError(error: unknown): OcrPolicyError {
  return error instanceof OcrPolicyError
    ? error
    : new OcrPolicyError("knowledge_ocr_failed", 500);
}

Deno.serve(async (request: Request): Promise<Response> => {
  const correlationId = crypto.randomUUID();
  try {
    if (request.method !== "POST") throw new OcrPolicyError("ocr_method_not_allowed", 405);
    // Signature/JWKS and all immutable GitHub claims are validated before the
    // request body, service-role client, Storage or any RPC is touched.
    const identity = await authenticateGithubOidc(request);
    const envelope = parseEnvelope(await readJson(request));
    const supabase = serviceClient();
    switch (envelope.action) {
      case "claim":
        return await claim(supabase, identity);
      case "heartbeat":
        return await heartbeat(supabase, identity, envelope.body);
      case "upload-part":
        return await uploadPart(supabase, identity, envelope.body);
      case "complete":
        return await complete(supabase, identity, envelope.body);
      case "fail":
        return await fail(supabase, identity, envelope.body);
    }
  } catch (error) {
    const safe = safeError(error);
    console.info(
      JSON.stringify({
        event: "knowledge_ocr_request_rejected",
        service: SERVICE_NAME,
        correlation_id: correlationId,
        safe_error_code: safe.code,
        status: safe.status,
      }),
    );
    const response = json(safe.status, {
      status: "rejected",
      error_code: safe.code,
      correlation_id: correlationId,
    });
    if (safe.status === 405) response.headers.set("allow", "POST");
    return response;
  }
});
