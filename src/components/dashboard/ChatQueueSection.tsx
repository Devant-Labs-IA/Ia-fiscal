import { Link } from "@tanstack/react-router";
import { ArrowRight, Clock } from "lucide-react";

import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { RiskBadge } from "@/components/common/StatusBadges";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { maskCnpj } from "@/lib/format";
import type { ChatQueueItem } from "@/types/fiscal";

interface ChatQueueSectionProps {
  items: ChatQueueItem[] | undefined;
  isLoading: boolean;
  isError: boolean;
  onRetry?: () => void;
  retrying?: boolean;
}

export function ChatQueueSection({
  items,
  isLoading,
  isError,
  onRetry,
  retrying,
}: ChatQueueSectionProps) {
  return (
    <SectionCard
      title="Atendimentos aguardando ação"
      description="Fila de contribuintes com resposta pendente do fiscal. As ações ficam concentradas na fila de atendimento."
    >
      {isError ? (
        <ErrorState
          message="Não foi possível carregar a fila de atendimento."
          onRetry={onRetry}
          retrying={retrying}
        />
      ) : isLoading ? (
        <SectionSkeleton rows={3} />
      ) : (items ?? []).length === 0 ? (
        <EmptyState message="Nenhum atendimento aguardando ação." />
      ) : (
        <ul className="divide-y divide-border">
          {(items ?? []).map((item) => (
            <li key={item.id} className="space-y-2.5 py-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">{item.taxpayerName}</span>
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {maskCnpj(item.cnpj)}
                  </span>
                  <RiskBadge risk={item.priority} />
                </div>
                <p className="mt-1 text-sm text-muted-foreground">{item.lastMessage}</p>
                <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                  <span className="inline-flex items-center gap-1">
                    <Clock className="size-3.5" aria-hidden />
                    {item.waitingLabel}
                  </span>
                  <Badge variant="outline" className="font-normal">
                    Origem: {item.origin}
                  </Badge>
                </div>
              </div>

              <Button asChild size="sm" variant="outline">
                <Link to="/atendimento" aria-label={`Abrir atendimento de ${item.taxpayerName}`}>
                  Abrir na fila
                  <ArrowRight className="size-4" aria-hidden />
                </Link>
              </Button>
            </li>
          ))}
        </ul>
      )}
    </SectionCard>
  );
}
