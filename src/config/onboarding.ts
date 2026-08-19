import type { AppRole } from "@/types/read-models";

export const ONBOARDING_VERSION = 2;

export function onboardingKeyForRole(role: AppRole): string {
  return `first-access:${role}`;
}

export type OnboardingCapability = "available" | "simulation" | "blocked" | "guidance";

export interface OnboardingStep {
  id: string;
  title: string;
  section: string;
  capability: OnboardingCapability;
  summary: string;
  actions: string[];
  routeLabel?: string;
}

export const ONBOARDING_CAPABILITY_LABELS: Record<OnboardingCapability, string> = {
  available: "Disponível",
  simulation: "Simulação",
  blocked: "Bloqueado",
  guidance: "Orientação",
};

const STAFF_INTRO: Record<Exclude<AppRole, "taxpayer" | "accountant">, OnboardingStep> = {
  platform_admin: {
    id: "platform-admin-intro",
    title: "Acompanhe a plataforma sem assumir a função fiscal",
    section: "Seu perfil",
    capability: "guidance",
    summary:
      "Seu perfil global acompanha os contextos cadastrados. A gestão de usuários e a decisão de cada caso continuam atribuídas ao administrador e à equipe municipal competente.",
    actions: [
      "Confirme o município selecionado antes de consultar ou configurar qualquer informação.",
      "Use Configurações para consultar o limite do seu acesso; não altere vínculos nem decida um procedimento fiscal sem o papel municipal correspondente.",
    ],
  },
  municipal_admin: {
    id: "municipal-admin-intro",
    title: "Organize o ambiente e acompanhe a operação municipal",
    section: "Seu perfil",
    capability: "guidance",
    summary:
      "Você administra acessos do município e também acompanha o fluxo operacional, sempre preservando a responsabilidade do fiscal sobre a conclusão do caso.",
    actions: [
      "Comece pela Visão Geral para identificar prioridades e bloqueios.",
      "Use Configurações apenas para usuários e controles administrativos autorizados.",
    ],
  },
  supervisor: {
    id: "supervisor-intro",
    title: "Supervisione prioridades, filas e decisões humanas",
    section: "Seu perfil",
    capability: "guidance",
    summary:
      "Seu fluxo combina acompanhamento das filas com revisão do trabalho fiscal. Indicadores e regras automáticas são indícios, não uma decisão tributária.",
    actions: [
      "Comece pelas exceções de maior prioridade na Visão Geral.",
      "Confirme evidências, atribuição e revisão antes de considerar um caso concluído.",
    ],
  },
  fiscal_auditor: {
    id: "fiscal-intro",
    title: "Siga o fluxo diário da fiscalização",
    section: "Seu perfil",
    capability: "guidance",
    summary:
      "O sistema organiza indícios e filas. Você continua responsável por conferir documentos, interpretar a base legal e registrar a decisão humana.",
    actions: [
      "Comece na Visão Geral, abra o contribuinte e confira a Visão Fiscal 360.",
      "Analise débitos, divergências e procedimentos antes de atuar no atendimento.",
    ],
  },
  legal_reviewer: {
    id: "legal-reviewer-intro",
    title: "Revise fundamentos antes de qualquer conclusão",
    section: "Seu perfil",
    capability: "guidance",
    summary:
      "Seu foco é validar a fundamentação, as limitações e o texto submetido à revisão. A regra automática não substitui a análise jurídica.",
    actions: [
      "Abra o procedimento e confronte a explicação com a base legal apresentada.",
      "Consulte o Segundo Cérebro como apoio, sempre verificando versão e vigência.",
    ],
  },
  support_readonly: {
    id: "support-intro",
    title: "Consulte o sistema sem executar ações fiscais",
    section: "Seu perfil",
    capability: "guidance",
    summary:
      "Seu acesso é somente leitura. Use as telas para orientar usuários e diagnosticar problemas, sem assumir atendimentos ou alterar decisões.",
    actions: [
      "Confirme o município e a tela relatada pelo usuário.",
      "Registre evidências do problema sem copiar dados fiscais para canais externos.",
    ],
  },
};

