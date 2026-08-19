import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import {
  assertKnowledgeSchedulerRequest,
  SchedulerAuthorizationError,
} from "../_shared/knowledge-scheduler-auth.ts";
import {
  buildDeterministicChunks,
  EXTERNAL_OCR_V1_MAX_PAGES,
  extractLegalBodyText,
  isExternalOcrEligiblePdfFailure,
} from "./extraction.ts";

import {
  assertCaptureStageIdentity,
  buildStoragePath,
  countUnicodeCharacters,
  discoverOfficialDocumentLinks,
  fetchOfficialArtifact,
  INGEST_CONTRACT_VERSION,
  IngestPolicyError,
  isUuid,
  parseIngestRequest,
  parseKnowledgeEndpoint,
  readJsonBody,
  sha256Hex,
  shouldAppendFailedFetchRun,
  shouldExtractCitableLegalBody,
  STORAGE_BUCKET,
  type FetchedArtifact,
  type KnowledgeEndpoint,
} from "./policy.ts";

type JsonRecord = Record<string, unknown>;

type CaptureResult = {
  fetch_run_id?: unknown;
  artifact_id?: unknown;
  status?: unknown;
  processing_status?: unknown;
  change_set_id?: unknown;
  candidate_version_id?: unknown;
  staging_status?: unknown;
  staged_sections?: unknown;
  staged_chunks?: unknown;
};

type PublicCaptureResult = {
  fetch_run_id: string;
  artifact_id: string;
  status: "captured" | "already_exists";
  processing_status: "under_review" | "requires_extraction";
  change_set_id: string | null;
  candidate_version_id: string | null;
  staging_status: "staged" | "already_staged" | "not_applicable";
  staged_sections: number;
  staged_chunks: number;
};

type UploadedArtifactAudit = {
  storagePath: string;
  contentSha256: string;
  uploadStatus: "created" | "already_present";
};

const SERVICE_NAME = "ia-fiscal-knowledge-ingest";
const ENDPOINTS_RPC = "ia_fiscal_get_knowledge_source_endpoints";
const CAPTURE_RPC = "ia_fiscal_capture_knowledge_source_v2";
const FAILURE_RPC = "ia_fiscal_record_knowledge_fetch_failure";
const DISCOVERY_RPC = "ia_fiscal_record_knowledge_discoveries";

function json(status: number, body: JsonRecord): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new IngestPolicyError("ingest_configuration_missing", 503);
  return value;
}

function safeLog(event: string, fields: JsonRecord): void {
  console.info(
    JSON.stringify({
      event,
      service: SERVICE_NAME,
      ...fields,
    }),
  );
}

function safeError(error: unknown): IngestPolicyError {
  if (error instanceof SchedulerAuthorizationError) {
    return new IngestPolicyError("scheduler_authorization_failed", 403);
  }
  return error instanceof IngestPolicyError
    ? error
    : new IngestPolicyError("knowledge_ingest_failed", 500);
}

function serviceClient(supabaseUrl: string, serviceRoleKey: string): SupabaseClient {
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      headers: {
        "x-ia-ingest": INGEST_CONTRACT_VERSION,
      },
    },
  });
}

async function fetchWithGovernedRetry(endpoint: KnowledgeEndpoint): Promise<FetchedArtifact> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await fetchOfficialArtifact(endpoint.requested_url, {
        municipalitySlug: endpoint.municipality_slug,
        endpointAllowedHosts: endpoint.allowed_hosts,
        expectedContentTypes: endpoint.expected_content_types,
      });
    } catch (error) {
      lastError = error;
      const policyError = error instanceof IngestPolicyError ? error : null;
      const retryable =
        policyError !== null &&
        (policyError.code === "source_fetch_failed" ||
          policyError.code === "source_fetch_timeout" ||
          (policyError.code === "source_http_error" &&
            (policyError.upstreamStatus === 429 || (policyError.upstreamStatus ?? 0) >= 500)));
      if (!retryable || attempt === 3) throw error;
      await new Promise((resolve) => setTimeout(resolve, attempt * 250));
    }
  }
  throw lastError;
}

