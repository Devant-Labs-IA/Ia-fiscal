import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

type SearchRequest = {
  municipality_id?: unknown;
  query?: unknown;
  limit?: unknown;
  offset?: unknown;
};

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_env:${name}`);
  return value;
}

function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get("origin")?.trim();
  const allowed = (Deno.env.get("IA_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  const headers: Record<string, string> = {
    "access-control-allow-headers":
      "authorization, apikey, content-type, x-client-info",
    "access-control-allow-methods": "POST, OPTIONS",
    "vary": "Origin",
  };

  if (origin && allowed.includes(origin)) {
    headers["access-control-allow-origin"] = origin;
  }
  return headers;
}

function json(
  request: Request,
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function toBoundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (typeof value !== "number" || !Number.isInteger(value)) return fallback;
  return Math.min(Math.max(value, minimum), maximum);
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(request),
    });
  }

  if (request.method !== "POST") {
    return json(request, 405, { error: "method_not_allowed" });
  }

  const authorization = request.headers.get("authorization")?.trim();
  if (!authorization?.toLowerCase().startsWith("bearer ")) {
    return json(request, 401, { error: "authorization_required" });
  }

  let body: SearchRequest;
  try {
    body = await request.json() as SearchRequest;
  } catch {
    return json(request, 400, { error: "invalid_json" });
  }

  const municipalityId = typeof body.municipality_id === "string"
    ? body.municipality_id.trim()
    : "";
  const query = typeof body.query === "string" ? body.query.trim() : "";
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(municipalityId)
  ) {
    return json(request, 400, { error: "invalid_municipality_id" });
  }
  if (query.length < 2 || query.length > 500) {
    return json(request, 400, { error: "invalid_query_length" });
  }

  const limit = toBoundedInteger(body.limit, 30, 1, 100);
  const offset = toBoundedInteger(body.offset, 0, 0, 10000);

  let supabaseUrl: string;
  let publishableKey: string;
  try {
    supabaseUrl = requiredEnv("SUPABASE_URL");
    publishableKey = requiredEnv("SUPABASE_ANON_KEY");
  } catch {
    return json(request, 503, { error: "search_configuration_missing" });
  }

  const supabase = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      headers: {
        authorization,
        "x-ia-search": "ia-fiscal-search-v1",
      },
    },
  });

  const token = authorization.slice("bearer ".length).trim();
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims(token);
  if (claimsError || !claimsData?.claims?.sub) {
    return json(request, 401, { error: "invalid_authorization" });
  }
  if (claimsData.claims.aal !== "aal2") {
    return json(request, 403, { error: "aal2_required" });
  }

  const { data, error } = await supabase.rpc("ia_search_fiscal", {
    p_municipality_id: municipalityId,
    p_query: query,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) {
    const denied = error.message.toLowerCase().includes("access denied");
    return json(request, denied ? 403 : 422, {
      error: denied ? "search_access_denied" : "search_execution_failed",
      code: error.code ?? null,
    });
  }

  return json(request, 200, {
    data,
    contract_version: "fiscal-search-v1",
  });
});
