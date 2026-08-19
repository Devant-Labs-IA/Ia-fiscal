import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.111.0";

import {
  KnowledgeSearchPolicyError,
  knowledgeSearchCorsHeaders,
  normalizeSearchEmbedding,
  parseKnowledgeSearchRequest,
  SEARCH_CONTRACT_VERSION,
  SEARCH_EMBEDDING_MODEL,
} from "./policy.ts";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new KnowledgeSearchPolicyError("search_configuration_missing", 503);
  return value;
}

function corsHeaders(request: Request): Record<string, string> {
  return knowledgeSearchCorsHeaders(
    request.headers.get("origin"),
    Deno.env.get("IA_ALLOWED_ORIGINS") ?? "",
  );
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

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  const startedAt = performance.now();
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(request) });
  }
  try {
    if (request.method !== "POST") {
      throw new KnowledgeSearchPolicyError("method_not_allowed", 405);
    }
    const authorization = request.headers.get("authorization")?.trim() ?? "";
    if (!authorization.toLowerCase().startsWith("bearer ")) {
      throw new KnowledgeSearchPolicyError("authorization_required", 401);
    }
    const token = authorization.slice("bearer ".length).trim();
    if (!token || token.length > 8_192) {
      throw new KnowledgeSearchPolicyError("invalid_authorization", 401);
    }
    const input = await parseKnowledgeSearchRequest(request);
    const client = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_ANON_KEY"),
      {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
          headers: {
            Authorization: authorization,
            "x-ia-knowledge-search": SEARCH_CONTRACT_VERSION,
          },
        },
      },
    );
    const { data: claimsData, error: claimsError } = await client.auth.getClaims(token);
    if (claimsError || !claimsData?.claims?.sub) {
      throw new KnowledgeSearchPolicyError("invalid_authorization", 401);
    }
    if (claimsData.claims.aal !== "aal2") {
      throw new KnowledgeSearchPolicyError("aal2_required", 403);
    }

    let queryEmbedding: string | null = null;
    try {
      const session = new Supabase.ai.Session(SEARCH_EMBEDDING_MODEL);
      const raw = await session.run(input.query, { mean_pool: true, normalize: true });
      queryEmbedding = JSON.stringify(normalizeSearchEmbedding(raw));
    } catch {
      // Lexical retrieval remains fail-closed to current, published tenant evidence.
      queryEmbedding = null;
    }

    const { data, error } = await client.rpc("ia_fiscal_hybrid_search_legal_knowledge", {
      p_municipality_id: input.municipalityId,
      p_query: input.query,
      p_query_embedding: queryEmbedding,
      p_limit: input.limit,
    });
    if (error) {
      const denied = error.code === "42501" || /access|required|denied/i.test(error.message);
      throw new KnowledgeSearchPolicyError(
        denied ? "knowledge_search_access_denied" : "knowledge_search_execution_failed",
        denied ? 403 : 422,
      );
    }
    const result = data && typeof data === "object" && !Array.isArray(data)
      ? data as Record<string, unknown>
      : {};
    const blockers = Array.isArray(result.blockers)
      ? result.blockers.filter((value): value is string => typeof value === "string").slice(0, 10)
      : [];
    const citationCount = Array.isArray(result.citations) ? result.citations.length : 0;
    console.info(JSON.stringify({
      event: "knowledge_search_succeeded",
      correlation_id: correlationId,
      municipality_id: input.municipalityId,
      answered: result.answered === true,
      blockers,
      citation_count: citationCount,
      retrieval_mode: typeof result.retrieval_mode === "string"
        ? result.retrieval_mode
        : "unknown",
      duration_ms: Math.max(0, Math.round(performance.now() - startedAt)),
    }));
    return json(request, 200, {
      data,
      correlation_id: correlationId,
      contract_version: SEARCH_CONTRACT_VERSION,
    });
  } catch (error) {
    const policyError = error instanceof KnowledgeSearchPolicyError
      ? error
      : new KnowledgeSearchPolicyError("knowledge_search_failed", 500);
    console.info(JSON.stringify({
      event: "knowledge_search_failed",
      correlation_id: correlationId,
      error_code: policyError.code,
    }));
    return json(request, policyError.status, {
      error: policyError.code,
      correlation_id: correlationId,
      contract_version: SEARCH_CONTRACT_VERSION,
    });
  }
});
