import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { assertPublicRuntimeConfiguration, isBrowser, runtimeConfig } from "@/config/runtime";
import type { Database } from "@/types/database.generated";

let singleton: SupabaseClient<Database> | undefined;

export function getSupabaseClient(): SupabaseClient<Database> {
  if (singleton) return singleton;

  assertPublicRuntimeConfiguration();
  singleton = createClient<Database>(
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
  return singleton;
}

export function resetSupabaseClientForTests(): void {
  singleton = undefined;
}
