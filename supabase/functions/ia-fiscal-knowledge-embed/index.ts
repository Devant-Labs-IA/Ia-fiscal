import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.111.0";

import {
  assertKnowledgeSchedulerRequest,
  SchedulerAuthorizationError,
} from "../_shared/knowledge-scheduler-auth.ts";
import {
  EMBED_CONTRACT_VERSION,
  EMBEDDING_DIMENSIONS,
  EMBEDDING_MODEL,
  EMBEDDING_MODEL_REVISION,
  EmbedPolicyError,
  normalizeEmbedding,
  parseEmbedRequest,
} from "./policy.ts";

type JsonRecord = Record<string, unknown>;
type EmbeddingJob = {
  job_id: string;
  content_text: string;
  provider_code: "supabase_ai";
  model: "gte-small";
  model_revision: "gte-small-384-v1";
  dimensions: 384;
};

const BATCH_DEADLINE_MS = 45_000;
const SINGLE_EMBED_TIMEOUT_MS = 8_000;

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

function isJob(value: unknown): value is EmbeddingJob {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const job = value as JsonRecord;
  return typeof job.job_id === "string" &&
    typeof job.content_text === "string" &&
    job.content_text.length >= 80 && job.content_text.length <= 8_000 &&
    job.provider_code === "supabase_ai" &&
    job.model === EMBEDDING_MODEL &&
    job.model_revision === EMBEDDING_MODEL_REVISION &&
    job.dimensions === EMBEDDING_DIMENSIONS;
}

async function failJob(client: SupabaseClient, jobId: string, code: string): Promise<void> {
  await client.rpc("ia_fiscal_fail_legal_embedding_job", {
    p_job_id: jobId,
    p_error_code: code,
  });
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(
      () => reject(new EmbedPolicyError("embedding_generation_timeout", 504)),
      timeoutMs,
    );
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  const startedAt = Date.now();
  try {
    const client = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    await assertKnowledgeSchedulerRequest(request, client, "embed");
    if (request.method !== "POST") throw new EmbedPolicyError("method_not_allowed", 405);
    const { batchSize } = await parseEmbedRequest(request);
    const { data, error } = await client.rpc("ia_fiscal_claim_legal_embedding_jobs", {
      p_batch_size: batchSize,
    });
    if (error || !Array.isArray(data) || !data.every(isJob)) {
      throw new EmbedPolicyError("embedding_job_contract_invalid", 503);
    }

    const session = new Supabase.ai.Session(EMBEDDING_MODEL);
    let completed = 0;
    let failed = 0;
    for (let index = 0; index < data.length; index += 1) {
      const job = data[index];
      if (Date.now() - startedAt >= BATCH_DEADLINE_MS) {
        for (const unprocessed of data.slice(index)) {
          await failJob(client, unprocessed.job_id, "embedding_batch_deadline_exceeded")
            .catch(() => undefined);
          failed += 1;
        }
        break;
      }
      try {
        const output = await withTimeout(
          session.run(job.content_text, { mean_pool: true, normalize: true }),
          SINGLE_EMBED_TIMEOUT_MS,
        );
        const embedding = normalizeEmbedding(output);
        const completion = await client.rpc("ia_fiscal_complete_legal_embedding_job", {
          p_job_id: job.job_id,
          p_embedding: JSON.stringify(embedding),
        });
        if (completion.error) throw new EmbedPolicyError("embedding_persist_failed", 503);
        completed += 1;
      } catch (error) {
        failed += 1;
        const code = error instanceof EmbedPolicyError
          ? error.code
          : "embedding_generation_failed";
        await failJob(client, job.job_id, code).catch(() => undefined);
      }
    }

    console.info(JSON.stringify({
      event: "knowledge_embedding_batch_completed",
      correlation_id: correlationId,
      claimed: data.length,
      completed,
      failed,
      model_revision: EMBEDDING_MODEL_REVISION,
    }));
    return json(failed > 0 ? 207 : 200, {
      data: { claimed: data.length, completed, failed },
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
