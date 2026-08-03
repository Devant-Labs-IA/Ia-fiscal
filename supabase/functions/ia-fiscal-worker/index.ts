import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

type JsonRecord = Record<string, unknown>;

type Job = {
  job_id: number;
  municipality_id: string;
  job_type: string;
  aggregate_type: string;
  aggregate_id: string;
  payload: JsonRecord;
  attempt_number: number;
  correlation_id: string;
};

const WORKER_NAME = "ia-fiscal-worker";
const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function response(status: number, body: JsonRecord): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_env:${name}`);
  return value;
}

function safeCode(error: unknown): string {
  if (error instanceof Error) {
    const normalized = error.message
      .replace(/[^a-zA-Z0-9:_-]/g, "_")
      .slice(0, 120);
    return normalized || "worker_error";
  }
  return "worker_error";
}

async function rpc<T>(
  supabase: SupabaseClient,
  name: string,
  args: JsonRecord,
): Promise<T> {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(`rpc_${name}:${error.code ?? "unknown"}`);
  return data as T;
}

async function heartbeat(
  supabase: SupabaseClient,
  workerId: string,
  stage: "started" | "completed" | "failed",
  claimedCount: number,
  result: JsonRecord,
): Promise<void> {
  await rpc(supabase, "ia_record_worker_heartbeat", {
    p_worker_name: WORKER_NAME,
    p_worker_id: workerId,
    p_stage: stage,
    p_claimed_count: claimedCount,
    p_result: result,
  });
}

async function completeJob(
  supabase: SupabaseClient,
  jobId: number,
  workerId: string,
): Promise<void> {
  await rpc(supabase, "ia_complete_job", {
    p_job_id: jobId,
    p_worker_id: workerId,
  });
}

async function failJob(
  supabase: SupabaseClient,
  jobId: number,
  workerId: string,
  code: string,
): Promise<void> {
  await rpc(supabase, "ia_fail_job", {
    p_job_id: jobId,
    p_worker_id: workerId,
    p_error_code: code.slice(0, 120),
    p_safe_error_detail: null,
  });
}

async function blockJob(
  supabase: SupabaseClient,
  jobId: number,
  workerId: string,
  code: string,
): Promise<void> {
  await rpc(supabase, "ia_block_job", {
    p_job_id: jobId,
    p_worker_id: workerId,
    p_reason_code: code.slice(0, 120),
    p_safe_detail: null,
  });
}

async function processCaseBatchItem(
  supabase: SupabaseClient,
  job: Job,
  workerId: string,
): Promise<string> {
  await rpc(supabase, "ia_process_case_batch_item", {
    p_batch_item_id: job.aggregate_id,
  });
  await completeJob(supabase, job.job_id, workerId);
  return "completed";
}

async function routeApprovedKnowledge(
  supabase: SupabaseClient,
  job: Job,
  workerId: string,
): Promise<string> {
  const result = await rpc<JsonRecord>(
    supabase,
    "ia_route_case_question_from_knowledge",
    { p_question_id: job.aggregate_id },
  );
  await completeJob(supabase, job.job_id, workerId);
  return typeof result.status === "string" ? result.status : "completed";
}

async function captureOnly(
  supabase: SupabaseClient,
  job: Job,
  workerId: string,
): Promise<string> {
  const reason = "sandbox_worker_external_io_disabled";

  if (job.job_type === "send_initial_notice") {
    await rpc(supabase, "ia_mark_notification_job_blocked", {
      p_job_id: job.job_id,
      p_reason: reason,
    });
  } else if (job.job_type === "generate_ai_draft") {
    await rpc(supabase, "ia_mark_ai_job_blocked", {
      p_job_id: job.job_id,
      p_reason: reason,
    });
  }

  await blockJob(supabase, job.job_id, workerId, reason);
  return "blocked";
}

async function processJob(
  supabase: SupabaseClient,
  job: Job,
  workerId: string,
): Promise<string> {
  switch (job.job_type) {
    case "process_case_batch_item":
      return await processCaseBatchItem(supabase, job, workerId);
    case "generate_ai_draft":
      return await routeApprovedKnowledge(supabase, job, workerId);
    case "send_initial_notice":
      return await captureOnly(supabase, job, workerId);
    default:
      await blockJob(
        supabase,
        job.job_id,
        workerId,
        "unsupported_job_type",
      );
      return "blocked";
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "GET") {
    return response(200, {
      status: "ok",
      service: WORKER_NAME,
      execution_enabled: Boolean(Deno.env.get("IA_WORKER_SECRET")),
      external_io: "disabled",
      approved_knowledge_routing: "enabled",
      mode: "sandbox",
    });
  }

  if (request.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }

  const expectedSecret = Deno.env.get("IA_WORKER_SECRET")?.trim();
  const suppliedSecret = request.headers.get("x-ia-worker-secret")?.trim();
  if (!expectedSecret || !suppliedSecret || suppliedSecret !== expectedSecret) {
    return response(403, { error: "worker_authorization_failed" });
  }

  let supabase: SupabaseClient;
  try {
    supabase = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
          headers: { "x-ia-worker": "ia-fiscal-worker-sandbox-v3" },
        },
      },
    );
  } catch {
    return response(503, { error: "worker_configuration_missing" });
  }

  const workerId = `edge:${crypto.randomUUID()}`;
  let jobs: Job[] = [];

  try {
    await heartbeat(supabase, workerId, "started", 0, {
      mode: "sandbox",
      external_io: "disabled",
    });
    jobs = await rpc<Job[]>(supabase, "ia_claim_jobs", {
      p_worker_id: workerId,
      p_limit: 1,
      p_lease_seconds: 180,
    });
  } catch (error) {
    try {
      await heartbeat(supabase, workerId, "failed", 0, {
        code: safeCode(error),
      });
    } catch {
      // The response remains safe even when observability is unavailable.
    }
    return response(500, { error: "job_claim_failed" });
  }

  const results: JsonRecord[] = [];
  for (const job of jobs) {
    try {
      const status = await processJob(supabase, job, workerId);
      results.push({ job_id: job.job_id, status });
    } catch (error) {
      const code = safeCode(error);
      try {
        await failJob(supabase, job.job_id, workerId, code);
        results.push({ job_id: job.job_id, status: "retry", error: code });
      } catch {
        results.push({
          job_id: job.job_id,
          status: "lease_recovery_required",
        });
      }
    }
  }

  try {
    await heartbeat(supabase, workerId, "completed", jobs.length, {
      mode: "sandbox",
      external_io: "disabled",
      results,
    });
  } catch {
    return response(500, {
      claimed: jobs.length,
      results,
      error: "worker_heartbeat_failed",
    });
  }

  return response(200, {
    claimed: jobs.length,
    results,
    mode: "sandbox",
    external_io: "disabled",
  });
});
