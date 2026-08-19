export const EMBED_CONTRACT_VERSION = "knowledge-embed-v1";
export const EMBEDDING_MODEL = "gte-small";
export const EMBEDDING_MODEL_REVISION = "gte-small-384-v1";
export const EMBEDDING_DIMENSIONS = 384;
export const MAX_EMBED_REQUEST_BYTES = 1_024;

export class EmbedPolicyError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number) {
    super(code);
    this.name = "EmbedPolicyError";
    this.code = code;
    this.status = status;
  }
}

export async function parseEmbedRequest(request: Request): Promise<{ batchSize: number }> {
  const declared = request.headers.get("content-length");
  if (declared && /^\d+$/.test(declared) && Number(declared) > MAX_EMBED_REQUEST_BYTES) {
    throw new EmbedPolicyError("request_too_large", 413);
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_EMBED_REQUEST_BYTES) {
    throw new EmbedPolicyError("request_too_large", 413);
  }
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new EmbedPolicyError("invalid_json", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new EmbedPolicyError("invalid_request", 400);
  }
  const record = body as Record<string, unknown>;
  if (Object.keys(record).some((key) => key !== "batch_size")) {
    throw new EmbedPolicyError("unsupported_request_field", 400);
  }
  const batchSize = record.batch_size ?? 16;
  if (!Number.isInteger(batchSize) || Number(batchSize) < 1 || Number(batchSize) > 32) {
    throw new EmbedPolicyError("invalid_batch_size", 400);
  }
  return { batchSize: Number(batchSize) };
}

export function normalizeEmbedding(value: unknown): number[] {
  const vector = ArrayBuffer.isView(value)
    ? Array.from(value as unknown as ArrayLike<number>)
    : Array.isArray(value)
    ? value
    : null;
  if (
    !vector ||
    vector.length !== EMBEDDING_DIMENSIONS ||
    !vector.every((entry) => typeof entry === "number" && Number.isFinite(entry))
  ) {
    throw new EmbedPolicyError("embedding_contract_invalid", 502);
  }
  return vector as number[];
}
