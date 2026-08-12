import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { CalendarDays } from "lucide-react";

import { useAuth } from "@/auth/AuthContext";
import { ErrorState, SectionSkeleton } from "@/components/common/SectionCard";
import { ActivityTimeline } from "@/components/dashboard/ActivityTimeline";
import { BlockersSection } from "@/components/dashboard/BlockersSection";
import { ChatQueueSection } from "@/components/dashboard/ChatQueueSection";
import { MetricGrid } from "@/components/dashboard/MetricCards";
import { NotificationsSection } from "@/components/dashboard/NotificationsSection";
import { PriorityCasesSection } from "@/components/dashboard/PriorityCasesSection";
import { ProcessingHealthSection } from "@/components/dashboard/ProcessingHealthSection";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { formatDate } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Dashboard do Fiscal — IA Fiscal" },
      {
        name: "description",
        content:
          "Painel operacional da fiscalização tributária de Cordeirópolis/SP: prioridades, débitos, atendimentos e saúde do processamento.",
      },
      { property: "og:title", content: "Dashboard do Fiscal — IA Fiscal" },
      {
        property: "og:description",
        content:
          "Gestão tributária inteligente para a Prefeitura: prioridades de fiscalização, débitos vencidos e atendimentos em um só painel.",
      },
    ],
  }),
  component: DashboardFiscal,
});

function DashboardFiscal() {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const summary = useQuery({
    queryKey: fiscalKeys.dashboard(municipalityId),
    queryFn: () => fiscalService.getDashboardSummary(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const cases = useQuery({
    queryKey: fiscalKeys.cases(municipalityId),
    queryFn: () => fiscalService.listFiscalCases(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const chat = useQuery({
    queryKey: fiscalKeys.chat(municipalityId),
    queryFn: () => fiscalService.listChatQueue(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const notifications = useQuery({
    queryKey: fiscalKeys.notifications(municipalityId),
    queryFn: () => fiscalService.listNotificationCandidates(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const health = useQuery({
    queryKey: fiscalKeys.health,
    queryFn: () => fiscalService.listProcessingHealth(),
  });
  const blockers = useQuery({
    queryKey: fiscalKeys.blockers(municipalityId),
    queryFn: () => fiscalService.listProductionBlockers(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const events = useQuery({
    queryKey: fiscalKeys.events(municipalityId),
    queryFn: () => fiscalService.listAuditEvents(municipalityId),
    enabled: Boolean(municipalityId),
  });

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-4">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
            {summary.data?.greeting ?? "Bom dia, Fiscal"}
          </h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            {summary.isLoading
              ? "Carregando resumo operacional do dia…"
              : (summary.data?.operationalSummary ?? "")}
          </p>
        </div>
        <p className="inline-flex shrink-0 items-center gap-1.5 rounded-md border border-border bg-card px-2.5 py-1.5 text-xs font-medium tabular-nums text-muted-foreground">
          <CalendarDays className="size-3.5" aria-hidden />
          {summary.data ? formatDate(summary.data.referenceDate) : "—"}
        </p>
      </header>

      {summary.isError ? (
        <ErrorState
          message="Não foi possível carregar os indicadores. Tente novamente."
          error={summary.error}
          onRetry={() => void summary.refetch()}
          retrying={summary.isFetching}
        />
      ) : summary.isLoading ? (
        <SectionSkeleton rows={3} />
      ) : (
        <MetricGrid metrics={summary.data?.metrics ?? []} />
      )}

      <PriorityCasesSection
        cases={cases.data}
        isLoading={cases.isLoading}
        isError={cases.isError}
        onRetry={() => void cases.refetch()}
        retrying={cases.isFetching}
      />

      <div className="grid gap-5 2xl:grid-cols-2">
        <ChatQueueSection
          items={chat.data}
          isLoading={chat.isLoading}
          isError={chat.isError}
          onRetry={() => void chat.refetch()}
          retrying={chat.isFetching}
        />
        <NotificationsSection
          items={notifications.data}
          isLoading={notifications.isLoading}
          isError={notifications.isError}
          onRetry={() => void notifications.refetch()}
          retrying={notifications.isFetching}
        />
      </div>

      <ProcessingHealthSection
        items={health.data}
        isLoading={health.isLoading}
        isError={health.isError}
        onRetry={() => void health.refetch()}
        retrying={health.isFetching}
      />

      <div className="grid gap-5 xl:grid-cols-2">
        <BlockersSection
          items={blockers.data}
          isLoading={blockers.isLoading}
          isError={blockers.isError}
          onRetry={() => void blockers.refetch()}
          retrying={blockers.isFetching}
        />
        <ActivityTimeline
          items={events.data}
          isLoading={events.isLoading}
          isError={events.isError}
          onRetry={() => void events.refetch()}
          retrying={events.isFetching}
        />
      </div>
    </div>
  );
}
