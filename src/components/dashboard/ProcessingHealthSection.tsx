import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { HealthBadge } from "@/components/common/StatusBadges";
import type { ProcessingHealthIndicator } from "@/types/fiscal";

interface ProcessingHealthSectionProps {
  items: ProcessingHealthIndicator[] | undefined;
  isLoading: boolean;
  isError: boolean;
  onRetry?: () => void;
  retrying?: boolean;
}

export function ProcessingHealthSection({
  items,
  isLoading,
  isError,
  onRetry,
  retrying,
}: ProcessingHealthSectionProps) {
  return (
    <SectionCard
      title="Saúde do processamento"
      description="Situação dos componentes que sustentam a apuração automatizada."
    >
      {isError ? (
        <ErrorState
          message="Não foi possível consultar a saúde do processamento."
          onRetry={onRetry}
          retrying={retrying}
        />
      ) : isLoading ? (
        <SectionSkeleton rows={3} />
      ) : (items ?? []).length === 0 ? (
        <EmptyState message="Nenhum componente de processamento foi observado." />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {(items ?? []).map((item) => (
            <article key={item.id} className="rounded-md border border-border p-3">
              <div className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-2">
                <h3 className="truncate text-sm font-medium">{item.label}</h3>
                <HealthBadge status={item.status} />
              </div>
              <p className="mt-2 text-xs text-muted-foreground">{item.detail}</p>
              <p className="mt-1 text-xs font-medium tabular-nums text-foreground/70">
                {item.metric}
              </p>
            </article>
          ))}
        </div>
      )}
    </SectionCard>
  );
}
