import { useMutation } from "@tanstack/react-query";
import {
  ArrowRight,
  BookOpenCheck,
  CheckCircle2,
  Clock3,
  ExternalLink,
  FileQuestion,
  FileSearch,
  RefreshCw,
  Search,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import { toast } from "sonner";

import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import {
  KnowledgeBlockers,
  KnowledgeStateBadge,
  KnowledgeValidity,
} from "@/components/knowledge/KnowledgeOperations";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { KNOWLEDGE_MIN_ANSWER_CONFIDENCE } from "@/features/knowledge/knowledge-models";
import type {
  KnowledgeCandidateInput,
  KnowledgeCatalogCoverage,
  KnowledgeHealthStatus,
  KnowledgeIndexStatus,
  KnowledgeOcrStatus,
  KnowledgeReviewerDirectory,
  KnowledgeReviewerEligibleStaff,
  KnowledgeReviewerGrant,
  KnowledgeReviewerStatus,
  KnowledgeScheduleStatus,
  KnowledgeSearchCitation,
  KnowledgeSearchResult,
} from "@/features/knowledge/knowledge-models";
import { cn } from "@/lib/utils";
import type { MunicipalityUser } from "@/types/read-models";

const EXAMPLE_QUESTIONS = [
  "Qual é o prazo de recolhimento do ISSQN?",
  "Quando ocorre o fato gerador do ITBI?",
  "Quais documentos são exigidos para revisar um débito?",
];

function safeDateTime(value: string | null): string {
  if (!value || Number.isNaN(Date.parse(value))) return "Não registrada";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}

function safeOfficialUrl(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

function currentDateInSaoPaulo(): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function citationIsCurrent(citation: KnowledgeSearchCitation): boolean {
  const today = currentDateInSaoPaulo();
  return Boolean(
    citation.publicationDate &&
    /^\d{4}-\d{2}-\d{2}$/.test(citation.publicationDate) &&
    citation.publicationDate <= today &&
    citation.validFrom &&
    /^\d{4}-\d{2}-\d{2}$/.test(citation.validFrom) &&
    citation.validFrom <= today &&
    (!citation.validUntil ||
      (/^\d{4}-\d{2}-\d{2}$/.test(citation.validUntil) && citation.validUntil >= today)),
  );
}

function citationIsVerifiable(citation: KnowledgeSearchCitation): boolean {
  return Boolean(
    citation.isValid &&
    citation.blockers.length === 0 &&
    citation.quotedExcerpt.trim() &&
    safeOfficialUrl(citation.officialUrl) &&
    citationIsCurrent(citation),
  );
}

function resultHasVerifiedAnswer(result: KnowledgeSearchResult): boolean {
  return Boolean(
    result.verified &&
    result.answered &&
    result.answer?.trim() &&
    result.confidence !== null &&
    result.confidence >= KNOWLEDGE_MIN_ANSWER_CONFIDENCE &&
    result.blockers.length === 0 &&
    result.citations.length > 0 &&
    result.citations.every(citationIsVerifiable),
  );
}

function confidenceLabel(value: number | null): string {
  if (value == null) return "Aderência não verificada";
  if (value >= 0.85) return "Evidência com alta aderência";
  if (value >= 0.65) return "Evidência com aderência moderada";
  if (value >= KNOWLEDGE_MIN_ANSWER_CONFIDENCE) return "Evidência com aderência suficiente";
  return "Evidência insuficiente";
}

function retrievalLabel(value: string): string {
  if (value === "lexical_portuguese") return "Busca textual integral em português";
  return "Método de busca não verificado";
}

function KnowledgeSearchCitations({ citations }: { citations: KnowledgeSearchCitation[] }) {
  if (citations.length === 0) {
    return <EmptyState message="Nenhum dispositivo oficial verificável foi localizado." />;
  }

  return (
    <ol className="space-y-3" aria-label="Evidências oficiais localizadas">
      {citations.map((citation, index) => {
        const officialUrl = safeOfficialUrl(citation.officialUrl);
        const verified = citationIsVerifiable(citation);
        return (
          <li
            key={citation.citationId}
            className={cn(
              "rounded-md border p-3",
              verified ? "border-border bg-background" : "border-critical/35 bg-critical-soft/50",
            )}
          >
            <div className="flex items-start gap-3">
              <span
                className={cn(
                  "grid size-7 shrink-0 place-items-center rounded-full text-xs font-semibold",
                  verified ? "bg-primary-soft text-primary" : "bg-critical-soft text-critical",
                )}
                aria-hidden
              >
                {index + 1}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <p className="text-sm font-semibold">{citation.sourceTitle}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {citation.officialIdentifier ?? "Identificação oficial não informada"} ·{" "}
                      {citation.sectionHeading ?? citation.citationLabel}
                    </p>
                  </div>
                  {verified ? (
                    <Badge
                      variant="outline"
                      className="border-success/40 bg-success-soft text-success"
                    >
                      <CheckCircle2 aria-hidden />
                      Vigente e verificável
                    </Badge>
                  ) : (
                    <Badge
                      variant="outline"
                      className="border-critical/40 bg-critical-soft text-critical"
                    >
                      Evidência bloqueada
                    </Badge>
                  )}
                </div>

                <blockquote className="mt-3 border-l-2 border-primary/40 pl-3 text-xs leading-relaxed text-muted-foreground">
                  {citation.quotedExcerpt}
                </blockquote>

                <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-border pt-2">
                  <p className="text-[11px] text-muted-foreground">
                    Vigência:{" "}
                    <KnowledgeValidity
                      validFrom={citation.validFrom}
                      validUntil={citation.validUntil}
                    />
                  </p>
                  {officialUrl ? (
                    <Button asChild size="sm" variant="outline">
                      <a href={officialUrl} target="_blank" rel="noreferrer">
                        Conferir no portal oficial
                        <ExternalLink aria-hidden />
                      </a>
                    </Button>
                  ) : null}
                </div>

                {!verified ? (
                  <div className="mt-3">
                    <KnowledgeBlockers
                      blockers={
                        citation.blockers.length > 0 ? citation.blockers : ["unverified_state"]
                      }
                    />
                  </div>
                ) : null}
              </div>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

interface KnowledgeCandidateDialogProps {
  question: string;
  citations: KnowledgeSearchCitation[];
  pending: boolean;
  onSubmit(input: KnowledgeCandidateInput): Promise<void>;
}

function KnowledgeCandidateDialog({
  question,
  citations,
  pending,
  onSubmit,
}: KnowledgeCandidateDialogProps) {
  const [open, setOpen] = useState(false);
  const [proposedAnswer, setProposedAnswer] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const validCitations = citations.filter(citationIsVerifiable);
  const [selectedSectionIds, setSelectedSectionIds] = useState<string[]>(() =>
    validCitations.map((citation) => citation.sectionId),
  );
  const normalizedAnswer = proposedAnswer.trim();
  const valid =
    normalizedAnswer.length >= 20 &&
    selectedSectionIds.length > 0 &&
    confirmation === "ENVIAR PARA REVISÃO";

  function setDialogOpen(nextOpen: boolean) {
    if (nextOpen) {
      setProposedAnswer("");
      setConfirmation("");
      setSelectedSectionIds(validCitations.map((citation) => citation.sectionId));
    } else {
      setProposedAnswer("");
      setConfirmation("");
      setSelectedSectionIds([]);
    }
    setOpen(nextOpen);
  }

  function toggleCitation(sectionId: string, checked: boolean) {
    setSelectedSectionIds((current) =>
      checked ? [...new Set([...current, sectionId])] : current.filter((id) => id !== sectionId),
    );
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || pending) return;
    try {
      await onSubmit({
        question,
        proposedAnswer: normalizedAnswer,
        citationSectionIds: selectedSectionIds,
        confirmation: "ENVIAR PARA REVISÃO",
      });
    } catch {
      return;
    }
    setDialogOpen(false);
  }

  return (
    <Dialog open={open} onOpenChange={setDialogOpen}>
      <DialogTrigger asChild>
        <Button type="button" variant="outline" disabled={validCitations.length === 0}>
          <Sparkles aria-hidden />
          Enviar proposta para revisão
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <form onSubmit={submit} className="space-y-4">
          <DialogHeader>
            <DialogTitle>Criar candidato de conhecimento</DialogTitle>
            <DialogDescription>
              A proposta entra na fila jurídica como rascunho. Ela nunca é publicada nem usada em
              respostas antes da revisão humana e da publicação explícita.
            </DialogDescription>
          </DialogHeader>

          <div className="rounded-md border border-border bg-muted/45 p-3">
            <p className="text-xs font-medium text-muted-foreground">Pergunta pesquisada</p>
            <p className="mt-1 text-sm font-semibold">{question}</p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="resposta-candidata">Resposta proposta</Label>
            <Textarea
              id="resposta-candidata"
              value={proposedAnswer}
              onChange={(event) => setProposedAnswer(event.target.value)}
              minLength={20}
              maxLength={8_000}
              className="min-h-32"
              placeholder="Redija uma orientação objetiva, sem extrapolar o que os dispositivos selecionados sustentam."
              required
            />
            <p className="text-xs text-muted-foreground">
              {normalizedAnswer.length.toLocaleString("pt-BR")} de 8.000 caracteres · mínimo de 20
            </p>
          </div>

          <fieldset className="rounded-md border border-border p-3">
            <legend className="px-1 text-sm font-medium">
              Fundamentação que seguirá para revisão
            </legend>
            <div className="mt-2 space-y-2">
              {validCitations.map((citation) => {
                const id = `citacao-candidata-${citation.sectionId}`;
                return (
                  <label
                    key={citation.sectionId}
                    htmlFor={id}
                    className="flex cursor-pointer items-start gap-3 rounded-md border border-border p-3 hover:bg-muted/50"
                  >
                    <Checkbox
                      id={id}
                      checked={selectedSectionIds.includes(citation.sectionId)}
                      onCheckedChange={(checked) =>
                        toggleCitation(citation.sectionId, checked === true)
                      }
                    />
                    <span className="min-w-0 text-xs">
                      <span className="block font-semibold text-foreground">
                        {citation.sourceTitle} · {citation.sectionHeading ?? citation.citationLabel}
                      </span>
                      <span className="mt-1 line-clamp-2 block text-muted-foreground">
                        {citation.quotedExcerpt}
                      </span>
                    </span>
                  </label>
                );
              })}
            </div>
            {selectedSectionIds.length === 0 ? (
              <p className="mt-2 text-xs text-critical" role="alert">
                Selecione ao menos um dispositivo oficial verificável.
              </p>
            ) : null}
          </fieldset>

          <div className="rounded-md border border-warning/40 bg-warning-soft/60 p-3">
            <Label htmlFor="confirmacao-candidato">Digite ENVIAR PARA REVISÃO para confirmar</Label>
            <Input
              id="confirmacao-candidato"
              value={confirmation}
              onChange={(event) => setConfirmation(event.target.value.toLocaleUpperCase("pt-BR"))}
              autoComplete="off"
              className="mt-2 bg-background"
            />
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => setDialogOpen(false)}
              disabled={pending}
            >
              Cancelar
            </Button>
            <Button type="submit" disabled={!valid || pending}>
              {pending ? "Enviando para revisão…" : "Enviar para revisão jurídica"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

interface KnowledgeSearchPanelProps {
  canSearch: boolean;
  canSubmitCandidates: boolean;
  onSearch(query: string): Promise<KnowledgeSearchResult>;
  onSubmitCandidate(input: KnowledgeCandidateInput): Promise<string>;
}

export function KnowledgeSearchPanel({
  canSearch,
  canSubmitCandidates,
  onSearch,
  onSubmitCandidate,
}: KnowledgeSearchPanelProps) {
  const [query, setQuery] = useState("");
  const normalizedQuery = query.trim();
  const search = useMutation({ mutationFn: onSearch });
  const candidate = useMutation({
    mutationFn: onSubmitCandidate,
    onSuccess: () =>
      toast.success("Proposta enviada para revisão", {
        description:
          "O conteúdo permanece como candidato até a aprovação jurídica e a publicação explícita.",
      }),
    onError: () =>
      toast.error("A proposta não foi enviada", {
        description: "Confira sua permissão, as citações selecionadas e tente novamente.",
      }),
  });
  const result = search.data;
  const verifiedAnswer = result ? resultHasVerifiedAnswer(result) : false;
  const verifiableCitations = useMemo(
    () => result?.citations.filter(citationIsVerifiable) ?? [],
    [result],
  );

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (
      !canSearch ||
      normalizedQuery.length < 5 ||
      normalizedQuery.length > 500 ||
      search.isPending
    ) {
      return;
    }
    search.mutate(normalizedQuery);
  }

  return (
    <SectionCard
      title="Consulta à legislação oficial"
      description="Faça uma pergunta em português. O sistema pesquisa integralmente o texto oficial vigente, sem gerar parecer automático."
      action={
        <Badge
          variant="outline"
          className="hidden border-success/40 bg-success-soft text-success sm:inline-flex"
        >
          <ShieldCheck aria-hidden />
          Trecho com fonte
        </Badge>
      }
    >
      {!canSearch ? (
        <div className="rounded-md border border-warning/40 bg-warning-soft/60 p-4" role="status">
          <p className="flex items-center gap-2 text-sm font-semibold text-warning-foreground">
            <ShieldAlert aria-hidden className="size-4" />
            Consulta não disponível para este acesso
          </p>
          <p className="mt-1 text-xs text-warning-foreground/85">
            Solicite ao administrador um vínculo municipal com permissão para consultar a base
            jurídica.
          </p>
        </div>
      ) : (
        <form onSubmit={submit} role="search" className="space-y-3">
          <Label htmlFor="pergunta-juridica">O que você precisa confirmar na legislação?</Label>
          <div className="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
            <Textarea
              id="pergunta-juridica"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              minLength={5}
              maxLength={500}
              rows={3}
              className="min-h-24 resize-y"
              placeholder="Ex.: Qual é o prazo de recolhimento do ISSQN para prestadores de serviços?"
              aria-describedby="orientacao-consulta"
              required
            />
            <Button
              type="submit"
              className="sm:h-24 sm:min-w-36"
              disabled={
                normalizedQuery.length < 5 || normalizedQuery.length > 500 || search.isPending
              }
            >
              {search.isPending ? (
                <RefreshCw className="animate-spin motion-reduce:animate-none" aria-hidden />
              ) : (
                <Search aria-hidden />
              )}
              {search.isPending ? "Consultando…" : "Consultar base"}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            {query.length.toLocaleString("pt-BR")} de 500 caracteres
          </p>
          <div className="flex flex-wrap items-center gap-2" id="orientacao-consulta">
            <span className="text-xs text-muted-foreground">Perguntas frequentes:</span>
            {EXAMPLE_QUESTIONS.map((example) => (
              <Button
                key={example}
                type="button"
                size="sm"
                variant="outline"
                className="h-auto whitespace-normal py-1.5 text-left"
                onClick={() => setQuery(example)}
              >
                {example}
              </Button>
            ))}
          </div>
        </form>
      )}

      <div className="mt-5 border-t border-border pt-5" aria-live="polite">
        {search.isPending ? (
          <div>
            <p className="mb-3 flex items-center gap-2 text-sm font-medium">
              <FileSearch className="size-4 text-primary" aria-hidden />
              Verificando texto, vigência e origem oficial…
            </p>
            <SectionSkeleton rows={3} />
          </div>
        ) : search.isError ? (
          <ErrorState
            message="Não foi possível consultar a base jurídica com segurança."
            error={search.error}
            onRetry={() => search.mutate(search.variables ?? normalizedQuery)}
            retrying={search.isPending}
          />
        ) : !result ? (
          <div className="rounded-md border border-dashed border-border px-4 py-8 text-center">
            <FileQuestion className="mx-auto size-7 text-muted-foreground" aria-hidden />
            <p className="mt-2 text-sm font-medium">
              O trecho oficial mais aderente aparecerá aqui
            </p>
            <p className="mx-auto mt-1 max-w-xl text-xs text-muted-foreground">
              O sistema pesquisa apenas versões oficiais publicadas e dentro da vigência. Ausência
              de evidência resulta em recusa, nunca em suposição.
            </p>
          </div>
        ) : (
          <div className="grid gap-4 xl:grid-cols-[minmax(0,1.15fr)_minmax(22rem,0.85fr)]">
            <article
              className={cn(
                "rounded-lg border p-4 sm:p-5",
                verifiedAnswer
                  ? "border-success/35 bg-success-soft/35"
                  : "border-warning/45 bg-warning-soft/45",
              )}
              aria-labelledby="resposta-juridica-titulo"
            >
              {verifiedAnswer ? (
                <>
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-success">
                        <BookOpenCheck className="size-4" aria-hidden />
                        Trecho oficial mais relevante
                      </p>
                      <h3 id="resposta-juridica-titulo" className="mt-2 text-lg font-semibold">
                        Evidência para análise fiscal
                      </h3>
                    </div>
                    <Badge
                      variant="outline"
                      className="border-success/40 bg-background text-success"
                    >
                      {confidenceLabel(result.confidence)}
                    </Badge>
                  </div>
                  <p className="mt-4 whitespace-pre-wrap text-sm leading-6">{result.answer}</p>
                  <div className="mt-4 rounded-md border border-success/25 bg-background/75 p-3 text-xs text-muted-foreground">
                    <p className="flex items-start gap-2">
                      <ShieldCheck className="mt-0.5 size-3.5 shrink-0 text-success" aria-hidden />
                      Este é um trecho recuperado da fonte oficial, não um parecer nem uma resposta
                      automática. Confira as evidências ao lado e registre a decisão humana no
                      processo fiscal.
                    </p>
                  </div>
                </>
              ) : (
                <>
                  <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-warning-foreground">
                    <ShieldAlert className="size-4" aria-hidden />
                    Resposta não liberada
                  </p>
                  <h3 id="resposta-juridica-titulo" className="mt-2 text-lg font-semibold">
                    A base oficial não sustenta uma resposta segura
                  </h3>
                  <p className="mt-2 text-sm leading-6 text-muted-foreground">
                    Nenhuma conclusão foi criada. Revise os dispositivos localizados, ajuste a
                    pergunta ou encaminhe uma proposta fundamentada para revisão jurídica.
                  </p>
                  {result.blockers.length > 0 ? (
                    <div className="mt-4">
                      <KnowledgeBlockers blockers={result.blockers} />
                    </div>
                  ) : null}
                </>
              )}

              <dl className="mt-4 grid gap-3 border-t border-current/10 pt-3 text-xs sm:grid-cols-2">
                <div>
                  <dt className="font-medium">Método</dt>
                  <dd className="mt-0.5 text-muted-foreground">
                    {retrievalLabel(result.retrievalMode)}
                  </dd>
                </div>
                <div>
                  <dt className="font-medium">Consulta verificada em</dt>
                  <dd className="mt-0.5 text-muted-foreground">
                    {safeDateTime(result.searchedAt)}
                  </dd>
                </div>
                <div className="sm:col-span-2">
                  <dt className="font-medium">Código da consulta</dt>
                  <dd className="mt-0.5 break-all font-mono text-muted-foreground">
                    {result.correlationId}
                  </dd>
                </div>
              </dl>

              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => search.mutate(result.query)}
                  disabled={search.isPending}
                >
                  <RefreshCw aria-hidden />
                  Refazer consulta
                </Button>
                {canSubmitCandidates ? (
                  <KnowledgeCandidateDialog
                    question={result.query}
                    citations={verifiableCitations}
                    pending={candidate.isPending}
                    onSubmit={async (input) => {
                      await candidate.mutateAsync(input);
                    }}
                  />
                ) : null}
              </div>
            </article>

            <aside
              className="rounded-lg border border-border bg-muted/35 p-4"
              aria-labelledby="evidencias-consulta-titulo"
            >
              <div className="mb-3 flex items-center justify-between gap-3">
                <div>
                  <h3 id="evidencias-consulta-titulo" className="text-sm font-semibold">
                    Evidências oficiais
                  </h3>
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {result.citations.length} dispositivo(s) localizado(s)
                  </p>
                </div>
                <ArrowRight className="hidden size-4 text-primary xl:block" aria-hidden />
              </div>
              <KnowledgeSearchCitations citations={result.citations} />
            </aside>
          </div>
        )}
      </div>
    </SectionCard>
  );
}

function indexCoverage(index: KnowledgeIndexStatus): number | null {
  if (index.eligibleSections <= 0 || index.indexedSections > index.eligibleSections) return null;
  return Math.round((index.indexedSections / index.eligibleSections) * 100);
}

function coverageUpstreamLabel(status: KnowledgeCatalogCoverage["upstreamStatus"]): string {
  if (status === "available") return "Portal oficial disponível";
  if (status === "unverified") return "Portal oficial ainda não verificado";
  if (status === "blocked_403") return "Portal oficial recusou o acesso (403)";
  if (status === "blocked_502") return "Portal oficial indisponível (502)";
  return "Portal oficial indisponível (503)";
}

export function KnowledgeAutomationPanel({
  schedule,
  index,
  ocr,
  health,
  reviewer,
  coverage,
  coverageLabel,
  corpusIntegral,
}: {
  schedule: KnowledgeScheduleStatus;
  index: KnowledgeIndexStatus;
  ocr: KnowledgeOcrStatus;
  health: KnowledgeHealthStatus;
  reviewer: KnowledgeReviewerStatus;
  coverage: KnowledgeCatalogCoverage[];
  coverageLabel: string;
  corpusIntegral: boolean;
}) {
  const indexCoveragePercent = indexCoverage(index);
  const nextRunVerified = Boolean(
    schedule.nextRunAt && !Number.isNaN(Date.parse(schedule.nextRunAt)),
  );
  const scheduleOperational = Boolean(
    schedule.enabled &&
    schedule.runtimeVerified &&
    schedule.timeZone &&
    nextRunVerified &&
    schedule.blockers.length === 0,
  );
  return (
    <div className="space-y-4">
      <SectionCard
        title="Atualização automática"
        description="Agenda de coleta, conferência de mudanças e reconstrução do índice jurídico."
        action={
          <KnowledgeStateBadge
            status={
              scheduleOperational ? "active" : schedule.blockers.length > 0 ? "blocked" : "paused"
            }
          />
        }
      >
        <div className="grid gap-3 lg:grid-cols-3">
          <div className="rounded-md border border-border bg-muted/35 p-4">
            <p className="flex items-center gap-2 text-sm font-semibold">
              <Clock3 className="size-4 text-primary" aria-hidden />
              Agenda
            </p>
            <p className="mt-2 text-sm">{schedule.cadenceLabel}</p>
            <p className="mt-1 text-xs text-muted-foreground">
              Fuso horário:{" "}
              {schedule.timeZone === "America/Sao_Paulo"
                ? "Brasília"
                : (schedule.timeZone ?? "Não verificado")}
            </p>
          </div>
          <div className="rounded-md border border-border bg-muted/35 p-4">
            <p className="flex items-center gap-2 text-sm font-semibold">
              <RefreshCw className="size-4 text-primary" aria-hidden />
              Execuções
            </p>
            <dl className="mt-2 space-y-2 text-xs">
              <div>
                <dt className="text-muted-foreground">Próxima verificação</dt>
                <dd className="font-medium">{safeDateTime(schedule.nextRunAt)}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">Última execução</dt>
                <dd className="font-medium">{safeDateTime(schedule.lastRunAt)}</dd>
              </div>
            </dl>
          </div>
          <div className="rounded-md border border-border bg-muted/35 p-4">
            <p className="flex items-center gap-2 text-sm font-semibold">
              <ShieldCheck className="size-4 text-primary" aria-hidden />
              Resultado mais recente
            </p>
            <div className="mt-2">
              <KnowledgeStateBadge status={schedule.lastRunStatus} />
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              Mudanças detectadas permanecem bloqueadas até a revisão humana.
            </p>
          </div>
        </div>
        {schedule.blockers.length > 0 ? (
          <div className="mt-3">
            <KnowledgeBlockers blockers={schedule.blockers} />
          </div>
        ) : null}
      </SectionCard>

      <SectionCard
        title="OCR jurídico governado"
        description="Leitura de leis oficiais digitalizadas sem publicar automaticamente o texto reconhecido."
        action={<KnowledgeStateBadge status={ocr.state} />}
      >
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          {[
            ["Na fila", ocr.jobs.queued],
            ["Em processamento", ocr.jobs.processing],
            ["Concluídos", ocr.jobs.completed],
            ["Intervenção necessária", ocr.jobs.deadLetter],
            ["Acima de 120 páginas", ocr.jobs.blockedPageLimit],
          ].map(([label, value]) => (
            <div key={label} className="rounded-md border border-border bg-muted/35 p-4">
              <p className="text-2xl font-semibold tabular-nums">
                {(value as number).toLocaleString("pt-BR")}
              </p>
              <p className="text-xs text-muted-foreground">{label}</p>
            </div>
          ))}
        </div>
        <div className="mt-3 grid gap-3 rounded-md border border-border bg-muted/20 p-4 text-xs sm:grid-cols-3">
          <div>
            <p className="text-muted-foreground">Último evento</p>
            <p className="mt-0.5 font-medium">{safeDateTime(ocr.lastEventAt)}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Limite desta versão</p>
            <p className="mt-0.5 font-medium">
              Até {ocr.limits.maxPages.toLocaleString("pt-BR")} páginas por documento
            </p>
          </div>
          <div>
            <p className="text-muted-foreground">Saída do OCR</p>
            <p className="mt-0.5 font-medium">Sempre encaminhada para revisão jurídica</p>
          </div>
        </div>
        <p className="mt-3 text-xs text-muted-foreground">
          O texto reconhecido é tratado como evidência não confiável até conferência humana. A
          esteira não aprova nem publica conteúdo automaticamente.
        </p>
        {ocr.blockers.length > 0 ? (
          <div className="mt-3">
            <KnowledgeBlockers blockers={ocr.blockers} />
          </div>
        ) : null}
      </SectionCard>

      <SectionCard
        title={corpusIntegral ? "Corpus integral verificado" : coverageLabel}
        description={
          corpusIntegral
            ? "Todas as classificações esperadas foram descobertas e publicadas com governança."
            : "A cobertura abaixo é operacional e parcial; descoberta não significa texto integral, revisão ou publicação."
        }
        action={<KnowledgeStateBadge status={corpusIntegral ? "healthy" : "attention"} />}
      >
        {coverage.length === 0 ? (
          <p
            className="rounded-md border border-critical/35 bg-critical-soft p-4 text-sm text-critical"
            role="alert"
          >
            Nenhuma classificação de cobertura foi verificada. O sistema não declara corpus
            integral.
          </p>
        ) : (
          <ul className="space-y-3">
            {coverage.map((item) => (
              <li
                key={item.coverageKey}
                className="rounded-md border border-border bg-muted/20 p-4"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="text-sm font-semibold">{item.title}</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {coverageUpstreamLabel(item.upstreamStatus)}
                    </p>
                  </div>
                  <KnowledgeStateBadge
                    status={
                      item.corpusIntegral
                        ? "healthy"
                        : item.upstreamStatus.startsWith("blocked_")
                          ? "blocked"
                          : "attention"
                    }
                    label="Cobertura"
                  />
                </div>
                <dl className="mt-3 grid gap-2 sm:grid-cols-3 xl:grid-cols-6">
                  {[
                    ["Esperados", item.expected == null ? "Não confirmado" : item.expected],
                    ["Descobertos", item.discovered],
                    ["Identidade conferida", item.identityVerified],
                    ["Extração na fila", item.extractionQueued],
                    ["Revisáveis", item.reviewable],
                    ["Publicados", item.published],
                  ].map(([label, value]) => (
                    <div key={label} className="rounded border border-border bg-background p-2.5">
                      <dt className="text-[11px] text-muted-foreground">{label}</dt>
                      <dd className="mt-0.5 text-sm font-semibold tabular-nums">
                        {typeof value === "number" ? value.toLocaleString("pt-BR") : value}
                      </dd>
                    </div>
                  ))}
                </dl>
                {item.blocker ? (
                  <div className="mt-3">
                    <KnowledgeBlockers blockers={[item.blocker]} />
                  </div>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </SectionCard>

      <SectionCard
        title="Cobertura da busca oficial em português"
        description="Somente dispositivos integrais de versões oficiais publicadas e vigentes entram no índice lexical."
        action={<KnowledgeStateBadge status={index.status} />}
      >
        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_18rem] lg:items-center">
          <div>
            <div className="flex items-center justify-between gap-3 text-sm">
              <span className="font-medium">Dispositivos disponíveis para consulta</span>
              <span className="font-semibold tabular-nums">
                {indexCoveragePercent == null ? "Não verificada" : `${indexCoveragePercent}%`}
              </span>
            </div>
            {indexCoveragePercent == null ? (
              <div
                className="mt-2 rounded-md border border-critical/35 bg-critical-soft p-3 text-xs text-critical"
                role="alert"
              >
                A cobertura não pode ser calculada com segurança enquanto as contagens do índice
                estiverem inconsistentes ou sem dispositivos elegíveis.
              </div>
            ) : (
              <progress
                className="mt-2 h-2 w-full accent-[var(--color-primary)]"
                value={index.indexedSections}
                max={index.eligibleSections}
                aria-label="Cobertura do índice jurídico"
              />
            )}
            <p className="mt-2 text-xs text-muted-foreground">
              {index.indexedSections.toLocaleString("pt-BR")} de{" "}
              {index.eligibleSections.toLocaleString("pt-BR")} dispositivo(s) elegível(is)
              indexado(s).
            </p>
            {index.blockers.length > 0 ? (
              <div className="mt-3">
                <KnowledgeBlockers blockers={index.blockers} />
              </div>
            ) : null}
          </div>
          <dl className="rounded-md border border-border bg-muted/35 p-4 text-xs">
            <div>
              <dt className="text-muted-foreground">Última indexação</dt>
              <dd className="mt-0.5 font-medium">{safeDateTime(index.lastIndexedAt)}</dd>
            </div>
            <div className="mt-3 border-t border-border pt-3">
              <dt className="text-muted-foreground">Mecanismo de representação</dt>
              <dd className="mt-0.5 font-medium">Índice lexical PT-BR integral</dd>
            </div>
            <div className="mt-3 border-t border-border pt-3">
              <dt className="text-muted-foreground">Busca semântica suplementar</dt>
              <dd className="mt-0.5 font-medium">
                {index.semanticStatus === "unsupported_language"
                  ? "Indisponível: modelo instalado incompatível com PT-BR"
                  : "Estado não verificado"}
              </dd>
              {index.semanticHistoricalChunks > 0 ? (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {index.semanticHistoricalChunks.toLocaleString("pt-BR")} vetor(es) legado(s)
                  preservado(s) apenas para auditoria, sem uso na consulta.
                </p>
              ) : null}
            </div>
          </dl>
        </div>
      </SectionCard>

      <SectionCard
        title="Revisão jurídica"
        description="Confirmação agregada da capacidade humana que governa aprovações e publicações."
        action={
          <KnowledgeStateBadge
            status={reviewer.verified && reviewer.configured ? "active" : "blocked"}
          />
        }
      >
        {reviewer.verified ? (
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-md border border-border bg-muted/35 p-4">
              <p className="text-2xl font-semibold tabular-nums">
                {reviewer.activeCount.toLocaleString("pt-BR")}
              </p>
              <p className="text-xs text-muted-foreground">revisor(es) jurídico(s) ativo(s)</p>
            </div>
            <div className="rounded-md border border-border bg-muted/35 p-4">
              <p className="text-sm font-semibold">
                {reviewer.currentUserCanReview
                  ? "Seu acesso pode revisar"
                  : "Seu acesso não pode revisar"}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                A autorização individual continua sendo revalidada no servidor em cada decisão.
              </p>
            </div>
          </div>
        ) : (
          <p className="rounded-md border border-critical/35 bg-critical-soft p-4 text-sm text-critical">
            A configuração dos revisores não foi comprovada. As ações de revisão permanecem
            indisponíveis.
          </p>
        )}
        {reviewer.blockers.length > 0 ? (
          <div className="mt-3">
            <KnowledgeBlockers blockers={reviewer.blockers} />
          </div>
        ) : null}
      </SectionCard>

      <SectionCard
        title="Saúde operacional"
        description="Alertas que impedem coleta, indexação, revisão ou publicação."
      >
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="rounded-md border border-border bg-muted/35 p-3">
            <p className="text-2xl font-semibold tabular-nums">
              {health.staleSources.toLocaleString("pt-BR")}
            </p>
            <p className="text-xs text-muted-foreground">fontes desatualizadas</p>
          </div>
          <div className="rounded-md border border-border bg-muted/35 p-3">
            <p className="text-2xl font-semibold tabular-nums">
              {health.failedSources.toLocaleString("pt-BR")}
            </p>
            <p className="text-xs text-muted-foreground">fontes com falha</p>
          </div>
          <div className="rounded-md border border-border bg-muted/35 p-3">
            <p className="text-2xl font-semibold tabular-nums">
              {health.blockedSources.toLocaleString("pt-BR")}
            </p>
            <p className="text-xs text-muted-foreground">fontes bloqueadas</p>
          </div>
        </div>
        {health.blockers.length > 0 ? (
          <div className="mt-4">
            <KnowledgeBlockers blockers={health.blockers} />
          </div>
        ) : null}
      </SectionCard>
    </div>
  );
}

function reviewerRoleLabel(role: string): string {
  if (role === "municipal_admin") return "Administrador municipal";
  if (role === "supervisor") return "Supervisor fiscal";
  if (role === "fiscal_auditor") return "Auditor fiscal";
  if (role === "legal_reviewer") return "Revisor jurídico";
  return "Papel não reconhecido";
}

function ReviewerGrantDialog({
  staff,
  user,
  pending,
  onConfirm,
}: {
  staff: KnowledgeReviewerEligibleStaff;
  user: MunicipalityUser;
  pending: boolean;
  onConfirm(validUntil: string | null, reason: string, confirmation: string): Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [validUntil, setValidUntil] = useState("");
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const validUntilShape = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(validUntil);
  const parsedValidity = validUntil && validUntilShape ? Date.parse(validUntil) : null;
  const valid =
    reason.trim().length >= 10 &&
    reason.trim().length <= 1_000 &&
    confirmation === "CONFIRMAR REVISOR JURIDICO" &&
    (!validUntil ||
      (parsedValidity !== null &&
        !Number.isNaN(parsedValidity) &&
        parsedValidity > Date.now() + 5 * 60_000));

  function resetState() {
    setValidUntil("");
    setReason("");
    setConfirmation("");
  }

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) resetState();
    setOpen(nextOpen);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || pending) return;
    try {
      await onConfirm(
        parsedValidity === null ? null : new Date(parsedValidity).toISOString(),
        reason.trim(),
        confirmation,
      );
    } catch {
      return;
    }
    handleOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button type="button" size="sm" variant="outline">
          Designar revisor
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-4">
          <DialogHeader>
            <DialogTitle>Designar capacidade de revisão jurídica</DialogTitle>
            <DialogDescription>
              {user.fullName} ({user.email}) receberá capacidade adicional para revisar conteúdo
              jurídico no município atual. A ação exige autenticação em duas etapas.
            </DialogDescription>
          </DialogHeader>
          <div className="rounded-md border border-border bg-muted/35 p-3 text-xs">
            <p className="font-semibold">{reviewerRoleLabel(staff.role)}</p>
            <p className="mt-1 text-muted-foreground">Vínculo verificado: {user.membershipId}</p>
          </div>
          <div className="space-y-2">
            <Label htmlFor={`validade-revisor-${staff.membershipId}`}>Validade (opcional)</Label>
            <Input
              id={`validade-revisor-${staff.membershipId}`}
              type="datetime-local"
              value={validUntil}
              onChange={(event) => setValidUntil(event.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Sem data, a capacidade permanece ativa até revogação explícita.
            </p>
          </div>
          <div className="space-y-2">
            <Label htmlFor={`motivo-revisor-${staff.membershipId}`}>Motivo da designação</Label>
            <Textarea
              id={`motivo-revisor-${staff.membershipId}`}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              minLength={10}
              maxLength={1_000}
              required
            />
          </div>
          <div className="rounded-md border border-warning/40 bg-warning-soft/60 p-3">
            <Label htmlFor={`confirmacao-revisor-${staff.membershipId}`}>
              Digite CONFIRMAR REVISOR JURIDICO para confirmar
            </Label>
            <Input
              id={`confirmacao-revisor-${staff.membershipId}`}
              value={confirmation}
              onChange={(event) => setConfirmation(event.target.value.toLocaleUpperCase("pt-BR"))}
              autoComplete="off"
              className="mt-2 bg-background"
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
              Cancelar
            </Button>
            <Button type="submit" disabled={!valid || pending}>
              {pending ? "Designando…" : "Confirmar designação"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function ReviewerRevokeDialog({
  grant,
  user,
  pending,
  onConfirm,
}: {
  grant: KnowledgeReviewerGrant;
  user: MunicipalityUser;
  pending: boolean;
  onConfirm(reason: string, confirmation: string): Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const valid =
    reason.trim().length >= 10 &&
    reason.trim().length <= 1_000 &&
    confirmation === "REVOGAR REVISOR JURIDICO";

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) {
      setReason("");
      setConfirmation("");
    }
    setOpen(nextOpen);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || pending) return;
    try {
      await onConfirm(reason.trim(), confirmation);
    } catch {
      return;
    }
    handleOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button type="button" size="sm" variant="outline">
          Revogar capacidade
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-4">
          <DialogHeader>
            <DialogTitle>Revogar capacidade de revisão</DialogTitle>
            <DialogDescription>
              A capacidade adicional de {user.fullName} ({user.email}) será revogada. O vínculo
              municipal não será alterado.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor={`motivo-revogacao-${grant.grantId}`}>Motivo da revogação</Label>
            <Textarea
              id={`motivo-revogacao-${grant.grantId}`}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              minLength={10}
              maxLength={1_000}
              required
            />
          </div>
          <div className="rounded-md border border-critical/35 bg-critical-soft/60 p-3">
            <Label htmlFor={`confirmacao-revogacao-${grant.grantId}`}>
              Digite REVOGAR REVISOR JURIDICO para confirmar
            </Label>
            <Input
              id={`confirmacao-revogacao-${grant.grantId}`}
              value={confirmation}
              onChange={(event) => setConfirmation(event.target.value.toLocaleUpperCase("pt-BR"))}
              autoComplete="off"
              className="mt-2 bg-background"
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
              Cancelar
            </Button>
            <Button type="submit" variant="destructive" disabled={!valid || pending}>
              {pending ? "Revogando…" : "Confirmar revogação"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function KnowledgeReviewerAdminPanel({
  directory,
  users,
  currentMembershipId,
  loading,
  error,
  retrying,
  pending,
  onRetry,
  onGrant,
  onRevoke,
}: {
  directory: KnowledgeReviewerDirectory | null;
  users: MunicipalityUser[];
  currentMembershipId: string | null;
  loading: boolean;
  error: unknown;
  retrying: boolean;
  pending: boolean;
  onRetry(): void;
  onGrant(
    staff: KnowledgeReviewerEligibleStaff,
    validUntil: string | null,
    reason: string,
    confirmation: string,
  ): Promise<void>;
  onRevoke(grant: KnowledgeReviewerGrant, reason: string, confirmation: string): Promise<void>;
}) {
  const usersByMembership = new Map(users.map((user) => [user.membershipId, user]));
  const eligible =
    directory?.eligibleStaff.filter(
      (staff) =>
        !staff.alreadyConfigured &&
        staff.role !== "legal_reviewer" &&
        staff.membershipId !== currentMembershipId,
    ) ?? [];
  const currentGrants = directory?.activeGrants.filter((grant) => grant.isCurrent) ?? [];

  return (
    <SectionCard
      title="Administração de revisores"
      description="Designações adicionais auditáveis; o papel municipal original não é alterado."
    >
      {loading ? (
        <SectionSkeleton rows={3} />
      ) : error || !directory?.verified || directory.piiExposed ? (
        <ErrorState
          message="Não foi possível verificar as designações de revisores."
          error={error}
          onRetry={onRetry}
          retrying={retrying}
        />
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          <section aria-labelledby="revisores-ativos-titulo">
            <h3 id="revisores-ativos-titulo" className="text-sm font-semibold">
              Capacidades adicionais ativas
            </h3>
            {currentGrants.length === 0 ? (
              <p className="mt-2 text-sm text-muted-foreground">
                Nenhuma designação adicional ativa.
              </p>
            ) : (
              <ul className="mt-2 space-y-2">
                {currentGrants.map((grant) => {
                  const user = usersByMembership.get(grant.membershipId);
                  return (
                    <li key={grant.grantId} className="rounded-md border border-border p-3">
                      <p className="text-sm font-semibold">
                        {user?.fullName ?? "Identidade do vínculo não verificada"}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {user?.email ?? grant.membershipId} · {reviewerRoleLabel(grant.role)}
                      </p>
                      <p className="mt-1 text-xs text-muted-foreground">
                        Validade: {grant.validUntil ? safeDateTime(grant.validUntil) : "sem prazo"}
                      </p>
                      {user ? (
                        <div className="mt-3">
                          <ReviewerRevokeDialog
                            grant={grant}
                            user={user}
                            pending={pending}
                            onConfirm={(reason, confirmation) =>
                              onRevoke(grant, reason, confirmation)
                            }
                          />
                        </div>
                      ) : (
                        <p className="mt-2 text-xs text-critical" role="alert">
                          Revogação indisponível até confirmar a identidade do vínculo.
                        </p>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </section>

          <section aria-labelledby="equipe-elegivel-titulo">
            <h3 id="equipe-elegivel-titulo" className="text-sm font-semibold">
              Equipe elegível
            </h3>
            {eligible.length === 0 ? (
              <p className="mt-2 text-sm text-muted-foreground">
                Nenhum vínculo adicional está disponível para designação.
              </p>
            ) : (
              <ul className="mt-2 space-y-2">
                {eligible.map((staff) => {
                  const user = usersByMembership.get(staff.membershipId);
                  return (
                    <li key={staff.membershipId} className="rounded-md border border-border p-3">
                      <p className="text-sm font-semibold">
                        {user?.fullName ?? "Identidade do vínculo não verificada"}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {user?.email ?? staff.membershipId} · {reviewerRoleLabel(staff.role)}
                      </p>
                      {user ? (
                        <div className="mt-3">
                          <ReviewerGrantDialog
                            staff={staff}
                            user={user}
                            pending={pending}
                            onConfirm={(validUntil, reason, confirmation) =>
                              onGrant(staff, validUntil, reason, confirmation)
                            }
                          />
                        </div>
                      ) : (
                        <p className="mt-2 text-xs text-critical" role="alert">
                          Designação indisponível até confirmar a identidade do vínculo.
                        </p>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </div>
      )}
    </SectionCard>
  );
}
