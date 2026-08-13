import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import {
  CheckCircle2,
  Clock3,
  Inbox,
  LockKeyhole,
  MessageSquareText,
  UserRoundCheck,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { RiskBadge } from "@/components/common/StatusBadges";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { formatDateTime } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type { ChatQueueItem } from "@/types/fiscal";

export const Route = createFileRoute("/atendimento")({
  head: () => ({
    meta: [
      { title: "Atendimento — IA Fiscal" },
      {
        name: "description",
        content:
          "Fila de perguntas do ambiente autenticado, com atribuição auditável e conversa protegida.",
      },
      { property: "og:title", content: "Atendimento — IA Fiscal" },
      {
        property: "og:description",
        content:
          "Fila de perguntas do ambiente autenticado, com atribuição auditável e conversa protegida.",
      },
    ],
  }),
  component: ServiceQueuePage,
});

const CLAIM_ROLES = new Set(["fiscal_auditor", "supervisor", "legal_reviewer"]);

function safeDateTime(value: string): string {
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? "Horário não informado" : formatDateTime(value);
}

function displayIdentifier(value: string): string {
  const digits = value.replace(/\D/g, "");
  if (digits.length !== 14) return value;
  return `${digits.slice(0, 2)}.${digits.slice(2, 5)}.***/**${digits.slice(10, 12)}-${digits.slice(12)}`;
}

function senderLabel(senderType: string): string {
  if (senderType === "taxpayer") return "Contribuinte";
  if (senderType === "accountant") return "Contabilidade";
  if (senderType === "fiscal") return "Equipe fiscal";
  return "Participante autorizado";
}

interface QueueItemProps {
  item: ChatQueueItem;
  membershipId: string | null;
  canClaim: boolean;
  claimPending: boolean;
  claimBlocked: boolean;
  onClaim(questionId: string): void;
}

function QueueItem({
  item,
  membershipId,
  canClaim,
  claimPending,
  claimBlocked,
  onClaim,
}: QueueItemProps) {
  const [conversationOpen, setConversationOpen] = useState(false);
  const conversation = useQuery({
    queryKey: fiscalKeys.caseMessages(item.municipalityId, item.caseId),
    queryFn: () => fiscalService.listCaseMessages(item.municipalityId, item.caseId),
    enabled: conversationOpen && Boolean(item.municipalityId && item.caseId),
  });

  const claimedByMe = Boolean(
    membershipId && item.assignedMembershipId && membershipId === item.assignedMembershipId,
  );
  const claimedByOther = Boolean(item.assignedMembershipId && !claimedByMe);
  const closed = ["answered", "closed", "cancelled"].includes(item.status);
  const claimEnabled = canClaim && !item.assignedMembershipId && !closed && !claimBlocked;

  return (
    <li className="rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="font-medium">{item.taxpayerName || "Contribuinte protegido"}</h3>
            <RiskBadge risk={item.priority} />
          </div>
          <p className="mt-1 text-xs tabular-nums text-muted-foreground">
            {item.caseNumber} · {displayIdentifier(item.cnpj)}
          </p>
        </div>
        <Badge variant="outline" className="font-normal">
          {item.origin}
        </Badge>
      </div>

      <div className="mt-4 rounded-md border border-border bg-muted/50 p-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Pergunta recebida
        </p>
        <p className="mt-1 whitespace-pre-wrap text-sm">{item.lastMessage}</p>
      </div>

      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
        <span className="inline-flex items-center gap-1.5">
          <Clock3 className="size-3.5" aria-hidden />
          {item.waitingLabel}
        </span>
        <span className="tabular-nums">Recebida em {safeDateTime(item.waitingSince)}</span>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-2">
        {closed ? (
          <Badge variant="secondary">Atendimento encerrado</Badge>
        ) : claimedByMe ? (
          <Badge className="bg-success-soft text-success hover:bg-success-soft">
            <CheckCircle2 className="mr-1 size-3.5" aria-hidden />
            Assumido por você
          </Badge>
        ) : claimedByOther ? (
          <Badge variant="secondary">Em análise por outro fiscal</Badge>
        ) : canClaim ? (
          <Button size="sm" disabled={!claimEnabled} onClick={() => onClaim(item.id)}>
            <UserRoundCheck className="size-4" aria-hidden />
            {claimPending ? "Assumindo…" : "Assumir atendimento"}
          </Button>
        ) : (
          <Badge variant="outline">Atribuição indisponível para este perfil</Badge>
        )}
      </div>

      <details
        className="mt-4 rounded-md border border-primary/20 bg-primary-soft/40"
        onToggle={(event) => setConversationOpen(event.currentTarget.open)}
      >
        <summary className="cursor-pointer px-3 py-2.5 text-sm font-medium text-primary">
          Consultar conversa protegida
        </summary>
        <div className="border-t border-primary/20 px-3 py-3">
          {conversation.isError ? (
            <ErrorState message="Não foi possível consultar esta conversa." />
          ) : conversation.isLoading ? (
            <SectionSkeleton rows={2} />
          ) : !conversation.data?.length ? (
            <EmptyState message="Nenhuma mensagem autorizada está disponível." />
          ) : (
            <ol className="space-y-3">
              {conversation.data.map((message) => (
                <li key={message.id} className="rounded-md border border-border bg-background p-3">
                  <div className="flex flex-wrap justify-between gap-2 text-xs text-muted-foreground">
                    <span>{senderLabel(message.senderType)}</span>
                    <time dateTime={message.createdAt}>{safeDateTime(message.createdAt)}</time>
                  </div>
                  <p className="mt-1 whitespace-pre-wrap text-sm">{message.body}</p>
                </li>
              ))}
            </ol>
          )}
          <p className="mt-3 text-xs text-muted-foreground">
            Exibindo até as 200 mensagens mais recentes, em ordem cronológica. Consulta somente
            leitura; redação, revisão e publicação permanecem bloqueadas durante a operação
            assistida.
          </p>
        </div>
      </details>
    </li>
  );
}

function ServiceQueuePage() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  const role = auth.access?.role ?? "";
  const municipalityId = auth.access?.municipalityId ?? "";
  const membershipId = auth.access?.membershipId ?? null;
  const canClaim = !auth.demo && Boolean(membershipId) && CLAIM_ROLES.has(role);

  const queue = useQuery({
    queryKey: fiscalKeys.chat(municipalityId),
    queryFn: () => fiscalService.listChatQueue(municipalityId),
    enabled: Boolean(municipalityId),
  });

  const claim = useMutation({
    mutationKey: ["claim-case-question"],
    mutationFn: async (questionId: string) => {
      if (!municipalityId || !membershipId) throw new Error("claim_context_missing");
      const claimedMembershipId = await fiscalService.claimCaseQuestion(
        questionId,
        municipalityId,
        membershipId,
        "human",
      );
      if (!membershipId || claimedMembershipId !== membershipId) {
        throw new Error("claim_membership_mismatch");
      }
      return claimedMembershipId;
    },
    retry: false,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: fiscalKeys.events(municipalityId) });
      toast.success("Atendimento assumido", {
        description: "A atribuição foi registrada na trilha de auditoria.",
      });
    },
    onError: () =>
      toast.error("Não foi possível assumir o atendimento", {
        description: "A fila será atualizada antes de uma nova tentativa.",
      }),
    onSettled: () => queryClient.invalidateQueries({ queryKey: fiscalKeys.chat(municipalityId) }),
  });

  const items = queue.data ?? [];
  const urgentCount = items.filter(
    (item) => item.priority === "alto" || item.priority === "critico",
  ).length;

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Atendimento</h1>
          <Badge variant="outline" className="border-primary/30 bg-primary-soft text-primary">
            <LockKeyhole className="mr-1 size-3.5" aria-hidden />
            Fluxo supervisionado
          </Badge>
        </div>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Perguntas recebidas no ambiente autenticado. Atribuição é interna e auditável; prioridade
          é operacional e não representa conclusão jurídica ou fiscal.
        </p>
      </header>

      <div className="grid gap-3 sm:grid-cols-2" aria-label="Resumo do atendimento">
        <div className="surface-card flex items-center gap-4 p-4">
          <span className="grid size-10 shrink-0 place-items-center rounded-md bg-primary-soft text-primary">
            <Inbox className="size-5" aria-hidden />
          </span>
          <div>
            <p className="text-2xl font-semibold tabular-nums">
              {queue.isLoading || queue.isError ? "—" : items.length}
            </p>
            <p className="text-xs text-muted-foreground">até 200 perguntas mais prioritárias</p>
          </div>
        </div>
        <div className="surface-card flex items-center gap-4 p-4">
          <span className="grid size-10 shrink-0 place-items-center rounded-md bg-warning-soft text-warning-foreground">
            <MessageSquareText className="size-5" aria-hidden />
          </span>
          <div>
            <p className="text-2xl font-semibold tabular-nums">
              {queue.isLoading || queue.isError ? "—" : urgentCount}
            </p>
            <p className="text-xs text-muted-foreground">com prioridade alta ou crítica</p>
          </div>
        </div>
      </div>

      <SectionCard
        title="Fila de perguntas"
        description="Fiscais autorizados podem assumir uma pergunta. Respostas e envios externos continuam bloqueados."
      >
        {queue.isError ? (
          <ErrorState message="Não foi possível carregar a fila de atendimento." />
        ) : queue.isLoading ? (
          <SectionSkeleton rows={4} />
        ) : items.length === 0 ? (
          <EmptyState message="Nenhuma pergunta está aguardando análise fiscal." />
        ) : (
          <ul className="space-y-3">
            {items.map((item) => (
              <QueueItem
                key={item.id}
                item={item}
                membershipId={membershipId}
                canClaim={canClaim}
                claimPending={claim.isPending && claim.variables === item.id}
                claimBlocked={claim.isPending}
                onClaim={(questionId) => claim.mutate(questionId)}
              />
            ))}
          </ul>
        )}
      </SectionCard>
    </div>
  );
}
