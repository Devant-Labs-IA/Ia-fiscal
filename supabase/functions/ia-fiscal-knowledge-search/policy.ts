export const SEARCH_CONTRACT_VERSION = "knowledge-search-v1";
export const SEARCH_RETRIEVAL_MODE = "lexical_portuguese";
export const SEARCH_LEXICAL_LANGUAGE = "pt-BR";
export const SEARCH_SEMANTIC_STATUS = "unsupported_language";
export const MAX_SEARCH_REQUEST_BYTES = 4_096;
export const BUILT_IN_SEARCH_ALLOWED_ORIGINS = Object.freeze([
  "https://ia-fiscal-homologacao-diego-4685-diego-4685s-projects.vercel.app",
  "https://ia-fiscal-homologacao.vercel.app",
]);

export class KnowledgeSearchPolicyError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number) {
    super(code);
    this.name = "KnowledgeSearchPolicyError";
    this.code = code;
    this.status = status;
  }
}

type ParsedSearchRequest = {
  municipalityId: string;
  query: string;
  limit: number;
};

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function parseKnowledgeSearchRequest(request: Request): Promise<ParsedSearchRequest> {
  const declared = request.headers.get("content-length");
  if (declared && /^\d+$/.test(declared) && Number(declared) > MAX_SEARCH_REQUEST_BYTES) {
    throw new KnowledgeSearchPolicyError("request_too_large", 413);
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_SEARCH_REQUEST_BYTES) {
    throw new KnowledgeSearchPolicyError("request_too_large", 413);
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new KnowledgeSearchPolicyError("invalid_json", 400);
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new KnowledgeSearchPolicyError("invalid_request", 400);
  }
  const body = value as Record<string, unknown>;
  if (Object.keys(body).some((key) => !["municipality_id", "query", "limit"].includes(key))) {
    throw new KnowledgeSearchPolicyError("unsupported_request_field", 400);
  }
  const municipalityId = typeof body.municipality_id === "string"
    ? body.municipality_id.trim()
    : "";
  const query = typeof body.query === "string" ? body.query.trim() : "";
  const limit = body.limit === undefined ? 8 : body.limit;
  if (!UUID_PATTERN.test(municipalityId)) {
    throw new KnowledgeSearchPolicyError("invalid_municipality_id", 400);
  }
  if (query.length < 2 || query.length > 500) {
    throw new KnowledgeSearchPolicyError("invalid_query_length", 400);
  }
  if (!Number.isInteger(limit) || Number(limit) < 1 || Number(limit) > 20) {
    throw new KnowledgeSearchPolicyError("invalid_limit", 400);
  }
  return { municipalityId, query, limit: Number(limit) };
}

export function knowledgeSearchCorsHeaders(
  origin: string | null,
  configuredOrigins = "",
): Record<string, string> {
  const allowed = new Set([
    ...BUILT_IN_SEARCH_ALLOWED_ORIGINS,
    ...configuredOrigins.split(",").map((value) => value.trim()).filter(Boolean),
  ]);
  const normalizedOrigin = origin?.trim() ?? "";
  const headers: Record<string, string> = {
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
    "access-control-allow-methods": "POST, OPTIONS",
    "vary": "Origin",
  };
  if (normalizedOrigin && allowed.has(normalizedOrigin)) {
    headers["access-control-allow-origin"] = normalizedOrigin;
  }
  return headers;
}
