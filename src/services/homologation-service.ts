import { isDemoMode } from "@/config/runtime";
import { getSupabaseClient } from "@/lib/supabase";
import type {
  CopilotAnswer,
  CopilotQuestionContext,
  InternalTestRecipient,
  QueueHomologationNotificationInput,
  QueueHomologationNotificationResult,
  TaxpayerCommunicationItem,
  TaxpayerRegimeReadModel,
  TaxpayerTimelineItem,
  TaxRegimeCode,
} from "@/types/homologation";

type Row = Record<string, unknown>;
type DataError = { code?: string; message?: string } | null;
type DataResponse = { data: unknown; error: DataError };

type FlexibleQuery = {
  select(columns: string): FlexibleQuery;
  eq(column: string, value: unknown): FlexibleQuery;
  order(
    column: string,
    options?: { ascending?: boolean; nullsFirst?: boolean },
  ): FlexibleQuery;
  limit(count: number): FlexibleQuery;
  abortSignal(signal: AbortSignal): Promise<DataResponse>;
};

type HomologationClient = {
  from(relation: string): FlexibleQuery;
  rpc(functionName: string, args: Record<string, unknown>): Promise<DataResponse>;
  functions: {
    invoke(functionName: string, options: { body: Record<string, unknown> }): Promise<DataResponse>;
  };
};

function client(): HomologationClient {
  return getSupabaseClient() as unknown as HomologationClient;
}

function stringValue(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function booleanValue(value: unknown): boolean {
  return value === true;
}

function objectValue(value: unknown): Row {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Row) : {};
}

function throwIfError(error: DataError, fallback: string): void {
  if (!error) return;
  throw new Error(error.code?.slice(0, 80) || fallback);
}

const DEMO_REGIMES: TaxpayerRegimeReadModel[] = [
  ["tp-1", "prestador", "Prestador de serviços"],
  ["tp-2", "informador", "Informador ou tomador"],
  ["tp-3", "simples_nacional", "Simples Nacional"],
  ["tp-4", "prestador", "Prestador de serviços"],
  ["tp-5", "simples_nacional", "Simples Nacional"],
].map(([taxpayerId, regimeCode, regimeLabel]) => ({
  municipalityId: "demo-cordeiropolis",
  taxpayerId,
  regimeCode: regimeCode as TaxRegimeCode,
  regimeLabel,
  source: "massa_sintetica",
  verified: true,
}));

async function listTaxpayerRegimes(
  municipalityId: string,
  taxpayerId?: string,
): Promise<TaxpayerRegimeReadModel[]> {
  if (isDemoMode()) {
    return taxpayerId
      ? DEMO_REGIMES.filter((item) => item.taxpayerId === taxpayerId)
      : DEMO_REGIMES;
  }

  let query = client()
    .from("vw_taxpayer_regimes")
    .select("*")
    .eq("municipality_id", municipalityId)
    .order("taxpayer_id", { ascending: true })
    .limit(1_000);
  if (taxpayerId) query = query.eq("taxpayer_id", taxpayerId);

  const { data, error } = await query.abortSignal(AbortSignal.timeout(12_000));
  throwIfError(error, "taxpayer_regime_query_failed");
  return (Array.isArray(data) ? (data as Row[]) : []).map((row) => ({
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    regimeCode: stringValue(row["regime_code"], "nao_informado") as TaxRegimeCode,
    regimeLabel: stringValue(row["regime_label"], "Regime não informado"),
    source: stringValue(row["regime_source"], "não verificada"),
    verified: booleanValue(row["regime_verified"]),
  }));
}

