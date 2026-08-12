import { useQuery } from "@tanstack/react-query";
import { Link, createFileRoute } from "@tanstack/react-router";
import { Search, WalletCards } from "lucide-react";
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
import { fiscalStatusLabel } from "@/lib/fiscal-labels";
import { formatCurrency, formatDate } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";

export const Route = createFileRoute("/debitos")({
  head: () => ({
    meta: [
      { title: "Débitos — IA Fiscal" },
      {
        name: "description",
        content: "Consolidação de períodos de débito autorizados para a sessão atual.",
      },
      { property: "og:title", content: "Débitos — IA Fiscal" },
      {
        property: "og:description",
        content: "Consolidação de períodos de débito autorizados para a sessão atual.",
      },
    ],
  }),
  component: DebtsPage,
});

function formatCompetence(value: string): string {
  const match = /^(\d{4})-(\d{2})/.exec(value);
  return match ? `${match[2]}/${match[1]}` : value || "—";
}

function safeDate(value: string | null): string {
  if (!value) return "—";
  try {
    return formatDate(value);
  } catch {
    return "—";
  }
}

function DebtsPage() {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("todos");
  const debts = useQuery({
    queryKey: fiscalKeys.debts(municipalityId),
    queryFn: () => fiscalService.listDebtPeriods(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const taxpayers = useQuery({
    queryKey: fiscalKeys.taxpayers(municipalityId),
    queryFn: () => fiscalService.listTaxpayerSummaries(municipalityId),
    enabled: Boolean(municipalityId),
  });

  const taxpayerById = useMemo(
    () => new Map((taxpayers.data ?? []).map((item) => [item.taxpayerId, item])),
    [taxpayers.data],
  );
  const statuses = useMemo(
    () => Array.from(new Set((debts.data ?? []).map((item) => item.status))).sort(),
    [debts.data],
  );
  const filtered = useMemo(() => {
    const term = query.trim().toLocaleLowerCase("pt-BR");
    return (debts.data ?? []).filter((item) => {
      const taxpayer = taxpayerById.get(item.taxpayerId);
      const matchesStatus = status === "todos" || item.status === status;
      const matchesTerm =
        term.length === 0 ||
        taxpayer?.legalName.toLocaleLowerCase("pt-BR").includes(term) ||
        taxpayer?.municipalRegistration.toLocaleLowerCase("pt-BR").includes(term) ||
        formatCompetence(item.competence).includes(term);
      return matchesStatus && Boolean(matchesTerm);
    });
  }, [debts.data, query, status, taxpayerById]);

  const totals = (debts.data ?? []).reduce(
    (result, item) => ({
      open: result.open + item.openBalance,
      overdue: result.overdue + item.overdueAmount,
      incomplete: result.incomplete + item.incompleteAmount,
    }),
    { open: 0, overdue: 0, incomplete: 0 },
  );
  const queryFailed = debts.isError || taxpayers.isError;
  const queryLoading = debts.isLoading || taxpayers.isLoading;

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Débitos</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Extrato consolidado por contribuinte e competência. Esta tela é somente leitura e não gera
          cobrança, guia ou comunicação.
        </p>
      </header>

      {queryLoading ? (
        <SectionSkeleton rows={3} />
      ) : queryFailed ? (
        <ErrorState
          message="Não foi possível carregar a consolidação de débitos."
          error={debts.error ?? taxpayers.error}
          onRetry={() => void Promise.all([debts.refetch(), taxpayers.refetch()])}
          retrying={debts.isFetching || taxpayers.isFetching}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-3">
          <DebtMetric label="Saldo em aberto" value={formatCurrency(totals.open)} />
          <DebtMetric label="Valor vencido" value={formatCurrency(totals.overdue)} />
          <DebtMetric label="Valor incompleto" value={formatCurrency(totals.incomplete)} />
        </div>
      )}

      <SectionCard
        title="Períodos de débito"
        description="Valores calculados pelo read model vigente na data de referência."
        action={
          <Badge variant="secondary" className="tabular-nums">
            {filtered.length} período{filtered.length === 1 ? "" : "s"}
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
              placeholder="Contribuinte, inscrição ou competência"
              aria-label="Pesquisar débito"
              className="pl-8"
            />
          </div>
          <Select value={status} onValueChange={setStatus}>
            <SelectTrigger className="w-full sm:w-48" aria-label="Filtrar situação do débito">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todas as situações</SelectItem>
              {statuses.map((item) => (
                <SelectItem key={item} value={item}>
                  {fiscalStatusLabel(item)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {queryLoading ? (
          <SectionSkeleton rows={6} />
        ) : queryFailed ? (
          <ErrorState
            message="Os períodos de débito estão temporariamente indisponíveis."
            error={debts.error ?? taxpayers.error}
            onRetry={() => void Promise.all([debts.refetch(), taxpayers.refetch()])}
            retrying={debts.isFetching || taxpayers.isFetching}
          />
        ) : filtered.length === 0 ? (
          <EmptyState message="Nenhum período de débito corresponde aos filtros aplicados." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Contribuinte</TableHead>
                  <TableHead>Competência</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead>Primeiro vencimento</TableHead>
                  <TableHead className="text-right">Constituído</TableHead>
                  <TableHead className="text-right">Vencido</TableHead>
                  <TableHead className="text-right">Saldo aberto</TableHead>
                  <TableHead>Regra</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((item) => {
                  const taxpayer = taxpayerById.get(item.taxpayerId);
                  return (
                    <TableRow key={`${item.taxpayerId}-${item.competence}-${item.ruleVersion}`}>
                      <TableCell className="min-w-60">
                        <Button asChild variant="link" className="h-auto justify-start p-0">
                          <Link
                            to="/contribuintes/$taxpayerId"
                            params={{ taxpayerId: item.taxpayerId }}
                          >
                            {taxpayer?.legalName ?? "Contribuinte autorizado"}
                          </Link>
                        </Button>
                        <span className="block text-xs text-muted-foreground">
                          {taxpayer?.municipalRegistration ?? item.taxpayerId.slice(0, 8)}
                        </span>
                      </TableCell>
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
                      <TableCell>
                        <span className="block text-xs font-medium">{item.ruleVersion}</span>
                        <span className="block text-xs text-muted-foreground">
                          {item.eligible ? "Elegível" : "Não elegível"}
                        </span>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </SectionCard>
    </div>
  );
}

function DebtMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="surface-card p-4">
      <WalletCards className="size-4 text-primary" aria-hidden />
      <p className="mt-3 text-xl font-semibold tabular-nums">{value}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">{label}</p>
    </div>
  );
}
