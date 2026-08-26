import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.111.0";

type Row = Record<string, unknown>;

type DispatchRequest = {
  outbox_id?: unknown;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CANONICAL_APP_ORIGIN = "https://ia-fiscal-homologacao.vercel.app";
const INTERNAL_SEND_ROLES = new Set([
  "municipal_admin",
  "supervisor",
  "fiscal_auditor",
  "legal_reviewer",
]);

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_env:${name}`);
  return value;
}

function configuredOrigins(): Set<string> {
  return new Set([
    CANONICAL_APP_ORIGIN,
    ...(Deno.env.get("IA_ALLOWED_ORIGINS") ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  ]);
}

function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get("origin")?.trim() ?? "";
  const headers: Record<string, string> = {
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
    "access-control-allow-methods": "POST, OPTIONS",
    vary: "Origin",
  };
  if (configuredOrigins().has(origin)) headers["access-control-allow-origin"] = origin;
  return headers;
}

function json(request: Request, status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asObject(value: unknown): Row {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Row) : {};
}

function blockedContent(subject: string, body: string): string | null {
  const content = `${subject}\n${body}`;
  if (/(https?:\/\/|www\.|href\s*=|<a(?:\s|>))/i.test(content)) return "link_not_allowed";
  if (/(?:r\$|\bbrl\b|(?:^|\s)\d{1,3}(?:\.\d{3})*,\d{2}(?:\s|$))/i.test(content)) {
    return "monetary_value_not_allowed";
  }
  if (/\b(anexo|anexos|anexa|anexado|attachment|attachments)\b/i.test(content)) {
    return "attachment_not_allowed";
  }
  if (subject.trim().length < 5 || subject.trim().length > 180) return "invalid_subject";
  if (body.trim().length < 40 || body.trim().length > 5_000) return "invalid_body";
  return null;
}

function inboundReplyAddress(outboxId: string): string | null {
  const domain = Deno.env.get("EMAIL_INBOUND_DOMAIN")?.trim().toLowerCase() ?? "";
  if (!/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(domain)) {
    return null;
  }
  return `processo+${outboxId}@${domain}`;
}

async function userCanDispatch(
  admin: ReturnType<typeof createClient>,
  userId: string,
  municipalityId: string,
  requestedBy: string,
): Promise<boolean> {
  if (userId === requestedBy) return true;

  const { data: platformAdmin } = await admin
    .from("platform_administrators")
    .select("user_id")
    .eq("user_id", userId)
    .eq("active", true)
    .is("revoked_at", null)
    .maybeSingle();
  if (platformAdmin) return true;

  const { data: membership } = await admin
    .from("municipality_memberships")
    .select("role")
    .eq("municipality_id", municipalityId)
    .eq("user_id", userId)
    .eq("status", "active")
    .lte("valid_from", new Date().toISOString())
    .or(`valid_until.is.null,valid_until.gt.${new Date().toISOString()}`)
    .maybeSingle();

  return Boolean(membership && INTERNAL_SEND_ROLES.has(stringValue(membership.role)));
}

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(request) });
  }
  if (request.method !== "POST") {
    return json(request, 405, { error: "method_not_allowed", correlation_id: correlationId });
  }

  const authorization = request.headers.get("authorization")?.trim() ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return json(request, 401, { error: "authorization_required", correlation_id: correlationId });
  }

  let body: DispatchRequest;
  try {
    body = (await request.json()) as DispatchRequest;
  } catch {
    return json(request, 400, { error: "invalid_json", correlation_id: correlationId });
  }

  const outboxId = stringValue(body.outbox_id).trim();
  if (!UUID_PATTERN.test(outboxId)) {
    return json(request, 400, { error: "invalid_outbox_id", correlation_id: correlationId });
  }

  let supabaseUrl: string;
  let publishableKey: string;
  let serviceRoleKey: string;
  try {
    supabaseUrl = env("SUPABASE_URL");
    publishableKey = env("SUPABASE_ANON_KEY");
    serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
  } catch {
    return json(request, 503, {
      error: "email_dispatch_configuration_missing",
      correlation_id: correlationId,
    });
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const token = authorization.slice("bearer ".length).trim();
  const { data: claimsData, error: claimsError } = await userClient.auth.getClaims(token);
  const userId = typeof claimsData?.claims?.sub === "string" ? claimsData.claims.sub : "";
  if (claimsError || !UUID_PATTERN.test(userId)) {
    return json(request, 401, { error: "invalid_authorization", correlation_id: correlationId });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: outboxData, error: outboxError } = await admin
    .from("homologation_notification_outbox")
    .select("*")
    .eq("id", outboxId)
    .maybeSingle();
  if (outboxError || !outboxData) {
    return json(request, 404, { error: "outbox_not_found", correlation_id: correlationId });
  }

  const outbox = asObject(outboxData);
  const municipalityId = stringValue(outbox.municipality_id);
  const requestedBy = stringValue(outbox.requested_by);
  if (!(await userCanDispatch(admin, userId, municipalityId, requestedBy))) {
    return json(request, 403, { error: "email_dispatch_denied", correlation_id: correlationId });
  }

  const currentStatus = stringValue(outbox.status);
  if (["sent", "delivered"].includes(currentStatus)) {
    return json(request, 200, {
      status: currentStatus,
      provider_message_id: outbox.provider_message_id ?? null,
      correlation_id: correlationId,
      idempotent: true,
    });
  }
  if (["cancelled", "bounced"].includes(currentStatus)) {
    return json(request, 409, {
      error: "outbox_not_dispatchable",
      status: currentStatus,
      correlation_id: correlationId,
    });
  }

  const recipientEmail = stringValue(outbox.recipient_email).trim().toLowerCase();
  const subject = stringValue(outbox.subject).trim();
  const messageText = stringValue(outbox.body_text).trim();
  const blocker = blockedContent(subject, messageText);
  if (blocker) {
    await admin
      .from("homologation_notification_outbox")
      .update({ status: "failed", safe_error_code: blocker, processed_at: new Date().toISOString() })
      .eq("id", outboxId);
    return json(request, 422, { error: blocker, correlation_id: correlationId });
  }

  const { data: allowlist } = await admin
    .from("homologation_email_allowlist")
    .select("user_id, email, status")
    .eq("municipality_id", municipalityId)
    .eq("user_id", stringValue(outbox.recipient_user_id))
    .eq("status", "active")
    .maybeSingle();
  if (!allowlist || stringValue(allowlist.email).trim().toLowerCase() !== recipientEmail) {
    return json(request, 403, { error: "recipient_not_allowlisted", correlation_id: correlationId });
  }

  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim();
  const from = Deno.env.get("EMAIL_FROM")?.trim();
  if (!apiKey || !from) {
    await admin
      .from("homologation_notification_outbox")
      .update({ status: "provider_pending", safe_error_code: "email_provider_not_configured" })
      .eq("id", outboxId);
    return json(request, 503, {
      error: "email_provider_not_configured",
      status: "provider_pending",
      correlation_id: correlationId,
    });
  }

  const replyAddress = inboundReplyAddress(outboxId) ?? Deno.env.get("EMAIL_REPLY_TO")?.trim() ?? null;
  const attemptedAt = new Date().toISOString();
  const nextAttemptCount = Number(outbox.attempt_count ?? 0) + 1;
  const { error: claimError } = await admin
    .from("homologation_notification_outbox")
    .update({
      status: "processing",
      provider_code: "resend",
      attempt_count: nextAttemptCount,
      last_attempt_at: attemptedAt,
      safe_error_code: null,
      reply_address: replyAddress,
    })
    .eq("id", outboxId)
    .in("status", ["provider_pending", "failed", "processing"]);
  if (claimError) {
    return json(request, 409, { error: "outbox_claim_failed", correlation_id: correlationId });
  }

  const providerPayload: Record<string, unknown> = {
    from,
    to: [recipientEmail],
    subject,
    text: messageText,
    tags: [
      { name: "system", value: "ia_fiscal" },
      { name: "outbox_id", value: outboxId },
    ],
  };
  if (replyAddress) providerPayload.reply_to = replyAddress;

  let providerResponse: Response;
  try {
    providerResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
        "idempotency-key": `ia-fiscal-${outboxId}`,
      },
      body: JSON.stringify(providerPayload),
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    await admin
      .from("homologation_notification_outbox")
      .update({ status: "failed", safe_error_code: "email_provider_unavailable" })
      .eq("id", outboxId);
    return json(request, 502, {
      error: "email_provider_unavailable",
      correlation_id: correlationId,
    });
  }

  const providerBody = asObject(await providerResponse.json().catch(() => ({})));
  const providerMessageId = stringValue(providerBody.id);
  if (!providerResponse.ok || !providerMessageId) {
    await admin
      .from("homologation_notification_outbox")
      .update({
        status: "failed",
        safe_error_code: `email_provider_${providerResponse.status}`,
        processed_at: new Date().toISOString(),
      })
      .eq("id", outboxId);
    return json(request, 502, {
      error: "email_provider_rejected",
      provider_status: providerResponse.status,
      correlation_id: correlationId,
    });
  }

  const processedAt = new Date().toISOString();
  const { error: updateError } = await admin
    .from("homologation_notification_outbox")
    .update({
      status: "sent",
      provider_code: "resend",
      provider_message_id: providerMessageId,
      safe_error_code: null,
      processed_at: processedAt,
      last_event_at: processedAt,
    })
    .eq("id", outboxId);
  if (updateError) {
    return json(request, 500, {
      error: "provider_sent_but_state_update_failed",
      provider_message_id: providerMessageId,
      correlation_id: correlationId,
    });
  }

  console.info(
    JSON.stringify({
      event: "internal_email_sent",
      correlation_id: correlationId,
      outbox_id: outboxId,
      municipality_id: municipalityId,
      provider: "resend",
    }),
  );

  return json(request, 200, {
    status: "sent",
    provider_message_id: providerMessageId,
    processed_at: processedAt,
    correlation_id: correlationId,
  });
});
