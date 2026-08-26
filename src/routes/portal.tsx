import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { CircleHelp, ExternalLink, LockKeyhole, MessageSquareText } from "lucide-react";
import { useRef, useState } from "react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { StatusBadge } from "@/components/common/StatusBadges";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import {
  AlertDialog,
  AlertDialogAction,
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
import { Textarea } from "@/components/ui/textarea";
import { formatDateTime } from "@/lib/format";
import {
  preparePortalQuestionSubmission,
  type PortalQuestionSubmission,
} from "@/routes/-portal-submission";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";

export const Route = createFileRoute("/portal")({
  head: () => ({
    meta: [
      { title: "Portal protegido — IA Fiscal" },
      {
        name: "description",
        content:
          "Consulta protegida dos próprios casos, histórico de conversa e canal de perguntas à fiscalização.",
      },
    ],
  }),
  component: PortalPage,
});

function portalSenderLabel(senderType: string): string {
  if (senderType === "taxpayer") return "Contribuinte";
  if (senderType === "accountant") return "Contabilidade";
  if (senderType === "fiscal") return "Equipe fiscal";
  return "Sistema";
}

function safeDateTime(value: string): string {
  return Number.isNaN(Date.parse(value)) ? "Data não informada" : formatDateTime(value);
}

function PortalConversation({
  municipalityId,
  caseId,
}: {
  municipalityId: string;
  caseId: string;
}) {
  const [conversationOpen, setConversationOpen] = useState(false);
  const messages = useQuery({
    queryKey: fiscalKeys.caseMessages(municipalityId, caseId),
    queryFn: () => fiscalService.listCaseMessages(municipalityId, caseId),
    enabled: conversationOpen && Boolean(municipalityId && caseId),
  });

  return (
    <details
      className="mt-4 rounded-md border border-primary/20 bg-primary-soft/30"
      onToggle={(event) => setConversationOpen(event.currentTarget.open)}
    >
      <summary className="cursor-pointer px-3 py-2.5 text-sm font-medium text-primary">
        Ver notificação e histórico da conversa
      </summary>
      <div className="border-t border-primary/20 px-3 py-3">
        {messages.isLoading ? (
          <SectionSkeleton rows={3} />
        ) : messages.isError ? (
          <ErrorState message="Não foi possível carregar a conversa deste processo." />
        ) : !messages.data?.length ? (
          <EmptyState message="Nenhuma mensagem está disponível neste processo." />
        ) : (
          <ol className="space-y-3">
            {messages.data.map((message) => (
              <li key={message.id} className="rounded-md border border-border bg-background p-3">
                <div className="flex flex-wrap justify-between gap-2 text-xs text-muted-foreground">
                  <span>{portalSenderLabel(message.senderType)}</span>
                  <time dateTime={message.createdAt}>{safeDateTime(message.createdAt)}</time>
                </div>
                <p className="mt-1 whitespace-pre-wrap text-sm">{message.body}</p>
              </li>
            ))}
          </ol>
        )}
      </div>
    </details>
  );
}

