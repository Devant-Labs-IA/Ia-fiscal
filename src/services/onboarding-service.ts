import { ONBOARDING_VERSION, onboardingKeyForRole } from "@/config/onboarding";
import { getSupabaseClient } from "@/lib/supabase";
import type { AppRole } from "@/types/read-models";

export interface OnboardingProgress {
  userId: string;
  onboardingKey: string;
  onboardingVersion: number;
  currentStep: number;
  completedAt: string | null;
  updatedAt: string;
}

export interface SaveOnboardingProgress {
  userId: string;
  role: AppRole;
  currentStep: number;
  completed: boolean;
}

function mapProgress(row: {
  user_id: string;
  onboarding_key: string;
  onboarding_version: number;
  current_step: number;
  completed_at: string | null;
  updated_at: string;
}): OnboardingProgress {
  return {
    userId: row.user_id,
    onboardingKey: row.onboarding_key,
    onboardingVersion: row.onboarding_version,
    currentStep: row.current_step,
    completedAt: row.completed_at,
    updatedAt: row.updated_at,
  };
}

export const onboardingService = {
  async load(userId: string, role: AppRole): Promise<OnboardingProgress | null> {
    const onboardingKey = onboardingKeyForRole(role);
    const { data, error } = await getSupabaseClient()
      .from("user_onboarding_progress")
      .select("user_id, onboarding_key, onboarding_version, current_step, completed_at, updated_at")
      .eq("user_id", userId)
      .eq("onboarding_key", onboardingKey)
      .maybeSingle();

    if (error) throw error;
    return data ? mapProgress(data) : null;
  },

  async save(input: SaveOnboardingProgress): Promise<OnboardingProgress> {
    const updatedAt = new Date().toISOString();
    const completedAt = input.completed ? updatedAt : null;
    const { data, error } = await getSupabaseClient()
      .from("user_onboarding_progress")
      .upsert(
        {
          user_id: input.userId,
          onboarding_key: onboardingKeyForRole(input.role),
          onboarding_version: ONBOARDING_VERSION,
          current_step: input.currentStep,
          completed_at: completedAt,
          updated_at: updatedAt,
        },
        { onConflict: "user_id,onboarding_key" },
      )
      .select("user_id, onboarding_key, onboarding_version, current_step, completed_at, updated_at")
      .single();

    if (error) throw error;
    return mapProgress(data);
  },
};

export type PersistenceResult<T> = { ok: true; value: T } | { ok: false; error: unknown };

export interface PersistenceQueue {
  enqueue<T>(task: () => Promise<T>): Promise<PersistenceResult<T>>;
}

/** Serializa gravações e sempre transforma rejeições em resultado tratado. */
export function createPersistenceQueue(): PersistenceQueue {
  let tail: Promise<void> = Promise.resolve();

  return {
    enqueue<T>(task: () => Promise<T>): Promise<PersistenceResult<T>> {
      const execution = tail.then(task, task);
      const settled: Promise<PersistenceResult<T>> = execution.then(
        (value): PersistenceResult<T> => ({ ok: true, value }),
        (error: unknown): PersistenceResult<T> => ({ ok: false, error }),
      );
      tail = settled.then(() => undefined);
      return settled;
    },
  };
}