const STAFF_FLOW: OnboardingStep[] = [
  {
    id: "overview",
    title: "Comece pelas prioridades do dia",
    section: "Visão Geral",
    capability: "available",
    routeLabel: "Visão Geral",
    summary:
      "O painel reúne casos prioritários, perguntas aguardando ação, notificações para validar e alertas de processamento.",
    actions: [
      "Abra primeiro os itens críticos ou altos e confirme se o responsável e a situação estão corretos.",
      "Trate a prioridade como ordem de trabalho, nunca como conclusão fiscal ou jurídica.",
    ],
  },
  {
    id: "taxpayers",
    title: "Localize o contribuinte e abra a visão completa",
    section: "Contribuintes e Visão Fiscal 360",
    capability: "available",
    routeLabel: "Contribuintes",
    summary:
      "Pesquise por nome, CNPJ ou inscrição municipal. Na Visão Fiscal 360, percorra Resumo, Débitos, Divergências e Procedimentos.",
    actions: [
      "Confira a identificação e a situação cadastral antes de analisar valores.",
      "Use as quatro abas para entender o contexto; nenhum campo isolado deve sustentar uma decisão.",
    ],
  },
  {
    id: "inspections",
    title: "Confira evidências e procedimentos fiscais",
    section: "Fiscalizações",
    capability: "available",
    routeLabel: "Fiscalizações",
    summary:
      "A tela organiza divergências detectadas e procedimentos já abertos. O sistema apresenta evidências, mas lançamento, autuação e decisão permanecem humanos.",
    actions: [
      "Abra a ficha do contribuinte para conferir período, diferença e fundamento da regra.",
      "Antes de concluir, valide documentos, base legal, bloqueios e necessidade de revisão.",
    ],
  },
  {
    id: "debts",
    title: "Leia os débitos por competência",
    section: "Débitos",
    capability: "available",
    routeLabel: "Débitos",
    summary:
      "Consulte vencimento, valor constituído, vencido e saldo em aberto. A regra exibida explica o critério municipal que classificou o débito.",
    actions: [
      "Compare competência, vencimento e saldo antes de relacionar o débito a uma divergência.",
      "Se os dados estiverem incompletos, interrompa a análise e solicite conferência da fonte.",
    ],
  },
  {
    id: "notifications",
    title: "Valide a prévia sem enviar ao cliente",
    section: "Notificações",
    capability: "simulation",
    routeLabel: "Notificações",
    summary:
      "Esta etapa permite consultar destinatários, contato mascarado, finalidade e motivos de bloqueio. A prévia é interna e não envia, agenda ou autoriza e-mail, WhatsApp ou notificação formal.",
    actions: [
      "Confira se o contato e o vínculo pertencem ao contribuinte correto.",
      "Use Visualizar simulação para revisar o texto; nenhuma mensagem sai do sistema nesta etapa.",
    ],
  },
  {
    id: "external-delivery",
    title: "Comunicações externas continuam protegidas",
    section: "E-mail e notificações",
    capability: "blocked",
    summary:
      "O envio externo está bloqueado. Não existe botão operacional para disparar mensagem ao cliente neste fluxo enquanto os controles e integrações não forem liberados.",
    actions: [
      "Não copie dados fiscais para um e-mail ou aplicativo de mensagens por fora do fluxo oficial.",
      "Um futuro aviso por e-mail deverá apenas direcionar ao portal autenticado, sem expor detalhes fiscais na mensagem.",
    ],
  },
  {
    id: "service",
    title: "Assuma perguntas na fila de atendimento",
    section: "Atendimento",
    capability: "available",
    routeLabel: "Atendimento",
    summary:
      "Perguntas registradas pelo contribuinte no portal caem na fila Atendimento. Perfis autorizados podem assumir o item e consultar a conversa protegida.",
    actions: [
      "Abra a pergunta, confirme o processo relacionado e assuma o atendimento quando for responsável.",
      "A atribuição fica na trilha de auditoria; evite trabalhar fora da fila.",
    ],
  },
  {
    id: "answer",
    title: "Redação e publicação de resposta ainda não estão disponíveis",
    section: "Resposta ao contribuinte",
    capability: "blocked",
    summary:
      "Hoje é possível receber, atribuir e consultar a conversa. A interface ainda não permite redigir, revisar ou publicar uma resposta ao portal do contribuinte.",
    actions: [
      "Não interprete Assumir atendimento como autorização para responder ou enviar mensagem.",
      "Quando esse fluxo for liberado, deverá seguir redação, revisão humana, publicação e disponibilização no portal autenticado.",
    ],
  },
  {
    id: "knowledge",
    title: "Consulte e governe o Segundo Cérebro",
    section: "Segundo Cérebro",
    capability: "guidance",
    routeLabel: "Segundo Cérebro",
    summary:
      "A biblioteca reúne respostas publicadas com citações verificáveis. As demais abas mostram fontes oficiais, mudanças detectadas, revisões pendentes e a saúde da coleta, sem substituir a análise da autoridade fiscal ou jurídica.",
    actions: [
      "Na Biblioteca, confira resposta, fonte oficial, dispositivo citado, versão e vigência antes de usar a orientação.",
      "Em Fontes oficiais e Saúde, verifique se a coleta está atualizada e se existe uma versão vigente publicada.",
      "Mudança coletada não é conhecimento aprovado: somente o revisor autorizado pode revisar e, em uma ação separada, publicar.",
      "Volte ao procedimento e confronte a orientação com os fatos e documentos do caso.",
    ],
  },
  {
    id: "reports",
    title: "Acompanhe resultados sem confundir indicador com decisão",
    section: "Relatórios",
    capability: "available",
    routeLabel: "Relatórios",
    summary:
      "Os relatórios consolidam produtividade, valores e processamento para acompanhamento da operação.",
    actions: [
      "Use os indicadores para identificar exceções e tendência de trabalho.",
      "Abra o caso de origem antes de tomar qualquer providência individual.",
    ],
  },
];

