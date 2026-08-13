import { useQuery } from "@tanstack/react-query";
import {
  AlertTriangle,
  CheckCircle2,
  CircleHelp,
  LoaderCircle,
  LockKeyhole,
  RefreshCw,
  Send,
} from "lucide-react";

import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  deriveExternalDeliverySafetyPresentation,
  type ExternalDeliveryChecklistState,
  type ExternalDeliverySafetyState,
} from "@/lib/external-delivery-readiness";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";

interface ExternalDeliveryReadinessPanelProps {
  municipalityId: string;
}

const STATUS_STYLES: Record<ExternalDeliverySafetyState, string> = {
  checking: "border-border bg-muted text-muted-foreground",
  blocked: "border-success/40 bg-success-soft text-success",
  attention: "border-warning/50 bg-warning-soft text-warning-foreground",
  unverified: "border-critical/40 bg-critical-soft text-critical",
};

function StatusIcon({
  state,
  className,
}: {
  state: ExternalDeliverySafetyState;
  className?: string;
}) {
  if (state === "checking") {
    return (
      <LoaderCircle
        className={cn("animate-spin motion-reduce:animate-none", className)}
        aria-hidden
      />
    );
  }
  if (state === "blocked") return <LockKeyhole className={className} aria-hidden />;
  return <AlertTriangle className={className} aria-hidden />;
}

function ChecklistIcon({ state }: { state: ExternalDeliveryChecklistState }) {
  if (state === "confirmed") {
    return <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-success" aria-hidden />;
  }
  if (state === "attention") {
    return <AlertTriangle className="mt-0.5 size-5 shrink-0 text-warning-foreground" aria-hidden />;
  }
  return <CircleHelp className="mt-0.5 size-5 shrink-0 text-muted-foreground" aria-hidden />;
}

function safeCheckedAt(value: string | null | undefined): string | null {
  if (!value || Number.isNaN(Date.parse(value))) return null;
  return formatDateTime(value);
}

export function ExternalDeliveryReadinessPanel({
  municipalityId,
}: ExternalDeliveryReadinessPanelProps) {
  const safetyQuery = useQuery({
    queryKey: fiscalKeys.externalDeliverySafety(municipalityId),
    queryFn: () => fiscalService.getAssistedOperationSafetyStatus(municipalityId),
    enabled: Boolean(municipalityId),
    staleTime: 30_000,
  });
  const queryState = safetyQuery.isPending ? "loading" : safetyQuery.isError ? "error" : "success";
  const presentation = deriveExternalDeliverySafetyPresentation(safetyQuery.data, queryState);
  const checkedAt = safeCheckedAt(safetyQuery.data?.checkedAt);

  return (
    <section className="surface-card" aria-labelledby="external-delivery-readiness-title">
      <div className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h2 id="external-delivery-readiness-title" className="text-base font-semibold">
              Comunicação externa
            </h2>
            <Badge
              variant="outline"
              className={cn("font-medium", STATUS_STYLES[presentation.state])}
            >
              <StatusIcon state={presentation.state} className="mr-1 size-3.5" />
              {presentation.title}
            </Badge>
          </div>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">{presentation.description}</p>
          {checkedAt && (
            <p className="mt-1 text-xs text-muted-foreground">Última verificação: {checkedAt}</p>
          )}
        </div>

        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button type="button" className="shrink-0">
              <Send className="mr-2 size-4" aria-hidden />
              Preparar envios externos
            </Button>
          </AlertDialogTrigger>
          <AlertDialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
            <AlertDialogHeader>
              <AlertDialogTitle>Preparação segura de envios externos</AlertDialogTitle>
              <AlertDialogDescription>
                Esta consulta apenas confere as proteções atuais. Ela não desbloqueia, agenda,
                autoriza ou envia nenhuma comunicação.
              </AlertDialogDescription>
            </AlertDialogHeader>

            <div className={cn("rounded-lg border p-4", STATUS_STYLES[presentation.state])}>
              <p className="flex items-start gap-2 font-medium">
                <StatusIcon state={presentation.state} className="mt-0.5 size-5 shrink-0" />
                {presentation.title}
              </p>
              <p className="mt-1 pl-7 text-sm">{presentation.description}</p>
            </div>

            <ol className="space-y-3" aria-label="Checklist das proteções de envio externo">
              {presentation.checklist.map((item) => (
                <li key={item.id} className="flex gap-3 rounded-lg border border-border p-3">
                  <ChecklistIcon state={item.state} />
                  <div>
                    <p className="text-sm font-medium">{item.label}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">{item.detail}</p>
                  </div>
                </li>
              ))}
            </ol>

            <div className="rounded-lg border border-border bg-muted/40 p-4 text-sm">
              <p className="font-medium">O que ainda precisa existir antes de uma liberação real</p>
              <p className="mt-1 text-muted-foreground">
                Provedor e remetente configurados, modelo aprovado, contatos verificados e
                autorização do responsável. Este painel não verifica esses requisitos e não muda
                nenhuma configuração.
              </p>
            </div>

            <AlertDialogFooter>
              <Button
                type="button"
                variant="outline"
                disabled={safetyQuery.isFetching}
                onClick={() => void safetyQuery.refetch()}
              >
                <RefreshCw
                  className={cn(
                    "mr-2 size-4",
                    safetyQuery.isFetching && "animate-spin motion-reduce:animate-none",
                  )}
                  aria-hidden
                />
                Verificar novamente
              </Button>
              <AlertDialogCancel>Fechar</AlertDialogCancel>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>
    </section>
  );
}
