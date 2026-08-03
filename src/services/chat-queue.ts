import type { ChatQueueItem, RiskLevel } from "@/types/fiscal";

const CLOSED_STATUSES = new Set(["answered", "closed", "cancelled"]);
const CLAIMED_STATUSES = new Set(["awaiting_fiscal", "claimed", "in_review"]);
const PRIORITY_RANK: Record<RiskLevel, number> = {
  baixo: 1,
  medio: 2,
  alto: 3,
  critico: 4,
};

function timestamp(value: string | null): number {
  if (!value) return Number.POSITIVE_INFINITY;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? Number.POSITIVE_INFINITY : parsed;
}

/**
 * Prioridade operacional da fila. Não representa risco jurídico nem conclusão fiscal.
 */
export function chatOperationalPriority(
  status: string,
  slaDueAt: string | null,
  nowMs = Date.now(),
): RiskLevel {
  if (CLOSED_STATUSES.has(status)) return "baixo";

  if (slaDueAt) {
    const dueMs = Date.parse(slaDueAt);
    if (!Number.isNaN(dueMs) && dueMs < nowMs) return "critico";
  }

  if (CLAIMED_STATUSES.has(status)) return "medio";
  return "alto";
}

export function normalizeHandlingMode(value: unknown): "unassigned" | "human" | "ai_assist" {
  return value === "human" || value === "ai_assist" ? value : "unassigned";
}

/** Ordena pela mesma prioridade exibida e usa SLA/chegada apenas como desempate. */
export function compareChatQueueItems(a: ChatQueueItem, b: ChatQueueItem): number {
  const priorityDifference = PRIORITY_RANK[b.priority] - PRIORITY_RANK[a.priority];
  if (priorityDifference !== 0) return priorityDifference;

  const slaDifference = timestamp(a.slaDueAt) - timestamp(b.slaDueAt);
  if (slaDifference !== 0) return slaDifference;

  const arrivalDifference = timestamp(a.waitingSince) - timestamp(b.waitingSince);
  return arrivalDifference !== 0 ? arrivalDifference : a.id.localeCompare(b.id);
}
