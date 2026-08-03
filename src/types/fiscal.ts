/**
 * Contratos de domínio da IA Fiscal.
 * Estes tipos são a fronteira entre a UI e a futura integração com o backend
 * externo (Supabase). Nenhum componente deve depender do formato dos mocks.
 */

export type RiskLevel = "baixo" | "medio" | "alto" | "critico";

export type HealthStatus = "operacional" | "atencao" | "critico" | "pausado";

export interface DashboardMetric {
  id: string;
  label: string;
  value: string;
  context: string;
  trend?: {
    direction: "alta" | "baixa" | "estavel";
    value: string;
  };
  tone: "neutro" | "positivo" | "atencao" | "critico";
  icon: "contribuintes" | "debitos" | "fiscalizacoes" | "notificacoes" | "atendimento" | "calculos";
  route: string;
}

export interface DashboardSummary {
  environmentLabel: string;
  greeting: string;
  operationalSummary: string;
  referenceDate: string;
  metrics: DashboardMetric[];
}

export interface Taxpayer {
  id: string;
  name: string;
  cnpj: string;
  tradeName: string;
  segment: string;
  city: string;
  registrationStatus: "ativo" | "suspenso" | "baixado";
  monitoredSince: string;
}

export interface Debt {
  id: string;
  taxpayerId: string;
  tax: string;
  competences: string[];
  amount: number;
  dueDate: string;
  status: "vencido" | "a_vencer" | "parcelado" | "em_discussao";
}

export interface FiscalCase {
  id: string;
  taxpayer: Taxpayer;
  divergenceType: string;
  divergenceDetail: string;
  amount: number;
  competences: string[];
  risk: RiskLevel;
  assignee: string;
  status: "novo" | "em_analise" | "aguardando_documento" | "concluido";
  legalBasis: string[];
  debt: Debt;
}

export interface NotificationCandidate {
  id: string;
  taxpayerName: string;
  cnpj: string;
  channel: "e-mail" | "whatsapp" | "portal";
  contact: string;
  contactValidated: boolean;
  templateName: string;
  status: "preparado" | "aguardando_validacao" | "bloqueado";
  blockedReason: string;
  draftMessage: string;
}

export interface ChatQueueItem {
  id: string;
  municipalityId: string;
  caseId: string;
  caseNumber: string;
  taxpayerName: string;
  cnpj: string;
  lastMessage: string;
  waitingSince: string;
  waitingLabel: string;
  slaDueAt: string | null;
  status: string;
  handlingMode: "unassigned" | "human" | "ai_assist";
  assignedMembershipId: string | null;
  claimedAt: string | null;
  origin: "portal do contribuinte" | "whatsapp" | "e-mail" | "atendimento presencial";
  priority: RiskLevel;
  suggestedReply: string;
}

export interface AuditEvent {
  id: string;
  type: "calculo" | "segundo_cerebro" | "escalonamento" | "notificacao";
  title: string;
  description: string;
  occurredAt: string;
  actor: string;
}

export interface ProcessingHealthIndicator {
  id: string;
  label: string;
  status: HealthStatus;
  detail: string;
  metric: string;
}

export interface ProductionBlocker {
  id: string;
  title: string;
  description: string;
  done: boolean;
  owner: string;
}
