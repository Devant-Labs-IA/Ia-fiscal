import type { AssistedOperationSafetyStatus } from "@/types/read-models";

export type ExternalDeliverySafetyState = "checking" | "blocked" | "attention" | "unverified";

export type ExternalDeliveryChecklistState = "confirmed" | "attention" | "unknown";

export interface ExternalDeliveryChecklistItem {
  id: string;
  label: string;
  detail: string;
  state: ExternalDeliveryChecklistState;
}

export interface ExternalDeliverySafetyPresentation {
  state: ExternalDeliverySafetyState;
  title: string;
  description: string;
  checklist: ExternalDeliveryChecklistItem[];
}

type QueryState = "loading" | "success" | "error";

function checklistItem(
  id: string,
  label: string,
  confirmed: boolean,
  confirmedDetail: string,
  attentionDetail: string,
  unknown: boolean,
): ExternalDeliveryChecklistItem {
  return {
    id,
    label,
    detail: unknown
      ? "Não foi possível confirmar este controle."
      : confirmed
        ? confirmedDetail
        : attentionDetail,
    state: unknown ? "unknown" : confirmed ? "confirmed" : "attention",
  };
}

export function deriveExternalDeliverySafetyPresentation(
  status: AssistedOperationSafetyStatus | undefined,
  queryState: QueryState,
): ExternalDeliverySafetyPresentation {
  const checking = queryState === "loading";
  const unknown = queryState === "error" || !status || !status.verified;
  const safelyBlocked = Boolean(
    status?.verified &&
    status.externalDeliveryBlocked &&
    status.masterLock &&
    !status.externalEmailEnabled &&
    !status.openEmailChannel &&
    !status.automaticNoticeEnabled &&
    status.pendingExternalJobs === 0,
  );

  const checklist: ExternalDeliveryChecklistItem[] = [
    checklistItem(
      "master-lock",
      "Trava mestra de comunicação",
      Boolean(status?.masterLock),
      "Ativa: nenhum envio externo pode prosseguir.",
      "Inativa: a proteção principal precisa ser revisada.",
      unknown,
    ),
    checklistItem(
      "external-email",
      "Envio externo por e-mail",
      !status?.externalEmailEnabled,
      "Desativado nas configurações municipais.",
      "Ativado: mantenha a operação suspensa até concluir a revisão.",
      unknown,
    ),
    checklistItem(
      "email-channel",
      "Canal externo de e-mail",
      !status?.openEmailChannel,
      "Fechado: nenhum canal de entrega está aberto.",
      "Aberto: o canal precisa ser revisado antes de qualquer uso.",
      unknown,
    ),
    checklistItem(
      "automatic-notice",
      "Avisos automáticos",
      !status?.automaticNoticeEnabled,
      "Desativados: não há disparo automático autorizado.",
      "Ativados: suspenda a automação até concluir a revisão.",
      unknown,
    ),
    checklistItem(
      "pending-jobs",
      "Fila de envios externos",
      status?.pendingExternalJobs === 0,
      "Sem tarefas externas pendentes.",
      `${status?.pendingExternalJobs ?? 0} tarefa(s) externa(s) aguardando processamento.`,
      unknown,
    ),
  ];

  if (checking) {
    return {
      state: "checking",
      title: "Verificando proteções",
      description: "Consultando o estado de segurança da comunicação externa.",
      checklist: checklist.map((item) => ({
        ...item,
        detail: "Aguardando verificação deste controle.",
        state: "unknown",
      })),
    };
  }

  if (unknown) {
    return {
      state: "unverified",
      title: "Estado não verificado",
      description:
        "Não foi possível confirmar as proteções. Por segurança, nenhuma liberação deve ser considerada.",
      checklist,
    };
  }

  if (safelyBlocked) {
    return {
      state: "blocked",
      title: "Envios externos bloqueados com segurança",
      description:
        "As proteções de bloqueio estão confirmadas. Esta verificação não autoriza nem realiza envios.",
      checklist,
    };
  }

  return {
    state: "attention",
    title: "Revisão de segurança necessária",
    description:
      "Um ou mais controles não estão no estado seguro esperado. Nenhum envio deve ser realizado.",
    checklist,
  };
}
