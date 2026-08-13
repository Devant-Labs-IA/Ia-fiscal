import { Check } from "lucide-react";

import { ErrorState, SectionCard, SectionSkeleton } from "@/components/common/SectionCard";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { ProductionBlocker } from "@/types/fiscal";

interface BlockersSectionProps {
  items: ProductionBlocker[] | undefined;
  isLoading: boolean;
  isError: boolean;
  onRetry?: () => void;
  retrying?: boolean;
}

export function BlockersSection({
  items,
  isLoading,
  isError,
  onRetry,
  retrying,
}: BlockersSectionProps) {
  const concluded = (items ?? []).filter((item) => item.done).length;

  return (
    <SectionCard
      title="Pendências para liberação externa"
      description="Itens obrigatórios antes de qualquer liberação de envio."
      action={
        <Badge variant="secondary" className="tabular-nums">
          {isLoading
            ? "carregando…"
            : isError
              ? "contagem indisponível"
              : `${concluded} de ${(items ?? []).length} concluídos`}
        </Badge>
      }
    >
      {isError ? (
        <ErrorState
          message="Não foi possível carregar as pendências de liberação externa."
          onRetry={onRetry}
          retrying={retrying}
        />
      ) : isLoading ? (
        <SectionSkeleton rows={4} />
      ) : (
        <ul className="space-y-3">
          {(items ?? []).map((item) => (
            <li key={item.id} className="flex gap-3">
              <span
                aria-hidden
                className={cn(
                  "mt-0.5 grid size-5 shrink-0 place-items-center rounded border",
                  item.done
                    ? "border-accent bg-success text-success-foreground"
                    : "border-border bg-muted",
                )}
              >
                {item.done && <Check className="size-3.5" />}
              </span>
              <div className="min-w-0">
                <p
                  className={cn(
                    "text-sm font-medium",
                    item.done && "text-muted-foreground line-through",
                  )}
                >
                  {item.title}
                  <span className="sr-only">{item.done ? " (concluído)" : " (pendente)"}</span>
                </p>
                <p className="text-xs text-muted-foreground">{item.description}</p>
                <p className="mt-0.5 text-xs text-muted-foreground">Responsável: {item.owner}</p>
              </div>
            </li>
          ))}
        </ul>
      )}
    </SectionCard>
  );
}
