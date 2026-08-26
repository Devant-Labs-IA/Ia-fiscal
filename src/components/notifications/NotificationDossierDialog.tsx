import { useMutation, useQuery } from "@tanstack/react-query";
import {
  AlertTriangle,
  Building2,
  Clock3,
  FileClock,
  MailCheck,
  MessageSquareText,
  ReceiptText,
  Send,
  ShieldCheck,
} from "lucide-react";
import { useMemo, useState, type ReactNode } from "react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
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
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  buildDefaultInternalEmailBody,
  DEFAULT_INTERNAL_EMAIL_SUBJECT,
  internalEmailBlockers,
} from "@/lib/homologation-policy";
import { formatCurrency, formatDateTime } from "@/lib/format";
import { dispatchInternalEmail } from "@/services/internal-email-service";
import { fiscalService } from "@/services/fiscal-service";
import { homologationService } from "@/services/homologation-service";
import type { NotificationRecipientReadModel } from "@/types/read-models";

interface NotificationDossierDialogProps {
  item: NotificationRecipientReadModel | null;
  open: boolean;
  onOpenChange(open: boolean): void;
}

interface SendResult {
  status: string;
  recipientMasked: string;
  providerMessageId: string | null;
}

function safeDateTime(value: string): string {
  if (!value || Number.isNaN(Date.parse(value))) return "Data não informada";
  return formatDateTime(value);
}

function communicationLabel(value: string): string {
  if (value === "notification") return "Notificação";
  if (value === "chat_message") return "Mensagem";
  if (value === "homologation_notification") return "E-mail interno";
  return "Comunicação";
}

function statusLabel(value: string): string {
  if (value === "sent") return "enviado";
  if (value === "delivered") return "entregue";
  if (value === "processing") return "processando";
  if (value === "failed") return "falhou";
  if (value === "bounced") return "devolvido";
  return "aguardando configuração do provedor";
}

