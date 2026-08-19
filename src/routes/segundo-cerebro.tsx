import { useMemo, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import {
  AlertTriangle,
  BookOpenCheck,
  DatabaseZap,
  FileSearch,
  FileClock,
  Files,
  FlaskConical,
  HeartPulse,
  LibraryBig,
  MapPin,
  RefreshCw,
  Search,
  ShieldCheck,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/auth/AuthContext";
import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import {
  KnowledgeAutomationPanel,
  KnowledgeReviewerAdminPanel,
  KnowledgeSearchPanel,
} from "@/components/knowledge/KnowledgeIntelligence";
import {
  KnowledgeBlockers,
  KnowledgeCitationList,
  KnowledgeChangesPanel,
  KnowledgeReviewsPanel,
  KnowledgeSourcesPanel,
  KnowledgeValidity,
} from "@/components/knowledge/KnowledgeOperations";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type {
  KnowledgeCandidateReviewDecision,
  KnowledgeCandidateInput,
  KnowledgeReviewDecision,
  KnowledgeReviewerEligibleStaff,
  KnowledgeReviewerGrant,
  KnowledgeReviewQueueItem,
  KnowledgeSourceChange,
  KnowledgeSourceEvidencePageRequest,
  LegalSourceReviewDecision,
  LegalSourceReviewMetadata,
} from "@/features/knowledge/knowledge-models";
import {
  knowledgeDivergenceScopeLabel,
  knowledgeIntentLabel,
  knowledgeTaxScopeLabel,
} from "@/lib/fiscal-labels";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type { KnowledgeArticleReadModel } from "@/types/read-models";

export const Route = createFileRoute("/segundo-cerebro")({
  head: () => ({
    meta: [
      { title: "Segundo Cérebro — IA Fiscal" },
      {
        name: "description",
        content:
          "Pesquisa jurídica municipal com respostas citadas, fontes oficiais, revisão humana e atualização automática.",
      },
    ],
  }),
  component: KnowledgePage,
});

type GovernanceAction =
  | {
      kind: "review-source";
      changeSetId: string;
      decision: LegalSourceReviewDecision;
      notes: string;
      confirmation: string;
      metadata: LegalSourceReviewMetadata;
    }
  | { kind: "publish-source"; sourceVersionId: string; confirmation: string }
  | {
      kind: "review-article";
      articleId: string;
      revisionId: string;
      decision: KnowledgeReviewDecision;
      notes: string;
      confirmation: string;
    }
  | {
      kind: "review-candidate";
      candidateId: string;
      decision: KnowledgeCandidateReviewDecision;
      notes: string;
      confirmation: string;
    }
  | { kind: "publish-article"; articleId: string; confirmation: string };

type ReviewerAction =
  | {
      kind: "grant";
      staff: KnowledgeReviewerEligibleStaff;
      validUntil: string | null;
      reason: string;
      confirmation: string;
    }
  | {
      kind: "revoke";
      grant: KnowledgeReviewerGrant;
      reason: string;
      confirmation: string;
    };

function safeDateTime(value: string | null | undefined): string {
  if (!value || Number.isNaN(Date.parse(value))) return "Estado não verificado";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}

function knowledgeActionErrorMessage(error: unknown): string {
  const value = error instanceof Error ? error.message : "";
  if (/42501|permission|denied/i.test(value)) {
    return "Seu papel atual ou sua autenticação não permitem concluir esta ação.";
  }
  if (/confirmation/i.test(value)) return "A confirmação digitada não corresponde à ação.";
  if (/citation/i.test(value)) return "Inclua ao menos uma citação oficial antes de aprovar.";
  if (/hash|changed/i.test(value)) {
    return "O conteúdo mudou após a revisão. Atualize a tela e revise a versão atual.";
  }
  return "O servidor manteve o conteúdo bloqueado. Atualize a tela e confira as pendências.";
}

function KnowledgeMetric({
  icon,
  value,
  label,
  tone = "primary",
}: {
  icon: ReactNode;
  value: number | null;
  label: string;
  tone?: "primary" | "success" | "warning" | "critical";
}) {
  const toneClass = {
    primary: "bg-primary-soft text-primary",
    success: "bg-success-soft text-success",
    warning: "bg-warning-soft text-warning-foreground",
    critical: "bg-critical-soft text-critical",
  }[tone];
  return (
    <div className="surface-card flex min-w-0 items-center gap-3 p-3.5">
      <span className={`grid size-9 shrink-0 place-items-center rounded-md ${toneClass}`}>
        {icon}
      </span>
      <div className="min-w-0">
        <p className="text-xl font-semibold tabular-nums">
          {value == null ? (
            <span role="status" aria-label={`Carregando ${label}`}>
              …
            </span>
          ) : (
            value.toLocaleString("pt-BR")
          )}
        </p>
        <p className="truncate text-xs text-muted-foreground">{label}</p>
      </div>
    </div>
  );
}

function KnowledgeCard({ item }: { item: KnowledgeArticleReadModel }) {
  return (
    <li className="rounded-lg border border-border bg-card p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="secondary">{knowledgeTaxScopeLabel(item.taxScope)}</Badge>
            <Badge variant="outline">{knowledgeDivergenceScopeLabel(item.divergenceScope)}</Badge>
            {item.isTest ? (
              <Badge
                variant="outline"
                className="border-warning/50 bg-warning-soft text-warning-foreground"
              >
                <FlaskConical className="mr-1 size-3.5" aria-hidden />
                Demonstração
              </Badge>
            ) : null}
          </div>
          <h3 className="mt-3 text-base font-semibold">{item.canonicalQuestion}</h3>
          <p className="mt-1 text-xs text-muted-foreground">
            Tema da orientação: {knowledgeIntentLabel(item.intentKey)}
          </p>
        </div>
        <Badge variant="outline" className="border-success/40 bg-success-soft text-success">
          <BookOpenCheck className="mr-1 size-3.5" aria-hidden />
          Publicada · versão {item.semanticVersion}
        </Badge>
      </div>

      <details className="mt-4 rounded-md border border-border bg-muted/40">
        <summary className="cursor-pointer px-3 py-2.5 text-sm font-medium">
          Consultar orientação fiscal
        </summary>
        <div className="border-t border-border px-3 py-3">
          <p className="whitespace-pre-wrap text-sm leading-relaxed">{item.answerBody}</p>
          <KnowledgeCitationList citations={item.citations} />
          <p className="mt-3 flex items-start gap-2 border-t border-border pt-3 text-xs text-muted-foreground">
            <ShieldCheck className="mt-0.5 size-3.5 shrink-0 text-success" aria-hidden />
            Conteúdo publicado por fluxo governado. Confira a origem oficial e a vigência antes de
            aplicá-lo a um caso concreto.
          </p>
        </div>
      </details>

      <dl className="mt-4 grid gap-3 text-xs sm:grid-cols-3">
        <div>
          <dt className="font-medium text-foreground">Publicação</dt>
          <dd className="mt-0.5 text-muted-foreground">{safeDateTime(item.publishedAt)}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="font-medium text-foreground">Vigência</dt>
          <dd className="mt-0.5 text-muted-foreground">
            <KnowledgeValidity validFrom={item.validFrom} validUntil={item.validUntil} />
          </dd>
        </div>
      </dl>
    </li>
  );
}

function KnowledgeLibrary({
  articles,
  loading,
  error,
  retrying,
  onRetry,
}: {
  articles: KnowledgeArticleReadModel[];
  loading: boolean;
  error: unknown;
  retrying: boolean;
  onRetry(): void;
}) {
  const [search, setSearch] = useState("");
  const filteredArticles = useMemo(() => {
    const normalized = search.trim().toLocaleLowerCase("pt-BR");
    if (!normalized) return articles;
    return articles.filter((item) =>
      [
        item.canonicalQuestion,
        knowledgeIntentLabel(item.intentKey),
        knowledgeTaxScopeLabel(item.taxScope),
        knowledgeDivergenceScopeLabel(item.divergenceScope),
        item.answerBody,
      ].some((value) => value.toLocaleLowerCase("pt-BR").includes(normalized)),
    );
  }, [articles, search]);

  return (
    <SectionCard
      title="Biblioteca tributária publicada"
      description="Somente orientações vigentes, aprovadas e vinculadas a fontes oficiais são exibidas."
      action={
        <span className="hidden text-xs tabular-nums text-muted-foreground sm:inline">
          {filteredArticles.length} resultado(s)
        </span>
      }
    >
      <label htmlFor="busca-conhecimento" className="sr-only">
        Buscar na biblioteca tributária
      </label>
      <div className="relative mb-4">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
          aria-hidden
        />
        <Input
          id="busca-conhecimento"
          type="search"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Buscar por pergunta, tributo ou tema"
          className="pl-9"
        />
      </div>

      {error ? (
        <ErrorState
          message="Não foi possível carregar a biblioteca tributária."
          error={error}
          onRetry={onRetry}
          retrying={retrying}
        />
      ) : loading ? (
        <SectionSkeleton rows={4} />
      ) : articles.length === 0 ? (
        <EmptyState message="Nenhuma orientação fiscal produtiva está publicada para este município." />
      ) : filteredArticles.length === 0 ? (
        <EmptyState message="Nenhuma orientação corresponde aos termos pesquisados." />
      ) : (
        <ul className="space-y-3">
          {filteredArticles.map((item) => (
            <KnowledgeCard key={item.articleId} item={item} />
          ))}
        </ul>
      )}
    </SectionCard>
  );
}

function KnowledgePage() {
  const auth = useAuth();
  const queryClient = useQueryClient();
  const municipalityId = auth.access?.municipalityId ?? "";
  const municipalityLabel = auth.access?.municipalityLabel ?? "Município não selecionado";
  const canManageReviewers = auth.access?.role === "municipal_admin";

  const operations = useQuery({
    queryKey: fiscalKeys.knowledgeOperations(municipalityId),
    queryFn: () => fiscalService.getKnowledgeOperationsSnapshot(municipalityId),
    enabled: Boolean(municipalityId),
  });
  const knowledge = useQuery({
    queryKey: fiscalKeys.knowledge(municipalityId),
    queryFn: () => fiscalService.listKnowledgeArticles(municipalityId),
    enabled:
      Boolean(municipalityId) &&
      operations.data?.verified === true &&
      operations.data.capabilities.canView === true,
  });
  const reviewerDirectory = useQuery({
    queryKey: fiscalKeys.knowledgeReviewers(municipalityId),
    queryFn: () => fiscalService.listKnowledgeReviewerCapabilities(municipalityId),
    enabled:
      Boolean(municipalityId) &&
      canManageReviewers &&
      operations.data?.verified === true &&
      operations.data.capabilities.canView === true,
    retry: false,
  });
  const reviewerUsers = useQuery({
    queryKey: fiscalKeys.municipalityUsers(municipalityId),
    queryFn: () => fiscalService.listMunicipalityUsers(municipalityId),
    enabled:
      Boolean(municipalityId) &&
      canManageReviewers &&
      operations.data?.verified === true &&
      operations.data.capabilities.canView === true,
    retry: false,
  });

  const action = useMutation({
    mutationFn: async (input: GovernanceAction) => {
      if (input.kind === "review-source") {
        return fiscalService.reviewLegalSourceChange(
          municipalityId,
          input.changeSetId,
          input.decision,
          input.notes,
          input.confirmation,
          input.metadata,
        );
      }
      if (input.kind === "publish-source") {
        return fiscalService.publishLegalSourceVersion(
          municipalityId,
          input.sourceVersionId,
          input.confirmation,
        );
      }
      if (input.kind === "review-article") {
        return fiscalService.reviewKnowledgeArticle(
          municipalityId,
          input.articleId,
          input.revisionId,
          input.decision,
          input.notes,
          input.confirmation,
        );
      }
      if (input.kind === "review-candidate") {
        return fiscalService.reviewKnowledgeCandidate(
          municipalityId,
          input.candidateId,
          input.decision,
          input.notes,
          input.confirmation,
        );
      }
      return fiscalService.publishKnowledgeArticle(
        municipalityId,
        input.articleId,
        input.confirmation,
      );
    },
    onSuccess: async (_result, input) => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: fiscalKeys.knowledgeOperations(municipalityId) }),
        queryClient.invalidateQueries({ queryKey: fiscalKeys.knowledge(municipalityId) }),
      ]);
      toast.success(input.kind.startsWith("review") ? "Revisão registrada" : "Conteúdo publicado", {
        description:
          "O estado foi recalculado pelo servidor e a trilha de governança foi preservada.",
      });
    },
    onError: (error) =>
      toast.error("A ação permaneceu bloqueada", {
        description: knowledgeActionErrorMessage(error),
      }),
  });
  const reviewerAction = useMutation({
    mutationFn: async (input: ReviewerAction) => {
      if (input.kind === "grant") {
        return fiscalService.grantKnowledgeReviewerCapability(
          municipalityId,
          input.staff.membershipId,
          input.validUntil,
          input.reason,
          input.confirmation,
        );
      }
      return fiscalService.revokeKnowledgeReviewerCapability(
        input.grant.grantId,
        input.reason,
        input.confirmation,
      );
    },
    onSuccess: async (_, input) => {
      await Promise.all([
        queryClient.invalidateQueries({
          queryKey: fiscalKeys.knowledgeOperations(municipalityId),
        }),
        queryClient.invalidateQueries({
          queryKey: fiscalKeys.knowledgeReviewers(municipalityId),
        }),
      ]);
      toast.success(
        input.kind === "grant" ? "Revisor jurídico designado" : "Capacidade de revisão revogada",
      );
    },
    onError: () => {
      toast.error("A configuração do revisor não foi alterada", {
        description:
          "Confirme autenticação em duas etapas, vínculo de administrador e os dados informados.",
      });
    },
  });

  async function reviewChange(
    change: KnowledgeSourceChange,
    decision: LegalSourceReviewDecision,
    notes: string,
    confirmation: string,
    metadata: LegalSourceReviewMetadata,
  ) {
    await action.mutateAsync({
      kind: "review-source",
      changeSetId: change.changeSetId,
      decision,
      notes,
      confirmation,
      metadata,
    });
  }

  async function publishChange(change: KnowledgeSourceChange, confirmation: string) {
    if (!change.candidateVersionId) throw new Error("candidate_version_missing");
    await action.mutateAsync({
      kind: "publish-source",
      sourceVersionId: change.candidateVersionId,
      confirmation,
    });
  }

  async function reviewSourceItem(
    item: KnowledgeReviewQueueItem,
    decision: LegalSourceReviewDecision,
    notes: string,
    confirmation: string,
    metadata: LegalSourceReviewMetadata,
  ) {
    if (!item.changeSetId) throw new Error("change_set_missing");
    await action.mutateAsync({
      kind: "review-source",
      changeSetId: item.changeSetId,
      decision,
      notes,
      confirmation,
      metadata,
    });
  }

  async function publishSourceItem(item: KnowledgeReviewQueueItem, confirmation: string) {
    if (!item.candidateVersionId) throw new Error("candidate_version_missing");
    await action.mutateAsync({
      kind: "publish-source",
      sourceVersionId: item.candidateVersionId,
      confirmation,
    });
  }

  async function reviewArticleItem(
    item: KnowledgeReviewQueueItem,
    decision: KnowledgeReviewDecision,
    notes: string,
    confirmation: string,
    _metadata: LegalSourceReviewMetadata,
  ) {
    if (confirmation !== "REVISAR" || !item.articleId || !item.revisionId) {
      throw new Error("review_confirmation_required");
    }
    await action.mutateAsync({
      kind: "review-article",
      articleId: item.articleId,
      revisionId: item.revisionId,
      decision,
      notes,
      confirmation,
    });
  }

  async function publishArticleItem(item: KnowledgeReviewQueueItem, confirmation: string) {
    if (!item.articleId) throw new Error("article_missing");
    await action.mutateAsync({
      kind: "publish-article",
      articleId: item.articleId,
      confirmation,
    });
  }

  async function reviewCandidateItem(
    item: KnowledgeReviewQueueItem,
    decision: KnowledgeCandidateReviewDecision,
    notes: string,
    confirmation: string,
  ) {
    if (confirmation !== "REVISAR CANDIDATO" || !item.candidateId) {
      throw new Error("candidate_review_confirmation_required");
    }
    await action.mutateAsync({
      kind: "review-candidate",
      candidateId: item.candidateId,
      decision,
      notes,
      confirmation,
    });
  }

  async function loadSourceEvidence(
    change: KnowledgeSourceChange,
    page?: KnowledgeSourceEvidencePageRequest,
  ) {
    return fiscalService.getLegalSourceChangeEvidence(municipalityId, change.changeSetId, page);
  }

  async function loadSourceItemEvidence(
    item: KnowledgeReviewQueueItem,
    page?: KnowledgeSourceEvidencePageRequest,
  ) {
    if (!item.changeSetId) throw new Error("change_set_missing");
    return fiscalService.getLegalSourceChangeEvidence(municipalityId, item.changeSetId, page);
  }

  async function loadArticleItemEvidence(item: KnowledgeReviewQueueItem) {
    if (!item.articleId || !item.revisionId) throw new Error("article_evidence_identifier_missing");
    return fiscalService.getKnowledgeArticleEvidence(
      municipalityId,
      item.articleId,
      item.revisionId,
    );
  }

  async function loadCandidateItemEvidence(item: KnowledgeReviewQueueItem) {
    if (!item.candidateId) throw new Error("candidate_evidence_identifier_missing");
    return fiscalService.getKnowledgeCandidateEvidence(municipalityId, item.candidateId);
  }

  const snapshot = operations.data;
  const pendingReviews = snapshot
    ? snapshot.summary.pendingSourceReviews +
      snapshot.summary.pendingArticleReviews +
      snapshot.summary.pendingCandidates
    : 0;
  const pendingGovernance = snapshot
    ? pendingReviews + snapshot.summary.pendingSourcePublications
    : 0;

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Segundo Cérebro</h1>
            <Badge variant="outline" className="border-primary/30 bg-primary-soft text-primary">
              <ShieldCheck className="mr-1 size-3.5" aria-hidden />
              Base fiscal governada
            </Badge>
          </div>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            Pergunte à legislação oficial, confira cada evidência e encaminhe melhorias para revisão
            humana. A base apoia a análise, mas não substitui a decisão da autoridade fiscal.
          </p>
        </div>
        <div className="rounded-md border border-border bg-card px-3 py-2 text-right shadow-sm">
          <p className="flex items-center justify-end gap-1.5 text-xs font-semibold">
            <MapPin className="size-3.5 text-primary" aria-hidden />
            {municipalityLabel}
          </p>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            Verificação: {safeDateTime(snapshot?.checkedAt)}
          </p>
        </div>
      </header>

      {operations.isLoading ? (
        <div className="surface-card p-4">
          <SectionSkeleton rows={3} />
        </div>
      ) : operations.isError || !snapshot?.verified || !snapshot.capabilities.canView ? (
        <section className="surface-card p-4" aria-label="Estado não verificado">
          <div className="mb-4 flex items-start gap-3 rounded-md border border-critical/40 bg-critical-soft p-4 text-critical">
            <AlertTriangle className="mt-0.5 size-5 shrink-0" aria-hidden />
            <div>
              <h2 className="font-semibold">Estado da base não verificado</h2>
              <p className="mt-1 text-sm">
                Por segurança, a biblioteca e as ações de governança permanecem indisponíveis até
                validar município, autenticação e permissões atuais.
              </p>
            </div>
          </div>
          <ErrorState
            message="Não foi possível verificar a operação do Segundo Cérebro."
            error={operations.error}
            onRetry={() => void operations.refetch()}
            retrying={operations.isFetching}
          />
        </section>
      ) : (
        <>
          <div
            className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5"
            aria-label="Resumo da base fiscal"
          >
            <KnowledgeMetric
              icon={<LibraryBig className="size-4" aria-hidden />}
              value={knowledge.isLoading ? null : (knowledge.data?.length ?? 0)}
              label="orientações publicadas"
              tone="success"
            />
            <KnowledgeMetric
              icon={<Files className="size-4" aria-hidden />}
              value={snapshot.summary.officialSources}
              label="fontes oficiais monitoradas"
            />
            <KnowledgeMetric
              icon={<FileClock className="size-4" aria-hidden />}
              value={pendingGovernance}
              label="revisões ou publicações pendentes"
              tone={pendingGovernance > 0 ? "warning" : "success"}
            />
            <KnowledgeMetric
              icon={<FileSearch className="size-4" aria-hidden />}
              value={snapshot.summary.pendingSourceExtractions}
              label="fontes aguardando extração integral"
              tone={snapshot.summary.pendingSourceExtractions > 0 ? "warning" : "success"}
            />
            <KnowledgeMetric
              icon={<DatabaseZap className="size-4" aria-hidden />}
              value={snapshot.summary.failedFetches24h}
              label="falhas de coleta em 24 horas"
              tone={snapshot.summary.failedFetches24h > 0 ? "critical" : "success"}
            />
          </div>

          {snapshot.health.blockers.length > 0 ? (
            <KnowledgeBlockers blockers={snapshot.health.blockers} />
          ) : null}

          <Tabs defaultValue="consultar" className="space-y-3">
            <div className="overflow-x-auto pb-1">
              <TabsList className="h-auto min-w-max justify-start">
                <TabsTrigger value="consultar" className="gap-2">
                  <Search className="size-4" aria-hidden />
                  Consultar
                </TabsTrigger>
                <TabsTrigger value="biblioteca" className="gap-2">
                  <LibraryBig className="size-4" aria-hidden />
                  Biblioteca
                </TabsTrigger>
                <TabsTrigger value="fontes" className="gap-2">
                  <Files className="size-4" aria-hidden />
                  Fontes oficiais
                </TabsTrigger>
                <TabsTrigger value="mudancas" className="gap-2">
                  <RefreshCw className="size-4" aria-hidden />
                  Mudanças
                  {snapshot.summary.openChanges > 0 ? (
                    <span className="rounded-full bg-warning-soft px-1.5 text-[10px] text-warning-foreground">
                      {snapshot.summary.openChanges}
                    </span>
                  ) : null}
                </TabsTrigger>
                <TabsTrigger value="revisoes" className="gap-2">
                  <BookOpenCheck className="size-4" aria-hidden />
                  Revisões
                  {pendingReviews > 0 ? (
                    <span className="rounded-full bg-warning-soft px-1.5 text-[10px] text-warning-foreground">
                      {pendingReviews}
                    </span>
                  ) : null}
                </TabsTrigger>
                <TabsTrigger value="saude" className="gap-2">
                  <HeartPulse className="size-4" aria-hidden />
                  Saúde
                </TabsTrigger>
              </TabsList>
            </div>

            <TabsContent value="consultar">
              <KnowledgeSearchPanel
                canSearch={snapshot.capabilities.canSearch}
                canSubmitCandidates={snapshot.capabilities.canSubmitCandidates}
                onSearch={(query) => fiscalService.searchLegalKnowledge(municipalityId, query)}
                onSubmitCandidate={async (input: KnowledgeCandidateInput) => {
                  const candidateId = await fiscalService.submitKnowledgeCandidate(
                    municipalityId,
                    input,
                  );
                  void queryClient.invalidateQueries({
                    queryKey: fiscalKeys.knowledgeOperations(municipalityId),
                  });
                  return candidateId;
                }}
              />
            </TabsContent>

            <TabsContent value="biblioteca">
              <KnowledgeLibrary
                articles={knowledge.data ?? []}
                loading={knowledge.isLoading}
                error={knowledge.error}
                retrying={knowledge.isFetching}
                onRetry={() => void knowledge.refetch()}
              />
            </TabsContent>

            <TabsContent value="fontes">
              <SectionCard
                title="Fontes oficiais monitoradas"
                description="Cada endereço, coleta e versão é isolado pelo município atual."
                action={
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge
                      variant="outline"
                      className={
                        snapshot.corpusIntegral
                          ? "border-success/40 bg-success-soft text-success"
                          : "border-warning/40 bg-warning-soft text-warning-foreground"
                      }
                    >
                      {snapshot.corpusIntegral
                        ? "Corpus integral verificado"
                        : snapshot.coverageLabel}
                    </Badge>
                    <span className="text-xs tabular-nums text-muted-foreground">
                      {snapshot.sources.length} fonte(s)
                    </span>
                  </div>
                }
              >
                <KnowledgeSourcesPanel sources={snapshot.sources} />
              </SectionCard>
            </TabsContent>

            <TabsContent value="mudancas">
              <SectionCard
                title="Mudanças detectadas"
                description="Alterações automáticas entram em revisão; nenhuma é publicada sozinha."
                action={
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {snapshot.changes.length} aberta(s)
                  </span>
                }
              >
                <KnowledgeChangesPanel
                  municipalityId={municipalityId}
                  changes={snapshot.changes}
                  pendingAction={action.isPending}
                  onLoadEvidence={loadSourceEvidence}
                  onReview={reviewChange}
                  onPublish={publishChange}
                />
              </SectionCard>
            </TabsContent>

            <TabsContent value="revisoes">
              <SectionCard
                title="Fila de revisão e publicação"
                description="O servidor revalida MFA, papel, vínculo municipal, citações, hash e vigência."
                action={
                  !snapshot.capabilities.canReviewArticles &&
                  !snapshot.capabilities.canReviewSourceVersions &&
                  !snapshot.capabilities.canReviewCandidates ? (
                    <Badge variant="outline">Somente leitura</Badge>
                  ) : null
                }
              >
                <KnowledgeReviewsPanel
                  municipalityId={municipalityId}
                  reviews={snapshot.reviews}
                  pendingAction={action.isPending}
                  onLoadSourceEvidence={loadSourceItemEvidence}
                  onLoadArticleEvidence={loadArticleItemEvidence}
                  onLoadCandidateEvidence={loadCandidateItemEvidence}
                  onReviewSource={reviewSourceItem}
                  onPublishSource={publishSourceItem}
                  onReviewArticle={reviewArticleItem}
                  onPublishArticle={publishArticleItem}
                  onReviewCandidate={reviewCandidateItem}
                />
              </SectionCard>
            </TabsContent>

            <TabsContent value="saude">
              <KnowledgeAutomationPanel
                schedule={snapshot.schedule}
                index={snapshot.index}
                ocr={snapshot.ocr}
                health={snapshot.health}
                reviewer={snapshot.reviewer}
                coverage={snapshot.coverage}
                coverageLabel={snapshot.coverageLabel}
                corpusIntegral={snapshot.corpusIntegral}
              />
              {canManageReviewers ? (
                <div className="mt-4">
                  <KnowledgeReviewerAdminPanel
                    directory={reviewerDirectory.data ?? null}
                    users={reviewerUsers.data ?? []}
                    currentMembershipId={auth.access?.membershipId ?? null}
                    loading={reviewerDirectory.isLoading || reviewerUsers.isLoading}
                    error={reviewerDirectory.error ?? reviewerUsers.error}
                    retrying={reviewerDirectory.isFetching || reviewerUsers.isFetching}
                    pending={reviewerAction.isPending}
                    onRetry={() => {
                      void reviewerDirectory.refetch();
                      void reviewerUsers.refetch();
                    }}
                    onGrant={async (staff, validUntil, reason, confirmation) => {
                      await reviewerAction.mutateAsync({
                        kind: "grant",
                        staff,
                        validUntil,
                        reason,
                        confirmation,
                      });
                    }}
                    onRevoke={async (grant, reason, confirmation) => {
                      await reviewerAction.mutateAsync({
                        kind: "revoke",
                        grant,
                        reason,
                        confirmation,
                      });
                    }}
                  />
                </div>
              ) : null}
            </TabsContent>
          </Tabs>
        </>
      )}
    </div>
  );
}
