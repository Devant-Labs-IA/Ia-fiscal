// @vitest-environment jsdom

import { describe, expect, it } from "vitest";

import {
  assertPublicRuntimeConfiguration,
  isDemoMode,
  runtimeConfig,
  setDemoMode,
} from "@/config/runtime";

describe("configuração pública", () => {
  it("aceita somente URL HTTPS e chave publicável", () => {
    expect(() => assertPublicRuntimeConfiguration()).not.toThrow();
    expect(runtimeConfig.supabaseUrl).toMatch(/^https:\/\//);
    expect(runtimeConfig.supabasePublishableKey).toMatch(/^sb_publishable_/);
  });

  it("não usa credencial administrativa no bundle", () => {
    expect(runtimeConfig.supabasePublishableKey).not.toMatch(/service_role|sb_secret_/i);
  });

  it("mantém o modo de demonstração desativado por padrão", () => {
    expect(runtimeConfig.allowDemo).toBe(false);
    window.sessionStorage.setItem("ia-fiscal:demo-mode", "true");
    expect(isDemoMode()).toBe(false);
    setDemoMode(true);
    expect(window.sessionStorage.getItem("ia-fiscal:demo-mode")).toBeNull();
  });
});