async function loadEndpoint(
  supabase: SupabaseClient,
  endpointId: string,
): Promise<KnowledgeEndpoint> {
  const { data, error } = await supabase.rpc(ENDPOINTS_RPC);
  if (error) throw new IngestPolicyError("endpoint_lookup_failed", 503);
  if (!Array.isArray(data)) throw new IngestPolicyError("endpoint_contract_invalid", 503);

  const rawEndpoint = data.find(
    (value) =>
      Boolean(value) &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      (value as JsonRecord).endpoint_id === endpointId,
  );
  if (!rawEndpoint) throw new IngestPolicyError("endpoint_not_found", 404);
  return parseKnowledgeEndpoint(rawEndpoint);
}

function isDuplicateStorageError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const record = error as Record<string, unknown>;
  const status = String(record.statusCode ?? record.status ?? "");
  const message = typeof record.message === "string" ? record.message.toLowerCase() : "";
  const name = typeof record.name === "string" ? record.name.toLowerCase() : "";
  return (
    status === "409" ||
    name === "duplicate" ||
    message.includes("already exists") ||
    message.includes("resource already exists")
  );
}

async function uploadArtifact(
  supabase: SupabaseClient,
  storagePath: string,
  artifact: FetchedArtifact,
): Promise<"created" | "already_present"> {
  const rawArtifact = new Uint8Array(artifact.bytes.byteLength);
  rawArtifact.set(artifact.bytes);
  const body = new Blob([rawArtifact], { type: artifact.mimeType });
  const { error } = await supabase.storage.from(STORAGE_BUCKET).upload(storagePath, body, {
    contentType: artifact.mimeType,
    cacheControl: "31536000",
    upsert: false,
  });
  if (!error) return "created";
  if (isDuplicateStorageError(error)) return "already_present";
  throw new IngestPolicyError("artifact_storage_failed", 502);
}

function nullableUuid(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (isUuid(value)) return value;
  throw new IngestPolicyError("capture_contract_invalid", 502);
}

function publicCaptureResult(value: unknown): PublicCaptureResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new IngestPolicyError("capture_contract_invalid", 502);
  }
  const result = value as CaptureResult;
  const status =
    result.status === "captured" || result.status === "already_exists" ? result.status : null;
  const processingStatus =
    result.processing_status === "under_review" ||
    result.processing_status === "requires_extraction"
      ? result.processing_status
      : null;
  if (!status || !processingStatus) {
    throw new IngestPolicyError("capture_contract_invalid", 502);
  }

  if (!isUuid(result.fetch_run_id) || !isUuid(result.artifact_id)) {
    throw new IngestPolicyError("capture_contract_invalid", 502);
  }

  const changeSetId = nullableUuid(result.change_set_id);
  const candidateVersionId = nullableUuid(result.candidate_version_id);
  assertCaptureStageIdentity(status, processingStatus, changeSetId, candidateVersionId);
  const stagingStatus =
    result.staging_status === "staged" ||
    result.staging_status === "already_staged" ||
    result.staging_status === "not_applicable"
      ? result.staging_status
      : null;
  const stagedSections = result.staged_sections;
  const stagedChunks = result.staged_chunks;
  if (
    !stagingStatus ||
    typeof stagedSections !== "number" ||
    !Number.isSafeInteger(stagedSections) ||
    typeof stagedChunks !== "number" ||
    !Number.isSafeInteger(stagedChunks) ||
    (candidateVersionId !== null &&
      (stagingStatus === "not_applicable" || stagedSections !== 1 || stagedChunks < 1)) ||
    (candidateVersionId === null &&
      (stagingStatus !== "not_applicable" || stagedSections !== 0 || stagedChunks !== 0))
  ) {
    throw new IngestPolicyError("capture_contract_invalid", 502);
  }

  return {
    fetch_run_id: result.fetch_run_id,
    artifact_id: result.artifact_id,
    status,
    processing_status: processingStatus,
    change_set_id: changeSetId,
    candidate_version_id: candidateVersionId,
    staging_status: stagingStatus,
    staged_sections: stagedSections,
    staged_chunks: stagedChunks,
  };
}