async function listTaxpayerTimeline(
  municipalityId: string,
  taxpayerId: string,
): Promise<TaxpayerTimelineItem[]> {
  if (isDemoMode()) {
    return [
      {
        municipalityId,
        taxpayerId,
        caseId: "fc-1",
        eventAt: "2026-07-31T09:00:00-03:00",
        itemType: "notification_prepared",
        title: "Notificação preparada para homologação",
        summary: "Prévia criada sem envio externo.",
        visibility: "staff",
      },
      {
        municipalityId,
        taxpayerId,
        caseId: "fc-1",
        eventAt: "2026-07-31T09:15:00-03:00",
        itemType: "question_submitted",
        title: "Pergunta registrada no atendimento",
        summary: "O contribuinte de teste questionou a competência 03/2026.",
        visibility: "participants",
      },
    ];
  }

  const { data, error } = await client()
    .from("vw_taxpayer_360_timeline")
    .select("*")
    .eq("municipality_id", municipalityId)
    .eq("taxpayer_id", taxpayerId)
    .order("event_at", { ascending: false })
    .limit(200)
    .abortSignal(AbortSignal.timeout(12_000));
  throwIfError(error, "taxpayer_timeline_query_failed");

  return (Array.isArray(data) ? (data as Row[]) : []).map((row) => ({
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    caseId: nullableString(row["case_id"]),
    eventAt: stringValue(row["event_at"]),
    itemType: stringValue(row["item_type"], "event"),
    title: stringValue(row["title"], "Evento registrado"),
    summary: stringValue(row["summary"]),
    visibility: stringValue(row["visibility"], "staff"),
  }));
}

async function listTaxpayerCommunications(
  municipalityId: string,
  taxpayerId: string,
): Promise<TaxpayerCommunicationItem[]> {
  if (isDemoMode()) {
    return [
      {
        municipalityId,
        taxpayerId,
        caseId: "fc-1",
        communicationId: "demo-notification-1",
        communicationType: "notification",
        direction: "outbound",
        channelOrSource: "email",
        title: "Aviso informativo",
        summary: "Mensagem de homologação registrada para um destinatário interno.",
        status: "prepared",
        visibility: "staff",
        deliveryMode: "homologation",
        externalDeliveryAttempted: false,
        occurredAt: "2026-07-31T09:00:00-03:00",
      },
      {
        municipalityId,
        taxpayerId,
        caseId: "fc-1",
        communicationId: "demo-message-1",
        communicationType: "chat_message",
        direction: "inbound",
        channelOrSource: "human",
        title: "taxpayer",
        summary: "Paguei a referência 03/2026. O pagamento aparece no sistema?",
        status: "published",
        visibility: "participants",
        deliveryMode: null,
        externalDeliveryAttempted: false,
        occurredAt: "2026-07-31T09:15:00-03:00",
      },
    ];
  }

  const { data, error } = await client()
    .from("vw_taxpayer_360_communications")
    .select("*")
    .eq("municipality_id", municipalityId)
    .eq("taxpayer_id", taxpayerId)
    .order("occurred_at", { ascending: true })
    .limit(200)
    .abortSignal(AbortSignal.timeout(12_000));
  throwIfError(error, "taxpayer_communications_query_failed");

  return (Array.isArray(data) ? (data as Row[]) : []).map((row) => ({
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    caseId: nullableString(row["case_id"]),
    communicationId: stringValue(row["communication_id"]),
    communicationType: stringValue(row["communication_type"], "communication"),
    direction: stringValue(row["direction"], "outbound") === "inbound" ? "inbound" : "outbound",
    channelOrSource: stringValue(row["channel_or_source"], "internal"),
    title: stringValue(row["title"], "Comunicação"),
    summary: stringValue(row["summary"]),
    status: stringValue(row["status"], "unknown"),
    visibility: stringValue(row["visibility"], "staff"),
    deliveryMode: nullableString(row["delivery_mode"]),
    externalDeliveryAttempted: booleanValue(row["external_delivery_attempted"]),
    occurredAt: stringValue(row["occurred_at"]),
  }));
}

