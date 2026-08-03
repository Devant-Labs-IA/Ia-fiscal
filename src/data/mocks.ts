/**
 * Dados fictícios de homologação. Centralizados aqui de propósito:
 * a substituição pelo backend externo acontece apenas em src/services.
 */
import type {
  AuditEvent,
  ChatQueueItem,
  DashboardSummary,
  Debt,
  FiscalCase,
  NotificationCandidate,
  ProcessingHealthIndicator,
  ProductionBlocker,
  Taxpayer,
} from "@/types/fiscal";

export const HOMOLOGATION_NOTICE = "Ambiente de homologação — nenhum envio externo autorizado";

export const MUNICIPALITY = "Cordeirópolis/SP";

export const currentFiscal = {
  name: "Fiscal de Homologação A",
  role: "Fiscal tributária",
  registration: "Matrícula HML-001",
  initials: "FH",
} as const;

export const dashboardSummary: DashboardSummary = {
  environmentLabel: HOMOLOGATION_NOTICE,
  greeting: "Bom dia, Fiscal",
  operationalSummary:
    "43 contribuintes monitorados, 2 fiscalizações com achados e 1 atendimento aguardando resposta. Nenhuma notificação foi liberada para envio.",
  referenceDate: "2026-07-31T09:00:00-03:00",
  metrics: [
    {
      id: "contribuintes",
      label: "Contribuintes monitorados",
      value: "43",
      context: "Base carregada da malha fiscal de homologação",
      trend: { direction: "estavel", value: "sem alteração na semana" },
      tone: "neutro",
      icon: "contribuintes",
      route: "/contribuintes",
    },
    {
      id: "debitos",
      label: "Débitos vencidos",
      value: "72",
      context: "Valor total de R$ 50.706,22 em 18 contribuintes",
      trend: { direction: "alta", value: "+6,4% vs. competência anterior" },
      tone: "critico",
      icon: "debitos",
      route: "/debitos",
    },
    {
      id: "fiscalizacoes",
      label: "Fiscalizações com achados",
      value: "2",
      context: "Divergência de base de cálculo do ISS",
      trend: { direction: "alta", value: "+1 nesta semana" },
      tone: "atencao",
      icon: "fiscalizacoes",
      route: "/fiscalizacoes",
    },
    {
      id: "notificacoes",
      label: "Destinatários aguardando validação",
      value: "86",
      context: "Preparados, porém sem autorização de envio",
      tone: "atencao",
      icon: "notificacoes",
      route: "/notificacoes",
    },
    {
      id: "atendimento",
      label: "Atendimento aguardando fiscal",
      value: "1",
      context: "Escalado pelo Segundo Cérebro há 42 minutos",
      tone: "atencao",
      icon: "atendimento",
      route: "/atendimento",
    },
    {
      id: "calculos",
      label: "Cálculos bloqueados",
      value: "24",
      context: "Dados insuficientes de faturamento declarado",
      trend: { direction: "baixa", value: "-3 após reprocessamento" },
      tone: "critico",
      icon: "calculos",
      route: "/relatorios",
    },
  ],
};

export const taxpayers: Taxpayer[] = [
  {
    id: "tp-1",
    name: "Empresa Alfa de Demonstração Ltda.",
    tradeName: "Alfa Demonstração",
    cnpj: "00000000000100",
    segment: "Beneficiamento de rochas ornamentais",
    city: "Cordeirópolis/SP",
    registrationStatus: "ativo",
    monitoredSince: "2025-11-03",
  },
  {
    id: "tp-2",
    name: "Empresa Beta de Demonstração Ltda.",
    tradeName: "Beta Demonstração",
    cnpj: "00000000000200",
    segment: "Transporte rodoviário de cargas",
    city: "Cordeirópolis/SP",
    registrationStatus: "ativo",
    monitoredSince: "2025-09-18",
  },
  {
    id: "tp-3",
    name: "Empresa Gama de Demonstração S/S",
    tradeName: "Gama Demonstração",
    cnpj: "00000000000300",
    segment: "Serviços odontológicos",
    city: "Cordeirópolis/SP",
    registrationStatus: "ativo",
    monitoredSince: "2026-01-22",
  },
  {
    id: "tp-4",
    name: "Empresa Delta de Demonstração Ltda.",
    tradeName: "Delta Demonstração",
    cnpj: "00000000000400",
    segment: "Construção de edifícios",
    city: "Cordeirópolis/SP",
    registrationStatus: "suspenso",
    monitoredSince: "2025-06-09",
  },
  {
    id: "tp-5",
    name: "Empresa Épsilon de Demonstração Ltda.",
    tradeName: "Épsilon Demonstração",
    cnpj: "00000000000500",
    segment: "Panificação e confeitaria",
    city: "Cordeirópolis/SP",
    registrationStatus: "ativo",
    monitoredSince: "2026-03-14",
  },
];

