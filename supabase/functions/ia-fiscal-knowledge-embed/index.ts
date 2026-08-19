import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.111.0";

import {
  assertKnowledgeSchedulerRequest,
  SchedulerAuthorizationError,
} from "../_shared/knowledge-scheduler-auth.ts";
import {
  EMBED_CONTRACT_VERSION,
  EmbedPolicyError,
  parseEmbedRequest,
  RETIRED_MODEL_REVISION,
} from "./policy.ts";

type JsonRecord = Record<string, unknown>;

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new EmbedPolicyError("embed_configuration_missing", 503);
  return value;
}

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

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  try {
    const client = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    await assertKnowledgeSchedulerRequest(request, client, "embed");
    if (request.method !== "POST") throw new EmbedPolicyError("method_not_allowed", 405);
    const { batchSize } = await parseEmbedRequest(request);

    console.info(JSON.stringify({
      event: "knowledge_embedding_retired_noop",
      correlation_id: correlationId,
      requested_batch_size: batchSize,
      claimed: 0,
      completed: 0,
      failed: 0,
      semantic_status: "unsupported_language",
      retired_model_revision: RETIRED_MODEL_REVISION,
    }));
    return json(200, {
      data: {
        claimed: 0,
        completed: 0,
        failed: 0,
        status: "retired_noop",
        semantic_status: "unsupported_language",
      },
      correlation_id: correlationId,
      contract_version: EMBED_CONTRACT_VERSION,
    });
  } catch (error) {
    const policyError = error instanceof SchedulerAuthorizationError
      ? new EmbedPolicyError("scheduler_authorization_failed", 403)
      : error instanceof EmbedPolicyError
      ? error
      : new EmbedPolicyError("knowledge_embedding_failed", 500);
    console.info(JSON.stringify({
      event: "knowledge_embedding_failed",
      correlation_id: correlationId,
      error_code: policyError.code,
    }));
    return json(policyError.status, {
      error: policyError.code,
      correlation_id: correlationId,
      contract_version: EMBED_CONTRACT_VERSION,
    });
  }
});
