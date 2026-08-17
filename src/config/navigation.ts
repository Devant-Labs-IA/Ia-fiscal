import {
  BarChart3,
  Brain,
  Building2,
  ClipboardCheck,
  LayoutDashboard,
  MessageSquare,
  Receipt,
  Send,
  Settings,
  type LucideIcon,
} from "lucide-react";

export interface NavItem {
  title: string;
  url: string;
  icon: LucideIcon;
  description: string;
}

/** Navegação do perfil Fiscal. */
export const fiscalNav: NavItem[] = [
  {
    title: "Visão Geral",
    url: "/",
    icon: LayoutDashboard,
    description: "Painel operacional do fiscal com prioridades do dia.",
  },
  {
    title: "Contribuintes",
    url: "/contribuintes",
    icon: Building2,
    description: "Cadastro, situação e histórico dos contribuintes monitorados.",
  },
  {
    title: "Fiscalizações",
    url: "/fiscalizacoes",
    icon: ClipboardCheck,
    description: "Casos abertos, achados e acompanhamento de procedimentos.",
  },
  {
    title: "Débitos",
    url: "/debitos",
    icon: Receipt,
    description: "Débitos vencidos, parcelamentos e valores em discussão.",
  },
  {
    title: "Notificações",
    url: "/notificacoes",
    icon: Send,
    description: "Simulação interna e validação de contatos, sem envio externo.",
  },
  {
    title: "Atendimento",
    url: "/atendimento",
    icon: MessageSquare,
    description: "Fila de atendimentos do contribuinte e escalonamentos.",
  },
  {
    title: "Segundo Cérebro",
    url: "/segundo-cerebro",
    icon: Brain,
    description: "Base de conhecimento tributário e respostas assistidas.",
  },
  {
    title: "Relatórios",
    url: "/relatorios",
    icon: BarChart3,
    description: "Indicadores de arrecadação, produtividade e processamento.",
  },
  {
    title: "Configurações",
    url: "/configuracoes",
    icon: Settings,
    description: "Operação assistida e perfis de acesso do município.",
  },
];

export const portalNav: NavItem[] = [
  {
    title: "Meu atendimento",
    url: "/portal",
    icon: MessageSquare,
    description: "Consulta protegida dos próprios casos e envio de perguntas à fiscalização.",
  },
];

/** Perfis principais expostos pela navegação autenticada. */
export const profiles = [
  { id: "fiscal", label: "Fiscal", basePath: "/" },
  { id: "contribuinte", label: "Contribuinte", basePath: "/portal" },
] as const;

export function findNavItem(pathname: string): NavItem | undefined {
  if (pathname.startsWith("/portal")) return portalNav[0];
  if (pathname === "/") return fiscalNav[0];
  return fiscalNav.find((item) => item.url !== "/" && pathname.startsWith(item.url));
}