export const debts: Debt[] = [
  {
    id: "db-1",
    taxpayerId: "tp-1",
    tax: "ISS — serviços prestados",
    competences: ["01/2026", "02/2026", "03/2026"],
    amount: 18420.55,
    dueDate: "2026-04-15",
    status: "vencido",
  },
  {
    id: "db-2",
    taxpayerId: "tp-2",
    tax: "ISS retido na fonte",
    competences: ["11/2025", "12/2025"],
    amount: 12760.4,
    dueDate: "2026-01-20",
    status: "vencido",
  },
  {
    id: "db-3",
    taxpayerId: "tp-3",
    tax: "ISS — sociedade uniprofissional",
    competences: ["02/2026", "03/2026"],
    amount: 7310.9,
    dueDate: "2026-04-10",
    status: "em_discussao",
  },
  {
    id: "db-4",
    taxpayerId: "tp-4",
    tax: "ISS — obra civil",
    competences: ["09/2025", "10/2025", "11/2025"],
    amount: 9184.22,
    dueDate: "2025-12-15",
    status: "vencido",
  },
  {
    id: "db-5",
    taxpayerId: "tp-5",
    tax: "Taxa de fiscalização de funcionamento",
    competences: ["01/2026"],
    amount: 3030.15,
    dueDate: "2026-02-28",
    status: "parcelado",
  },
];

export const fiscalCases: FiscalCase[] = [
  {
    id: "fc-1",
    taxpayer: taxpayers[0]!,
    divergenceType: "Base de cálculo divergente",
    divergenceDetail:
      "Notas fiscais emitidas somam R$ 312.480,00 no trimestre, enquanto a base declarada para ISS foi de R$ 168.900,00.",
    amount: 18420.55,
    competences: ["01/2026", "02/2026", "03/2026"],
    risk: "critico",
    assignee: "Fiscal de Homologação A",
    status: "em_analise",
    legalBasis: [
      "Lei Complementar 116/2003, art. 7º — base de cálculo do ISS",
      "Código Tributário Municipal, art. 128 — obrigação acessória de declaração",
    ],
    debt: debts[0]!,
  },
  {
    id: "fc-2",
    taxpayer: taxpayers[1]!,
    divergenceType: "Retenção não recolhida",
    divergenceDetail:
      "Tomadores declararam retenção de ISS em 14 notas; não há recolhimento correspondente nas competências de 11/2025 e 12/2025.",
    amount: 12760.4,
    competences: ["11/2025", "12/2025"],
    risk: "alto",
    assignee: "Fiscal de Homologação B",
    status: "aguardando_documento",
    legalBasis: [
      "Lei Complementar 116/2003, art. 6º — responsabilidade tributária",
      "Decreto Municipal 4.512/2019, art. 22 — prazo de recolhimento",
    ],
    debt: debts[1]!,
  },
  {
    id: "fc-3",
    taxpayer: taxpayers[2]!,
    divergenceType: "Enquadramento indevido",
    divergenceDetail:
      "Regime de sociedade uniprofissional aplicado com dois sócios não habilitados no conselho de classe.",
    amount: 7310.9,
    competences: ["02/2026", "03/2026"],
    risk: "medio",
    assignee: "Fiscal de Homologação A",
    status: "novo",
    legalBasis: [
      "Decreto-Lei 406/1968, art. 9º, §3º — tributação fixa por profissional",
      "Código Tributário Municipal, art. 96 — requisitos de enquadramento",
    ],
    debt: debts[2]!,
  },
  {
    id: "fc-4",
    taxpayer: taxpayers[3]!,
    divergenceType: "Obra sem habite-se declarado",
    divergenceDetail:
      "Alvará com área de 1.850 m² e nenhuma nota de serviço de construção civil vinculada ao endereço.",
    amount: 9184.22,
    competences: ["09/2025", "10/2025", "11/2025"],
    risk: "alto",
    assignee: "Fiscal de Homologação C",
    status: "em_analise",
    legalBasis: [
      "Lei Complementar 116/2003, item 7.02 da lista de serviços",
      "Código de Obras Municipal, art. 61 — vistoria e habite-se",
    ],
    debt: debts[3]!,
  },
  {
    id: "fc-5",
    taxpayer: taxpayers[4]!,
    divergenceType: "Taxa de funcionamento em atraso",
    divergenceDetail:
      "Parcelamento firmado em 02/2026 com duas parcelas em atraso e emissão de notas mantida.",
    amount: 3030.15,
    competences: ["01/2026"],
    risk: "baixo",
    assignee: "Fiscal de Homologação B",
    status: "aguardando_documento",
    legalBasis: [
      "Código Tributário Municipal, art. 210 — taxas de licença",
      "Lei Municipal 3.998/2021, art. 5º — parcelamento administrativo",
    ],
    debt: debts[4]!,
  },
];

