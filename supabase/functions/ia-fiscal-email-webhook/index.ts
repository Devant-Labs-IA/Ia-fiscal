import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.111.0";
import { Webhook } from "npm:svix@1.79.0";

type Row = Record<string, unknown>;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_env:${name}`);
  return value;
}

function asObject(value: unknown): Row {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Row) : {};
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function stripHtml(value: string): string {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/\s+/g, " ")
    .trim();
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function parseOutboxId(to: string[]): string | null {
  for (const recipient of to) {
    const match = /(?:^|<)processo\+([0-9a-f-]{36})@/i.exec(recipient.trim());
    if (match?.[1] && UUID_PATTERN.test(match[1])) return match[1];
  }
  return null;
}

async function retrieveReceivedEmail(apiKey: string, emailId: string): Promise<Row | null> {
  const response = await fetch(
    `https://api.resend.com/emails/receiving/${encodeURIComponent(emailId)}`,
    {
      headers: { authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(20_000),
    },
  );
  if (!response.ok) return null;
  return asObject(await response.json());
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  let webhookSecret: string;
  let resendApiKey: string;
  let supabaseUrl: string;
  let serviceRoleKey: string;
  try {
    webhookSecret = env("RESEND_WEBHOOK_SECRET");
    resendApiKey = env("RESEND_API_KEY");
    supabaseUrl = env("SUPABASE_URL");
    serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
  } catch {
    return json(503, { error: "webhook_configuration_missing" });
  }

  const rawBody = await request.text();
  const svixId = request.headers.get("svix-id")?.trim() ?? "";
  const svixTimestamp = request.headers.get("svix-timestamp")?.trim() ?? "";
  const svixSignature = request.headers.get("svix-signature")?.trim() ?? "";
  if (!svixId || !svixTimestamp || !svixSignature) {
    return json(400, { error: "webhook_signature_missing" });
  }

  let verified: unknown;
  try {
    verified = new Webhook(webhookSecret).verify(rawBody, {
      "svix-id": svixId,
      "svix-timestamp": svixTimestamp,
      "svix-signature": svixSignature,
    });
  } catch {
    return json(400, { error: "invalid_webhook_signature" });
  }

  const event = asObject(verified);
  const eventType = stringValue(event.type);
  const data = asObject(event.data);
  const providerMessageId = stringValue(data.email_id);
  const eventCreatedAt = stringValue(event.created_at) || new Date().toISOString();
  const payloadHash = await sha256(rawBody);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let outboxId: string | null = null;
  let municipalityId: string | null = null;
  let outbox: Row | null = null;

  if (eventType === "email.received") {
    outboxId = parseOutboxId(stringArray(data.to));
    if (outboxId) {
      const { data: outboxData } = await admin
        .from("homologation_notification_outbox")
        .select("*")
        .eq("id", outboxId)
        .maybeSingle();
      outbox = outboxData ? asObject(outboxData) : null;
      municipalityId = outbox ? stringValue(outbox.municipality_id) : null;
    }
  } else if (providerMessageId) {
    const { data: outboxData } = await admin
      .from("homologation_notification_outbox")
      .select("*")
      .eq("provider_code", "resend")
      .eq("provider_message_id", providerMessageId)
      .maybeSingle();
    outbox = outboxData ? asObject(outboxData) : null;
    outboxId = outbox ? stringValue(outbox.id) : null;
    municipalityId = outbox ? stringValue(outbox.municipality_id) : null;
  }

  if (!outbox || !outboxId || !municipalityId) {
    console.info(
      JSON.stringify({
        event: "email_webhook_unmatched",
        provider_event_type: eventType,
        provider_event_id: svixId,
      }),
    );
    return json(200, { received: true, matched: false });
  }

  const safePayload = {
    event_type: eventType,
    outbox_id: outboxId,
    provider_message_id: providerMessageId || null,
    attachment_count: Array.isArray(data.attachments) ? data.attachments.length : 0,
  };

  await admin.rpc("ia_record_email_provider_event", {
    p_municipality_id: municipalityId,
    p_provider_event_id: svixId,
    p_provider_message_id: providerMessageId || null,
    p_event_type: eventType,
    p_payload_sha256: payloadHash,
    p_safe_payload: safePayload,
    p_occurred_at: eventCreatedAt,
  });

  if (eventType === "email.received") {
    const received = await retrieveReceivedEmail(resendApiKey, providerMessageId);
    if (!received) {
      return json(502, { error: "received_email_retrieval_failed" });
    }

    const text = stringValue(received.text);
    const html = stringValue(received.html);
    const bodyText = (text || stripHtml(html)).slice(0, 20_000);
    const attachments = Array.isArray(received.attachments) ? received.attachments : [];
    const from = stringValue(received.from || data.from).trim().toLowerCase();
    const to = stringArray(received.to).length > 0 ? stringArray(received.to) : stringArray(data.to);

    const { data: stored, error: storeError } = await admin.rpc(
      "ia_store_internal_inbound_email",
      {
        p_outbox_id: outboxId,
        p_provider_email_id: providerMessageId,
        p_provider_message_id: stringValue(received.message_id || data.message_id) || null,
        p_from_email: from,
        p_to_emails: to,
        p_subject: stringValue(received.subject || data.subject),
        p_body_text: bodyText,
        p_attachments_count: attachments.length,
        p_received_at: stringValue(received.created_at || data.created_at) || eventCreatedAt,
      },
    );
    if (storeError) {
      console.error(
        JSON.stringify({
          event: "internal_email_store_failed",
          outbox_id: outboxId,
          code: storeError.code,
        }),
      );
      return json(422, { error: "internal_email_store_failed" });
    }

    return json(200, { received: true, matched: true, result: stored });
  }

  const statusByEvent: Record<string, string> = {
    "email.sent": "sent",
    "email.delivered": "delivered",
    "email.bounced": "bounced",
    "email.failed": "failed",
  };
  const nextStatus = statusByEvent[eventType];
  if (nextStatus) {
    const patch: Record<string, unknown> = {
      status: nextStatus,
      last_event_at: eventCreatedAt,
      safe_error_code:
        nextStatus === "bounced"
          ? "email_bounced"
          : nextStatus === "failed"
            ? "email_delivery_failed"
            : null,
    };
    if (nextStatus === "delivered") patch.delivered_at = eventCreatedAt;
    if (["sent", "delivered", "failed", "bounced"].includes(nextStatus)) {
      patch.processed_at = eventCreatedAt;
    }
    await admin.from("homologation_notification_outbox").update(patch).eq("id", outboxId);
  }

  return json(200, { received: true, matched: true, status: nextStatus ?? "ignored" });
});