async function captureArtifact(
  supabase: SupabaseClient,
  endpoint: KnowledgeEndpoint,
  artifact: FetchedArtifact,
  sha256: string,
  storagePath: string,
  extractedText: string | null,
  chunks: ReturnType<typeof buildDeterministicChunks>,
  extractedCharacterCount: number,
  storageUpload: "created" | "already_present",
  observedAt: string,
  correlationId: string,
  extractionParser: string | null,
  extractionPageCount: number | null,
  extractionBlocker: string | null,
  onRpcCommitted: () => void,
): Promise<PublicCaptureResult> {
  const { data, error } = await supabase.rpc(CAPTURE_RPC, {
    p_source_id: endpoint.source_id,
    p_requested_url: endpoint.requested_url,
    p_final_url: artifact.finalUrl,
    p_content_sha256: sha256,
    p_mime_type: artifact.mimeType,
    p_byte_size: artifact.byteSize,
    p_storage_bucket: STORAGE_BUCKET,
    p_storage_path: storagePath,
    p_extracted_text: extractedText,
    p_sections:
      extractedText === null
        ? null
        : [
            {
              section_key: "integral",
              heading: "Texto integral oficial",
              ordinal: 1,
              content_text: extractedText,
              chunks,
            },
          ],
    p_etag: artifact.etag,
    p_last_modified: artifact.lastModified,
    p_http_status: artifact.httpStatus,
    p_observed_at: observedAt,
    p_correlation_id: correlationId,
    p_metadata: {
      contract_version: INGEST_CONTRACT_VERSION,
      endpoint_id: endpoint.endpoint_id,
      endpoint_kind: endpoint.endpoint_kind,
      trust_tier: endpoint.trust_tier,
      parser_hint: endpoint.parser_hint,
      content_mode: endpoint.content_mode,
      citable_body: endpoint.citable_body,
      redirect_count: artifact.redirectCount,
      storage_upload: storageUpload,
      extraction_complete: extractedText !== null,
      content_truncated: false,
      extracted_char_count: extractedCharacterCount,
      extraction_parser: extractionParser,
      extraction_page_count: extractionPageCount,
      extraction_blocker: extractionBlocker,
      content_handling: {
        trust: "untrusted_external_document",
        executable_content: "never_executed",
        extraction: extractedText === null ? "raw_only" : "plain_text_untrusted",
        extracted_characters: extractedCharacterCount,
      },
    },
  });
  if (error) throw new IngestPolicyError("capture_rpc_failed", 502);
  onRpcCommitted();
  return publicCaptureResult(data);
}

async function recordDiscoveries(
  supabase: SupabaseClient,
  endpointId: string,
  discoveries: ReturnType<typeof discoverOfficialDocumentLinks>,
  observedAt: string,
): Promise<void> {
  if (discoveries.length === 0) return;
  const { error } = await supabase.rpc(DISCOVERY_RPC, {
    p_endpoint_id: endpointId,
    p_assets: discoveries,
    p_observed_at: observedAt,
  });
  if (error) throw new IngestPolicyError("discovery_record_failed", 502);
}

