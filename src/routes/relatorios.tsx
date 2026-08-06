import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { AlertTriangle, CircleDollarSign, FileSearch, Users } from "lucide-react";

import { useAuth } from "@/auth/AuthContext";
import { ErrorState, SectionCard, SectionSkeleton } from "@/components/common/SectionCard";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { formatCurrency, formatNumber } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";

export const Route = createFileRoute("/relatorios")({
  head: () => ({ meta: [{ title: "Relatório operacional — IA Fiscal" }] }),
  component: ReportsPage,
});

function ReportsPage() {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const report = useQuery({
    queryKey: fiscalKeys.report(municipalityId),
    queryFn: () => fiscalService.getOperationalReport(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const cards = report.data
    ? [
        {
          label: "Contribuintes monitorados",
          value: formatNumber(report.data.taxpayerCount),
          icon: Users,
        },
        {
          label: "Saldo aberto observado",
          value: formatCurrency(report.data.openBalanceTotal),
          icon: CircleDollarSign,
        },
        {
          label: "Divergências ativas",
          value: formatNumber(report.data.activeDivergenceCount),
          icon: FileSearch,
        },
        {
          label: "Cálculos bloqueados",
          value: formatNumber(report.data.blockedCalculationCount),
          icon: AlertTriangle,
        },
      ]
    : [];

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />
      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Relatório operacional</h1>
        <p className="mt-2 max-w-3xl text-sm text-muted-foreground">
          Indicadores de triagem em homologação. Valores não constituem lançamento, crédito
          tributário ou decisão fiscal.
        </p>
      </header>
      {report.isLoading ? (
        <SectionSkeleton rows={4} />
      ) : report.isError ? (
        <ErrorState message="Não foi possível consolidar os indicadores." />
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {cards.map((card) => (
              <div key={card.label} className="surface-card p-5">
                <card.icon className="size-5 text-primary" aria-hidden />
                <p className="mt-4 text-2xl font-semibold tabular-nums">{card.value}</p>
                <p className="mt-1 text-xs text-muted-foreground">{card.label}</p>
              </div>
            ))}
          </div>
          <div className="grid gap-5 lg:grid-cols-2">
            <SectionCard title="Fiscalização" description="Inventário do estágio atual">
              <dl className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <dt className="text-muted-foreground">Períodos vencidos</dt>
                  <dd className="mt-1 text-lg font-semibold">
                    {formatNumber(report.data!.overduePeriodCount)}
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Casos ativos</dt>
                  <dd className="mt-1 text-lg font-semibold">
                    {formatNumber(report.data!.activeCaseCount)}
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Valor em divergências</dt>
                  <dd className="mt-1 text-lg font-semibold">
                    {formatCurrency(report.data!.divergenceAmountTotal)}
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Perguntas aguardando</dt>
                  <dd className="mt-1 text-lg font-semibold">
                    {formatNumber(report.data!.waitingQuestionCount)}
                  </dd>
                </div>
              </dl>
            </SectionCard>
            <SectionCard
              title="Comunicação protegida"
              description="Nenhum envio externo autorizado"
            >
              <dl className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <dt className="text-muted-foreground">Destinatários candidatos</dt>
                  <dd className="mt-1 text-lg font-semibold">
                    {formatNumber(report.data!.recipientCandidateCount)}
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Prontos, aguardando autorização</dt>
                  <dd className="mt-1 text-lg font-semibold">
                    {formatNumber(report.data!.deliveryReadyCount)}
                  </dd>
                </div>
                <div className="col-span-2 rounded-md border border-critical/30 bg-critical-soft p-3">
                  <dt className="text-critical">Envios externos executados</dt>
                  <dd className="mt-1 text-lg font-semibold text-critical">
                    {formatNumber(report.data!.externalDeliveryCount)}
                  </dd>
                </div>
              </dl>
            </SectionCard>
          </div>
        </>
      )}
    </div>
  );
}
