import { Link } from "@tanstack/react-router";
import {
  ArrowDownRight,
  ArrowUpRight,
  Brain,
  Building2,
  ClipboardCheck,
  MessageSquare,
  Minus,
  Receipt,
  Send,
  type LucideIcon,
} from "lucide-react";

import { cn } from "@/lib/utils";
import type { DashboardMetric } from "@/types/fiscal";

const icons: Record<DashboardMetric["icon"], LucideIcon> = {
  contribuintes: Building2,
  debitos: Receipt,
  fiscalizacoes: ClipboardCheck,
  notificacoes: Send,
  atendimento: MessageSquare,
  calculos: Brain,
};

const toneStyles: Record<DashboardMetric["tone"], string> = {
  neutro: "bg-primary-soft text-primary",
  positivo: "bg-success-soft text-success",
  atencao: "bg-warning-soft text-warning-foreground",
  critico: "bg-critical-soft text-critical",
};

const trendIcons = {
  alta: ArrowUpRight,
  baixa: ArrowDownRight,
  estavel: Minus,
} as const;

export function MetricCard({ metric }: { metric: DashboardMetric }) {
  const Icon = icons[metric.icon];
  const TrendIcon = metric.trend ? trendIcons[metric.trend.direction] : null;

  return (
    <Link
      to={metric.route}
      className="surface-card group flex flex-col gap-3 p-4 transition-colors hover:border-primary/40 hover:bg-primary-soft/40 focus-visible:border-primary"
      aria-label={`${metric.label}: ${metric.value}`}
    >
      <div className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-2">
        <p className="min-w-0 text-sm font-medium text-muted-foreground">{metric.label}</p>
        <span
          className={cn(
            "grid size-9 shrink-0 place-items-center rounded-md",
            toneStyles[metric.tone],
          )}
        >
          <Icon className="size-4" aria-hidden />
        </span>
      </div>

      <p className="text-3xl font-semibold tabular-nums tracking-tight">{metric.value}</p>

      <div className="space-y-1">
        <p className="text-xs text-muted-foreground">{metric.context}</p>
        {metric.trend && TrendIcon && (
          <p className="flex items-center gap-1 text-xs font-medium text-foreground/70">
            <TrendIcon className="size-3.5" aria-hidden />
            {metric.trend.value}
          </p>
        )}
      </div>
    </Link>
  );
}

export function MetricGrid({ metrics }: { metrics: DashboardMetric[] }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {metrics.map((metric) => (
        <MetricCard key={metric.id} metric={metric} />
      ))}
    </div>
  );
}
