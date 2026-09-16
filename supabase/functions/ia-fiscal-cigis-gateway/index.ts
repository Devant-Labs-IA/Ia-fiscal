import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Alias técnico temporário para clientes da primeira versão.
// Toda a lógica canônica está em ia-fiscal-sigis-gateway.
Deno.serve(async (request: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  if (!supabaseUrl) {
    return new Response(
      JSON.stringify({ error: "sigis_gateway_configuration_missing" }),
      {
        status: 503,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
        },
      },
    );
  }

  const headers = new Headers();
  for (const name of ["authorization", "apikey", "content-type", "origin", "x-client-info"]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }

  try {
    const upstream = await fetch(`${supabaseUrl.replace(/\/$/, "")}/functions/v1/ia-fiscal-sigis-gateway`, {
      method: request.method,
      headers,
      body: request.method === "GET" || request.method === "HEAD" ? undefined : request.body,
      signal: AbortSignal.timeout(30_000),
      redirect: "error",
    });

    const responseHeaders = new Headers();
    for (const name of [
      "content-type",
      "cache-control",
      "access-control-allow-origin",
      "access-control-allow-headers",
      "access-control-allow-methods",
      "vary",
    ]) {
      const value = upstream.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }
    responseHeaders.set("x-compatibility-alias", "ia-fiscal-sigis-gateway");

    return new Response(upstream.body, {
      status: upstream.status,
      headers: responseHeaders,
    });
  } catch {
    return new Response(JSON.stringify({ error: "sigis_gateway_unavailable" }), {
      status: 503,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      },
    });
  }
});
