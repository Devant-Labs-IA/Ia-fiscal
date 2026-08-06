import { Link, useRouterState } from "@tanstack/react-router";
import { ShieldCheck } from "lucide-react";

import { useAuth } from "@/auth/AuthContext";
import { fiscalNav, portalNav } from "@/config/navigation";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "@/components/ui/sidebar";

const ROLE_LABELS = {
  platform_admin: "Administração da plataforma",
  municipal_admin: "Administração municipal",
  supervisor: "Supervisão fiscal",
  fiscal_auditor: "Fiscalização",
  legal_reviewer: "Revisão jurídica",
  taxpayer: "Contribuinte",
  accountant: "Contabilidade",
} as const;

export function AppSidebar() {
  const auth = useAuth();
  const { state, setOpenMobile } = useSidebar();
  const collapsed = state === "collapsed";
  const pathname = useRouterState({ select: (r) => r.location.pathname });

  const isActive = (url: string) => (url === "/" ? pathname === "/" : pathname.startsWith(url));
  const isPortal = auth.access?.role === "taxpayer" || auth.access?.role === "accountant";
  const isPlatformAdmin = auth.access?.role === "platform_admin";
  const canConfigure = auth.access?.platformAdmin || auth.access?.role === "municipal_admin";
  const navigation = isPortal
    ? portalNav
    : isPlatformAdmin
      ? fiscalNav.filter((item) => item.url === "/configuracoes")
      : fiscalNav.filter((item) => item.url !== "/configuracoes" || canConfigure);
  const identity = String(
    auth.user?.user_metadata?.["full_name"] ?? auth.user?.email ?? "Usuário autenticado",
  );
  const roleLabel = auth.access?.platformAdmin
    ? "Administrador global"
    : auth.access
      ? ROLE_LABELS[auth.access.role]
      : "Acesso restrito";

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader className="border-b border-sidebar-border px-3 py-4">
        <div className="flex min-w-0 items-center gap-3">
          <div className="grid size-9 shrink-0 place-items-center rounded-md bg-sidebar-primary text-sidebar-primary-foreground">
            <ShieldCheck className="size-5" aria-hidden />
          </div>
          {!collapsed && (
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold tracking-tight">IA Fiscal</p>
              <p className="truncate text-xs text-sidebar-foreground/70">
                Gestão Tributária Inteligente
              </p>
            </div>
          )}
        </div>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          {!collapsed && <SidebarGroupLabel>Perfil fiscal</SidebarGroupLabel>}
          <SidebarGroupContent>
            <SidebarMenu>
              {navigation.map((item) => (
                <SidebarMenuItem key={item.url}>
                  <SidebarMenuButton asChild isActive={isActive(item.url)} tooltip={item.title}>
                    <Link
                      to={item.url}
                      className="flex items-center gap-2"
                      onClick={() => setOpenMobile(false)}
                    >
                      <item.icon className="size-4 shrink-0" aria-hidden />
                      <span className="truncate">{item.title}</span>
                    </Link>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="border-t border-sidebar-border">
        {!collapsed ? (
          <div className="px-2 py-1">
            <p className="truncate text-xs font-medium">{identity}</p>
            <p className="truncate text-xs text-sidebar-foreground/70">{roleLabel}</p>
          </div>
        ) : null}
      </SidebarFooter>
    </Sidebar>
  );
}
