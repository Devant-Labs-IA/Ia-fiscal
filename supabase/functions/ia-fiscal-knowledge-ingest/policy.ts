export const INGEST_CONTRACT_VERSION = "knowledge-ingest-v2";
export const MAX_REQUEST_BYTES = 4 * 1024;
export const MAX_ARTIFACT_BYTES = 50 * 1024 * 1024;
export const MAX_EXTRACTED_CHARACTERS = 2_000_000;
export const MAX_PDF_PAGES = 500;
export const MAX_PDF_IMAGE_PIXELS = 16_777_216;
export const FETCH_TIMEOUT_MS = 20_000;
export const MAX_REDIRECTS = 3;
export const STORAGE_BUCKET = "legal-source-artifacts";
// Hosted Supabase Edge exposes neither Web Worker nor Node vm isolation.
// DOCX must remain unreachable until extraction runs in a separately terminable service.
export const DOCX_MIME_TYPE =
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
export const DOCX_DISABLED_CODE = "source_docx_disabled_edge_runtime";

export type MunicipalitySlug = "cordeiropolis-sp" | "araras-sp";

export type IngestRequest = {
  endpointId: string;
  dryRun: boolean;
};

export type KnowledgeEndpoint = {
  endpoint_id: string;
  municipality_id: string;
  municipality_slug: MunicipalitySlug;
  source_id: string;
  source_title: string;
  requested_url: string;
  trust_tier: string;
  endpoint_kind: string;
  endpoint_status: "active";
  content_mode: "catalog_only" | "legal_body";
  citable_body: boolean;
  activation_blocker: string | null;
  parser_hint: string;
  expected_content_types: string[];
  allowed_hosts: string[];
};

export type FetchArtifactOptions = {
  municipalitySlug: MunicipalitySlug;
  endpointAllowedHosts: string[];
  expectedContentTypes: string[];
  maximumBytes?: number;
  timeoutMs?: number;
  maximumRedirects?: number;
  fetchImpl?: typeof fetch;
};

export type FetchedArtifact = {
  bytes: Uint8Array;
  requestedUrl: string;
  finalUrl: string;
  finalHost: string;
  mimeType: "text/html" | "application/xhtml+xml" | "text/plain" | "application/pdf";
  contentType: string;
  byteSize: number;
  etag: string | null;
  lastModified: string | null;
  httpStatus: number;
  redirectCount: number;
};

export type KnowledgeDiscovery = {
  url: string;
  relation_kind:
    "attachment" | "previous_version" | "related_document" | "publication_copy" | "catalog_page";
  mime_type: string | null;
  byte_size: null;
  label: string | null;
};

type HostRule = {
  hostname: string;
  pathPrefixes?: readonly string[];
};

const MUNICIPALITY_HOST_RULES: Record<MunicipalitySlug, readonly HostRule[]> = {
  "cordeiropolis-sp": [
    {
      hostname: "cordeiropolis.sp.gov.br",
      pathPrefixes: ["/jornal-do-municipio/"],
    },
    {
      hostname: "www.cordeiropolis.sp.gov.br",
      pathPrefixes: ["/jornal-do-municipio/", "/wp-content/uploads/"],
    },
    {
      hostname: "cordeiropolis.siscam.com.br",
      pathPrefixes: ["/documentos/documento/", "/documentos/pesquisa/", "/arquivo", "/index/"],
    },
  ],
  "araras-sp": [
    {
      hostname: "araras.siscam.com.br",
      pathPrefixes: ["/documentos/documento/", "/documentos/pesquisa/", "/arquivo", "/index/"],
    },
    {
      hostname: "legislacaodigital.com.br",
      pathPrefixes: ["/araras-sp"],
    },
    {
      hostname: "www.legislacaodigital.com.br",
      pathPrefixes: ["/araras-sp"],
    },
    {
      hostname: "app.assistechpublicacoes.com.br",
      pathPrefixes: ["/diario-oficial/pmararassp"],
    },
    {
      hostname: "ganhatempo.araras.sp.gov.br",
      pathPrefixes: ["/guiafacil/pesquisa-publica/servicos/"],
    },
  ],
};

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const REDIRECT_STATUSES = new Set([301, 302, 303, 307, 308]);
const SUPPORTED_MIME_TYPES = new Set([
  "text/html",
  "application/xhtml+xml",
  "application/pdf",
  "text/plain",
  "application/octet-stream",
]);