const ADMIN_SETTINGS: OnboardingStep = {
  id: "settings",
  title: "Gerencie somente acessos e controles autorizados",
  section: "Configurações",
  capability: "available",
  routeLabel: "Configurações",
  summary:
    "Administradores podem revisar o contexto municipal, os controles ativos e os vínculos de usuários. Alterações de papel devem respeitar a separação de funções.",
  actions: [
    "Confirme o e-mail e o papel antes de adicionar ou atualizar um vínculo.",
    "Suspenda um acesso que não seja mais necessário; não compartilhe contas entre pessoas.",
  ],
};

const COMPLETE: OnboardingStep = {
  id: "complete",
  title: "Fluxo diário recomendado",
  section: "Conclusão",
  capability: "guidance",
  summary:
    "Visão Geral → contribuinte → evidências → débitos e divergências → procedimento → atendimento → conferência final.",
  actions: [
    "Pare diante de dado incompleto, contato não validado ou fundamento pendente.",
    "Você poderá abrir este treinamento novamente pelo botão Ajuda na barra superior.",
  ],
};

const PORTAL_COMPLETE: OnboardingStep = {
  id: "portal-complete",
  title: "Fluxo do portal protegido",
  section: "Conclusão",
  capability: "guidance",
  summary:
    "Caso autorizado → conferência do resumo → registro da pergunta → confirmação → acompanhamento pelo canal oficial.",
  actions: [
    "Guarde o número do processo e não considere a pergunta registrada como uma resposta ou ciência formal.",
    "Você poderá abrir este treinamento novamente pelo botão Ajuda na barra superior.",
  ],
};

