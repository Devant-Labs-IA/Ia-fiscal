import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { Bot, Clock3, Inbox, LockKeyhole, MessageSquareText } from "lucide-react";

import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { RiskBadge } from "@/components/common/StatusBadges";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { formatDateTime } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type { ChatQueueItem } from "@/types/fiscal";

export const Route = createFileRoute("/atendimento")({
  head: () => ({
    meta: [
      { title: "Atendimento — IA Fiscal" },
      {
        name: "description",
        content:
          "Fila de perguntas do ambiente autenticado, com prioridade operacional e orientação para revisão fiscal.",
      },
      { property: "og:title", content: "Atendimento — IA Fiscal" },
      {
        property: "og:description",
        content:
          "Fila de perguntas do ambiente autenticado, com prioridade operacional e orientação para revisão fiscal.",
      },
    ],
  }),
  component: ServiceQueuePage,
});

function safeDateTime(value: string): string {
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? "Horário não informado" : formatDateTime(value);
}

function displayIdentifier(value: string): string {
  const digits = value.replace(/\D/g, "");
  if (digits.length !== 14) return value;
  return `${digits.slice(0, 2)}.${digits.slice(2, 5)}.***/**${digits.slice(10, 12)}-${digits.slice(12)}`;
}

function QueueItem({ item }: { item: ChatQueueItem }) {
  return (
    <li className="rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="font-medium">{item.taxpayerName || "Contribuinte protegido"}</h3>
            <RiskBadge risk={item.priority} />
          </div>
          <p className="mt-1 text-xs tabular-nums text-muted-foreground">
            {displayIdentifier(item.cnpj)}
          </p>
        </div>
        <Badge variant="outline" className="font-normal">
          {item.origin}
        </Badge>
      </div>

      <div className="mt-4 rounded-md border border-border bg-muted/50 p-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Pergunta recebida
        </p>
        <p className="mt-1 whitespace-pre-wrap text-sm">{item.lastMessage}</p>
      </div>

      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
        <span className="inline-flex items-center gap-1.5">
          <Clock3 className="size-3.5" aria-hidden />
          {item.waitingLabel}
        </span>
        <span className="tabular-nums">Recebida em {safeDateTime(item.waitingSince)}</span>
      </div>

      <details className="mt-4 rounded-md border border-primary/20 bg-primary-soft/40">
        <summary className="cursor-pointer px-3 py-2.5 text-sm font-medium text-primary">
          Consultar orientação de apoio
        </summary>
        <div className="border-t border-primary/20 px-3 py-3">
          <p className="flex items-start gap-2 text-sm">
            <Bot className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
            <span className="whitespace-pre-wrap">
              {item.suggestedReply || "Nenhuma orientação foi preparada para esta pergunta."}
            </span>
          </p>
          <p className="mt-3 text-xs text-muted-foreground">
            Conteúdo de apoio, sem efeito fiscal. Uma resposta nova exige revisão humana; esta tela
            não salva nem envia mensagens.
          </p>
        </div>
      </details>
    </li>
  );
}

function ServiceQueuePage() {
  const queue = useQuery({
    queryKey: fiscalKeys.chat,
    queryFn: () => fiscalService.listChatQueue(),
  });

  const items = queue.data ?? [];
  const urgentCount = items.filter(
    (item) => item.priority === "alto" || item.priority === "critico",
  ).length;

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Atendimento</h1>
          <Badge variant="outline" className="border-primary/30 bg-primary-soft text-primary">
            <LockKeyhole className="mr-1 size-3.5" aria-hidden />
            Somente leitura
          </Badge>
        </div>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Perguntas recebidas no ambiente autenticado. Prioridade é operacional e não representa
          conclusão jurídica ou fiscal.
        </p>
      </header>

      <div className="grid gap-3 sm:grid-cols-2" aria-label="Resumo do atendimento">
        <div className="surface-card flex items-center gap-4 p-4">
          <span className="grid size-10 shrink-0 place-items-center rounded-md bg-primary-soft text-primary">
            <Inbox className="size-5" aria-hidden />
          </span>
          <div>
            <p className="text-2xl font-semibold tabular-nums">
              {queue.isLoading ? "—" : items.length}
            </p>
            <p className="text-xs text-muted-foreground">perguntas aguardando análise</p>
          </div>
        </div>
        <div className="surface-card flex items-center gap-4 p-4">
          <span className="grid size-10 shrink-0 place-items-center rounded-md bg-warning-soft text-warning-foreground">
            <MessageSquareText className="size-5" aria-hidden />
          </span>
          <div>
            <p className="text-2xl font-semibold tabular-nums">
              {queue.isLoading ? "—" : urgentCount}
            </p>
            <p className="text-xs text-muted-foreground">com prioridade alta ou crítica</p>
          </div>
        </div>
      </div>

      <SectionCard
        title="Fila de perguntas"
        description="Nenhuma ação de assumir, responder ou enviar está habilitada nesta versão."
      >
        {queue.isError ? (
          <ErrorState message="Não foi possível carregar a fila de atendimento." />
        ) : queue.isLoading ? (
          <SectionSkeleton rows={4} />
        ) : items.length === 0 ? (
          <EmptyState message="Nenhuma pergunta está aguardando análise fiscal." />
        ) : (
          <ul className="space-y-3">
            {items.map((item) => (
              <QueueItem key={item.id} item={item} />
            ))}
          </ul>
        )}
      </SectionCard>
    </div>
  );
}
