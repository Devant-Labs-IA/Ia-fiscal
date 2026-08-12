import { BellOff, Check, LoaderCircle, MapPin, Search } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { runtimeConfig } from "@/config/runtime";
import { fiscalService } from "@/services/fiscal-service";
import type { SearchResultItem } from "@/types/read-models";

const ROLE_LABELS = {
  platform_admin: "Administração da plataforma",
  municipal_admin: "Administração municipal",
  supervisor: "Supervisão fiscal",
  fiscal_auditor: "Fiscalização",
  legal_reviewer: "Revisão jurídica",
  support_readonly: "Suporte — somente leitura",
  taxpayer: "Contribuinte",
  accountant: "Contabilidade",
} as const;

function initials(value: string): string {
  const parts = value.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "IA";
  return `${parts[0]?.[0] ?? ""}${parts.length > 1 ? (parts.at(-1)?.[0] ?? "") : ""}`.toUpperCase();
}

export function Topbar() {
  const auth = useAuth();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResultItem[]>([]);
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);
  const [switchingMunicipality, setSwitchingMunicipality] = useState(false);
  const searchRequestRef = useRef(0);
  const isPortal = auth.access?.role === "taxpayer" || auth.access?.role === "accountant";
  const canSearch = !isPortal && auth.access?.role !== "platform_admin";
  const identity = String(auth.user?.user_metadata?.["full_name"] ?? auth.user?.email ?? "Usuário");
  const roleLabel =
    auth.access?.platformAdmin && auth.access.role !== "platform_admin"
      ? `Administrador global · ${ROLE_LABELS[auth.access.role]}`
      : auth.access?.platformAdmin
        ? "Administrador global"
        : auth.access
          ? ROLE_LABELS[auth.access.role]
          : "Acesso restrito";

  useEffect(() => {
    searchRequestRef.current += 1;
    setQuery("");
    setResults([]);
    setSearching(false);
    setSearched(false);
  }, [auth.access?.municipalityId]);

  async function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalized = query.trim();
    if (normalized.length < 2) {
      toast.info("Digite pelo menos dois caracteres para pesquisar.");
      return;
    }
    if (!auth.access) return;
    const requestId = ++searchRequestRef.current;
    const municipalityId = auth.access.municipalityId;
    setSearching(true);
    setSearched(true);
    try {
      const nextResults = await fiscalService.searchFiscal(normalized, municipalityId);
      if (requestId !== searchRequestRef.current) return;
      setResults(nextResults);
    } catch {
      if (requestId !== searchRequestRef.current) return;
      setResults([]);
      toast.error("A busca protegida não pôde ser concluída.");
    } finally {
      if (requestId === searchRequestRef.current) setSearching(false);
    }
  }

  async function selectMunicipality(municipalityId: string) {
    setSwitchingMunicipality(true);
    try {
      const selected = await auth.selectMunicipality(municipalityId);
      toast.success("Contexto municipal alterado", {
        description: selected.label,
      });
    } catch {
      toast.error("Não foi possível trocar o município", {
        description: "Seu vínculo pode ter sido alterado. Atualize o acesso e tente novamente.",
      });
    } finally {
      setSwitchingMunicipality(false);
    }
  }

  return (
    <header className="sticky top-0 z-30 border-b border-border bg-card/95 backdrop-blur supports-[backdrop-filter]:bg-card/90">
      <div className="flex items-center gap-3 px-3 py-2.5 sm:px-6">
        <SidebarTrigger aria-label="Recolher ou expandir o menu" />

        {canSearch ? (
          <form className="relative min-w-0 flex-1" role="search" onSubmit={submitSearch}>
            <label className="sr-only" htmlFor="busca-global">
              Buscar contribuinte, CNPJ ou processo
            </label>
            <div className="relative max-w-xl">
              {searching ? (
                <LoaderCircle
                  className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground"
                  aria-hidden
                />
              ) : (
                <Search
                  className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                  aria-hidden
                />
              )}
              <Input
                id="busca-global"
                name="busca"
                value={query}
                onChange={(event) => {
                  searchRequestRef.current += 1;
                  setQuery(event.target.value);
                  setSearching(false);
                  setSearched(false);
                }}
                placeholder="Buscar contribuinte, CNPJ ou processo"
                className="h-9 bg-background pl-9"
                maxLength={500}
                autoComplete="off"
              />
            </div>
            {searched && !searching ? (
              <div className="absolute left-0 top-11 z-50 w-full max-w-xl rounded-md border border-border bg-popover p-2 text-popover-foreground shadow-lg">
                {results.length === 0 ? (
                  <p className="px-3 py-4 text-sm text-muted-foreground">
                    Nenhum resultado autorizado.
                  </p>
                ) : (
                  <ul className="space-y-1">
                    {results.map((result, index) => (
                      <li key={`${result.resultType}-${result.route ?? "none"}-${index}`}>
                        {result.route?.startsWith("/") ? (
                          <a
                            className="block rounded px-3 py-2 text-sm hover:bg-accent"
                            href={result.route}
                            onClick={() => setSearched(false)}
                          >
                            <span className="block font-medium">{result.title}</span>
                            <span className="block text-xs text-muted-foreground">
                              {result.subtitle}
                            </span>
                          </a>
                        ) : (
                          <div className="rounded px-3 py-2 text-sm">
                            <span className="block font-medium">{result.title}</span>
                            <span className="block text-xs text-muted-foreground">
                              {result.subtitle}
                            </span>
                          </div>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="mt-1 w-full"
                  onClick={() => setSearched(false)}
                >
                  Fechar resultados
                </Button>
              </div>
            ) : null}
          </form>
        ) : (
          <div className="flex-1" />
        )}

        {auth.access?.platformAdmin && auth.municipalityContexts.length > 1 ? (
          <Select
            value={auth.access.municipalityId}
            disabled={switchingMunicipality}
            onValueChange={(municipalityId) => void selectMunicipality(municipalityId)}
          >
            <SelectTrigger
              className="hidden w-[240px] shrink-0 border-border bg-primary-soft text-primary md:flex"
              aria-label="Município em que o administrador global está atuando"
            >
              <MapPin className="size-3.5 shrink-0" aria-hidden />
              <SelectValue placeholder="Selecionar município" />
            </SelectTrigger>
            <SelectContent>
              {auth.municipalityContexts.map((municipality) => (
                <SelectItem key={municipality.id} value={municipality.id}>
                  {municipality.label} · {ROLE_LABELS[municipality.role]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        ) : (
          <Badge
            variant="outline"
            className="hidden shrink-0 gap-1.5 border-border bg-primary-soft text-primary md:inline-flex"
          >
            <MapPin className="size-3.5" aria-hidden />
            {auth.access?.municipalityLabel ?? runtimeConfig.municipalityLabel}
          </Badge>
        )}

        <Button
          variant="ghost"
          size="icon"
          className="shrink-0"
          aria-label="Envios externos desabilitados em homologação"
          onClick={() =>
            toast.info("Envios externos desabilitados", {
              description:
                "Nenhum e-mail, WhatsApp ou notificação formal é disparado neste ambiente.",
            })
          }
        >
          <BellOff className="size-4" aria-hidden />
        </Button>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              className="shrink-0 gap-2 px-2"
              aria-label={`Menu de ${identity}, ${roleLabel}`}
            >
              <Avatar className="size-7">
                <AvatarFallback className="bg-primary text-xs text-primary-foreground">
                  {initials(identity)}
                </AvatarFallback>
              </Avatar>
              <span className="hidden max-w-48 text-left text-xs leading-tight lg:block">
                <span className="block truncate font-medium">{identity}</span>
                <span className="block truncate text-muted-foreground">{roleLabel}</span>
              </span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-64">
            <DropdownMenuLabel>
              <span className="block truncate">{identity}</span>
              <span className="block text-xs font-normal text-muted-foreground">{roleLabel}</span>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            {auth.access?.platformAdmin ? (
              <>
                <DropdownMenuLabel className="text-xs text-muted-foreground">
                  <span className="block">Contexto municipal atual</span>
                  <span className="mt-1 block text-sm font-medium text-foreground">
                    {auth.access.municipalityLabel}
                  </span>
                  <span className="block font-normal">{ROLE_LABELS[auth.access.role]}</span>
                </DropdownMenuLabel>
                {auth.municipalityContexts.length > 1 ? (
                  <>
                    <DropdownMenuSeparator />
                    <DropdownMenuLabel className="text-xs text-muted-foreground">
                      Atuar no município
                    </DropdownMenuLabel>
                    {auth.municipalityContexts.map((municipality) => (
                      <DropdownMenuItem
                        key={municipality.id}
                        disabled={switchingMunicipality}
                        onSelect={() => void selectMunicipality(municipality.id)}
                      >
                        <Check
                          className={
                            municipality.id === auth.access?.municipalityId
                              ? "size-4 opacity-100"
                              : "size-4 opacity-0"
                          }
                          aria-hidden
                        />
                        <span className="min-w-0">
                          <span className="block truncate">{municipality.label}</span>
                          <span className="block truncate text-xs text-muted-foreground">
                            {ROLE_LABELS[municipality.role]}
                          </span>
                        </span>
                      </DropdownMenuItem>
                    ))}
                  </>
                ) : null}
                <DropdownMenuSeparator />
              </>
            ) : null}
            {auth.demo ? (
              <DropdownMenuItem onClick={auth.leaveDemo}>Sair da demonstração</DropdownMenuItem>
            ) : (
              <DropdownMenuItem onClick={() => void auth.signOut()}>
                Encerrar sessão
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