export const chatQueue: ChatQueueItem[] = [
  {
    id: "cq-1",
    taxpayerName: "Empresa Alfa de Demonstração Ltda.",
    cnpj: "00000000000100",
    lastMessage:
      "Recebi uma cobrança de ISS de janeiro, mas emitimos as notas pelo portal. Como faço a conferência?",
    waitingSince: "2026-07-31T08:18:00-03:00",
    waitingLabel: "aguardando há 42 min",
    origin: "portal do contribuinte",
    priority: "alto",
    suggestedReply:
      "Bom dia. Verificamos que as notas de 01/2026 foram emitidas, porém a base declarada ficou abaixo do total emitido. Você pode conferir o comparativo no portal, aba Declarações, e retificar a competência até o vencimento. Caso confirme o valor, o débito será recalculado automaticamente.",
  },
  {
    id: "cq-2",
    taxpayerName: "Empresa Beta de Demonstração Ltda.",
    cnpj: "00000000000200",
    lastMessage: "Preciso da segunda via da guia de 12/2025 com o novo vencimento.",
    waitingSince: "2026-07-31T07:05:00-03:00",
    waitingLabel: "aguardando há 1 h 55 min",
    origin: "whatsapp",
    priority: "medio",
    suggestedReply:
      "Bom dia. A segunda via da guia de 12/2025 pode ser emitida no portal do contribuinte, em Débitos, selecionando a competência. O valor é atualizado com juros e multa até a data escolhida para pagamento.",
  },
  {
    id: "cq-3",
    taxpayerName: "Empresa Gama de Demonstração S/S",
    cnpj: "00000000000300",
    lastMessage:
      "Discordamos do enquadramento aplicado. Podemos apresentar documentos do conselho?",
    waitingSince: "2026-07-30T17:40:00-03:00",
    waitingLabel: "aguardando há 15 h",
    origin: "e-mail",
    priority: "critico",
    suggestedReply:
      "Boa tarde. Sim. A comprovação de habilitação dos sócios pode ser anexada no processo administrativo, aba Documentos. A análise do enquadramento fica suspensa até a manifestação fiscal.",
  },
];

export const notificationCandidates: NotificationCandidate[] = [
  {
    id: "nc-1",
    taxpayerName: "Empresa Alfa de Demonstração Ltda.",
    cnpj: "00000000000100",
    channel: "e-mail",
    contact: "nao-enviar@example.invalid",
    contactValidated: false,
    templateName: "Notificação de divergência de base — ISS",
    status: "aguardando_validacao",
    blockedReason: "Contato de e-mail sem confirmação de titularidade",
    draftMessage:
      "Prezados, identificamos divergência entre as notas emitidas e a base declarada de ISS nas competências 01/2026 a 03/2026. Solicitamos retificação ou manifestação no prazo de 15 dias.",
  },
  {
    id: "nc-2",
    taxpayerName: "Empresa Beta de Demonstração Ltda.",
    cnpj: "00000000000200",
    channel: "whatsapp",
    contact: "(00) 00000-0000 — fictício",
    contactValidated: true,
    templateName: "Aviso de débito vencido — ISS retido",
    status: "preparado",
    blockedReason: "Aguardando autorização de envio da chefia fiscal",
    draftMessage:
      "Prezados, consta retenção de ISS declarada por tomadores sem recolhimento correspondente em 11/2025 e 12/2025. Regularize ou apresente comprovantes pelo portal.",
  },
  {
    id: "nc-3",
    taxpayerName: "Empresa Delta de Demonstração Ltda.",
    cnpj: "00000000000400",
    channel: "portal",
    contact: "Caixa postal do portal do contribuinte",
    contactValidated: false,
    templateName: "Intimação para apresentação de documentos",
    status: "bloqueado",
    blockedReason: "Template pendente de aprovação jurídica",
    draftMessage:
      "Prezados, solicitamos a apresentação das notas de serviço vinculadas à obra do alvará HML-0001 no prazo de 10 dias.",
  },
];