const PLATFORM_COMPLETE: OnboardingStep = {
  id: "platform-complete",
  title: "Fluxo da administração da plataforma",
  section: "Conclusão",
  capability: "guidance",
  summary:
    "Contexto municipal → limite do acesso global → encaminhamento ao administrador municipal responsável.",
  actions: [
    "Não use o perfil global para assumir trabalho fiscal nem para contornar a separação de funções.",
    "Você poderá abrir este treinamento novamente pelo botão Ajuda na barra superior.",
  ],
};

const READ_ONLY_SERVICE: OnboardingStep = {
  id: "service-read-only",
  title: "Acompanhe a fila sem assumir atendimentos",
  section: "Atendimento",
  capability: "guidance",
  routeLabel: "Atendimento",
  summary:
    "Seu perfil pode consultar a organização da fila, mas não pode assumir uma pergunta nem registrar uma decisão fiscal.",
  actions: [
    "Use a fila para orientar o usuário ou acompanhar o andamento permitido ao seu perfil.",
    "Encaminhe a pergunta para um fiscal, supervisor ou revisor autorizado; não trabalhe fora da atribuição formal.",
  ],
};

const PORTAL_STEPS: Record<"taxpayer" | "accountant", OnboardingStep[]> = {
  taxpayer: [
    {
      id: "portal-access",
      title: "Consulte apenas os seus atendimentos",
      section: "Portal protegido",
      capability: "available",
      summary:
        "O portal apresenta somente casos vinculados ao seu acesso. Ele é informativo e não substitui o canal oficial de ciência ou processo.",
      actions: [
        "Confira o número e o resumo do caso antes de registrar uma dúvida.",
        "Não informe senhas, dados bancários ou dados de terceiros na mensagem.",
      ],
    },
    {
      id: "portal-question",
      title: "Registre uma pergunta para a equipe fiscal",
      section: "Enviar uma pergunta",
      capability: "available",
      summary:
        "A pergunta é gravada no caso e cai na fila interna Atendimento. Ela não produz ciência, prazo, confissão ou resposta automática.",
      actions: [
        "Selecione o caso correto, escreva a dúvida e revise antes de confirmar.",
        "A resposta pela interface ainda está bloqueada; aguarde a orientação do canal oficial.",
      ],
    },
    PORTAL_COMPLETE,
  ],
  accountant: [
    {
      id: "accountant-access",
      title: "Atue somente nos vínculos autorizados",
      section: "Portal da contabilidade",
      capability: "available",
      summary:
        "O acesso da contabilidade é limitado aos contribuintes formalmente vinculados ao usuário.",
      actions: [
        "Confirme o contribuinte e o processo antes de consultar ou registrar uma dúvida.",
        "Não compartilhe informações entre clientes ou por canais não autorizados.",
      ],
    },
    {
      id: "accountant-question",
      title: "Envie a dúvida para a fila fiscal protegida",
      section: "Enviar uma pergunta",
      capability: "available",
      summary:
        "A pergunta fica vinculada ao caso e aparece na fila Atendimento da equipe fiscal. Não há resposta automática nem efeito jurídico.",
      actions: [
        "Descreva objetivamente a dúvida sem inserir credenciais ou dados bancários.",
        "A publicação de respostas pelo sistema ainda está bloqueada.",
      ],
    },
    PORTAL_COMPLETE,
  ],
};

export function onboardingStepsForRole(role: AppRole): OnboardingStep[] {
  if (role === "taxpayer" || role === "accountant") return PORTAL_STEPS[role];
  if (role === "platform_admin") return [STAFF_INTRO.platform_admin, PLATFORM_COMPLETE];

  const staffFlow = STAFF_FLOW.map((step) =>
    step.id === "service" && (role === "municipal_admin" || role === "support_readonly")
      ? READ_ONLY_SERVICE
      : step,
  );
  const steps = [STAFF_INTRO[role], ...staffFlow];
  if (role === "municipal_admin") steps.push(ADMIN_SETTINGS);
  steps.push(COMPLETE);
  return steps;
}
