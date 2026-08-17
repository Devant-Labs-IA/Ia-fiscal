import { beforeEach, describe, expect, it, vi } from "vitest";

import { createPersistenceQueue, onboardingService } from "@/services/onboarding-service";

const mocks = vi.hoisted(() => {
  const chain = {
    select: vi.fn(),
    eq: vi.fn(),
    maybeSingle: vi.fn(),
    upsert: vi.fn(),
    single: vi.fn(),
  };
  return { chain, from: vi.fn() };
});

vi.mock("@/lib/supabase", () => ({
  getSupabaseClient: () => ({ from: mocks.from }),
}));

beforeEach(() => {
  Object.values(mocks.chain).forEach((mock) => mock.mockReset());
  mocks.from.mockReset().mockReturnValue(mocks.chain);
  mocks.chain.select.mockReturnValue(mocks.chain);
  mocks.chain.eq.mockReturnValue(mocks.chain);
  mocks.chain.upsert.mockReturnValue(mocks.chain);
});

describe("persistência do onboarding", () => {
  it("carrega somente a chave versionada do perfil atual", async () => {
    mocks.chain.maybeSingle.mockResolvedValue({
      data: {
        user_id: "user-1",
        onboarding_key: "first-access:fiscal_auditor",
        onboarding_version: 2,
        current_step: 4,
        completed_at: null,
        updated_at: "2026-08-13T12:00:00Z",
      },
      error: null,
    });

    await expect(onboardingService.load("user-1", "fiscal_auditor")).resolves.toMatchObject({
      userId: "user-1",
      onboardingKey: "first-access:fiscal_auditor",
      onboardingVersion: 2,
      currentStep: 4,
    });
    expect(mocks.chain.eq).toHaveBeenCalledWith("user_id", "user-1");
    expect(mocks.chain.eq).toHaveBeenCalledWith("onboarding_key", "first-access:fiscal_auditor");
  });

  it("salva por chave composta sem substituir o progresso de outro perfil", async () => {
    mocks.chain.single.mockResolvedValue({
      data: {
        user_id: "user-1",
        onboarding_key: "first-access:supervisor",
        onboarding_version: 2,
        current_step: 2,
        completed_at: "2026-08-13T12:05:00Z",
        updated_at: "2026-08-13T12:05:00Z",
      },
      error: null,
    });

    await onboardingService.save({
      userId: "user-1",
      role: "supervisor",
      currentStep: 2,
      completed: true,
    });

    expect(mocks.chain.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        user_id: "user-1",
        onboarding_key: "first-access:supervisor",
        onboarding_version: 2,
        current_step: 2,
      }),
      { onConflict: "user_id,onboarding_key" },
    );
  });

  it("serializa gravações e converte rejeições em resultados tratados", async () => {
    const queue = createPersistenceQueue();
    const order: string[] = [];
    let releaseFirst: (() => void) | undefined;
    const first = queue.enqueue(
      () =>
        new Promise<void>((_resolve, reject) => {
          order.push("primeira-iniciada");
          releaseFirst = () => reject(new Error("falha esperada"));
        }),
    );
    const second = queue.enqueue(async () => {
      order.push("segunda-iniciada");
      return "salvo";
    });

    await Promise.resolve();
    expect(order).toEqual(["primeira-iniciada"]);
    releaseFirst?.();

    await expect(first).resolves.toMatchObject({ ok: false });
    await expect(second).resolves.toEqual({ ok: true, value: "salvo" });
    expect(order).toEqual(["primeira-iniciada", "segunda-iniciada"]);
  });
});
