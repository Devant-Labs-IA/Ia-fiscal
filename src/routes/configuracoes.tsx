import { createFileRoute } from "@tanstack/react-router";
import { CheckCircle2, LockKeyhole, Server, ShieldAlert } from "lucide-react";

import { useAuth } from "@/auth/AuthContext";
import { SectionCard } from "@/components/common/SectionCard";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { runtimeConfig } from "@/config/runtime";

export const Route = createFileRoute("/configuracoes")({
  head: () => ({ meta: [{ title: "Configuração segura — IA Fiscal" }] }),
  component: SettingsPage,
});

function SettingsPage() {
  const auth = useAuth();
  const canView = auth.access?.platformAdmin || auth.access?.role === "municipal_admin";
  if (!canView) {
    return (
      <div className="py-4">
        <SectionCard title="Acesso administrativo necessário">
          <p className="flex gap-2 text-sm text-muted-foreground">
            <LockKeyhole className="size-5 shrink-0" aria-hidden />
            Seu papel não permite consultar parâmetros administrativos.
          </p>
        </SectionCard>
      </div>
    );
  }
  const host = new URL(runtimeConfig.supabaseUrl).host;
  const activeMunicipality = auth.municipalityContexts.find(
    (municipality) => municipality.id === auth.access?.municipalityId,
  );
  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />
      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Configuração segura</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Diagnóstico somente de leitura. Alterações de ambiente exigem revisão e novo deploy.
        </p>
      </header>
      <div className="grid gap-5 lg:grid-cols-2">
        <SectionCard
          title="Ambiente"
          action={<Badge variant="outline">{runtimeConfig.environment}</Badge>}
        >
          <dl className="space-y-3 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground">Município</dt>
              <dd className="font-medium">
                {auth.access?.municipalityLabel ?? runtimeConfig.municipalityLabel}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground">IBGE</dt>
              <dd className="font-mono">
                {activeMunicipality?.ibgeCode ?? runtimeConfig.municipalityIbge}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground">Fonte de dados</dt>
              <dd className="font-medium">
                {auth.demo ? "Demonstração fictícia" : runtimeConfig.dataMode}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground">Backend</dt>
              <dd className="font-mono text-xs">{host}</dd>
            </div>
          </dl>
        </SectionCard>
        <SectionCard title="Controles ativos">
          <ul className="space-y-3 text-sm">
            <li className="flex gap-2">
              <CheckCircle2 className="size-5 shrink-0 text-success" aria-hidden />
              Autenticação Supabase e vínculo de acesso obrigatórios
            </li>
            <li className="flex gap-2">
              <CheckCircle2 className="size-5 shrink-0 text-success" aria-hidden />
              Chave pública no navegador; nenhuma chave de serviço
            </li>
            <li className="flex gap-2">
              <Server className="size-5 shrink-0 text-primary" aria-hidden />
              Funções de busca e worker exigem JWT
            </li>
            <li className="flex gap-2">
              <ShieldAlert className="size-5 shrink-0 text-warning" aria-hidden />
              Produção e comunicação externa permanecem bloqueadas
            </li>
          </ul>
        </SectionCard>
      </div>
    </div>
  );
}
