import type { SupabaseClient } from "npm:@supabase/supabase-js@2.111.0";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class SchedulerAuthorizationError extends Error {
  readonly status = 403;

  constructor() {
    super("scheduler_authorization_failed");
    this.name = "SchedulerAuthorizationError";
  }
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function assertKnowledgeSchedulerRequest(
  request: Request,
  serviceClient: SupabaseClient,
  scope: "ingest" | "embed",
): Promise<void> {
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new SchedulerAuthorizationError();
  }
  const secret = authorization.slice("bearer ".length).trim();
  const nonce = request.headers.get("x-ia-scheduler-nonce")?.trim() ?? "";
  const issuedAt = request.headers.get("x-ia-scheduler-issued-at")?.trim() ?? "";
  if (!secret || secret.length > 512 || !UUID_PATTERN.test(nonce)) {
    throw new SchedulerAuthorizationError();
  }
  const parsedIssuedAt = Date.parse(issuedAt);
  if (!Number.isFinite(parsedIssuedAt)) throw new SchedulerAuthorizationError();

  const { data, error } = await serviceClient.rpc(
    "ia_fiscal_validate_knowledge_scheduler_request",
    {
      p_secret_sha256: await sha256Hex(secret),
      p_nonce: nonce,
      p_issued_at: new Date(parsedIssuedAt).toISOString(),
      p_scope: scope,
    },
  );
  if (error || data !== true) throw new SchedulerAuthorizationError();
}
