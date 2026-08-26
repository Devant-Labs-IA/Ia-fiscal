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

type QueryBuilder = {
  select(columns: string): QueryBuilder;
  eq(column: string, value: unknown): QueryBuilder;
  order(
    column: string,
    options?: { ascending?: boolean; nullsFirst?: boolean },
  ): QueryBuilder;
  limit(count: number): QueryBuilder;
  abortSignal(signal: AbortSignal): Promise<DataResponse>;
};

type HomologationClient = {
  from(relation: string): QueryBuilder;
  rpc(functionName: string, args: Record<string, unknown>): Promise<DataResponse>;
  functions: {
    invoke(functionName: string, options: { body: Record<string, unknown> }): Promise<DataResponse>;
  };
};

function client(): HomologationClient {
  return getSupabaseClient() as unknown as HomologationClient;
}

function rows(value: unknown): Row[] {
  return Array.isArray(value) ? (value as Row[]) : [];
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

function timestampValue(value: string): number {
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

const DEMO_REGIMES: TaxpayerRegimeReadModel[] = [
  {
    municipalityId: "demo-cordeiropolis",
    taxpayerId: "tp-1",
    regimeCode: "prestador",
    regimeLabel: "Prestador de serviços",
    source: "massa_sintetica",
    verified: true,
  },
  {
    municipalityId: "demo-cordeiropolis",
    taxpayerId: "tp-2",
    regimeCode: "informador",
    regimeLabel: "Informador ou tomador",
    source: "massa_sintetica",
    verified: true,
  },
  {
    municipalityId: "demo-cordeiropolis",
    taxpayerId: "tp-3",
    regimeCode: "simples_nacional",
    regimeLabel: "Simples Nacional",
    source: "massa_sintetica",
    verified: true,
  },
  {
    municipalityId: "demo-cordeiropolis",
    taxpayerId: "tp-4",
    regimeCode: "prestador",
    regimeLabel: "Prestador de serviços",
    source: "massa_sintetica",
    verified: true,
  },
  {
    municipalityId: "demo-cordeiropolis",
    taxpayerId: "tp-5",
    regimeCode: "simples_nacional",
    regimeLabel: "Simples Nacional",
    source: "massa_sintetica",
    verified: true,
  },
];

function mapRegime(row: Row): TaxpayerRegimeReadModel {
  return {
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    regimeCode: stringValue(row["regime_code"], "nao_informado") as TaxRegimeCode,
    regimeLabel: stringValue(row["regime_label"], "Regime não informado"),
    source: stringValue(row["regime_source"], "nao_verificada"),
    verified: booleanValue(row["regime_verified"]),
  };
}

function mapTimeline(row: Row): TaxpayerTimelineItem {
  return {
    municipalityId: stringValue(row["municipality_id"]),
    taxpayerId: stringValue(row["taxpayer_id"]),
    caseId: nullableString(row["case_id"]),
    eventAt: stringValue(row["event_at"]),
    itemType: stringValue(row["item_type"], "event"),
    title: stringValue(row["title"], "Evento registrado"),
    summary: stringValue(row["summary"]),
    visibility: stringValue(row["visibility"], "staff"),
  };
}

function mapCommunication(row: Row): TaxpayerCommunicationItem {
  return {
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
  };
}

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

  const response = await query.abortSignal(AbortSignal.timeout(12_000));
  throwIfError(response.error, "taxpayer_regime_query_failed");
  return rows(response.data).map(mapRegime);
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

  const [timelineResponse, outboxResponse] = await Promise.all([
    client()
      .from("vw_taxpayer_360_timeline")
      .select("*")
      .eq("municipality_id", municipalityId)
      .eq("taxpayer_id", taxpayerId)
      .order("event_at", { ascending: false })
      .limit(200)
      .abortSignal(AbortSignal.timeout(12_000)),
    client()
      .from("homologation_notification_outbox")
      .select("id, municipality_id, taxpayer_id, case_id, subject, status, queued_at")
      .eq("municipality_id", municipalityId)
      .eq("taxpayer_id", taxpayerId)
      .order("queued_at", { ascending: false })
      .limit(100)
      .abortSignal(AbortSignal.timeout(12_000)),
  ]);
  throwIfError(timelineResponse.error, "taxpayer_timeline_query_failed");

  const timeline = rows(timelineResponse.data).map(mapTimeline);
  const queued: TaxpayerTimelineItem[] = outboxResponse.error
    ? []
    : rows(outboxResponse.data).map((row) => ({
        municipalityId: stringValue(row["municipality_id"]),
        taxpayerId: stringValue(row["taxpayer_id"]),
        caseId: nullableString(row["case_id"]),
        eventAt: stringValue(row["queued_at"]),
        itemType: "homologation_notification_queued",
        title: "Teste de notificação registrado na fila interna",
        summary: `${stringValue(row["subject"], "Mensagem informativa")} · situação ${stringValue(
          row["status"],
          "provider_pending",
        )}`,
        visibility: "staff",
      }));

  return [...timeline, ...queued].sort(
    (left, right) => timestampValue(right.eventAt) - timestampValue(left.eventAt),
  );
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

  const [communicationResponse, outboxResponse] = await Promise.all([
    client()
      .from("vw_taxpayer_360_communications")
      .select("*")
      .eq("municipality_id", municipalityId)
      .eq("taxpayer_id", taxpayerId)
      .order("occurred_at", { ascending: true })
      .limit(200)
      .abortSignal(AbortSignal.timeout(12_000)),
    client()
      .from("homologation_notification_outbox")
      .select("id, municipality_id, taxpayer_id, case_id, subject, body_text, status, queued_at")
      .eq("municipality_id", municipalityId)
      .eq("taxpayer_id", taxpayerId)
      .order("queued_at", { ascending: true })
      .limit(100)
      .abortSignal(AbortSignal.timeout(12_000)),
  ]);
  throwIfError(communicationResponse.error, "taxpayer_communications_query_failed");

  const communications = rows(communicationResponse.data).map(mapCommunication);
  const queued: TaxpayerCommunicationItem[] = outboxResponse.error
    ? []
    : rows(outboxResponse.data).map((row) => ({
        municipalityId: stringValue(row["municipality_id"]),
        taxpayerId: stringValue(row["taxpayer_id"]),
        caseId: nullableString(row["case_id"]),
        communicationId: stringValue(row["id"]),
        communicationType: "homologation_notification",
        direction: "outbound",
        channelOrSource: "internal_email_outbox",
        title: stringValue(row["subject"], "Aviso informativo"),
        summary: stringValue(row["body_text"]),
        status: stringValue(row["status"], "provider_pending"),
        visibility: "staff",
        deliveryMode: "homologation",
        externalDeliveryAttempted: false,
        occurredAt: stringValue(row["queued_at"]),
      }));

  return [...communications, ...queued].sort(
    (left, right) => timestampValue(left.occurredAt) - timestampValue(right.occurredAt),
  );
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

  const response = await client().rpc("ia_list_homologation_recipients", {
    p_municipality_id: municipalityId,
  });
  throwIfError(response.error, "homologation_recipients_query_failed");
  return rows(response.data).map((row) => ({
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

  const response = await client().rpc("ia_queue_homologation_notification", {
    p_municipality_id: input.municipalityId,
    p_candidate_id: input.candidateId,
    p_taxpayer_id: input.taxpayerId,
    p_recipient_user_id: input.recipientUserId,
    p_subject: input.subject,
    p_body: input.body,
    p_client_request_id: input.clientRequestId,
  });
  throwIfError(response.error, "homologation_notification_queue_failed");
  const row = objectValue(response.data);
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

  const response = await client().functions.invoke("ia-fiscal-copilot", {
    body: {
      municipality_id: context.municipalityId,
      question,
      pathname: context.pathname,
      taxpayer_id: context.taxpayerId,
      case_id: context.caseId,
    },
  });
  throwIfError(response.error, "copilot_request_failed");
  const row = objectValue(response.data);
  const sourceRows = rows(row["sources"]);
  return {
    answer: stringValue(row["answer"], "Não foi possível gerar uma resposta informativa."),
    dataPoints: Array.isArray(row["data_points"])
      ? row["data_points"].filter((value): value is string => typeof value === "string")
      : [],
    sources: sourceRows.map((source) => ({
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