async function listInternalTestRecipients(
  municipalityId: string,
): Promise<InternalTestRecipient[]> {
  if (isDemoMode()) {
    return [
      {
        userId: "demo-internal-user",
        email: "equipe-interna@example.test",
        fullName: "Equipe interna de homologação",
        role: "fiscal_auditor",
        source: "internal_user",
      },
    ];
  }

  const { data, error } = await client().rpc("ia_list_homologation_recipients", {
    p_municipality_id: municipalityId,
  });
  throwIfError(error, "homologation_recipients_query_failed");

  return (Array.isArray(data) ? (data as Row[]) : []).map((row) => ({
    userId: stringValue(row["user_id"]),
    email: stringValue(row["email"]),
    fullName: stringValue(row["full_name"], "Usuário interno"),
    role: stringValue(row["role"], "support_readonly"),
    source: "internal_user",
  }));
}

async function queueTestNotification(
  input: QueueHomologationNotificationInput,
): Promise<QueueHomologationNotificationResult> {
  if (isDemoMode()) {
    return {
      outboxId: crypto.randomUUID(),
      status: "provider_pending",
      queuedAt: new Date().toISOString(),
      recipientMasked: `${input.recipientUserId.slice(0, 4)}***`,
    };
  }

  const { data, error } = await client().rpc("ia_queue_homologation_notification", {
    p_municipality_id: input.municipalityId,
    p_candidate_id: input.candidateId,
    p_taxpayer_id: input.taxpayerId,
    p_recipient_user_id: input.recipientUserId,
    p_subject: input.subject,
    p_body: input.body,
    p_client_request_id: input.clientRequestId,
  });
  throwIfError(error, "homologation_notification_queue_failed");
  const row = objectValue(data);
  return {
    outboxId: stringValue(row["outbox_id"]),
    status: stringValue(row["status"], "provider_pending"),
    queuedAt: stringValue(row["queued_at"], new Date().toISOString()),
    recipientMasked: stringValue(row["recipient_masked"], "***"),
  };
}

async function askCopilot(
  question: string,
  context: CopilotQuestionContext,
): Promise<CopilotAnswer> {
  if (isDemoMode()) {
    return {
      answer:
        "Na massa de demonstração, o contribuinte possui registros de débito, divergência, procedimento e atendimento. A resposta é informativa e precisa ser validada pelo fiscal.",
      dataPoints: [
        "Consulta limitada ao município e ao perfil da sessão.",
        context.taxpayerId
          ? "Contexto do contribuinte selecionado incluído."
          : "Nenhum contribuinte específico foi selecionado.",
      ],
      sources: [
        {
          kind: "demo",
          title: "Massa sintética de homologação",
          reference: context.pathname,
          occurredAt: null,
        },
      ],
      limitations: ["A API do CIGIS ainda não está conectada neste cenário."],
      correlationId: crypto.randomUUID(),
      mode: "deterministic",
    };
  }

  const { data, error } = await client().functions.invoke("ia-fiscal-copilot", {
    body: {
      municipality_id: context.municipalityId,
      question,
      pathname: context.pathname,
      taxpayer_id: context.taxpayerId,
      case_id: context.caseId,
    },
  });
  throwIfError(error, "copilot_request_failed");
  const row = objectValue(data);
  const sources = Array.isArray(row["sources"]) ? (row["sources"] as Row[]) : [];
  return {
    answer: stringValue(row["answer"], "Não foi possível gerar uma resposta informativa."),
    dataPoints: Array.isArray(row["data_points"])
      ? row["data_points"].filter((value): value is string => typeof value === "string")
      : [],
    sources: sources.map((source) => ({
      kind: stringValue(source["kind"], "database"),
      title: stringValue(source["title"], "Fonte autorizada"),
      reference: stringValue(source["reference"]),
      occurredAt: nullableString(source["occurred_at"]),
    })),
    limitations: Array.isArray(row["limitations"])
      ? row["limitations"].filter((value): value is string => typeof value === "string")
      : [],
    correlationId: stringValue(row["correlation_id"], crypto.randomUUID()),
    mode: row["mode"] === "ai" ? "ai" : "deterministic",
  };
}

export const homologationService = {
  listTaxpayerRegimes,
  listTaxpayerTimeline,
  listTaxpayerCommunications,
  listInternalTestRecipients,
  queueTestNotification,
  askCopilot,
};
