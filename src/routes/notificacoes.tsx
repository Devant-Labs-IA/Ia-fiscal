import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { Ban, CheckCircle2, Clock3, MailCheck, ShieldAlert } from "lucide-react";
import { useState } from "react";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { ExternalDeliveryReadinessPanel } from "@/components/notifications/ExternalDeliveryReadinessPanel";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  blockReasonSummary,
  fiscalStatusLabel,
  notificationPurposeLabel,
  recipientTypeLabel,
} from "@/lib/fiscal-labels";
import { formatDateTime } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type { NotificationRecipientReadModel } from "@/types/read-models";

export const Route = createFileRoute("/notificacoes")({
  head: () => ({
    meta: [
      { title: "Notificações — IA Fiscal" },
      {
        name: "description",
        content:
          "Consulta de destinatários, validações e bloqueios de comunicação na operação assistida.",
      },
      { property: "og:title", content: "Notificações — IA Fiscal" },
      {
        property: "og:description",
        content:
          "Consulta de destinatários, validações e bloqueios de comunicação na operação assistida.",
      },
    ],
  }),
  component: NotificationsPage,
});

function safeDateTime(value: string): string {
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? "Data não informada" : formatDateTime(value);
}

function RecipientCard({
  item,
  onSimulate,
}: {
  item: NotificationRecipientReadModel;
  onSimulate: () => void;
}) {
  return (
    <li className="rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-medium">{recipientTypeLabel(item.recipientType)}</span>
            <Badge variant="secondary" className="font-medium">
              {fiscalStatusLabel(item.candidateStatus)}
            </Badge>
          </div>
          <p className="mt-1 break-all text-sm text-muted-foreground">{item.maskedEmail}</p>
        </div>

        <span className="inline-flex items-center gap-1.5 text-xs tabular-nums text-muted-foreground">
          <Clock3 className="size-3.5" aria-hidden />
          {safeDateTime(item.createdAt)}
        </span>
      </div>

      <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Finalidade proposta
          </dt>
          <dd className="mt-1">{notificationPurposeLabel(item.proposedFor)}</dd>
        </div>
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Prioridade operacional
          </dt>
          <dd className="mt-1 tabular-nums">{item.priority || "Não definida"}</dd>
        </div>
      </dl>

      <div className="mt-4 rounded-md border border-border bg-muted/50 p-3">
        <p className="flex items-start gap-2 text-sm">
          {item.safeForDelivery ? (
            <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-success" aria-hidden />
          ) : (
            <ShieldAlert className="mt-0.5 size-4 shrink-0 text-warning-foreground" aria-hidden />
          )}
          <span>
            <span className="font-medium">
              {item.safeForDelivery ? "Validações internas concluídas." : "Entrega bloqueada."}
            </span>{" "}
            {blockReasonSummary(item.deliveryBlockReason)}
          </span>
        </p>
      </div>

      <Button type="button" variant="outline" size="sm" className="mt-4" onClick={onSimulate}>
        Visualizar simulação
      </Button>
    </li>
  );
}

function NotificationsPage() {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const [simulation, setSimulation] = useState<NotificationRecipientReadModel | null>(null);
  const recipients = useQuery({
    queryKey: fiscalKeys.recipients(municipalityId),
    queryFn: () => fiscalService.listNotificationRecipients(municipalityId),
    enabled: Boolean(municipalityId),
  });

  const items = recipients.data ?? [];
  const blockedCount = items.filter((item) => !item.safeForDelivery).length;
  const readyCount = items.filter((item) => item.safeForDelivery).length;

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Notificações</h1>
          <Badge variant="outline" className="border-critical/40 bg-critical-soft text-critical">
            <Ban className="mr-1 size-3.5" aria-hidden />
            Envio externo desativado
          </Badge>
        </div>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Consulta dos candidatos a destinatário e das validações internas. Esta área não envia,
          agenda ou autoriza comunicações.
        </p>
      </header>

      <ExternalDeliveryReadinessPanel municipalityId={municipalityId} />

      <div className="grid gap-3 sm:grid-cols-3" aria-label="Resumo das notificações">
        <div className="surface-card p-4">
          <MailCheck className="size-5 text-primary" aria-hidden />
          <p className="mt-3 text-2xl font-semibold tabular-nums">
            {recipients.isLoading ? "—" : items.length}
          </p>
          <p className="text-xs text-muted-foreground">candidatos visíveis</p>
        </div>
        <div className="surface-card p-4">
          <ShieldAlert className="size-5 text-warning-foreground" aria-hidden />
          <p className="mt-3 text-2xl font-semibold tabular-nums">
            {recipients.isLoading ? "—" : blockedCount}
          </p>
          <p className="text-xs text-muted-foreground">com validações pendentes</p>
        </div>
        <div className="surface-card p-4">
          <CheckCircle2 className="size-5 text-success" aria-hidden />
          <p className="mt-3 text-2xl font-semibold tabular-nums">
            {recipients.isLoading ? "—" : readyCount}
          </p>
          <p className="text-xs text-muted-foreground">aptos somente na etapa interna</p>
        </div>
      </div>

      <SectionCard
        title="Fila de destinatários"
        description="Endereços permanecem mascarados; detalhes fiscais não são expostos em e-mail."
      >
        {recipients.isError ? (
          <ErrorState
            message="Não foi possível carregar os candidatos a destinatário."
            error={recipients.error}
            onRetry={() => void recipients.refetch()}
            retrying={recipients.isFetching}
          />
        ) : recipients.isLoading ? (
          <SectionSkeleton rows={5} />
        ) : items.length === 0 ? (
          <EmptyState message="Nenhum candidato a destinatário está disponível para consulta." />
        ) : (
          <ul className="space-y-3">
            {items.map((item) => (
              <RecipientCard
                key={item.candidateId}
                item={item}
                onSimulate={() => setSimulation(item)}
              />
            ))}
          </ul>
        )}
      </SectionCard>

      <Dialog open={Boolean(simulation)} onOpenChange={(open) => !open && setSimulation(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Simulação da notificação</DialogTitle>
            <DialogDescription>
              Prévia local para conferência interna. Nenhuma mensagem será enviada ou agendada.
            </DialogDescription>
          </DialogHeader>
          {simulation && (
            <div className="space-y-4">
              <div className="rounded-md border border-border bg-muted/50 p-4 text-sm">
                <p>Olá,</p>
                <p className="mt-3">
                  Existe uma informação disponível para conferência no portal autenticado:{" "}
                  {notificationPurposeLabel(simulation.proposedFor).toLocaleLowerCase("pt-BR")}.
                </p>
                <p className="mt-3">
                  Acesse o ambiente oficial para consultar os detalhes. Esta prévia não inicia
                  prazo, cobrança ou procedimento fiscal.
                </p>
              </div>
              <div className="rounded-md border border-warning/40 bg-warning-soft p-3 text-sm text-warning-foreground">
                Simulação somente leitura. O envio externo permanece bloqueado na operação
                assistida.
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
