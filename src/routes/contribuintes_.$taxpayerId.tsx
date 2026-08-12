import { useQuery } from "@tanstack/react-query";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowLeft, Building2, CircleAlert, FileSearch, ReceiptText } from "lucide-react";
import { useState, type ReactNode } from "react";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { StatusBadge } from "@/components/common/StatusBadges";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  blockReasonLabel,
  debtClassificationRuleLabel,
  divergenceTypeDetails,
  fiscalOperationalReasonLabel,
  fiscalRulePresentation,
} from "@/lib/fiscal-labels";
import { formatCnpj, formatCurrency, formatDate } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type { DebtPeriod, DivergenceReadModel, FiscalCaseReadModel } from "@/types/read-models";

export const Route = createFileRoute("/contribuintes_/$taxpayerId")({
  head: () => ({
    meta: [
      { title: "Visão fiscal 360 — IA Fiscal" },
      {
        name: "description",
        content: "Visão fiscal consolidada do contribuinte autorizado para a sessão.",
      },
    ],
  }),
  component: Taxpayer360Page,
});

type DetailTab = "resumo" | "debitos" | "divergencias" | "casos";

function safeDate(value: string | null): string {
  if (!value) return "—";
  try {
    return formatDate(value);
  } catch {
    return "—";
  }
}

function formatCompetence(value: string): string {
  const match = /^(\d{4})-(\d{2})/.exec(value);
  return match ? `${match[2]}/${match[1]}` : value || "—";
}

function formatTaxId(value: string): string {
  return value.replace(/\D/g, "").length === 14 ? formatCnpj(value) : value;
}

