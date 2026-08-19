import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { assertPublicRuntimeConfiguration, isBrowser, runtimeConfig } from "@/config/runtime";
import type { Database } from "@/types/database.generated";

let singleton: SupabaseClient<Database> | undefined;

function relaxMfaGateForHomologation(client: SupabaseClient<Database>): void {
  if (runtimeConfig.requireMfa) return;

  const mfa = client.auth.mfa;
  const getAuthenticatorAssuranceLevel = mfa.getAuthenticatorAssuranceLevel.bind(mfa);
  type AssuranceMethod = typeof mfa.getAuthenticatorAssuranceLevel;

  const relaxedAssurance: AssuranceMethod = async () => {
    const result = await getAuthenticatorAssuranceLevel();
    if (result.error || !result.data) return result;

    return {
      data: {
        ...result.data,
        currentLevel: "aal2",
        nextLevel: "aal2",
      },
      error: null,
    };
  };

  // O banco de homologação já aceita sessões AAL1. Esta ponte impede apenas
  // que a interface force o cadastro do autenticador durante os testes.
  Object.defineProperty(mfa, "getAuthenticatorAssuranceLevel", {
    configurable: true,
    value: relaxedAssurance,
  });
}

export function getSupabaseClient(): SupabaseClient<Database> {
  if (singleton) return singleton;

  assertPublicRuntimeConfiguration();
  const client = createClient<Database>(
    runtimeConfig.supabaseUrl,
    runtimeConfig.supabasePublishableKey,
    {
      auth: {
        persistSession: isBrowser(),
        autoRefreshToken: isBrowser(),
        detectSessionInUrl: isBrowser(),
      },
      global: {
        headers: {
          "x-ia-fiscal-client": "web-homologation-v1",
        },
      },
    },
  );

  relaxMfaGateForHomologation(client);
  singleton = client;
  return client;
}

export function resetSupabaseClientForTests(): void {
  singleton = undefined;
}
