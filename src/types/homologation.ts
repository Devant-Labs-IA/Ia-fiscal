export type TaxRegimeCode =
  | "simples_nacional"
  | "prestador"
  | "informador"
  | "nao_informado";

export interface TaxpayerRegimeReadModel {
  municipalityId: string;
  taxpayerId: string;
  regimeCode: TaxRegimeCode;
  regimeLabel: string;
  source: string;
  verified: boolean;
}

export interface TaxpayerTimelineItem {
  municipalityId: string;
  taxpayerId: string;
  caseId: string | null;
  eventAt: string;
  itemType: string;
  title: string;
  summary: string;
  visibility: string;
}

export interface TaxpayerCommunicationItem {
  municipalityId: string;
  taxpayerId: string;
  caseId: string | null;
  communicationId: string;
  communicationType: string;
  direction: "inbound" | "outbound";
  channelOrSource: string;
  title: string;
  summary: string;
  status: string;
  visibility: string;
  deliveryMode: string | null;
  externalDeliveryAttempted: boolean;
  occurredAt: string;
}

export interface InternalTestRecipient {
  userId: string;
  email: string;
  fullName: string;
  role: string;
  source: "internal_user";
}

export interface QueueHomologationNotificationInput {
  municipalityId: string;
  candidateId: string;
  taxpayerId: string;
  recipientUserId: string;
  subject: string;
  body: string;
  clientRequestId: string;
}

export interface QueueHomologationNotificationResult {
  outboxId: string;
  status: string;
  queuedAt: string;
  recipientMasked: string;
}

export interface CopilotQuestionContext {
  municipalityId: string;
  role: string;
  pathname: string;
  taxpayerId: string | null;
  caseId: string | null;
}

export interface CopilotSource {
  kind: string;
  title: string;
  reference: string;
  occurredAt: string | null;
}

export interface CopilotAnswer {
  answer: string;
  dataPoints: string[];
  sources: CopilotSource[];
  limitations: string[];
  correlationId: string;
  mode: "ai" | "deterministic";
}
