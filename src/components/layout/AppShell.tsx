import { Link, Navigate, useRouterState } from "@tanstack/react-router";
import type { ReactNode } from "react";

import { useAuth } from "@/auth/AuthContext";
import { AppSidebar } from "@/components/layout/AppSidebar";
import { Topbar } from "@/components/layout/Topbar";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { findNavItem } from "@/config/navigation";

function AppBreadcrumb() {
  const pathname = useRouterState({ select: (r) => r.location.pathname });
  const current = findNavItem(pathname);

  return (
    <Breadcrumb className="px-3 pt-4 sm:px-6">
      <BreadcrumbList>
        <BreadcrumbItem>
          {pathname === "/" ? (
            <BreadcrumbPage>Visão Geral</BreadcrumbPage>
          ) : (
            <BreadcrumbLink asChild>
              <Link to="/">Visão Geral</Link>
            </BreadcrumbLink>
          )}
        </BreadcrumbItem>
        {pathname !== "/" && (
          <>
            <BreadcrumbSeparator />
            <BreadcrumbItem>
              <BreadcrumbPage>{current?.title ?? "Página"}</BreadcrumbPage>
            </BreadcrumbItem>
          </>
        )}
      </BreadcrumbList>
    </Breadcrumb>
  );
}

export function AppShell({ children }: { children: ReactNode }) {
  const auth = useAuth();
  const pathname = useRouterState({ select: (r) => r.location.pathname });
  const isPortal = auth.access?.role === "taxpayer" || auth.access?.role === "accountant";
  const isPlatformAdmin = auth.access?.role === "platform_admin";

  if (isPortal && !pathname.startsWith("/portal")) {
    return <Navigate to="/portal" replace />;
  }
  if (isPlatformAdmin && !pathname.startsWith("/configuracoes")) {
    return <Navigate to="/configuracoes" replace />;
  }

  return (
    <SidebarProvider>
      <div className="flex min-h-screen w-full bg-background">
        <AppSidebar />
        <SidebarInset className="min-w-0 flex-1 bg-background">
          <Topbar />
          <AppBreadcrumb />
          <div className="px-3 pb-12 pt-3 sm:px-6">{children}</div>
        </SidebarInset>
      </div>
    </SidebarProvider>
  );
}
