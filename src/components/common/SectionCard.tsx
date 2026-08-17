import type { ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { fiscalQueryErrorMessage } from "@/lib/query-policy";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

interface SectionCardProps {
  title: string;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}

export function SectionCard({ title, description, action, children, className }: SectionCardProps) {
  return (
    <section className={cn("surface-card", className)} aria-label={title}>
      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-3 border-b border-border px-4 py-3.5 sm:px-5">
        <div className="min-w-0">
          <h2 className="truncate text-base font-semibold">{title}</h2>
          {description && <p className="mt-0.5 text-xs text-muted-foreground">{description}</p>}
        </div>
        {action}
      </header>
      <div className="px-4 py-4 sm:px-5">{children}</div>
    </section>
  );
}

export function SectionSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div className="space-y-3" role="status" aria-label="Carregando informações">
      {Array.from({ length: rows }).map((_, index) => (
        <Skeleton key={index} className="h-12 w-full" />
      ))}
    </div>
  );
}

export function EmptyState({ message }: { message: string }) {
  return (
    <p className="rounded-md border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
      {message}
    </p>
  );
}

interface ErrorStateProps {
  message: string;
  error?: unknown | undefined;
  onRetry?: (() => void) | undefined;
  retrying?: boolean | undefined;
}

export function ErrorState({ message, error, onRetry, retrying = false }: ErrorStateProps) {
  return (
    <div
      role="alert"
      className="rounded-md border border-critical/40 bg-critical-soft px-4 py-6 text-center text-sm text-critical"
    >
      <p>{fiscalQueryErrorMessage(error, message)}</p>
      {onRetry && (
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="mt-3 border-critical/30 bg-background text-foreground"
          disabled={retrying}
          onClick={onRetry}
        >
          {retrying ? "Tentando novamente…" : "Tentar novamente"}
        </Button>
      )}
    </div>
  );
}
