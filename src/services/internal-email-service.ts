import { getSupabaseClient } from "@/lib/supabase";

export interface InternalEmailDispatchResult {
  status: string;
  providerMessageId: string | null;
  processedAt: string | null;
  correlationId: string | null;
}

type DataError = { code?: string; message?: string } | null;
type DataResponse = { data: unknown; error: DataError };

type EdgeClient = {
  functions: {
    invoke(functionName: string, options: { body: Record<string, unknown> }): Promise<DataResponse>;
  };
};

function client(): EdgeClient {
  return getSupabaseClient() as unknown as EdgeClient;
}

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

export async function dispatchInternalEmail(outboxId: string): Promise<InternalEmailDispatchResult> {
  const response = await client().functions.invoke("ia-fiscal-email-dispatch", {
    body: { outbox_id: outboxId },
  });
  if (response.error) {
    throw new Error(response.error.code?.slice(0, 80) || "internal_email_dispatch_failed");
  }

  const data = objectValue(response.data);
  if (typeof data["error"] === "string") {
    throw new Error(String(data["error"]).slice(0, 120));
  }

  return {
    status: stringValue(data["status"]) || "provider_pending",
    providerMessageId: stringValue(data["provider_message_id"]) || null,
    processedAt: stringValue(data["processed_at"]) || null,
    correlationId: stringValue(data["correlation_id"]) || null,
  };
}
