import { describe, expect, it } from "vitest";

import {
  chatOperationalPriority,
  compareChatQueueItems,
  normalizeHandlingMode,
} from "@/services/chat-queue";
import type { ChatQueueItem } from "@/types/fiscal";

describe("prioridade operacional do atendimento", () => {
  const now = Date.parse("2026-08-02T12:00:00-03:00");

  it("prioriza SLA vencido sem transformar o valor em conclusão fiscal", () => {
    expect(chatOperationalPriority("submitted", "2026-08-02T11:59:00-03:00", now)).toBe("critico");
  });

  it("distingue pergunta nova, assumida e encerrada", () => {
    expect(chatOperationalPriority("submitted", null, now)).toBe("alto");
    expect(chatOperationalPriority("awaiting_fiscal", null, now)).toBe("medio");
    expect(chatOperationalPriority("answered", "2026-08-01T00:00:00-03:00", now)).toBe("baixo");
  });

  it("normaliza modos desconhecidos como não atribuídos", () => {
    expect(normalizeHandlingMode("human")).toBe("human");
    expect(normalizeHandlingMode("ai_assist")).toBe("ai_assist");
    expect(normalizeHandlingMode("automatic")).toBe("unassigned");

    const base = {
      municipalityId: "municipality-1",
      caseId: "case-1",
      caseNumber: "FIS-1",
      taxpayerName: "Contribuinte",
      cnpj: "identificador protegido",
      lastMessage: "Pergunta",
      waitingLabel: "SLA registrado",
      status: "waiting",
      handlingMode: "unassigned",
      assignedMembershipId: null,
      claimedAt: null,
      origin: "portal do contribuinte",
      suggestedReply: "Sem resposta automática",
    } satisfies Omit<ChatQueueItem, "id" | "priority" | "slaDueAt" | "waitingSince">;
    const queue: ChatQueueItem[] = [
      {
        ...base,
        id: "medium",
        priority: "medio",
        slaDueAt: null,
        waitingSince: "2026-08-02T09:00:00Z",
      },
      {
        ...base,
        id: "critical",
        priority: "critico",
        slaDueAt: "2026-08-02T08:00:00Z",
        waitingSince: "2026-08-02T08:00:00Z",
      },
    ];
    expect(queue.sort(compareChatQueueItems).map((item) => item.id)).toEqual([
      "critical",
      "medium",
    ]);
  });
});