type DeclaredMimeType = FetchedArtifact["mimeType"] | "application/octet-stream";

export class IngestPolicyError extends Error {
  readonly code: string;
  readonly responseStatus: number;
  readonly upstreamStatus: number | null;

  constructor(code: string, responseStatus: number, upstreamStatus: number | null = null) {
    super(code);
    this.name = "IngestPolicyError";
    this.code = code;
    this.responseStatus = responseStatus;
    this.upstreamStatus = upstreamStatus;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function normalizedHostname(value: string): string {
  return value.trim().toLocaleLowerCase("en-US").replace(/\.$/, "");
}

function isIpLiteral(hostname: string): boolean {
  if (hostname.startsWith("[") || hostname.includes(":")) return true;
  const parts = hostname.split(".");
  return parts.length === 4 && parts.every((part) => /^\d{1,3}$/.test(part));
}

function parsePositiveInteger(value: string | null): number | null {
  if (!value || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function sanitizedHeader(value: string | null): string | null {
  if (!value) return null;
  const sanitized = value
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .trim()
    .slice(0, 512);
  return sanitized || null;
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export function shouldAppendFailedFetchRun(dryRun: boolean, captureCommitted: boolean): boolean {
  return !dryRun && !captureCommitted;
}

export function assertCaptureStageIdentity(
  status: "captured" | "already_exists",
  processingStatus: "under_review" | "requires_extraction",
  changeSetId: string | null,
  candidateVersionId: string | null,
): void {
  if (processingStatus === "requires_extraction" && candidateVersionId !== null) {
    throw new IngestPolicyError("capture_contract_invalid", 502);
  }
  if (
    processingStatus === "under_review" &&
    ((changeSetId === null) !== (candidateVersionId === null) ||
      (status === "captured" && !changeSetId))
  ) {
    throw new IngestPolicyError("capture_contract_invalid", 502);
  }
}

export function parseIngestRequest(value: unknown): IngestRequest {
  if (!isRecord(value)) throw new IngestPolicyError("invalid_request", 400);

  const allowedKeys = new Set(["endpoint_id", "dry_run"]);
  if (Object.keys(value).some((key) => !allowedKeys.has(key))) {
    throw new IngestPolicyError("unsupported_request_field", 400);
  }
  if (!isUuid(value.endpoint_id)) {
    throw new IngestPolicyError("invalid_endpoint_id", 400);
  }
  if (value.dry_run !== undefined && typeof value.dry_run !== "boolean") {
    throw new IngestPolicyError("invalid_dry_run", 400);
  }

  return {
    endpointId: value.endpoint_id,
    dryRun: value.dry_run === true,
  };
}

export function parseKnowledgeEndpoint(value: unknown): KnowledgeEndpoint {
  if (!isRecord(value)) throw new IngestPolicyError("endpoint_contract_invalid", 503);

  const municipalitySlug = value.municipality_slug;
  const endpointStatus = value.endpoint_status;
  const contentMode = value.content_mode;
  const citableBody = value.citable_body;
  const activationBlocker = value.activation_blocker;
  const expectedContentTypes = value.expected_content_types;
  const allowedHosts = value.allowed_hosts;
  if (
    !isUuid(value.endpoint_id) ||
    !isUuid(value.municipality_id) ||
    !isUuid(value.source_id) ||
    (municipalitySlug !== "cordeiropolis-sp" && municipalitySlug !== "araras-sp") ||
    typeof value.source_title !== "string" ||
    !value.source_title.trim() ||
    typeof value.requested_url !== "string" ||
    typeof value.trust_tier !== "string" ||
    typeof value.endpoint_kind !== "string" ||
    endpointStatus !== "active" ||
    (contentMode !== "catalog_only" && contentMode !== "legal_body") ||
    typeof citableBody !== "boolean" ||
    (contentMode === "legal_body") !== citableBody ||
    (activationBlocker !== null && typeof activationBlocker !== "string") ||
    typeof value.parser_hint !== "string" ||
    !Array.isArray(expectedContentTypes) ||
    expectedContentTypes.length === 0 ||
    !expectedContentTypes.every((item) => typeof item === "string") ||
    !Array.isArray(allowedHosts) ||
    allowedHosts.length === 0 ||
    !allowedHosts.every((item) => typeof item === "string")
  ) {
    throw new IngestPolicyError("endpoint_contract_invalid", 503);
  }

  const normalizedExpectedContentTypes = expectedContentTypes.map((item) =>
    item.split(";", 1)[0].trim().toLowerCase(),
  );
  const safeExpectedContentTypes = normalizedExpectedContentTypes.filter(
    (item) => item !== DOCX_MIME_TYPE,
  );
  if (safeExpectedContentTypes.length === 0) {
    throw new IngestPolicyError(DOCX_DISABLED_CODE, 503);
  }

  return {
    endpoint_id: value.endpoint_id,
    municipality_id: value.municipality_id,
    municipality_slug: municipalitySlug,
    source_id: value.source_id,
    source_title: value.source_title.trim().slice(0, 300),
    requested_url: value.requested_url,
    trust_tier: value.trust_tier.trim().slice(0, 80),
    endpoint_kind: value.endpoint_kind.trim().slice(0, 80),
    endpoint_status: endpointStatus,
    content_mode: contentMode,
    citable_body: citableBody,
    activation_blocker:
      typeof activationBlocker === "string" ? activationBlocker.trim().slice(0, 500) || null : null,
    parser_hint: value.parser_hint.trim().slice(0, 80),
    expected_content_types: safeExpectedContentTypes,
    allowed_hosts: allowedHosts.map(normalizedHostname),
  };
}

export function shouldExtractCitableLegalBody(
  endpoint: Pick<KnowledgeEndpoint, "endpoint_status" | "content_mode" | "citable_body">,
  mimeType: FetchedArtifact["mimeType"],
): boolean {
  return (
    endpoint.endpoint_status === "active" &&
    endpoint.content_mode === "legal_body" &&
    endpoint.citable_body
  );
}

export async function readJsonBody(request: Request): Promise<unknown> {
  const declaredLength = parsePositiveInteger(request.headers.get("content-length"));
  if (declaredLength !== null && declaredLength > MAX_REQUEST_BYTES) {
    throw new IngestPolicyError("request_too_large", 413);
  }
  if (!request.body) throw new IngestPolicyError("invalid_json", 400);

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;
    size += value.byteLength;
    if (size > MAX_REQUEST_BYTES) {
      await reader.cancel("request_limit_reached");
      throw new IngestPolicyError("request_too_large", 413);
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new IngestPolicyError("invalid_json", 400);
  }
}

export function assertAllowedOfficialUrl(
  rawUrl: string,
  municipalitySlug: MunicipalitySlug,
  endpointAllowedHosts: string[],
): URL {
  if (!rawUrl || rawUrl.length > 2_048 || /[\u0000-\u001f\u007f]/.test(rawUrl)) {
    throw new IngestPolicyError("source_url_invalid", 422);
  }

  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new IngestPolicyError("source_url_invalid", 422);
  }

  const hostname = normalizedHostname(url.hostname);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    (url.port && url.port !== "443") ||
    url.hash ||
    !hostname ||
    isIpLiteral(hostname) ||
    hostname === "localhost" ||
    hostname.endsWith(".localhost") ||
    hostname.endsWith(".local") ||
    hostname.endsWith(".internal")
  ) {
    throw new IngestPolicyError("source_url_not_allowed", 422);
  }

  const registeredHosts = new Set(endpointAllowedHosts.map(normalizedHostname));
  if (!registeredHosts.has(hostname)) {
    throw new IngestPolicyError("source_host_not_registered", 422);
  }

  const rule = MUNICIPALITY_HOST_RULES[municipalitySlug].find(
    (candidate) => candidate.hostname === hostname,
  );
  if (!rule) throw new IngestPolicyError("source_host_not_allowed", 422);

  const normalizedPath = url.pathname.toLocaleLowerCase("en-US");
  if (
    rule.pathPrefixes &&
    !rule.pathPrefixes.some((prefix) =>
      normalizedPath.startsWith(prefix.toLocaleLowerCase("en-US")),
    )
  ) {
    throw new IngestPolicyError("source_path_not_allowed", 422);
  }

  return url;
}

export function normalizeMimeType(contentType: string | null): DeclaredMimeType {
  const mimeType = (contentType ?? "").split(";", 1)[0]?.trim().toLowerCase() ?? "";
  if (mimeType === DOCX_MIME_TYPE) {
    throw new IngestPolicyError(DOCX_DISABLED_CODE, 415);
  }
  if (!SUPPORTED_MIME_TYPES.has(mimeType)) {
    throw new IngestPolicyError("unsupported_source_mime", 415);
  }
  return mimeType as DeclaredMimeType;
}

function assertExpectedMimeType(mimeType: string, expectedContentTypes: string[]): void {
  const normalizedExpected = new Set(
    expectedContentTypes.map((value) => value.split(";", 1)[0]?.trim().toLowerCase()),
  );
  if (!normalizedExpected.has(mimeType)) {
    throw new IngestPolicyError("unexpected_source_mime", 415);
  }
}

async function readResponseBytes(response: Response, maximumBytes: number): Promise<Uint8Array> {
  const declaredLength = parsePositiveInteger(response.headers.get("content-length"));
  if (declaredLength !== null && declaredLength > maximumBytes) {
    await response.body?.cancel("artifact_limit_reached");
    throw new IngestPolicyError("source_artifact_too_large", 413, response.status);
  }
  if (!response.body) throw new IngestPolicyError("source_body_missing", 502, response.status);

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    let read: ReadableStreamReadResult<Uint8Array>;
    try {
      read = await reader.read();
    } catch {
      throw new IngestPolicyError("source_body_read_failed", 502, response.status);
    }
    const { done, value } = read;
    if (done) break;
    if (!value) continue;
    size += value.byteLength;
    if (size > maximumBytes) {
      await reader.cancel("artifact_limit_reached");
      throw new IngestPolicyError("source_artifact_too_large", 413, response.status);
    }
    chunks.push(value);
  }
  if (size === 0) throw new IngestPolicyError("source_body_empty", 502, response.status);

  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function hasPdfSignature(bytes: Uint8Array): boolean {
  const prefix = new TextDecoder("ascii").decode(bytes.slice(0, Math.min(bytes.length, 1_024)));
  return prefix.includes("%PDF-");
}

function hasZipSignature(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 4 &&
    bytes[0] === 0x50 &&
    bytes[1] === 0x4b &&
    ((bytes[2] === 0x03 && bytes[3] === 0x04) ||
      (bytes[2] === 0x05 && bytes[3] === 0x06) ||
      (bytes[2] === 0x07 && bytes[3] === 0x08))
  );
}

export async function fetchOfficialArtifact(
  rawUrl: string,
  options: FetchArtifactOptions,
): Promise<FetchedArtifact> {
  const maximumBytes = options.maximumBytes ?? MAX_ARTIFACT_BYTES;
  const timeoutMs = options.timeoutMs ?? FETCH_TIMEOUT_MS;
  const maximumRedirects = options.maximumRedirects ?? MAX_REDIRECTS;
  const fetchImpl = options.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort("source_fetch_timeout"), timeoutMs);
  let currentUrl = assertAllowedOfficialUrl(
    rawUrl,
    options.municipalitySlug,
    options.endpointAllowedHosts,
  );
  let redirectCount = 0;

  try {
    while (true) {
      let response: Response;
      try {
        response = await fetchImpl(currentUrl, {
          method: "GET",
          redirect: "manual",
          credentials: "omit",
          referrerPolicy: "no-referrer",
          signal: controller.signal,
          headers: {
            accept:
              "text/html, application/xhtml+xml, text/plain, application/pdf, application/octet-stream;q=0.8",
            "user-agent": "IA-Fiscal-Knowledge-Ingest/2.0",
          },
        });
      } catch {
        if (controller.signal.aborted) {
          throw new IngestPolicyError("source_fetch_timeout", 504);
        }
        throw new IngestPolicyError("source_fetch_failed", 502);
      }

      if (REDIRECT_STATUSES.has(response.status)) {
        const location = response.headers.get("location");
        await response.body?.cancel("redirect_not_consumed");
        if (!location) {
          throw new IngestPolicyError("source_redirect_missing_location", 502, response.status);
        }
        if (redirectCount >= maximumRedirects) {
          throw new IngestPolicyError("source_redirect_limit_reached", 502, response.status);
        }

        let nextUrl: URL;
        try {
          nextUrl = new URL(location, currentUrl);
        } catch {
          throw new IngestPolicyError("source_redirect_invalid", 502, response.status);
        }
        currentUrl = assertAllowedOfficialUrl(
          nextUrl.toString(),
          options.municipalitySlug,
          options.endpointAllowedHosts,
        );
        redirectCount += 1;
        continue;
      }

      if (!response.ok) {
        await response.body?.cancel("upstream_status_not_consumed");
        throw new IngestPolicyError("source_http_error", 502, response.status);
      }

      const responseContentType = sanitizedHeader(response.headers.get("content-type"));
      let declaredMimeType: DeclaredMimeType;
      try {
        declaredMimeType = normalizeMimeType(responseContentType);
        assertExpectedMimeType(declaredMimeType, options.expectedContentTypes);
      } catch (error) {
        await response.body?.cancel("source_mime_rejected");
        throw error;
      }
      let bytes: Uint8Array;
      try {
        bytes = await readResponseBytes(response, maximumBytes);
      } catch (error) {
        if (controller.signal.aborted) {
          throw new IngestPolicyError("source_fetch_timeout", 504, response.status);
        }
        throw error;
      }
      let mimeType: FetchedArtifact["mimeType"];
      if (declaredMimeType === "application/octet-stream") {
        if (hasPdfSignature(bytes)) {
          mimeType = "application/pdf";
        } else if (hasZipSignature(bytes)) {
          throw new IngestPolicyError(DOCX_DISABLED_CODE, 415);
        } else {
          throw new IngestPolicyError("source_mime_content_mismatch", 415);
        }
      } else {
        mimeType = declaredMimeType;
        if (mimeType === "application/pdf" && !hasPdfSignature(bytes)) {
          throw new IngestPolicyError("source_mime_content_mismatch", 415);
        }
      }

      return {
        bytes,
        requestedUrl: rawUrl,
        finalUrl: currentUrl.toString(),
        finalHost: normalizedHostname(currentUrl.hostname),
        mimeType,
        contentType: responseContentType ?? mimeType,
        byteSize: bytes.byteLength,
        etag: sanitizedHeader(response.headers.get("etag")),
        lastModified: sanitizedHeader(response.headers.get("last-modified")),
        httpStatus: response.status,
        redirectCount,
      };
    }
  } finally {
    clearTimeout(timeout);
  }
}

function decodeHtml(bytes: Uint8Array, contentType: string): string {
  const charsetMatch = /charset\s*=\s*["']?([^;"'\s]+)/i.exec(contentType);
  const charset = charsetMatch?.[1]?.toLowerCase() ?? "utf-8";
  const supportedCharset = new Set([
    "utf-8",
    "utf8",
    "us-ascii",
    "iso-8859-1",
    "latin1",
    "windows-1252",
  ]).has(charset)
    ? charset
    : "utf-8";
  try {
    return new TextDecoder(supportedCharset).decode(bytes);
  } catch {
    return new TextDecoder().decode(bytes);
  }
}

function decodeHtmlEntities(value: string): string {
  const named: Record<string, string> = {
    aacute: "á",
    acirc: "â",
    agrave: "à",
    amp: "&",
    apos: "'",
    atilde: "ã",
    auml: "ä",
    ccedil: "ç",
    eacute: "é",
    ecirc: "ê",
    egrave: "è",
    gt: ">",
    hellip: "…",
    iacute: "í",
    lt: "<",
    mdash: "—",
    ndash: "–",
    nbsp: " ",
    oacute: "ó",
    ocirc: "ô",
    ordf: "ª",
    ordm: "º",
    otilde: "õ",
    ouml: "ö",
    quot: '"',
    uacute: "ú",
    uuml: "ü",
  };
  return value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (entity, key: string) => {
    if (key.startsWith("#x") || key.startsWith("#X")) {
      const point = Number.parseInt(key.slice(2), 16);
      return Number.isSafeInteger(point) && point <= 0x10ffff
        ? String.fromCodePoint(point)
        : entity;
    }
    if (key.startsWith("#")) {
      const point = Number.parseInt(key.slice(1), 10);
      return Number.isSafeInteger(point) && point <= 0x10ffff
        ? String.fromCodePoint(point)
        : entity;
    }
    const decoded = named[key.toLowerCase()];
    if (!decoded) return entity;
    return /^[A-Z]/.test(key) && /^\p{L}$/u.test(decoded)
      ? decoded.toLocaleUpperCase("pt-BR")
      : decoded;
  });
}

export function extractUntrustedHtmlText(
  bytes: Uint8Array,
  contentType = "text/html; charset=utf-8",
): string | null {
  const html = decodeHtml(bytes, contentType);
  const withoutExecutableElements = html
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(
      /<\s*(script|style|noscript|template|svg|canvas)\b[^>]*>[\s\S]*?<\s*\/\s*\1\s*>/gi,
      " ",
    )
    .replace(/<\s*(script|style|noscript|template|svg|canvas)\b[^>]*\/\s*>/gi, " ")
    .replace(/<\s*br\s*\/?>/gi, "\n")
    .replace(/<\s*\/\s*(p|div|section|article|header|footer|main|aside|li|tr|h[1-6])\s*>/gi, "\n")
    .replace(/<[^>]+>/g, " ");
  return normalizeExtractedText(decodeHtmlEntities(withoutExecutableElements));
}

export function discoverOfficialDocumentLinks(
  bytes: Uint8Array,
  contentType: string,
  baseUrl: string,
  municipalitySlug: MunicipalitySlug,
  endpointAllowedHosts: string[],
): KnowledgeDiscovery[] {
  const html = decodeHtml(bytes, contentType);
  const base = assertAllowedOfficialUrl(baseUrl, municipalitySlug, endpointAllowedHosts);
  const discoveries = new Map<string, KnowledgeDiscovery>();
  const pattern = /<a\b[^>]*?\bhref\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const rawHref = decodeHtmlEntities(match[1] ?? match[2] ?? match[3] ?? "").trim();
    if (!rawHref || rawHref.startsWith("#") || rawHref.toLowerCase().startsWith("javascript:")) {
      continue;
    }
    try {
      const resolved = new URL(rawHref, base);
      resolved.hash = "";
      const allowed = assertAllowedOfficialUrl(
        resolved.toString(),
        municipalitySlug,
        endpointAllowedHosts,
      );
      if (allowed.toString() === base.toString()) continue;
      const lowerPath = allowed.pathname.toLowerCase();
      const looksLikeDocument =
        lowerPath.includes("/arquivo") ||
        lowerPath.includes("/documentos/documento/") ||
        lowerPath.includes("/documentos/pesquisa/") ||
        /\.(pdf|docx?|rtf)$/i.test(lowerPath);
      if (!looksLikeDocument) continue;
      const label =
        normalizeExtractedText(
          decodeHtmlEntities((match[4] ?? "").replace(/<[^>]+>/g, " ")),
        )?.slice(0, 300) ?? null;
      const labelLower = label?.toLocaleLowerCase("pt-BR") ?? "";
      const mimeType =
        lowerPath.endsWith(".pdf") || /\bpdf\b/.test(labelLower)
          ? "application/pdf"
          : lowerPath.endsWith(".docx") || /\bdocx\b/.test(labelLower)
            ? "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            : lowerPath.endsWith(".doc") || /\bdoc\b/.test(labelLower)
              ? "application/msword"
              : lowerPath.endsWith(".rtf") || /\brtf\b/.test(labelLower)
                ? "application/rtf"
                : null;
      const relationKind = lowerPath.includes("/documentos/pesquisa/")
        ? "catalog_page"
        : lowerPath.includes("/documentos/documento/")
          ? "related_document"
          : "attachment";
      discoveries.set(allowed.toString(), {
        url: allowed.toString(),
        relation_kind: relationKind,
        mime_type: mimeType,
        byte_size: null,
        label,
      });
      if (discoveries.size >= 100) break;
    } catch (error) {
      if (!(error instanceof IngestPolicyError)) throw error;
    }
  }
  const rank = (item: KnowledgeDiscovery): number =>
    item.relation_kind === "attachment" && item.mime_type === "application/pdf"
      ? 0
      : item.relation_kind === "attachment" &&
          item.mime_type ===
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ? 1
        : item.relation_kind === "related_document"
          ? 2
          : item.relation_kind === "catalog_page"
            ? 3
            : 4;
  const attachmentId = (item: KnowledgeDiscovery): number => {
    if (item.relation_kind !== "attachment") return -1;
    try {
      const value = new URL(item.url).searchParams.get("Id");
      const parsed = value && /^\d+$/.test(value) ? Number(value) : -1;
      return Number.isSafeInteger(parsed) ? parsed : -1;
    } catch {
      return -1;
    }
  };
  return [...discoveries.values()].sort(
    (left, right) =>
      rank(left) - rank(right) ||
      attachmentId(right) - attachmentId(left) ||
      left.url.localeCompare(right.url),
  );
}

