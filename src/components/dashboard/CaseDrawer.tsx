import { Link } from "@tanstack/react-router";
import { FileText, Landmark, Receipt } from "lucide-react";

import { RiskBadge, StatusBadge } from "@/components/common/StatusBadges";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { formatCurrency, formatDate, maskCnpj } from "@/lib/format";
import type { FiscalCase } from "@/types/fiscal";

interface CaseDrawerProps {
  fiscalCase: FiscalCase | null;
  onOpenChange: (open: boolean) => void;
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs font-medium text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 text-sm">{value}</dd>
    </div>
  );
}

export function CaseDrawer({ fiscalCase, onOpenChange }: CaseDrawerProps) {
  const hasFinancialReference = Boolean(fiscalCase?.competences.length);

  return (
    <Sheet open={Boolean(fiscalCase)} onOpenChange={onOpenChange}>
      <SheetContent className="w-full overflow-y-auto sm:max-w-xl">
        {fiscalCase && (
          <>
            <SheetHeader className="space-y-1 text-left">
              <SheetTitle className="text-lg">{fiscalCase.taxpayer.name}</SheetTitle>
              <SheetDescription>
                CNPJ {maskCnpj(fiscalCase.taxpayer.cnpj)} · {fiscalCase.taxpayer.segment}
              </SheetDescription>
            </SheetHeader>

            <div className="space-y-6 px-4 pb-8">
              <HomologationBanner />

              <div className="flex flex-wrap items-center gap-2">
                <RiskBadge risk={fiscalCase.risk} />
                <StatusBadge status={fiscalCase.status} />
                <StatusBadge status={fiscalCase.taxpayer.registrationStatus} />
              </div>

              <section>
                <h3 className="flex items-center gap-2 text-sm font-semibold">
                  <Landmark className="size-4 text-primary" aria-hidden />
                  Resumo do contribuinte
                </h3>
                <dl className="mt-3 grid grid-cols-2 gap-3">
                  <Field label="Nome fantasia" value={fiscalCase.taxpayer.tradeName} />
                  <Field label="Município" value={fiscalCase.taxpayer.city} />
                  <Field
                    label="Monitorado desde"
                    value={formatDate(fiscalCase.taxpayer.monitoredSince)}
                  />
                  <Field label="Responsável pelo caso" value={fiscalCase.assignee} />
                </dl>
              </section>

              <Separator />

              <section>
                <h3 className="flex items-center gap-2 text-sm font-semibold">
                  <FileText className="size-4 text-primary" aria-hidden />
                  Divergência apurada
                </h3>
                <p className="mt-2 text-sm font-medium">{fiscalCase.divergenceType}</p>
                <p className="mt-1 text-sm text-muted-foreground">{fiscalCase.divergenceDetail}</p>
                <p className="mt-2 text-xs text-muted-foreground">
                  Competências: {fiscalCase.competences.join(", ")}
                </p>
              </section>

              <Separator />

              <section>
                <h3 className="flex items-center gap-2 text-sm font-semibold">
                  <Receipt className="size-4 text-primary" aria-hidden />
                  Referência financeira da divergência
                </h3>
                <dl className="mt-3 grid grid-cols-2 gap-3">
                  <Field label="Escopo" value={fiscalCase.debt.tax} />
                  <Field label="Situação" value={fiscalCase.debt.status.replace("_", " ")} />
                  <Field
                    label="Fim do período"
                    value={
                      hasFinancialReference ? formatDate(fiscalCase.debt.dueDate) : "Não vinculado"
                    }
                  />
                  <Field
                    label="Diferença apurada"
                    value={
                      hasFinancialReference
                        ? formatCurrency(fiscalCase.debt.amount)
                        : "Não vinculada"
                    }
                  />
                </dl>
              </section>

              <Separator />

              <section>
                <h3 className="text-sm font-semibold">Base legal</h3>
                <ul className="mt-2 space-y-2 text-sm text-muted-foreground">
                  {fiscalCase.legalBasis.map((basis) => (
                    <li key={basis} className="flex gap-2">
                      <span
                        className="mt-1.5 size-1.5 shrink-0 rounded-full bg-accent"
                        aria-hidden
                      />
                      {basis}
                    </li>
                  ))}
                </ul>
              </section>

              <div className="flex flex-wrap gap-2">
                <Button asChild>
                  <Link to="/fiscalizacoes">Abrir fiscalizações</Link>
                </Button>
                <Button asChild variant="outline">
                  <Link
                    to="/contribuintes/$taxpayerId"
                    params={{ taxpayerId: fiscalCase.taxpayer.id }}
                  >
                    Ver contribuinte 360
                  </Link>
                </Button>
              </div>
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