export function NotificationDossierDialog({
  item,
  open,
  onOpenChange,
}: NotificationDossierDialogProps) {
  const auth = useAuth();
  const municipalityId = auth.access?.municipalityId ?? "";
  const [recipientUserId, setRecipientUserId] = useState("");
  const [sendResult, setSendResult] = useState<SendResult | null>(null);
  const subject = DEFAULT_INTERNAL_EMAIL_SUBJECT;
  const body = buildDefaultInternalEmailBody();
  const blockers = useMemo(() => internalEmailBlockers(subject, body), [body, subject]);
  const taxpayerId = item?.taxpayerId ?? "";

  const summaries = useQuery({
    queryKey: ["notification-dossier", municipalityId, taxpayerId, "summary"],
    queryFn: () => fiscalService.listTaxpayerSummaries(municipalityId),
    enabled: open && Boolean(municipalityId && taxpayerId),
  });
  const debts = useQuery({
    queryKey: ["notification-dossier", municipalityId, taxpayerId, "debts"],
    queryFn: () => fiscalService.listDebtPeriods(municipalityId, taxpayerId),
    enabled: open && Boolean(municipalityId && taxpayerId),
  });
  const divergences = useQuery({
    queryKey: ["notification-dossier", municipalityId, taxpayerId, "divergences"],
    queryFn: () => fiscalService.listDivergences(municipalityId, taxpayerId),
    enabled: open && Boolean(municipalityId && taxpayerId),
  });
  const cases = useQuery({
    queryKey: ["notification-dossier", municipalityId, taxpayerId, "cases"],
    queryFn: () => fiscalService.listFiscalCaseRows(municipalityId, taxpayerId),
    enabled: open && Boolean(municipalityId && taxpayerId),
  });
  const regimes = useQuery({
    queryKey: ["notification-dossier", municipalityId, taxpayerId, "regime"],
    queryFn: () => homologationService.listTaxpayerRegimes(municipalityId, taxpayerId),
    enabled: open && Boolean(municipalityId && taxpayerId),
    retry: false,
  });
  const timeline = useQuery({
    queryKey: ["notification-dossier", municipalityId, taxpayerId, "timeline"],
    queryFn: () => homologationService.listTaxpayerTimeline(municipalityId, taxpayerId),
    enabled: open && Boolean(municipalityId && taxpayerId),
    retry: false,
  });
  const communications = useQuery({
    queryKey: ["notification-dossier", municipalityId, taxpayerId, "communications"],
    queryFn: () => homologationService.listTaxpayerCommunications(municipalityId, taxpayerId),
    enabled: open && Boolean(municipalityId && taxpayerId),
    retry: false,
  });
  const recipients = useQuery({
    queryKey: ["notification-dossier", municipalityId, "internal-recipients"],
    queryFn: () => homologationService.listInternalTestRecipients(municipalityId),
    enabled: open && Boolean(municipalityId),
    retry: false,
  });

  const taxpayer = summaries.data?.find((candidate) => candidate.taxpayerId === taxpayerId);
  const regime = regimes.data?.[0];
  const selectedRecipient = recipients.data?.find(
    (candidate) => candidate.userId === recipientUserId,
  );
  const hasFiscalContext = (debts.data?.length ?? 0) > 0 || (divergences.data?.length ?? 0) > 0;
  const qualityGatePassed = Boolean(
    taxpayer?.taxId && regime?.verified && hasFiscalContext && selectedRecipient,
  );

  const send = useMutation({
    mutationFn: async (): Promise<SendResult> => {
      if (!item || !selectedRecipient) throw new Error("internal_recipient_missing");
      const queued = await homologationService.queueTestNotification({
        municipalityId,
        candidateId: item.candidateId,
        taxpayerId: item.taxpayerId,
        recipientUserId: selectedRecipient.userId,
        subject,
        body,
        clientRequestId: crypto.randomUUID(),
      });

      try {
        const dispatched = await dispatchInternalEmail(queued.outboxId);
        return {
          status: dispatched.status,
          recipientMasked: queued.recipientMasked,
          providerMessageId: dispatched.providerMessageId,
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : "";
        if (/provider_not_configured|configuration_missing/.test(message)) {
          return {
            status: "provider_pending",
            recipientMasked: queued.recipientMasked,
            providerMessageId: null,
          };
        }
        throw error;
      }
    },
    onSuccess: (result) => {
      setSendResult(result);
      if (["sent", "delivered"].includes(result.status)) {
        toast.success("E-mail interno enviado", {
          description: `Destinatário ${result.recipientMasked}. O contato original não foi utilizado.`,
        });
      } else {
        toast.success("E-mail interno registrado", {
          description: "O envio será concluído assim que o provedor estiver configurado.",
        });
      }
    },
    onError: () =>
      toast.error("O envio permaneceu bloqueado", {
        description:
          "Confira a qualidade dos dados, o destinatário interno e a configuração do provedor.",
      }),
  });

  function setOpen(nextOpen: boolean) {
    if (!nextOpen) {
      setRecipientUserId("");
      setSendResult(null);
      send.reset();
    }
    onOpenChange(nextOpen);
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-5xl">
        <DialogHeader>
          <DialogTitle>Dossiê da notificação</DialogTitle>
          <DialogDescription>
            Confira o contexto fiscal, o histórico e a conversa antes de enviar para um usuário
            interno. O contato original permanece bloqueado.
          </DialogDescription>
        </DialogHeader>

        {!item ? null : (
          <Tabs defaultValue="contexto" className="mt-2 space-y-4">
            <TabsList className="grid h-auto w-full grid-cols-2 gap-1 md:grid-cols-4">
              <TabsTrigger value="contexto">Contexto</TabsTrigger>
              <TabsTrigger value="historico">Histórico</TabsTrigger>
              <TabsTrigger value="conversa">Conversa</TabsTrigger>
              <TabsTrigger value="email">Enviar e-mail</TabsTrigger>
            </TabsList>

            <TabsContent value="contexto" className="space-y-4">
              {summaries.isLoading ? (
                <SectionSkeleton rows={4} />
              ) : summaries.isError || !taxpayer ? (
                <ErrorState message="Não foi possível validar o contribuinte desta notificação." />
              ) : (
                <>
                  <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                    <DossierMetric
                      icon={<Building2 aria-hidden />}
                      label="Contribuinte"
                      value={taxpayer.legalName}
                    />
                    <DossierMetric
                      icon={<ReceiptText aria-hidden />}
                      label="Saldo visível"
                      value={formatCurrency(taxpayer.openBalanceTotal)}
                    />
                    <DossierMetric
                      icon={<AlertTriangle aria-hidden />}
                      label="Divergências ativas"
                      value={String(taxpayer.activeDivergenceCount)}
                    />
                    <DossierMetric
                      icon={<MessageSquareText aria-hidden />}
                      label="Perguntas aguardando"
                      value={String(taxpayer.waitingQuestionCount)}
                    />
                  </div>

                  <SectionCard
                    title="Validação de qualidade"
                    description="O envio só avança com dados fiscais mínimos e destinatário interno."
                  >
                    <ul className="space-y-2 text-sm">
                      <QualityRow
                        ok={Boolean(taxpayer.taxId)}
                        label="CNPJ ou documento fiscal identificado"
                      />
                      <QualityRow
                        ok={regime?.verified === true}
                        label={`Regime: ${regime?.regimeLabel ?? "não informado"}`}
                      />
                      <QualityRow
                        ok={(debts.data?.length ?? 0) > 0}
                        label={`${debts.data?.length ?? 0} competência(s) de débito vinculada(s)`}
                      />
                      <QualityRow
                        ok={(divergences.data?.length ?? 0) > 0}
                        label={`${divergences.data?.length ?? 0} divergência(s) vinculada(s)`}
                      />
                      <QualityRow
                        ok={(cases.data?.length ?? 0) > 0}
                        label={`${cases.data?.length ?? 0} procedimento(s) vinculado(s)`}
                      />
                      <QualityRow
                        ok={(recipients.data?.length ?? 0) > 0}
                        label="Lista de usuários internos disponível"
                      />
                    </ul>
                  </SectionCard>
                </>
              )}
            </TabsContent>

            <TabsContent value="historico">
              <SectionCard
                title="Histórico do contribuinte"
                description="Eventos registrados no dossiê fiscal, do mais recente para o mais antigo."
              >
                {timeline.isLoading ? (
                  <SectionSkeleton rows={5} />
                ) : timeline.isError ? (
                  <ErrorState message="O histórico ainda não está disponível." />
                ) : !timeline.data?.length ? (
                  <EmptyState message="Nenhum evento foi localizado para este contribuinte." />
                ) : (
                  <ol className="space-y-3">
                    {timeline.data.map((event, index) => (
                      <li
                        key={`${event.eventAt}-${event.itemType}-${index}`}
                        className="rounded-md border border-border p-3"
                      >
                        <div className="flex flex-wrap justify-between gap-2">
                          <p className="font-medium">{event.title}</p>
                          <time className="text-xs text-muted-foreground" dateTime={event.eventAt}>
                            {safeDateTime(event.eventAt)}
                          </time>
                        </div>
                        <p className="mt-1 text-sm text-muted-foreground">
                          {event.summary || "Evento sem descrição adicional."}
                        </p>
                        <Badge variant="outline" className="mt-2">
                          {event.itemType}
                        </Badge>
                      </li>
                    ))}
                  </ol>
                )}
              </SectionCard>
            </TabsContent>

            <TabsContent value="conversa">
              <SectionCard
                title="Notificação e conversa"
                description="O e-mail inicial e as mensagens posteriores permanecem no mesmo processo."
              >
                {communications.isLoading ? (
                  <SectionSkeleton rows={5} />
                ) : communications.isError ? (
                  <ErrorState message="As comunicações ainda não estão disponíveis." />
                ) : !communications.data?.length ? (
                  <EmptyState message="Nenhuma comunicação foi registrada para este contribuinte." />
                ) : (
                  <ol className="space-y-3">
                    {communications.data.map((communication) => (
                      <li
                        key={communication.communicationId}
                        className="rounded-md border border-border bg-background p-3"
                      >
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <div className="flex flex-wrap items-center gap-2">
                            <Badge variant="secondary">
                              {communicationLabel(communication.communicationType)}
                            </Badge>
                            <Badge variant="outline">
                              {communication.direction === "inbound" ? "Recebida" : "Enviada"}
                            </Badge>
                          </div>
                          <time
                            className="text-xs text-muted-foreground"
                            dateTime={communication.occurredAt}
                          >
                            {safeDateTime(communication.occurredAt)}
                          </time>
                        </div>
                        <p className="mt-3 whitespace-pre-wrap text-sm">
                          {communication.summary || "Conteúdo não disponível."}
                        </p>
                        <p className="mt-2 text-xs text-muted-foreground">
                          {communication.channelOrSource} · {communication.status}
                        </p>
                      </li>
                    ))}
                  </ol>
                )}
              </SectionCard>
            </TabsContent>

            <TabsContent value="email" className="space-y-4">
              <SectionCard
                title="Mensagem informativa"
                description="Sem link, anexo ou valor. O destinatário é orientado a acessar o CIGIS."
              >
                <div className="rounded-md border border-border bg-muted/40 p-4 text-sm">
                  <p className="font-semibold">{subject}</p>
                  <p className="mt-4 whitespace-pre-wrap">{body}</p>
                </div>
                {blockers.length > 0 ? (
                  <ul className="mt-3 space-y-1 text-sm text-critical">
                    {blockers.map((blocker) => (
                      <li key={blocker}>• {blocker}</li>
                    ))}
                  </ul>
                ) : (
                  <p className="mt-3 flex items-center gap-2 text-sm text-success">
                    <ShieldCheck className="size-4" aria-hidden />
                    Conteúdo aprovado pela política determinística de envio interno.
                  </p>
                )}
              </SectionCard>

              <SectionCard
                title="Destinatário interno"
                description="Somente usuários internos ativos e autorizados aparecem nesta lista."
              >
                {recipients.isLoading ? (
                  <SectionSkeleton rows={2} />
                ) : recipients.isError ? (
                  <ErrorState message="A lista interna ainda não está disponível no backend." />
                ) : !recipients.data?.length ? (
                  <EmptyState message="Nenhum usuário interno está disponível para receber o teste." />
                ) : (
                  <div className="space-y-4">
                    <Select value={recipientUserId} onValueChange={setRecipientUserId}>
                      <SelectTrigger aria-label="Escolher destinatário interno">
                        <SelectValue placeholder="Selecione um usuário interno" />
                      </SelectTrigger>
                      <SelectContent>
                        {recipients.data.map((recipient) => (
                          <SelectItem key={recipient.userId} value={recipient.userId}>
                            {recipient.fullName} · {recipient.email}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>

                    {selectedRecipient ? (
                      <div className="rounded-md border border-primary/20 bg-primary-soft p-3 text-sm">
                        <p className="font-medium">{selectedRecipient.fullName}</p>
                        <p className="text-muted-foreground">{selectedRecipient.email}</p>
                        <p className="mt-1 text-xs text-muted-foreground">
                          Papel interno: {selectedRecipient.role}
                        </p>
                      </div>
                    ) : null}

                    <Button
                      type="button"
                      className="w-full"
                      disabled={
                        !qualityGatePassed ||
                        blockers.length > 0 ||
                        send.isPending ||
                        summaries.isError ||
                        !taxpayer
                      }
                      onClick={() => send.mutate()}
                    >
                      <Send className="size-4" aria-hidden />
                      {send.isPending ? "Enviando…" : "Enviar e-mail interno"}
                    </Button>

                    {sendResult ? (
                      <p className="flex items-center gap-2 rounded-md border border-success/30 bg-success-soft p-3 text-sm text-success">
                        <MailCheck className="size-4" aria-hidden />
                        Situação do envio: {statusLabel(sendResult.status)}.
                      </p>
                    ) : (
                      <p className="flex items-start gap-2 text-xs text-muted-foreground">
                        <Clock3 className="mt-0.5 size-3.5 shrink-0" aria-hidden />
                        O contato original nunca é utilizado. O sistema registra o conteúdo, o
                        destinatário interno e o resultado do provedor.
                      </p>
                    )}
                  </div>
                )}
              </SectionCard>
            </TabsContent>
          </Tabs>
        )}
      </DialogContent>
    </Dialog>
  );
}

function DossierMetric({
  icon,
  label,
  value,
}: {
  icon: ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="surface-card p-4">
      <span className="text-primary [&>svg]:size-4">{icon}</span>
      <p className="mt-3 line-clamp-2 font-semibold">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{label}</p>
    </div>
  );
}

function QualityRow({ ok, label }: { ok: boolean; label: string }) {
  return (
    <li className="flex items-start gap-2">
      {ok ? (
        <ShieldCheck className="mt-0.5 size-4 shrink-0 text-success" aria-hidden />
      ) : (
        <FileClock className="mt-0.5 size-4 shrink-0 text-warning-foreground" aria-hidden />
      )}
      <span>{label}</span>
    </li>
  );
}
