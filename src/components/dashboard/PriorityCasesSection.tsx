import { useMemo, useState } from "react";
import { Search } from "lucide-react";

import { EmptyState, SectionCard, SectionSkeleton } from "@/components/common/SectionCard";
import { RiskBadge, StatusBadge } from "@/components/common/StatusBadges";
import { CaseDrawer } from "@/components/dashboard/CaseDrawer";
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
import type { FiscalCase, RiskLevel } from "@/types/fiscal";

interface PriorityCasesSectionProps {
  cases: FiscalCase[] | undefined;
  isLoading: boolean;
}

export function PriorityCasesSection({ cases, isLoading }: PriorityCasesSectionProps) {
  const [query, setQuery] = useState("");
  const [risk, setRisk] = useState<RiskLevel | "todos">("todos");
  const [selected, setSelected] = useState<FiscalCase | null>(null);

  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase();
    return (cases ?? []).filter((item) => {
      const matchesRisk = risk === "todos" || item.risk === risk;
      const matchesTerm =
        term.length === 0 ||
        item.taxpayer.name.toLowerCase().includes(term) ||
        item.divergenceType.toLowerCase().includes(term) ||
        item.taxpayer.cnpj.includes(term.replace(/\D/g, "")) ||
        item.assignee.toLowerCase().includes(term);
      return matchesRisk && matchesTerm;
    });
  }, [cases, query, risk]);

  return (
    <>
      <SectionCard
        title="Prioridades de fiscalização"
        description="Casos com maior impacto de arrecadação apurados na malha de homologação."
        action={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative">
              <Search
                className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden
              />
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Filtrar por empresa ou divergência"
                aria-label="Filtrar prioridades de fiscalização"
                className="h-9 w-56 pl-8"
              />
            </div>
            <Select value={risk} onValueChange={(value) => setRisk(value as RiskLevel | "todos")}>
              <SelectTrigger className="h-9 w-36" aria-label="Filtrar por risco">
                <SelectValue placeholder="Risco" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="todos">Todos os riscos</SelectItem>
                <SelectItem value="critico">Crítico</SelectItem>
                <SelectItem value="alto">Alto</SelectItem>
                <SelectItem value="medio">Médio</SelectItem>
                <SelectItem value="baixo">Baixo</SelectItem>
              </SelectContent>
            </Select>
          </div>
        }
      >
        {isLoading ? (
          <SectionSkeleton rows={5} />
        ) : filtered.length === 0 ? (
          <EmptyState message="Nenhum caso corresponde aos filtros aplicados." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Contribuinte</TableHead>
                  <TableHead>Divergência</TableHead>
                  <TableHead className="text-right">Valor</TableHead>
                  <TableHead>Competências</TableHead>
                  <TableHead>Risco</TableHead>
                  <TableHead>Responsável</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead className="text-right">Ação</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((item) => (
                  <TableRow key={item.id} className="hover:bg-muted/60">
                    <TableCell className="min-w-52">
                      <span className="block font-medium">{item.taxpayer.name}</span>
                      <span className="block text-xs tabular-nums text-muted-foreground">
                        {maskCnpj(item.taxpayer.cnpj)}
                      </span>
                    </TableCell>
                    <TableCell className="min-w-44 text-sm">{item.divergenceType}</TableCell>
                    <TableCell className="text-right font-medium tabular-nums">
                      {formatCurrency(item.amount)}
                    </TableCell>
                    <TableCell className="text-xs tabular-nums text-muted-foreground">
                      {item.competences.join(", ")}
                    </TableCell>
                    <TableCell>
                      <RiskBadge risk={item.risk} />
                    </TableCell>
                    <TableCell className="text-sm">{item.assignee}</TableCell>
                    <TableCell>
                      <StatusBadge status={item.status} />
                    </TableCell>
                    <TableCell className="text-right">
                      <Button size="sm" variant="outline" onClick={() => setSelected(item)}>
                        Analisar caso
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </SectionCard>

      <CaseDrawer fiscalCase={selected} onOpenChange={(open) => !open && setSelected(null)} />
    </>
  );
}