export const processingHealth: ProcessingHealthIndicator[] = [
  {
    id: "ph-worker",
    label: "Worker sandbox",
    status: "operacional",
    detail: "Execução isolada, sem saída para a internet",
    metric: "último ciclo às 08:52",
  },
  {
    id: "ph-fila",
    label: "Fila de processamento",
    status: "atencao",
    detail: "24 itens retidos por dados insuficientes",
    metric: "31 itens na fila",
  },
  {
    id: "ph-calculos",
    label: "Cálculos tributários",
    status: "atencao",
    detail: "Concluídos 178 de 202 cálculos da rodada",
    metric: "88% concluídos",
  },
  {
    id: "ph-rls",
    label: "Políticas RLS",
    status: "operacional",
    detail: "Acesso restrito por perfil e por município",
    metric: "12 políticas ativas",
  },
  {
    id: "ph-realtime",
    label: "Realtime",
    status: "operacional",
    detail: "Assinaturas de atendimento e fila ativas",
    metric: "latência média 240 ms",
  },
];

export const productionBlockers: ProductionBlocker[] = [
  {
    id: "pb-1",
    title: "Validação de contatos dos destinatários",
    description: "86 destinatários preparados; 41 contatos ainda sem confirmação de titularidade.",
    done: false,
    owner: "Equipe de cadastro",
  },
  {
    id: "pb-2",
    title: "Aprovação jurídica do template de notificação",
    description: "Texto da intimação aguarda parecer da procuradoria municipal.",
    done: false,
    owner: "Procuradoria",
  },
  {
    id: "pb-3",
    title: "URL pública dos processos",
    description:
      "Endereço definitivo dos processos administrativos já homologado em ambiente interno.",
    done: true,
    owner: "TI da Prefeitura",
  },
  {
    id: "pb-4",
    title: "Autorização formal de envio",
    description: "Nenhum disparo externo será liberado sem despacho assinado pela chefia fiscal.",
    done: false,
    owner: "Chefia fiscal",
  },
  {
    id: "pb-5",
    title: "Homologação ponta a ponta",
    description: "Roteiro de teste completo executado em 3 de 8 fluxos previstos.",
    done: false,
    owner: "Fiscalização + TI",
  },
];

export const auditEvents: AuditEvent[] = [
  {
    id: "ae-1",
    type: "calculo",
    title: "Cálculo concluído",
    description:
      "ISS recalculado para Empresa Alfa de Demonstração nas competências 01/2026 a 03/2026, com diferença de R$ 18.420,55.",
    occurredAt: "2026-07-31T08:52:00-03:00",
    actor: "Worker sandbox",
  },
  {
    id: "ae-2",
    type: "segundo_cerebro",
    title: "Pergunta respondida pelo Segundo Cérebro",
    description:
      "Dúvida sobre emissão de segunda via respondida com base no Código Tributário Municipal, art. 154.",
    occurredAt: "2026-07-31T08:20:00-03:00",
    actor: "Segundo Cérebro",
  },
  {
    id: "ae-3",
    type: "escalonamento",
    title: "Pergunta escalada ao fiscal",
    description:
      "Questionamento de enquadramento da Empresa Gama de Demonstração encaminhado para análise humana.",
    occurredAt: "2026-07-30T17:41:00-03:00",
    actor: "Segundo Cérebro",
  },
  {
    id: "ae-4",
    type: "notificacao",
    title: "Notificação criada em rascunho",
    description:
      "Notificação de divergência de base gerada para 86 destinatários e mantida em rascunho, sem envio.",
    occurredAt: "2026-07-30T16:10:00-03:00",
    actor: "Fiscal de Homologação A",
  },
];
