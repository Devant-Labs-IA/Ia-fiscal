import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.111.0";

type Row = Record<string, unknown>;

type CigisAction =
  | "overview"
  | "taxpayer"
  | "regime"
  | "debts"
  | "payment"
  | "current_account"
  | "history"
  | "inspections";

type GatewayRequest = {
  municipality_id?: unknown;
  taxpayer_id?: unknown;
  tax_id?: unknown;
  action?: unknown;
  competence?: unknown;
  from_date?: unknown;
  to_date?: unknown;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COMPETENCE_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const ACTIONS = new Set<CigisAction>([
  "overview",
  "taxpayer",
  "regime",
  "debts",
  "payment",
  "current_account",
  "history",
  "inspections",
]);
const CANONICAL_APP_ORIGIN = "https://ia-fiscal-homologacao.vercel.app";

let oauthCache: { token: string; expiresAt: number } | null = null;

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

function nullableUuid(value: unknown): string | null {
  const normalized = stringValue(value).trim();
  return UUID_PATTERN.test(normalized) ? normalized : null;
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

async function hashIdentifier(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .slice(0, 8)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function cigisHeaders(): Promise<Record<string, string>> {
  const clientId = Deno.env.get("CIGIS_CLIENT_ID")?.trim();
  const clientSecret = Deno.env.get("CIGIS_CLIENT_SECRET")?.trim();
  const tokenUrl = Deno.env.get("CIGIS_TOKEN_URL")?.trim();

  if (clientId && clientSecret && tokenUrl) {
    if (oauthCache && oauthCache.expiresAt > Date.now() + 30_000) {
      return { authorization: `Bearer ${oauthCache.token}` };
    }

    const form = new URLSearchParams({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
    });
    const scope = Deno.env.get("CIGIS_SCOPE")?.trim();
    if (scope) form.set("scope", scope);

    const response = await fetch(tokenUrl, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: form,
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) throw new Error("cigis_oauth_failed");
    const payload = asObject(await response.json());
    const token = stringValue(payload.access_token);
    if (!token) throw new Error("cigis_oauth_token_missing");
    const expiresIn = Number(payload.expires_in ?? 300);
    oauthCache = {
      token,
      expiresAt: Date.now() + Math.max(60, Number.isFinite(expiresIn) ? expiresIn : 300) * 1_000,
    };
    return { authorization: `Bearer ${token}` };
  }

  const apiKey = Deno.env.get("CIGIS_API_KEY")?.trim();
  if (apiKey) {
    const headerName = (Deno.env.get("CIGIS_API_KEY_HEADER")?.trim() || "x-api-key").toLowerCase();
    if (!/^[a-z0-9-]{2,80}$/.test(headerName)) throw new Error("invalid_cigis_api_key_header");
    return { [headerName]: apiKey };
  }

  throw new Error("cigis_credentials_missing");
}

function buildPath(
  prefix: string,
  action: Exclude<CigisAction, "overview">,
  taxId: string,
  competence: string | null,
  fromDate: string | null,
  toDate: string | null,
): string {
  const base = `${prefix}/contribuintes/${encodeURIComponent(taxId)}`;
  const pathByAction: Record<Exclude<CigisAction, "overview">, string> = {
    taxpayer: base,
    regime: `${base}/regime`,
    debts: `${base}/debitos`,
    payment: `${base}/pagamentos`,
    current_account: `${base}/conta-corrente`,
    history: `${base}/historico`,
    inspections: `${base}/fiscalizacoes`,
  };
  const url = new URL(pathByAction[action], "https://contract.local");
  if (competence) url.searchParams.set("competencia", competence);
  if (fromDate) url.searchParams.set("data_inicial", fromDate);
  if (toDate) url.searchParams.set("data_final", toDate);
  return `${url.pathname}${url.search}`;
}

async function fetchCigis(
  baseUrl: string,
  path: string,
  headers: Record<string, string>,
  correlationId: string,
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const response = await fetch(new URL(path, `${baseUrl.replace(/\/$/, "")}/`), {
    headers: {
      ...headers,
      accept: "application/json",
      "x-correlation-id": correlationId,
      "user-agent": "ia-fiscal-cigis-gateway/1.0",
    },
    signal: AbortSignal.timeout(15_000),
  });

  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 1_500_000) {
    return { ok: false, status: 502, data: { error: "cigis_response_too_large" } };
  }

  const data = await response.json().catch(() => null);
  return { ok: response.ok, status: response.status, data };
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

  let body: GatewayRequest;
  try {
    body = (await request.json()) as GatewayRequest;
  } catch {
    return json(request, 400, { error: "invalid_json", correlation_id: correlationId });
  }

  const municipalityId = stringValue(body.municipality_id).trim();
  const taxpayerId = nullableUuid(body.taxpayer_id);
  const taxId = stringValue(body.tax_id).replace(/\D/g, "");
  const action = stringValue(body.action).trim() as CigisAction;
  const competence = stringValue(body.competence).trim() || null;
  const fromDate = stringValue(body.from_date).trim() || null;
  const toDate = stringValue(body.to_date).trim() || null;

  if (!UUID_PATTERN.test(municipalityId)) {
    return json(request, 400, { error: "invalid_municipality_id", correlation_id: correlationId });
  }
  if (!ACTIONS.has(action)) {
    return json(request, 400, { error: "invalid_action", correlation_id: correlationId });
  }
  if (!taxpayerId && ![11, 14].includes(taxId.length)) {
    return json(request, 400, { error: "taxpayer_context_required", correlation_id: correlationId });
  }
  if (competence && !COMPETENCE_PATTERN.test(competence)) {
    return json(request, 400, { error: "invalid_competence", correlation_id: correlationId });
  }
  if ((fromDate && !DATE_PATTERN.test(fromDate)) || (toDate && !DATE_PATTERN.test(toDate))) {
    return json(request, 400, { error: "invalid_date_filter", correlation_id: correlationId });
  }

  let supabaseUrl: string;
  let publishableKey: string;
  try {
    supabaseUrl = env("SUPABASE_URL");
    publishableKey = env("SUPABASE_ANON_KEY");
  } catch {
    return json(request, 503, { error: "gateway_configuration_missing", correlation_id: correlationId });
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const token = authorization.slice("bearer ".length).trim();
  const { data: claimsData, error: claimsError } = await userClient.auth.getClaims(token);
  if (claimsError || !claimsData?.claims?.sub) {
    return json(request, 401, { error: "invalid_authorization", correlation_id: correlationId });
  }

  const { data: accessData, error: accessError } = await userClient.rpc(
    "ia_cigis_resolve_access" as never,
    {
      p_municipality_id: municipalityId,
      p_taxpayer_id: taxpayerId,
      p_tax_id: taxId || null,
    } as never,
  );
  if (accessError) {
    const denied = accessError.code === "42501";
    return json(request, denied ? 403 : 404, {
      error: denied ? "cigis_access_denied" : "cigis_taxpayer_not_found",
      correlation_id: correlationId,
    });
  }

  const access = asObject(accessData);
  const authorizedTaxId = stringValue(access.tax_id);
  const authorizedTaxpayerId = stringValue(access.taxpayer_id);
  if (![11, 14].includes(authorizedTaxId.length) || !UUID_PATTERN.test(authorizedTaxpayerId)) {
    return json(request, 422, { error: "invalid_authorized_context", correlation_id: correlationId });
  }

  const baseUrl = Deno.env.get("CIGIS_BASE_URL")?.trim();
  if (!baseUrl) {
    return json(request, 503, {
      error: "cigis_not_configured",
      configured: false,
      correlation_id: correlationId,
    });
  }

  let authHeaders: Record<string, string>;
  try {
    authHeaders = await cigisHeaders();
  } catch (error) {
    return json(request, 503, {
      error: error instanceof Error ? error.message : "cigis_credentials_missing",
      configured: false,
      correlation_id: correlationId,
    });
  }

  const prefix = (Deno.env.get("CIGIS_API_PREFIX")?.trim() || "/api/v1").replace(/\/$/, "");
  const execute = (requestedAction: Exclude<CigisAction, "overview">) =>
    fetchCigis(
      baseUrl,
      buildPath(prefix, requestedAction, authorizedTaxId, competence, fromDate, toDate),
      authHeaders,
      correlationId,
    );

  let result: unknown;
  if (action === "overview") {
    const [taxpayer, regime, debts, currentAccount, inspections] = await Promise.all([
      execute("taxpayer"),
      execute("regime"),
      execute("debts"),
      execute("current_account"),
      execute("inspections"),
    ]);
    result = {
      taxpayer: taxpayer.ok ? taxpayer.data : null,
      regime: regime.ok ? regime.data : null,
      debts: debts.ok ? debts.data : null,
      current_account: currentAccount.ok ? currentAccount.data : null,
      inspections: inspections.ok ? inspections.data : null,
      upstream_status: {
        taxpayer: taxpayer.status,
        regime: regime.status,
        debts: debts.status,
        current_account: currentAccount.status,
        inspections: inspections.status,
      },
    };
  } else {
    const upstream = await execute(action);
    if (!upstream.ok) {
      return json(request, upstream.status === 404 ? 404 : 502, {
        error: upstream.status === 404 ? "cigis_record_not_found" : "cigis_upstream_error",
        upstream_status: upstream.status,
        correlation_id: correlationId,
      });
    }
    result = upstream.data;
  }

  console.info(
    JSON.stringify({
      event: "cigis_query_completed",
      correlation_id: correlationId,
      municipality_id: municipalityId,
      taxpayer_hash: await hashIdentifier(authorizedTaxId),
      action,
    }),
  );

  return json(request, 200, {
    configured: true,
    action,
    taxpayer_id: authorizedTaxpayerId,
    data: result,
    source: "cigis_api",
    fetched_at: new Date().toISOString(),
    correlation_id: correlationId,
  });
});
