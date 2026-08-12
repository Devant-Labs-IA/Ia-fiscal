import { useQuery } from "@tanstack/react-query";
import { Link, createFileRoute } from "@tanstack/react-router";
import { AlertTriangle, FileSearch, Scale } from "lucide-react";
import { useState } from "react";

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
  confidentialityLabel,
  divergenceTypeDetails,
  fiscalRulePresentation,
} from "@/lib/fiscal-labels";
import { formatCurrency, formatDate, maskCnpj } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";

export const Route = createFileRoute("/fiscalizacoes")({
  head: () => ({
    meta: [
      { title: "Fiscalizações — IA Fiscal" },
      {
        name: "description",
        content: "Leitura de divergências e procedimentos fiscais autorizados para a sessão.",
      },
      { property: "og:title", content: "Fiscalizações — IA Fiscal" },
      {
        property: "og:description",
        content: "Leitura de divergências e procedimentos fiscais autorizados para a sessão.",
      },
    ],
  }),
  component: InspectionsPage,
});

type InspectionTab = "divergencias" | "casos";

function safeDate(value: string | null): string {
  if (!value) return "—";
  try {
    return formatDate(value);
  } catch {
    return "—";
  }
}

function InspectionsPage() {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const [activeTab, setActiveTab] = useState<InspectionTab>("divergencias");
  const divergences = useQuery({
    queryKey: fiscalKeys.divergences(municipalityId),
    queryFn: () => fiscalService.listDivergences(municipalityId),
    enabled: Boolean(municipalityId) && activeTab === "divergencias",
  });
  const cases = useQuery({
    queryKey: fiscalKeys.caseRows(municipalityId),
    queryFn: () => fiscalService.listFiscalCaseRows(municipalityId),
    enabled: Boolean(municipalityId) && activeTab === "casos",
  });

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Fiscalizações</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Divergências detectadas e procedimentos já abertos. A plataforma apresenta evidências;
          lançamento, autuação e decisão permanecem sob responsabilidade da autoridade fiscal.
        </p>
      </header>

      <div className="rounded-md border border-warning/40 bg-warning-soft px-4 py-3 text-sm text-warning-foreground">
        <p className="flex items-start gap-2">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
          Nenhuma ação externa ou efeito jurídico é produzido nesta tela de homologação.
        </p>
      </div>

      <Tabs
        value={activeTab}
        onValueChange={(value) => setActiveTab(value as InspectionTab)}
        className="space-y-4"
      >
        <TabsList className="grid w-full max-w-md grid-cols-2">
          <TabsTrigger value="divergencias">Divergências</TabsTrigger>
          <TabsTrigger value="casos">Procedimentos</TabsTrigger>
        </TabsList>

        <TabsContent value="divergencias">
          <SectionCard
            title="Divergências fiscais"
            description="Resultado determinístico das regras ativas no ambiente de homologação."
            action={
              <Badge variant="secondary" className="tabular-nums">
                {divergences.data?.length ?? 0} registro
                {(divergences.data?.length ?? 0) === 1 ? "" : "s"}
              </Badge>
            }
          >
            {divergences.isLoading ? (
              <SectionSkeleton rows={6} />
            ) : divergences.isError ? (
              <ErrorState
                message="Não foi possível carregar as divergências fiscais."
                error={divergences.error}
                onRetry={() => void divergences.refetch()}
                retrying={divergences.isFetching}
              />
            ) : !divergences.data?.length ? (
              <EmptyState message="Nenhuma divergência está visível para esta sessão." />
            ) : (
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Contribuinte</TableHead>
                      <TableHead>Tipo</TableHead>
                      <TableHead>Período</TableHead>
                      <TableHead className="text-right">Diferença</TableHead>
                      <TableHead>Situação</TableHead>
                      <TableHead>Regra</TableHead>
                      <TableHead>Bloqueios</TableHead>
                      <TableHead className="text-right">Ficha</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {divergences.data.map((item) => {
                      const rule = fiscalRulePresentation(
                        item.ruleCode,
                        item.ruleVersion,
                        item.ruleName,
                        item.ruleDescription,
                      );
                      return (
                        <TableRow key={item.divergenceId}>
                          <TableCell className="min-w-60">
                            <span className="block font-medium">{item.taxpayerName}</span>
                            <span className="block text-xs tabular-nums text-muted-foreground">
                              {maskCnpj(item.taxId)}
                            </span>
                          </TableCell>
                          <TableCell className="min-w-56">
                            <span className="block text-sm font-medium">
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
                          <TableCell className="min-w-64">
                            <span className="block text-xs font-medium">{rule.label}</span>
                            <span className="mt-0.5 block text-xs text-muted-foreground">
                              {rule.description}
                            </span>
                          </TableCell>
                          <TableCell className="max-w-64 text-xs text-muted-foreground">
                            {item.blockReasons.length > 0
                              ? item.blockReasons.map(blockReasonLabel).join(" · ")
                              : "Sem bloqueio registrado"}
                          </TableCell>
                          <TableCell className="text-right">
                            <Button asChild variant="outline" size="sm">
                              <Link
                                to="/contribuintes/$taxpayerId"
                                params={{ taxpayerId: item.taxpayerId }}
                              >
                                Ver 360
                              </Link>
                            </Button>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
          </SectionCard>
        </TabsContent>

        <TabsContent value="casos">
          <SectionCard
            title="Procedimentos fiscais"
            description="Casos já constituídos no fluxo interno, exibidos sem ações de escrita."
            action={
              <Badge variant="secondary" className="tabular-nums">
                {cases.data?.length ?? 0} caso{(cases.data?.length ?? 0) === 1 ? "" : "s"}
              </Badge>
            }
          >
            {cases.isLoading || cases.fetchStatus === "idle" ? (
              <SectionSkeleton rows={5} />
            ) : cases.isError ? (
              <ErrorState
                message="Não foi possível carregar os procedimentos fiscais."
                error={cases.error}
                onRetry={() => void cases.refetch()}
                retrying={cases.isFetching}
              />
            ) : !cases.data?.length ? (
              <EmptyState message="Nenhum procedimento fiscal está visível para esta sessão." />
            ) : (
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Caso</TableHead>
                      <TableHead>Contribuinte</TableHead>
                      <TableHead>Situação</TableHead>
                      <TableHead>Explicação</TableHead>
                      <TableHead>Revisão legal</TableHead>
                      <TableHead>Atualização</TableHead>
                      <TableHead className="text-right">Ficha</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {cases.data.map((item) => (
                      <TableRow key={item.caseId}>
                        <TableCell>
                          <span className="block font-medium tabular-nums">{item.caseNumber}</span>
                          <span className="block text-xs text-muted-foreground">
                            {confidentialityLabel(item.confidentiality)}
                          </span>
                        </TableCell>
                        <TableCell className="min-w-60 font-medium">{item.taxpayerName}</TableCell>
                        <TableCell>
                          <StatusBadge status={item.status} />
                        </TableCell>
                        <TableCell className="max-w-80">
                          <span className="block text-sm font-medium">
                            {item.explanationTitle ?? "Sem título publicado"}
                          </span>
                          <span className="line-clamp-2 text-xs text-muted-foreground">
                            {item.explanationSummary ?? "Sem explicação disponível."}
                          </span>
                        </TableCell>
                        <TableCell>
                          <Badge variant={item.legalReviewRequired ? "outline" : "secondary"}>
                            {item.legalReviewRequired ? "Obrigatória" : "Não indicada"}
                          </Badge>
                        </TableCell>
                        <TableCell className="whitespace-nowrap text-xs tabular-nums">
                          {safeDate(item.updatedAt ?? item.openedAt)}
                        </TableCell>
                        <TableCell className="text-right">
                          <Button asChild variant="outline" size="sm">
                            <Link
                              to="/contribuintes/$taxpayerId"
                              params={{ taxpayerId: item.taxpayerId }}
                            >
                              Ver 360
                            </Link>
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </SectionCard>
        </TabsContent>
      </Tabs>

      <div className="grid gap-3 sm:grid-cols-2">
        <ReadOnlyNotice
          icon={<FileSearch className="size-4" aria-hidden />}
          title="Evidência antes de conclusão"
          text="Uma divergência é indício operacional e não constitui lançamento por si só."
        />
        <ReadOnlyNotice
          icon={<Scale className="size-4" aria-hidden />}
          title="Decisão humana"
          text="Revisões legais e atos privativos permanecem atribuídos ao agente competente."
        />
      </div>
    </div>
  );
}

function ReadOnlyNotice({
  icon,
  title,
  text,
}: {
  icon: React.ReactNode;
  title: string;
  text: string;
}) {
  return (
    <div className="surface-card p-4">
      <div className="flex items-center gap-2 font-medium text-primary">
        {icon}
        <h2 className="text-sm">{title}</h2>
      </div>
      <p className="mt-2 text-xs text-muted-foreground">{text}</p>
    </div>
  );
}