async function recordFailure(
  supabase: SupabaseClient,
  endpoint: KnowledgeEndpoint,
  ingestError: IngestPolicyError,
  observedAt: string,
  correlationId: string,
  uploadedArtifact: UploadedArtifactAudit | null,
): Promise<void> {
  const { error } = await supabase.rpc(FAILURE_RPC, {
    p_source_id: endpoint.source_id,
    p_requested_url: endpoint.requested_url,
    p_http_status: ingestError.upstreamStatus,
    p_error_code: ingestError.code.slice(0, 120),
    p_error_detail: null,
    p_observed_at: observedAt,
    p_correlation_id: correlationId,
    p_metadata: {
      contract_version: INGEST_CONTRACT_VERSION,
      endpoint_id: endpoint.endpoint_id,
      endpoint_kind: endpoint.endpoint_kind,
      ...(uploadedArtifact === null
        ? {}
        : {
            orphaned_storage_artifact: {
              disposition: "preserved_for_reconciliation",
              storage_bucket: STORAGE_BUCKET,
              storage_path: uploadedArtifact.storagePath,
              content_sha256: uploadedArtifact.contentSha256,
              upload_status: uploadedArtifact.uploadStatus,
            },
          }),
    },
  });
  if (error) throw new IngestPolicyError("failure_record_failed", 502);
}

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  const startedAt = Date.now();

  let supabase: SupabaseClient | null = null;
  let endpoint: KnowledgeEndpoint | null = null;
  let dryRun = false;
  let captureCommitted = false;
  let uploadedArtifact: UploadedArtifactAudit | null = null;

  try {
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    supabase = serviceClient(supabaseUrl, serviceRoleKey);
    await assertKnowledgeSchedulerRequest(request, supabase, "ingest");
    if (request.method !== "POST") {
      throw new IngestPolicyError("method_not_allowed", 405);
    }

    const requestBody = parseIngestRequest(await readJsonBody(request));
    dryRun = requestBody.dryRun;
    endpoint = await loadEndpoint(supabase, requestBody.endpointId);

    const artifact = await fetchWithGovernedRetry(endpoint);
    const contentSha256 = await sha256Hex(artifact.bytes);
    let extraction: Awaited<ReturnType<typeof extractLegalBodyText>> | null = null;
    let extractionBlocker: string | null = null;
    let externalOcrPageCount: number | null = null;
    if (shouldExtractCitableLegalBody(endpoint, artifact.mimeType)) {
      try {
        extraction = await extractLegalBodyText(artifact);
      } catch (error) {
        if (
          !dryRun &&
          artifact.mimeType === "application/pdf" &&
          isExternalOcrEligiblePdfFailure(error)
        ) {
          extractionBlocker =
            error.pageCount <= EXTERNAL_OCR_V1_MAX_PAGES
              ? error.code
              : "external_ocr_page_limit_exceeded";
          externalOcrPageCount = error.pageCount;
        } else {
          throw error;
        }
      }
    }
    const extractedText = extraction?.text ?? null;
    const extractionPageCount = extraction?.pageCount ?? externalOcrPageCount;
    const extractedCharacterCount =
      extractedText === null ? 0 : countUnicodeCharacters(extractedText);
    const chunks = extractedText === null ? [] : buildDeterministicChunks(extractedText);
    const expectedStagedChunks = extractedText === null ? 0 : Math.max(1, chunks.length);
    const discoveries =
      artifact.mimeType === "text/html" || artifact.mimeType === "application/xhtml+xml"
        ? discoverOfficialDocumentLinks(
            artifact.bytes,
            artifact.contentType,
            artifact.finalUrl,
            endpoint.municipality_slug,
            endpoint.allowed_hosts,
          )
        : [];
    const storagePath = buildStoragePath(
      endpoint.municipality_slug,
      endpoint.source_id,
      contentSha256,
      artifact.mimeType,
    );

    if (dryRun) {
      safeLog("knowledge_ingest_dry_run_completed", {
        correlation_id: correlationId,
        endpoint_id: endpoint.endpoint_id,
        municipality_slug: endpoint.municipality_slug,
        source_id: endpoint.source_id,
        content_mode: endpoint.content_mode,
        citable_body: endpoint.citable_body,
        source_host: artifact.finalHost,
        mime_type: artifact.mimeType,
        byte_size: artifact.byteSize,
        redirect_count: artifact.redirectCount,
        duration_ms: Date.now() - startedAt,
      });
      return json(200, {
        data: {
          status: "validated",
          mode: "dry_run",
          endpoint_id: endpoint.endpoint_id,
          municipality_slug: endpoint.municipality_slug,
          source_id: endpoint.source_id,
          content_mode: endpoint.content_mode,
          citable_body: endpoint.citable_body,
          activation_blocker: endpoint.activation_blocker,
          source_host: artifact.finalHost,
          mime_type: artifact.mimeType,
          byte_size: artifact.byteSize,
          content_sha256: contentSha256,
          redirect_count: artifact.redirectCount,
          extraction_status:
            extractedText === null ? "requires_extraction" : "plain_text_untrusted",
          extraction_parser: extraction?.parser ?? null,
          extraction_page_count: extractionPageCount,
          extracted_characters: extractedCharacterCount,
          staged_sections: extractedText === null ? 0 : 1,
          staged_chunks: expectedStagedChunks,
          discovered_assets: discoveries.length,
        },
        correlation_id: correlationId,
        contract_version: INGEST_CONTRACT_VERSION,
      });
    }

    const storageUpload = await uploadArtifact(supabase, storagePath, artifact);
    uploadedArtifact = {
      storagePath,
      contentSha256,
      uploadStatus: storageUpload,
    };
    const observedAt = new Date().toISOString();
    const capture = await captureArtifact(
      supabase,
      endpoint,
      artifact,
      contentSha256,
      storagePath,
      extractedText,
      chunks,
      extractedCharacterCount,
      storageUpload,
      observedAt,
      correlationId,
      extraction?.parser ?? null,
      extractionPageCount,
      extractionBlocker,
      () => {
        captureCommitted = true;
      },
    );
    if (
      (extractedText === null && capture.processing_status !== "requires_extraction") ||
      (extractedText !== null && capture.processing_status !== "under_review")
    ) {
      throw new IngestPolicyError("capture_contract_invalid", 502);
    }
    await recordDiscoveries(supabase, endpoint.endpoint_id, discoveries, observedAt);

    safeLog("knowledge_ingest_completed", {
      correlation_id: correlationId,
      endpoint_id: endpoint.endpoint_id,
      municipality_slug: endpoint.municipality_slug,
      source_id: endpoint.source_id,
      content_mode: endpoint.content_mode,
      citable_body: endpoint.citable_body,
      source_host: artifact.finalHost,
      mime_type: artifact.mimeType,
      byte_size: artifact.byteSize,
      redirect_count: artifact.redirectCount,
      storage_upload: storageUpload,
      capture_status: capture.status,
      processing_status: capture.processing_status,
      staging_status: capture.staging_status,
      staged_sections: capture.staged_sections,
      staged_chunks: capture.staged_chunks,
      discovered_assets: discoveries.length,
      duration_ms: Date.now() - startedAt,
    });

    return json(capture.status === "captured" ? 201 : 200, {
      data: {
        ...capture,
        endpoint_id: endpoint.endpoint_id,
        municipality_slug: endpoint.municipality_slug,
        source_id: endpoint.source_id,
        content_mode: endpoint.content_mode,
        citable_body: endpoint.citable_body,
        activation_blocker: endpoint.activation_blocker,
        source_host: artifact.finalHost,
        mime_type: artifact.mimeType,
        byte_size: artifact.byteSize,
        content_sha256: contentSha256,
        extraction_status: extractedText === null ? "requires_extraction" : "plain_text_untrusted",
        extraction_parser: extraction?.parser ?? null,
        extraction_page_count: extractionPageCount,
        extraction_blocker: extractionBlocker,
        staging_status: capture.staging_status,
        staged_sections: capture.staged_sections,
        staged_chunks: capture.staged_chunks,
        discovered_assets: discoveries.length,
      },
      correlation_id: correlationId,
      contract_version: INGEST_CONTRACT_VERSION,
    });
  } catch (error) {
    const ingestError = safeError(error);
    const observedAt = new Date().toISOString();
    if (supabase && endpoint && shouldAppendFailedFetchRun(dryRun, captureCommitted)) {
      try {
        await recordFailure(
          supabase,
          endpoint,
          ingestError,
          observedAt,
          correlationId,
          uploadedArtifact,
        );
      } catch {
        safeLog("knowledge_ingest_failure_record_failed", {
          correlation_id: correlationId,
          endpoint_id: endpoint.endpoint_id,
          municipality_slug: endpoint.municipality_slug,
          source_id: endpoint.source_id,
          error_code: "failure_record_failed",
        });
      }
    }

    safeLog("knowledge_ingest_failed", {
      correlation_id: correlationId,
      endpoint_id: endpoint?.endpoint_id ?? null,
      municipality_slug: endpoint?.municipality_slug ?? null,
      source_id: endpoint?.source_id ?? null,
      error_code: ingestError.code,
      upstream_status: ingestError.upstreamStatus,
      dry_run: dryRun,
      capture_committed: captureCommitted,
      storage_orphan_preserved: uploadedArtifact !== null && !captureCommitted,
      duration_ms: Date.now() - startedAt,
    });
    return json(ingestError.responseStatus, {
      error: ingestError.code,
      correlation_id: correlationId,
      contract_version: INGEST_CONTRACT_VERSION,
    });
  }
});