function PortalPage() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  const [body, setBody] = useState("");
  const [selectedCaseId, setSelectedCaseId] = useState("");
  const [confirmationOpen, setConfirmationOpen] = useState(false);
  const submissionRef = useRef<PortalQuestionSubmission | null>(null);
  const isPortalRole = auth.access?.role === "taxpayer" || auth.access?.role === "accountant";
  const municipalityId = auth.access?.municipalityId ?? "";

  const cases = useQuery({
    queryKey: fiscalKeys.portal(municipalityId),
    queryFn: () => fiscalService.listPortalCases(municipalityId),
    enabled: isPortalRole && Boolean(municipalityId),
  });

  const activeCaseId = selectedCaseId || cases.data?.[0]?.caseId || "";
  const submit = useMutation({
    mutationFn: (submission: PortalQuestionSubmission) =>
      fiscalService.submitCaseQuestion(
        submission.caseId,
        submission.body,
        submission.clientRequestId,
      ),
    onSuccess: async (_questionId, submission) => {
      if (submissionRef.current?.clientRequestId === submission.clientRequestId) {
        submissionRef.current = null;
      }
      setBody("");
      setConfirmationOpen(false);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: fiscalKeys.portal(municipalityId) }),
        queryClient.invalidateQueries({
          queryKey: fiscalKeys.caseMessages(municipalityId, submission.caseId),
        }),
      ]);
      toast.success("Pergunta registrada", {
        description:
          "A equipe fiscal fará a análise. Não há resposta automática nem efeito jurídico.",
      });
    },
    onError: () => toast.error("A pergunta não pôde ser registrada."),
  });

  function confirmSubmission() {
    const submission = preparePortalQuestionSubmission(submissionRef.current, activeCaseId, body);
    submissionRef.current = submission;
    submit.mutate(submission);
  }

  if (!isPortalRole) {
    return (
      <div className="space-y-5 py-4">
        <HomologationBanner />
        <SectionCard
          title="Portal protegido"
          description="Área exclusiva para vínculos de contribuinte ou contabilidade."
        >
          <div className="flex items-start gap-3 rounded-md border border-border bg-muted/30 p-4">
            <LockKeyhole className="mt-0.5 size-5 text-primary" aria-hidden />
            <p className="text-sm text-muted-foreground">
              Seu perfil fiscal não pode assumir a identidade de um contribuinte. Use as telas
              internas de atendimento e fiscalização.
            </p>
          </div>
        </SectionCard>
      </div>
    );
  }

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />
      <header>
        <p className="text-sm font-medium text-primary">Acesso protegido</p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight sm:text-3xl">
          Meus atendimentos fiscais
        </h1>
        <p className="mt-2 max-w-3xl text-sm text-muted-foreground">
          Consulte somente os casos vinculados ao seu usuário, desde a notificação inicial até as
          mensagens posteriores. Este canal é informativo e não substitui DTE, processo formal ou
          atendimento oficial.
        </p>
      </header>

      {cases.isLoading ? (
        <SectionSkeleton rows={4} />
      ) : cases.isError ? (
        <ErrorState message="Não foi possível consultar os casos autorizados." />
      ) : !cases.data?.length ? (
        <EmptyState message="Nenhum caso está disponível para este vínculo." />
      ) : (
        <div className="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(320px,1fr)]">
          <div className="space-y-4">
            {cases.data.map((item) => (
              <SectionCard
                key={item.caseId}
                title={item.title || item.caseNumber}
                description={`Processo ${item.caseNumber}`}
                action={<StatusBadge status={item.caseStatus} />}
              >
                <div className="space-y-3 text-sm">
                  <p>{item.summary || "Resumo em preparação pela equipe fiscal."}</p>
                  {item.legalBasisSummary ? (
                    <div className="rounded-md bg-muted/40 p-3">
                      <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                        Base informativa
                      </p>
                      <p className="mt-1 text-sm">{item.legalBasisSummary}</p>
                    </div>
                  ) : null}
                  <div className="flex flex-wrap items-center gap-2">
                    {item.legalReviewRequired ? (
                      <Badge variant="outline">Revisão jurídica pendente</Badge>
                    ) : null}
                    {item.officialSystemUrl?.startsWith("https://") ? (
                      <Button asChild size="sm" variant="outline">
                        <a href={item.officialSystemUrl} target="_blank" rel="noreferrer">
                          Ambiente oficial <ExternalLink className="size-3.5" aria-hidden />
                        </a>
                      </Button>
                    ) : null}
                  </div>
                </div>
                <PortalConversation municipalityId={municipalityId} caseId={item.caseId} />
              </SectionCard>
            ))}
          </div>

          <SectionCard
            title="Enviar uma pergunta"
            description="A pergunta entra na fila interna para revisão humana."
          >
            <div className="space-y-4">
              <label className="block space-y-2 text-sm font-medium">
                Caso relacionado
                <select
                  className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
                  value={activeCaseId}
                  disabled={submit.isPending}
                  onChange={(event) => setSelectedCaseId(event.target.value)}
                >
                  {cases.data.map((item) => (
                    <option key={item.caseId} value={item.caseId}>
                      {item.caseNumber}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block space-y-2 text-sm font-medium">
                Sua dúvida
                <Textarea
                  rows={7}
                  value={body}
                  maxLength={4000}
                  disabled={submit.isPending}
                  onChange={(event) => setBody(event.target.value)}
                  placeholder="Descreva sua dúvida sem incluir senhas ou dados bancários."
                />
              </label>
              <p className="flex gap-2 text-xs text-muted-foreground">
                <CircleHelp className="size-4 shrink-0" aria-hidden />
                Uma resposta nova exige revisão fiscal. O envio não gera ciência, prazo ou
                confissão.
              </p>
              <AlertDialog
                open={confirmationOpen}
                onOpenChange={(open) => {
                  if (!submit.isPending) setConfirmationOpen(open);
                }}
              >
                <AlertDialogTrigger asChild>
                  <Button className="w-full" disabled={body.trim().length < 5 || submit.isPending}>
                    <MessageSquareText className="size-4" aria-hidden />
                    Revisar e registrar pergunta
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Registrar esta pergunta?</AlertDialogTitle>
                    <AlertDialogDescription>
                      Ela será gravada no caso selecionado e ficará visível à equipe fiscal. Nenhuma
                      mensagem externa será enviada automaticamente.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel disabled={submit.isPending}>
                      Voltar e revisar
                    </AlertDialogCancel>
                    <AlertDialogAction
                      type="button"
                      disabled={submit.isPending}
                      onClick={(event) => {
                        event.preventDefault();
                        confirmSubmission();
                      }}
                    >
                      {submit.isPending ? "Registrando…" : "Confirmar registro"}
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            </div>
          </SectionCard>
        </div>
      )}
    </div>
  );
}