export function normalizeExtractedText(value: string): string | null {
  const normalized = value
    .replace(/\r\n?/g, "\n")
    .replace(/[\t\f\v ]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (!normalized) return null;
  let extractedCharacters = 0;
  for (const _character of normalized) {
    extractedCharacters += 1;
    if (extractedCharacters > MAX_EXTRACTED_CHARACTERS) {
      throw new IngestPolicyError("source_extracted_text_too_large", 413);
    }
  }
  return normalized;
}

export function countUnicodeCharacters(value: string): number {
  let count = 0;
  for (const _character of value) count += 1;
  return count;
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const source = new Uint8Array(bytes.byteLength);
  source.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", source);
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join(
    "",
  );
}

export async function constantTimeSecretEquals(
  candidate: string,
  expected: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [candidateDigest, expectedDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(candidate)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const candidateBytes = new Uint8Array(candidateDigest);
  const expectedBytes = new Uint8Array(expectedDigest);
  let mismatch = candidateBytes.byteLength ^ expectedBytes.byteLength;
  for (let index = 0; index < candidateBytes.byteLength; index += 1) {
    mismatch |= candidateBytes[index] ^ expectedBytes[index];
  }
  return mismatch === 0;
}

export function buildStoragePath(
  municipalitySlug: MunicipalitySlug,
  sourceId: string,
  sha256: string,
  mimeType: FetchedArtifact["mimeType"],
): string {
  if (!isUuid(sourceId) || !SHA256_PATTERN.test(sha256)) {
    throw new IngestPolicyError("storage_identity_invalid", 500);
  }
  const extension =
    mimeType === "application/pdf" ? "pdf" : mimeType === "text/plain" ? "txt" : "html";
  return `${municipalitySlug}/${sourceId}/${sha256}/artifact.${extension}`;
}

export function builtInAllowedHosts(municipalitySlug: MunicipalitySlug): string[] {
  return MUNICIPALITY_HOST_RULES[municipalitySlug].map((rule) => rule.hostname);
}
