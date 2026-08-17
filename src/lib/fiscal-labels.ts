export interface FiscalLabelDetails {
  label: string;
  description: string;
}

function normalizeFiscalCode(value: string): string {
  return value
    .trim()
    .replace(/([a-z\d])([A-Z])/g, "$1_$2")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("pt-BR")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function readablePortugueseText(value: string): string | null {
  const text = value.trim();
  if (!text) return null;
  if (/^[a-z0-9]+(?:[_-][a-z0-9]+)+$/i.test(text)) return null;
  if (
    /[áàãâéêíóôõúç]/i.test(text) ||
    /\b(aguardando|aviso|conta|contato|contribuinte|dados|diferença|documento|envio|externo|fiscal|municipal|não|orientação|pendente|procedimento|regra|resposta|saldo|sem|tema|validação|valor)\b/i.test(
      text,
    )
  ) {
    return text
      .replace(/ambiente de homologação/gi, "operação assistida")
      .replace(/de homologação/gi, "da operação assistida")
      .replace(/homologação/gi, "operação assistida")
      .replace(/^./, (letter) => letter.toLocaleUpperCase("pt-BR"));
  }
  return null;
}

const statusLabels: Record<string, string> = {
  active: "Ativo",
  ativo: "Ativo",
  answered: "Respondido",
  awaiting_fiscal: "Aguardando análise fiscal",
  awaiting_validation: "Aguardando validação",
  aguardando_documento: "Aguardando documento",
  aguardando_validacao: "Aguardando validação",
  a_vencer: "A vencer",
  blocked: "Bloqueado",
  blocked_unverified: "Bloqueado por validação pendente",
  bloqueado: "Bloqueado",
  baixado: "Baixado",
  cancelled: "Cancelado",
  canceled: "Cancelado",
  claimed: "Em análise",
  closed: "Encerrado",
  concluido: "Concluído",
  converted: "Convertida em procedimento fiscal",
  draft: "Em preparação",
  em_aberto: "Em aberto",
  em_analise: "Em análise",
  em_discussao: "Em discussão",
  eligible_after_verification: "Apto após validação",
  expired: "Cadastro substituído ou expirado",
  failed: "Falhou",
  future: "A vencer",
  incomplete: "Dados incompletos",
  inactive: "Inativo",
  initial_notice_pending: "Aviso inicial pendente",
  initial_notice_sent: "Aviso inicial registrado como enviado",
  in_review: "Em revisão",
  novo: "Novo",
  open: "Em aberto",
  overdue: "Vencido",
  paid: "Pago",
  parcelado: "Parcelado",
  pending: "Pendente",
  pending_regulation: "Aguardando regulamentação",
  pending_revalidation: "Aguardando nova conferência",
  prepared: "Preparado",
  preparado: "Preparado",
  published: "Publicado",
  ready: "Pronto",
  rejected: "Rejeitado",
  revoked: "Revogado",
  review_pending: "Aguardando revisão",
  settled: "Quitado",
  sem_vencimento: "Sem vencimento informado",
  submitted: "Recebido",
  suspended: "Suspenso",
  suspenso: "Suspenso",
  under_review: "Em revisão",
  unknown: "Situação não informada",
  vencido: "Vencido",
  waiting: "Aguardando atendimento",
};

export function fiscalStatusLabel(value: string): string {
  const normalized = normalizeFiscalCode(value);
  return statusLabels[normalized] ?? readablePortugueseText(value) ?? "Situação em análise";
}

const divergenceLabels: Record<string, FiscalLabelDetails> = {
  current_account_balance: {
    label: "Saldo da conta corrente municipal",
    description: "Compara os valores lançados, pagos e ainda em aberto no período.",
  },
  document_amount_mismatch: {
    label: "Diferença entre documento e valor declarado",
    description: "Indica que o valor do documento não coincide com o valor informado.",
  },
  missing_declaration: {
    label: "Declaração não localizada",
    description: "Indica ausência da declaração esperada para o período.",
  },
  payment_mismatch: {
    label: "Diferença de pagamento",
    description: "Compara o valor devido com o pagamento identificado para o período.",
  },
};

export function divergenceTypeDetails(value: string): FiscalLabelDetails {
  const normalized = normalizeFiscalCode(value);
  return (
    divergenceLabels[normalized] ?? {
      label: readablePortugueseText(value) ?? "Divergência fiscal em análise",
      description: "Indício operacional que precisa ser conferido pela equipe fiscal.",
    }
  );
}

export function divergenceTypeLabel(value: string): string {
  return divergenceTypeDetails(value).label;
}

const taxpayerTypeLabels: Record<string, string> = {
  company: "Pessoa jurídica",
  individual: "Pessoa física",
  other: "Outro tipo de contribuinte",
};

export function taxpayerTypeLabel(value: string): string {
  return taxpayerTypeLabels[normalizeFiscalCode(value)] ?? "Tipo cadastral não informado";
}

export function fiscalRuleDetails(
  value: string,
  version: number | string | null,
): FiscalLabelDetails {
  const normalized = normalizeFiscalCode(value);
  const versionLabel =
    version == null || version === "" ? "versão não informada" : `versão ${version}`;

  if (normalized.includes("current_account_balance")) {
    return {
      label: `Conferência do saldo da conta corrente — ${versionLabel}`,
      description:
        "Compara lançamentos, pagamentos e saldo em aberto; requer conferência da equipe fiscal.",
    };
  }
  if (normalized.includes("homologation")) {
    return {
      label: `Regra da operação assistida — ${versionLabel}`,
      description: "Critério automatizado em conferência pela equipe fiscal.",
    };
  }
  return {
    label: `Regra fiscal configurada — ${versionLabel}`,
    description: "Critério automatizado que deve ser conferido antes de qualquer conclusão fiscal.",
  };
}

export function fiscalRulePresentation(
  code: string,
  version: number | string | null,
  configuredName: string | null,
  configuredDescription: string | null,
): FiscalLabelDetails {
  const fallback = fiscalRuleDetails(code, version);
  return {
    label: configuredName
      ? (readablePortugueseText(configuredName) ?? fallback.label)
      : fallback.label,
    description: configuredDescription
      ? (readablePortugueseText(configuredDescription) ?? fallback.description)
      : fallback.description,
  };
}

const operationalReasonLabels: Record<string, string> = {
  no_current_approved_exact_knowledge:
    "Ainda não existe uma resposta aprovada na base de conhecimento para este questionamento.",
};

export function fiscalOperationalReasonLabel(value: string): string {
  const normalized = normalizeFiscalCode(value);
  return (
    operationalReasonLabels[normalized] ??
    readablePortugueseText(value) ??
    "Motivo operacional pendente de validação pela equipe fiscal."
  );
}

export function debtClassificationRuleDetails(value: string): FiscalLabelDetails {
  const normalized = normalizeFiscalCode(value);
  const version = /_v(\d+)$/.exec(normalized)?.[1];

  if (normalized.includes("current_account_maturity")) {
    return {
      label: `Classificação de vencimentos da conta corrente — ${
        version ? `versão ${version}` : "versão configurada"
      }`,
      description:
        "Classifica cada competência conforme o vencimento e o saldo que permanece em aberto.",
    };
  }
  if (normalized.includes("demo")) {
    return {
      label: "Classificação demonstrativa de vencimentos",
      description: "Critério demonstrativo; exige conferência antes de qualquer uso fiscal.",
    };
  }
  return {
    label: "Regra municipal de classificação de débito",
    description: "Critério municipal usado para organizar a situação do débito por competência.",
  };
}

export function debtClassificationRuleLabel(value: string): string {
  return debtClassificationRuleDetails(value).label;
}

const blockReasonLabels: Record<string, string> = {
  assisted_external_delivery_locked: "Envio externo bloqueado na operação assistida",
  contact_unverified: "Contato ainda não verificado",
  delivery_not_authorized: "Envio externo não autorizado",
  external_delivery_disabled: "Envio externo desativado na operação assistida",
  external_delivery_locked: "Envio externo bloqueado na operação assistida",
  external_delivery_not_authorized: "Envio externo não autorizado",
  invalid_contact: "Contato inválido",
  missing_contact: "Contato não cadastrado",
  missing_email: "E-mail não cadastrado",
  missing_verified_contact: "Nenhum contato verificado",
  pending_revalidation: "Aguardando nova conferência",
  relationship_unverified: "Vínculo com o contribuinte ainda não verificado",
  superseded_contact_or_relationship: "Contato ou vínculo substituído por cadastro mais recente",
  unverified: "Contato ainda não verificado",
  unverification: "Contato ainda não verificado",
  validation_pending: "Validação interna pendente",
};

export function blockReasonLabel(value: string): string {
  const normalized = normalizeFiscalCode(value);
  if (!normalized) return "Validação interna pendente";
  if (blockReasonLabels[normalized]) return blockReasonLabels[normalized];
  if (normalized.includes("unverif")) return "Contato ainda não verificado";
  if (normalized.includes("external") && normalized.includes("author")) {
    return "Envio externo não autorizado";
  }
  return readablePortugueseText(value) ?? "Pendência de validação interna";
}

export function blockReasonSummary(value: unknown): string {
  const reasons = parseBlockReasons(value);
  return reasons.length ? reasons.map(blockReasonLabel).join(" · ") : "Validação interna pendente";
}

const recipientTypeLabels: Record<string, string> = {
  accountant: "Contabilidade responsável",
  legal_representative: "Representante legal",
  taxpayer: "Contribuinte",
};

export function recipientTypeLabel(value: string): string {
  return recipientTypeLabels[normalizeFiscalCode(value)] ?? "Destinatário autorizado";
}

const notificationPurposeLabels: Record<string, string> = {
  case_update: "Atualização de procedimento fiscal",
  debt_reminder: "Lembrete de débito",
  divergence_notice: "Aviso sobre divergência para conferência",
  document_request: "Solicitação de documento",
  initial_inspection_alert: "Aviso inicial para conferência fiscal",
  initial_inspection_alert_sandbox: "Aviso inicial para conferência fiscal",
  initial_notice: "Aviso inicial de conferência",
  revalidation_notice: "Pedido de nova conferência",
};

const notificationChannelLabels: Record<string, string> = {
  email: "E-mail",
  portal: "Portal protegido",
  whatsapp: "WhatsApp",
};

export function notificationChannelLabel(value: string): string {
  return notificationChannelLabels[normalizeFiscalCode(value)] ?? "Canal protegido";
}

export function notificationPurposeLabel(value: string): string {
  return (
    notificationPurposeLabels[normalizeFiscalCode(value)] ??
    readablePortugueseText(value) ??
    "Comunicação fiscal interna"
  );
}

const confidentialityLabels: Record<string, string> = {
  confidential: "Acesso restrito",
  internal: "Uso interno",
  public: "Acesso público",
  restricted: "Acesso restrito",
};

export function confidentialityLabel(value: string): string {
  return confidentialityLabels[normalizeFiscalCode(value)] ?? "Acesso controlado";
}

const workerStatusLabels: Record<string, string> = {
  critical: "Crítico",
  degraded: "Com atenção",
  disabled: "Desativado",
  error: "Com falha",
  failed: "Com falha",
  healthy: "Operacional",
  operational: "Operacional",
  paused: "Pausado",
  ready: "Operacional",
  running: "Em execução",
  stale: "Sem atualização recente",
  stopped: "Parado",
  unhealthy: "Crítico",
  unknown: "Situação não informada",
  warning: "Com atenção",
};

export function workerStatusLabel(value: string): string {
  return workerStatusLabels[normalizeFiscalCode(value)] ?? "Situação não reconhecida";
}

const processingWorkerLabels: Record<string, string> = {
  calculation_worker: "Processador de cálculos fiscais",
  delivery_worker: "Processador de comunicações internas",
  divergence_worker: "Processador de divergências fiscais",
  fiscal_worker: "Processador fiscal",
  notification_worker: "Processador de simulações de notificação",
  sandbox_worker: "Processador da operação assistida",
  worker_sandbox: "Processador da operação assistida",
};

export function processingWorkerLabel(value: string): string {
  return processingWorkerLabels[normalizeFiscalCode(value)] ?? "Processador fiscal interno";
}

const environmentLabels: Record<string, string> = {
  assisted_operation: "Operação assistida",
  development: "Desenvolvimento",
  homologation: "Operação assistida",
  production: "Produção",
  staging: "Operação assistida",
  test: "Testes",
};

export function environmentLabel(value: string): string {
  return environmentLabels[normalizeFiscalCode(value)] ?? "Ambiente controlado";
}

export function workerHealthStatus(
  value: string,
): "operacional" | "atencao" | "critico" | "pausado" {
  const normalized = normalizeFiscalCode(value);
  if (["healthy", "operational", "ready", "running"].includes(normalized)) {
    return "operacional";
  }
  if (["critical", "error", "failed", "unhealthy"].includes(normalized)) return "critico";
  if (["disabled", "paused", "stopped"].includes(normalized)) return "pausado";
  return "atencao";
}

const eventTypeLabels: Record<string, string> = {
  approved_response_published: "Resposta aprovada registrada",
  case_created: "Procedimento criado",
  case_opened: "Procedimento aberto",
  case_question_claimed: "Atendimento assumido pela equipe fiscal",
  document_added: "Documento incluído",
  manual_response_published: "Resposta manual registrada",
  question_submitted: "Pergunta recebida",
  status_changed: "Situação do procedimento atualizada",
};

export function fiscalEventTypeLabel(value: string): string {
  return eventTypeLabels[normalizeFiscalCode(value)] ?? "Evento do procedimento fiscal";
}

const visibilityLabels: Record<string, string> = {
  confidential: "acesso restrito",
  internal: "uso interno",
  participants: "participantes do procedimento",
  public: "acesso público",
  restricted: "acesso restrito",
  staff: "equipe fiscal",
  taxpayer: "contribuinte vinculado",
};

export function visibilityLabel(value: string): string {
  return visibilityLabels[normalizeFiscalCode(value)] ?? "acesso controlado";
}

const operationalFieldLabels: Record<string, string> = {
  candidate_status: "Situação do destinatário",
  contact_number: "Número de contato",
  delivery_block_reason: "Motivo do bloqueio",
  execution_mode: "Modo de execução",
  location: "Localização",
  proposed_for: "Finalidade da comunicação",
  recipient_type: "Tipo de destinatário",
  rule_code: "Regra aplicada",
  rule_version: "Versão da regra",
  state: "Situação",
  state_key: "Identificador da situação",
};

export function operationalFieldLabel(value: string): string {
  return operationalFieldLabels[normalizeFiscalCode(value)] ?? "Informação operacional";
}

const knowledgeTaxScopeLabels: Record<string, string> = {
  fiscal_case_answer: "Resposta de procedimento fiscal",
  iss: "ISS",
  issqn: "ISSQN",
  simple_national: "Simples Nacional",
};

export function knowledgeTaxScopeLabel(value: string): string {
  return (
    knowledgeTaxScopeLabels[normalizeFiscalCode(value)] ??
    readablePortugueseText(value) ??
    "Tema tributário cadastrado"
  );
}

const knowledgeDivergenceScopeLabels: Record<string, string> = {
  case_chat: "Atendimento do procedimento",
  current_account_balance: "Saldo da conta corrente municipal",
  document_amount_mismatch: "Diferença entre documento e valor declarado",
  missing_declaration: "Declaração não localizada",
  payment_mismatch: "Diferença de pagamento",
};

export function knowledgeDivergenceScopeLabel(value: string): string {
  return (
    knowledgeDivergenceScopeLabels[normalizeFiscalCode(value)] ??
    readablePortugueseText(value) ??
    "Tema fiscal cadastrado"
  );
}

const knowledgeIntentLabels: Record<string, string> = {
  why_overdue_iss_may_trigger_inspection: "Fiscalização relacionada a débito de ISS vencido",
};

export function knowledgeIntentLabel(value: string): string {
  const normalized = normalizeFiscalCode(value);
  if (/^qa_[a-f0-9]{8,}$/.test(normalized)) return "Pergunta fiscal revisada";
  return (
    knowledgeIntentLabels[normalized] ??
    readablePortugueseText(value) ??
    "Orientação fiscal cadastrada"
  );
}

function collectBlockReasons(value: unknown, output: string[], depth: number): void {
  if (depth > 5 || output.length >= 20 || value == null || value === false) return;

  if (typeof value === "string") {
    const text = value.trim();
    if (!text) return;
    if (text.includes(";")) {
      text
        .split(";")
        .map((item) => item.trim())
        .filter(Boolean)
        .forEach((item) => collectBlockReasons(item, output, depth + 1));
      return;
    }
    if (
      (text.startsWith("[") && text.endsWith("]")) ||
      (text.startsWith("{") && text.endsWith("}"))
    ) {
      try {
        collectBlockReasons(JSON.parse(text), output, depth + 1);
        return;
      } catch {
        if (text.startsWith("{") && text.endsWith("}")) {
          text
            .slice(1, -1)
            .split(",")
            .map((item) => item.trim().replace(/^"|"$/g, ""))
            .filter(Boolean)
            .forEach((item) => collectBlockReasons(item, output, depth + 1));
          return;
        }
      }
    }
    output.push(text);
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((item) => collectBlockReasons(item, output, depth + 1));
    return;
  }

  if (typeof value !== "object") return;
  const record = value as Record<string, unknown>;
  const valueKeys = ["code", "reason", "message", "label"];
  const containerKeys = ["reasons", "block_reasons", "codes", "items"];
  let matched = false;

  for (const key of valueKeys) {
    if (record[key] == null) continue;
    matched = true;
    collectBlockReasons(record[key], output, depth + 1);
  }
  for (const key of containerKeys) {
    if (record[key] == null) continue;
    matched = true;
    collectBlockReasons(record[key], output, depth + 1);
  }
  if (matched) return;

  Object.entries(record).forEach(([key, item]) => {
    if (item === true) output.push(key);
    else if (typeof item === "string" || Array.isArray(item)) {
      collectBlockReasons(item, output, depth + 1);
    }
  });
}

export function parseBlockReasons(value: unknown): string[] {
  const reasons: string[] = [];
  collectBlockReasons(value, reasons, 0);
  return [...new Set(reasons.map((item) => item.trim()).filter(Boolean))].slice(0, 20);
}
