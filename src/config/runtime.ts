const DEFAULT_SUPABASE_URL = "https://qvgenxcrdrqyiyozxtdt.supabase.co";
const DEFAULT_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Frt254fLpExL7A52zWNCnw_ZXLP7k33";

export type DataMode = "supabase" | "mock";

function readBoolean(value: string | undefined, fallback: boolean): boolean {
  if (value == null || value.trim() === "") return fallback;
  return value.trim().toLowerCase() === "true";
}

export const runtimeConfig = {
  environment: import.meta.env["VITE_APP_ENV"] ?? "homologation",
  dataMode: (import.meta.env["VITE_DATA_MODE"] ?? "supabase") as DataMode,
  allowDemo: readBoolean(import.meta.env["VITE_ALLOW_DEMO"], false),
  supabaseUrl: import.meta.env["VITE_SUPABASE_URL"] ?? DEFAULT_SUPABASE_URL,
  supabasePublishableKey:
    import.meta.env["VITE_SUPABASE_PUBLISHABLE_KEY"] ?? DEFAULT_SUPABASE_PUBLISHABLE_KEY,
  municipalityLabel: import.meta.env["VITE_MUNICIPALITY_LABEL"] ?? "Cordeirópolis/SP",
  municipalityIbge: import.meta.env["VITE_MUNICIPALITY_IBGE"] ?? "3512407",
  timezone: import.meta.env["VITE_APP_TIMEZONE"] ?? "America/Sao_Paulo",
} as const;

const DEMO_STORAGE_KEY = "ia-fiscal:demo-mode";

export function isBrowser(): boolean {
  return typeof window !== "undefined";
}

export function isDemoMode(): boolean {
  if (!runtimeConfig.allowDemo) return false;
  if (runtimeConfig.dataMode === "mock") return true;
  if (!isBrowser()) return false;
  return window.sessionStorage.getItem(DEMO_STORAGE_KEY) === "true";
}

export function setDemoMode(enabled: boolean): void {
  if (!isBrowser()) return;
  if (enabled && !runtimeConfig.allowDemo) {
    window.sessionStorage.removeItem(DEMO_STORAGE_KEY);
    return;
  }
  if (enabled) window.sessionStorage.setItem(DEMO_STORAGE_KEY, "true");
  else window.sessionStorage.removeItem(DEMO_STORAGE_KEY);
}

export function assertPublicRuntimeConfiguration(): void {
  if (!runtimeConfig.supabaseUrl.startsWith("https://")) {
    throw new Error("invalid_supabase_url");
  }
  if (!runtimeConfig.supabasePublishableKey.startsWith("sb_publishable_")) {
    throw new Error("invalid_supabase_publishable_key");
  }
}
