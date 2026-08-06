import { useQuery } from "@tanstack/react-query";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowRight, Building2, Search } from "lucide-react";
import { useMemo, useState } from "react";

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
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatCurrency, maskCnpj } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";

export const Route = createFileRoute("/contribuintes")({
  head: () => ({
    meta: [
      { title: "Contribuintes — IA Fiscal" },
      {
        name: "description",
        content: "Visão operacional dos contribuintes autorizados para a sessão atual.",
      },
      { property: "og:title", content: "Contribuintes — IA Fiscal" },
      {
        property: "og:description",
        content: "Visão operacional dos contribuintes autorizados para a sessão atual.",
      },
    ],
  }),
  component: TaxpayersPage,
});

type AttentionFilter = "todos" | "com_atencao" | "sem_atencao";

function TaxpayersPage() {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const [query, setQuery] = useState("");
  const [attention, setAttention] = useState<AttentionFilter>("todos");
  const taxpayers = useQuery({
    queryKey: fiscalKeys.taxpayers(municipalityId),
    queryFn: () => fiscalService.listTaxpayerSummaries(municipalityId),
    enabled: Boolean(municipalityId),
  });

  const filtered = useMemo(() => {
    const term = query.trim().toLocaleLowerCase("pt-BR");
    const digits = query.replace(/\D/g, "");

    return (taxpayers.data ?? []).filter((item) => {
      const needsAttention =
        item.openBalanceTotal > 0 ||
        item.activeDivergenceCount > 0 ||
        item.blockedCalculationCount > 0 ||
        item.waitingQuestionCount > 0;
      const matchesAttention =
        attention === "todos" || (attention === "com_atencao" ? needsAttention : !needsAttention);
      const matchesTerm =
        term.length === 0 ||
        item.legalName.toLocaleLowerCase("pt-BR").includes(term) ||
        item.tradeName.toLocaleLowerCase("pt-BR").includes(term) ||
        item.municipalRegistration.toLocaleLowerCase("pt-BR").includes(term) ||
        (digits.length > 0 && item.taxId.replace(/\D/g, "").includes(digits));

      return matchesAttention && matchesTerm;
    });
  }, [attention, query, taxpayers.data]);

  const openBalance = (taxpayers.data ?? []).reduce(
    (total, item) => total + item.openBalanceTotal,
    0,
  );
  const activeCases = (taxpayers.data ?? []).reduce(
    (total, item) => total + item.activeCaseCount,
    0,
  );

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Contribuintes</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Leitura consolidada dos cadastros alcançados pelas permissões da sessão. Abra a ficha para
          consultar a visão fiscal 360.
        </p>
      </header>

      {taxpayers.isLoading ? (
        <SectionSkeleton rows={3} />
      ) : taxpayers.isError ? (
        <ErrorState message="Não foi possível carregar os contribuintes autorizados." />
      ) : (
        <div className="grid gap-3 sm:grid-cols-3">
          <SummaryMetric
            label="Contribuintes visíveis"
            value={String((taxpayers.data ?? []).length)}
          />
          <SummaryMetric label="Saldo em aberto" value={formatCurrency(openBalance)} />
          <SummaryMetric label="Casos ativos" value={String(activeCases)} />
        </div>
      )}

      <SectionCard
        title="Cadastro fiscal"
        description="A pesquisa ocorre somente sobre os registros já autorizados pelo banco."
        action={
          <Badge variant="secondary" className="tabular-nums">
            {filtered.length} registro{filtered.length === 1 ? "" : "s"}
          </Badge>
        }
      >
        <div className="mb-4 flex flex-col gap-2 sm:flex-row">
          <div className="relative min-w-0 flex-1">
            <Search
              className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
              aria-hidden
            />
            <Input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Razão social, CNPJ ou inscrição municipal"
              aria-label="Pesquisar contribuinte"
              className="pl-8"
            />
          </div>
          <Select
            value={attention}
            onValueChange={(value) => setAttention(value as AttentionFilter)}
          >
            <SelectTrigger className="w-full sm:w-52" aria-label="Filtrar necessidade de atenção">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos</SelectItem>
              <SelectItem value="com_atencao">Com atenção operacional</SelectItem>
              <SelectItem value="sem_atencao">Sem atenção pendente</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {taxpayers.isLoading ? (
          <SectionSkeleton rows={6} />
        ) : taxpayers.isError ? (
          <ErrorState message="A listagem de contribuintes está temporariamente indisponível." />
        ) : filtered.length === 0 ? (
          <EmptyState message="Nenhum contribuinte corresponde aos filtros aplicados." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Contribuinte</TableHead>
                  <TableHead>Inscrição municipal</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead className="text-right">Saldo em aberto</TableHead>
                  <TableHead className="text-right">Divergências ativas</TableHead>
                  <TableHead>Ação prioritária</TableHead>
                  <TableHead className="text-right">Ficha</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((item) => (
                  <TableRow key={item.taxpayerId}>
                    <TableCell className="min-w-64">
                      <span className="block font-medium">{item.legalName}</span>
                      <span className="block text-xs tabular-nums text-muted-foreground">
                        {maskCnpj(item.taxId)}
                      </span>
                    </TableCell>
                    <TableCell className="tabular-nums">{item.municipalRegistration}</TableCell>
                    <TableCell>
                      <StatusBadge status={item.taxpayerStatus} />
                    </TableCell>
                    <TableCell className="text-right font-medium tabular-nums">
                      {formatCurrency(item.openBalanceTotal)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {item.activeDivergenceCount}
                    </TableCell>
                    <TableCell className="max-w-72 text-sm text-muted-foreground">
                      {item.primaryActionLabel ?? "Sem ação prioritária registrada"}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button asChild variant="outline" size="sm">
                        <Link
                          to="/contribuintes/$taxpayerId"
                          params={{ taxpayerId: item.taxpayerId }}
                        >
                          Abrir 360
                          <ArrowRight className="size-4" aria-hidden />
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
    </div>
  );
}

function SummaryMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="surface-card p-4">
      <Building2 className="size-4 text-primary" aria-hidden />
      <p className="mt-3 text-xl font-semibold tabular-nums">{value}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">{label}</p>
    </div>
  );
}
