import { describe, expect, it } from "vitest";

import { assertPublicRuntimeConfiguration, runtimeConfig } from "@/config/runtime";

describe("configuração pública", () => {
  it("aceita somente URL HTTPS e chave publicável", () => {
    expect(() => assertPublicRuntimeConfiguration()).not.toThrow();
    expect(runtimeConfig.supabaseUrl).toMatch(/^https:\/\//);
    expect(runtimeConfig.supabasePublishableKey).toMatch(/^sb_publishable_/);
  });

  it("não usa credencial administrativa no bundle", () => {
    expect(runtimeConfig.supabasePublishableKey).not.toMatch(/service_role|sb_secret_/i);
  });
});
