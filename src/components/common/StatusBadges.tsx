import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { HealthStatus, RiskLevel } from "@/types/fiscal";

const riskLabels: Record<RiskLevel, string> = {
  baixo: "Baixo",
  medio: "Médio",
  alto: "Alto",
  critico: "Crítico",
};

const riskStyles: Record<RiskLevel, string> = {
  baixo: "border-border bg-muted text-muted-foreground",
  medio: "border-accent/40 bg-success-soft text-success",
  alto: "border-warning/50 bg-warning-soft text-warning-foreground",
  critico: "border-critical/40 bg-critical-soft text-critical",
};

export function RiskBadge({ risk }: { risk: RiskLevel }) {
  return (
    <Badge variant="outline" className={cn("font-medium", riskStyles[risk])}>
      {riskLabels[risk]}
    </Badge>
  );
}

const caseStatusLabels: Record<string, string> = {
  novo: "Novo",
  em_analise: "Em análise",
  aguardando_documento: "Aguardando documento",
  concluido: "Concluído",
  vencido: "Vencido",
  a_vencer: "A vencer",
  parcelado: "Parcelado",
  em_discussao: "Em discussão",
  preparado: "Preparado",
  aguardando_validacao: "Aguardando validação",
  bloqueado: "Bloqueado",
  ativo: "Ativo",
  suspenso: "Suspenso",
  baixado: "Baixado",
};

export function StatusBadge({ status }: { status: string }) {
  return (
    <Badge variant="secondary" className="font-medium">
      {caseStatusLabels[status] ?? status}
    </Badge>
  );
}

const healthLabels: Record<HealthStatus, string> = {
  operacional: "Operacional",
  atencao: "Atenção",
  critico: "Crítico",
  pausado: "Pausado",
};

const healthStyles: Record<HealthStatus, string> = {
  operacional: "border-accent/40 bg-success-soft text-success",
  atencao: "border-warning/50 bg-warning-soft text-warning-foreground",
  critico: "border-critical/40 bg-critical-soft text-critical",
  pausado: "border-border bg-muted text-muted-foreground",
};

export function HealthBadge({ status }: { status: HealthStatus }) {
  return (
    <Badge variant="outline" className={cn("font-medium", healthStyles[status])}>
      {healthLabels[status]}
    </Badge>
  );
}