function Taxpayer360Page() {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const { taxpayerId } = Route.useParams();
  const [activeTab, setActiveTab] = useState<DetailTab>("resumo");

  const summaries = useQuery({
    queryKey: fiscalKeys.taxpayers(municipalityId),
    queryFn: () => fiscalService.listTaxpayerSummaries(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const debts = useQuery({
    queryKey: fiscalKeys.debts(municipalityId, taxpayerId),
    queryFn: () => fiscalService.listDebtPeriods(municipalityId, taxpayerId),
    enabled: Boolean(municipalityId) && activeTab === "debitos",
  });
  const divergences = useQuery({
    queryKey: fiscalKeys.divergences(municipalityId, taxpayerId),
    queryFn: () => fiscalService.listDivergences(municipalityId, taxpayerId),
    enabled: Boolean(municipalityId) && activeTab === "divergencias",
  });
  const cases = useQuery({
    queryKey: fiscalKeys.caseRows(municipalityId, taxpayerId),
    queryFn: () => fiscalService.listFiscalCaseRows(municipalityId, taxpayerId),
    enabled: Boolean(municipalityId) && activeTab === "casos",
  });
  const taxpayer = summaries.data?.find((item) => item.taxpayerId === taxpayerId);

  if (summaries.isLoading) {
    return (
      <div className="space-y-5 py-4">
        <HomologationBanner />
        <SectionSkeleton rows={7} />
      </div>
    );
  }

  if (summaries.isError) {
    return (
      <div className="space-y-5 py-4">
        <HomologationBanner />
        <ErrorState message="Não foi possível carregar a ficha fiscal do contribuinte." />
        <Button asChild variant="outline">
          <Link to="/contribuintes">
            <ArrowLeft className="size-4" aria-hidden />
            Voltar aos contribuintes
          </Link>
        </Button>
      </div>
    );
  }

  if (!taxpayer) {
    return (
      <div className="space-y-5 py-4">
        <HomologationBanner />
        <EmptyState message="Contribuinte inexistente ou não autorizado para esta sessão." />
        <Button asChild variant="outline">
          <Link to="/contribuintes">
            <ArrowLeft className="size-4" aria-hidden />
            Voltar aos contribuintes
          </Link>
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <Button asChild variant="ghost" size="sm" className="mb-3 -ml-2">
          <Link to="/contribuintes">
            <ArrowLeft className="size-4" aria-hidden />
            Contribuintes
          </Link>
        </Button>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
              Visão fiscal 360
            </p>
            <h1 className="mt-1 text-2xl font-semibold tracking-tight sm:text-3xl">
              {taxpayer.legalName}
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {taxpayer.tradeName || "Sem nome fantasia"} · IM {taxpayer.municipalRegistration} ·{" "}
              <span className="tabular-nums">{formatTaxId(taxpayer.taxId)}</span>
            </p>
          </div>
          <StatusBadge status={taxpayer.taxpayerStatus} />
        </div>
      </header>

      {taxpayer.primaryActionLabel && (
        <div className="rounded-md border border-warning/40 bg-warning-soft px-4 py-3">
          <p className="flex items-start gap-2 text-sm font-medium text-warning-foreground">
            <CircleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
            {taxpayer.primaryActionLabel}
          </p>
          {taxpayer.primaryActionReason && (
            <p className="mt-1 pl-6 text-xs text-warning-foreground/80">
              {fiscalOperationalReasonLabel(taxpayer.primaryActionReason)}
            </p>
          )}
        </div>
      )}

      <Tabs
        value={activeTab}
        onValueChange={(value) => setActiveTab(value as DetailTab)}
        className="space-y-4"
      >
        <TabsList className="grid h-auto w-full grid-cols-2 gap-1 sm:max-w-2xl sm:grid-cols-4">
          <TabsTrigger value="resumo">Resumo</TabsTrigger>
          <TabsTrigger value="debitos">Débitos</TabsTrigger>
          <TabsTrigger value="divergencias">Divergências</TabsTrigger>
          <TabsTrigger value="casos">Procedimentos</TabsTrigger>
        </TabsList>

        <TabsContent value="resumo" className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <DetailMetric
              icon={<ReceiptText className="size-4" aria-hidden />}
              label="Saldo em aberto"
              value={formatCurrency(taxpayer.openBalanceTotal)}
            />
            <DetailMetric
              icon={<CircleAlert className="size-4" aria-hidden />}
              label="Divergências ativas"
              value={String(taxpayer.activeDivergenceCount)}
            />
            <DetailMetric
              icon={<FileSearch className="size-4" aria-hidden />}
              label="Casos ativos"
              value={String(taxpayer.activeCaseCount)}
            />
            <DetailMetric
              icon={<Building2 className="size-4" aria-hidden />}
              label="Pendências de atendimento"
              value={String(taxpayer.waitingQuestionCount)}
            />
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <SectionCard title="Conta corrente" description="Consolidação dos períodos fiscais.">
              <DefinitionList
                items={[
                  ["Períodos registrados", String(taxpayer.debtPeriodCount)],
                  ["Períodos vencidos", String(taxpayer.overduePeriodCount)],
                  ["Períodos incompletos", String(taxpayer.incompleteDebtPeriodCount)],
                  ["Vencimento mais antigo", safeDate(taxpayer.oldestOpenDueOn)],
                ]}
              />
            </SectionCard>
            <SectionCard
              title="Contatos e responsáveis"
              description="Indicadores de validação cadastral."
            >
              <DefinitionList
                items={[
                  ["Contatos cadastrados", String(taxpayer.contactCount)],
                  ["Contatos verificados", String(taxpayer.verifiedContactCount)],
                  ["Responsáveis cadastrados", String(taxpayer.responsibleCount)],
                  [
                    "Responsáveis aptos para entrega",
                    String(taxpayer.deliveryReadyResponsibleCount),
                  ],
                ]}
              />
            </SectionCard>
          </div>
        </TabsContent>

        <TabsContent value="debitos">
          <DebtTab data={debts.data} isLoading={debts.isLoading} isError={debts.isError} />
        </TabsContent>
        <TabsContent value="divergencias">
          <DivergenceTab
            data={divergences.data}
            isLoading={divergences.isLoading}
            isError={divergences.isError}
          />
        </TabsContent>
        <TabsContent value="casos">
          <CasesTab data={cases.data} isLoading={cases.isLoading} isError={cases.isError} />
        </TabsContent>
      </Tabs>
    </div>
  );
}

function DetailMetric({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return (
    <div className="surface-card p-4">
      <span className="text-primary">{icon}</span>
      <p className="mt-3 text-xl font-semibold tabular-nums">{value}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">{label}</p>
    </div>
  );
}

function DefinitionList({ items }: { items: [string, string][] }) {
  return (
    <dl className="divide-y divide-border">
      {items.map(([label, value]) => (
        <div
          key={label}
          className="flex items-center justify-between gap-4 py-2 first:pt-0 last:pb-0"
        >
          <dt className="text-sm text-muted-foreground">{label}</dt>
          <dd className="font-medium tabular-nums">{value}</dd>
        </div>
      ))}
    </dl>
  );
}

interface QueryTabProps<T> {
  data: T[] | undefined;
  isLoading: boolean;
  isError: boolean;
}

function DebtTab({ data, isLoading, isError }: QueryTabProps<DebtPeriod>) {
  return (
    <SectionCard
      title="Débitos por competência"
      description="Consulta carregada somente ao abrir esta aba."
    >
      {isLoading ? (
        <SectionSkeleton rows={5} />
      ) : isError ? (
        <ErrorState message="Não foi possível carregar os débitos deste contribuinte." />
      ) : !data?.length ? (
        <EmptyState message="Nenhum período de débito está visível para este contribuinte." />
      ) : (
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Competência</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead>Vencimento</TableHead>
                <TableHead className="text-right">Constituído</TableHead>
                <TableHead className="text-right">Vencido</TableHead>
                <TableHead className="text-right">Saldo aberto</TableHead>
                <TableHead>Regra</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.map((item) => (
                <TableRow key={`${item.competence}-${item.ruleVersion}`}>
                  <TableCell className="font-medium tabular-nums">
                    {formatCompetence(item.competence)}
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={item.status} />
                  </TableCell>
                  <TableCell className="tabular-nums">{safeDate(item.firstDueOn)}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatCurrency(item.assessedAmount)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatCurrency(item.overdueAmount)}
                  </TableCell>
                  <TableCell className="text-right font-medium tabular-nums">
                    {formatCurrency(item.openBalance)}
                  </TableCell>
                  <TableCell className="text-xs">
                    {debtClassificationRuleLabel(item.ruleVersion)} ·{" "}
                    {item.eligible ? "elegível" : "não elegível"}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </SectionCard>
  );
}

function DivergenceTab({ data, isLoading, isError }: QueryTabProps<DivergenceReadModel>) {
  return (
    <SectionCard
      title="Divergências"
      description="Achados produzidos pelas regras determinísticas vigentes."
    >
      {isLoading ? (
        <SectionSkeleton rows={5} />
      ) : isError ? (
        <ErrorState message="Não foi possível carregar as divergências deste contribuinte." />
      ) : !data?.length ? (
        <EmptyState message="Nenhuma divergência está visível para este contribuinte." />
      ) : (
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tipo</TableHead>
                <TableHead>Período</TableHead>
                <TableHead className="text-right">Diferença</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead>Regra</TableHead>
                <TableHead>Bloqueios</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.map((item) => {
                const rule = fiscalRulePresentation(
                  item.ruleCode,
                  item.ruleVersion,
                  item.ruleName,
                  item.ruleDescription,
                );
                return (
                  <TableRow key={item.divergenceId}>
                    <TableCell className="min-w-56">
                      <span className="block font-medium">
                        {divergenceTypeDetails(item.divergenceType).label}
                      </span>
                      <span className="mt-0.5 block text-xs text-muted-foreground">
                        {divergenceTypeDetails(item.divergenceType).description}
                      </span>
                    </TableCell>
                    <TableCell className="whitespace-nowrap text-xs tabular-nums">
                      {safeDate(item.periodStart)} a {safeDate(item.periodEnd)}
                    </TableCell>
                    <TableCell className="text-right font-medium tabular-nums">
                      {formatCurrency(item.differenceAmount)}
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={item.status} />
                    </TableCell>
                    <TableCell className="min-w-64 text-xs">
                      <span className="block font-medium">{rule.label}</span>
                      <span className="mt-0.5 block text-muted-foreground">{rule.description}</span>
                    </TableCell>
                    <TableCell className="max-w-64 text-xs text-muted-foreground">
                      {item.blockReasons.length
                        ? item.blockReasons.map(blockReasonLabel).join(" · ")
                        : "Sem bloqueio"}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      )}
    </SectionCard>
  );
}

function CasesTab({ data, isLoading, isError }: QueryTabProps<FiscalCaseReadModel>) {
  return (
    <SectionCard
      title="Procedimentos fiscais"
      description="Casos internos vinculados ao contribuinte."
    >
      {isLoading ? (
        <SectionSkeleton rows={5} />
      ) : isError ? (
        <ErrorState message="Não foi possível carregar os procedimentos deste contribuinte." />
      ) : !data?.length ? (
        <EmptyState message="Nenhum procedimento fiscal está visível para este contribuinte." />
      ) : (
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Caso</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead>Explicação</TableHead>
                <TableHead>Base legal</TableHead>
                <TableHead>Revisão</TableHead>
                <TableHead>Atualização</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.map((item) => (
                <TableRow key={item.caseId}>
                  <TableCell className="font-medium tabular-nums">{item.caseNumber}</TableCell>
                  <TableCell>
                    <StatusBadge status={item.status} />
                  </TableCell>
                  <TableCell className="max-w-72">
                    <span className="block text-sm font-medium">
                      {item.explanationTitle ?? "Sem título publicado"}
                    </span>
                    <span className="line-clamp-2 text-xs text-muted-foreground">
                      {item.explanationSummary ?? "Sem explicação disponível."}
                    </span>
                  </TableCell>
                  <TableCell className="max-w-72 text-xs text-muted-foreground">
                    {item.legalBasisSummary ?? "Não informada"}
                  </TableCell>
                  <TableCell>
                    <Badge variant={item.legalReviewRequired ? "outline" : "secondary"}>
                      {item.legalReviewRequired ? "Obrigatória" : "Não indicada"}
                    </Badge>
                  </TableCell>
                  <TableCell className="whitespace-nowrap text-xs tabular-nums">
                    {safeDate(item.updatedAt ?? item.openedAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </SectionCard>
  );
}
