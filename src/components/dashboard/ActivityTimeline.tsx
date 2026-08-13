import { Brain, Calculator, FileEdit, UserCheck, type LucideIcon } from "lucide-react";

import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { formatDateTime } from "@/lib/format";
import type { AuditEvent } from "@/types/fiscal";

const eventIcons: Record<AuditEvent["type"], LucideIcon> = {
  calculo: Calculator,
  segundo_cerebro: Brain,
  escalonamento: UserCheck,
  notificacao: FileEdit,
};

interface ActivityTimelineProps {
  items: AuditEvent[] | undefined;
  isLoading: boolean;
  isError: boolean;
  onRetry?: () => void;
  retrying?: boolean;
}

export function ActivityTimeline({
  items,
  isLoading,
  isError,
  onRetry,
  retrying,
}: ActivityTimelineProps) {
  return (
    <SectionCard
      title="Atividade recente"
      description="Eventos registrados durante a operação assistida."
    >
      {isError ? (
        <ErrorState
          message="Não foi possível carregar a atividade recente."
          onRetry={onRetry}
          retrying={retrying}
        />
      ) : isLoading ? (
        <SectionSkeleton rows={4} />
      ) : (items ?? []).length === 0 ? (
        <EmptyState message="Nenhum evento auditável foi encontrado." />
      ) : (
        <ol className="relative space-y-5 border-l border-border pl-6">
          {(items ?? []).map((item) => {
            const Icon = eventIcons[item.type];
            return (
              <li key={item.id} className="relative">
                <span className="absolute -left-[2.15rem] grid size-6 place-items-center rounded-full border border-border bg-card text-primary">
                  <Icon className="size-3.5" aria-hidden />
                </span>
                <p className="text-sm font-medium">{item.title}</p>
                <p className="mt-0.5 text-sm text-muted-foreground">{item.description}</p>
                <p className="mt-1 text-xs tabular-nums text-muted-foreground">
                  {formatDateTime(item.occurredAt)} · {item.actor}
                </p>
              </li>
            );
          })}
        </ol>
      )}
    </SectionCard>
  );
}
