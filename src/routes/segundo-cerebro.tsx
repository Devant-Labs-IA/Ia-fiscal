import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { BookOpenCheck, FlaskConical, LibraryBig, Search, ShieldCheck } from "lucide-react";

import {
  EmptyState,
  ErrorState,
  SectionCard,
  SectionSkeleton,
} from "@/components/common/SectionCard";
import { HomologationBanner } from "@/components/layout/HomologationBanner";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { formatDate } from "@/lib/format";
import { fiscalKeys, fiscalService } from "@/services/fiscal-service";
import type { KnowledgeArticleReadModel } from "@/types/read-models";

export const Route = createFileRoute("/segundo-cerebro")({
  head: () => ({
    meta: [
      { title: "Segundo Cérebro — IA Fiscal" },
      {
        name: "description",
        content:
          "Consulta à base de conhecimento tributário governada, versionada e disponível ao município.",
      },
      { property: "og:title", content: "Segundo Cérebro — IA Fiscal" },
      {
        property: "og:description",
        content:
          "Consulta à base de conhecimento tributário governada, versionada e disponível ao município.",
      },
    ],
  }),
  component: KnowledgePage,
});

function readableToken(value: string): string {
  if (!value) return "Não informado";
  return value.replaceAll("_", " ").replace(/^./, (letter) => letter.toUpperCase());
}

function safeDate(value: string | null): string {
  if (!value || Number.isNaN(Date.parse(value))) return "Não informada";
  return formatDate(value);
}

function KnowledgeCard({ item }: { item: KnowledgeArticleReadModel }) {
  return (
    <li className="rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="secondary">{readableToken(item.taxScope)}</Badge>
            <Badge variant="outline">{readableToken(item.divergenceScope)}</Badge>
            {item.isTest && (
              <Badge
                variant="outline"
                className="border-warning/50 bg-warning-soft text-warning-foreground"
              >
                <FlaskConical className="mr-1 size-3.5" aria-hidden />
                Conteúdo de teste
              </Badge>
            )}
          </div>
          <h3 className="mt-3 text-base font-semibold">{item.canonicalQuestion}</h3>
          <p className="mt-1 text-xs text-muted-foreground">
            Intenção: {readableToken(item.intentKey)}
          </p>
        </div>

        <span className="rounded-md bg-primary-soft px-2.5 py-1 text-xs font-semibold text-primary">
          versão {item.semanticVersion}
        </span>
      </div>

      <details className="mt-4 rounded-md border border-border bg-muted/40">
        <summary className="cursor-pointer px-3 py-2.5 text-sm font-medium">
          Consultar resposta governada
        </summary>
        <div className="border-t border-border px-3 py-3">
          <p className="whitespace-pre-wrap text-sm leading-relaxed">{item.answerBody}</p>
        </div>
      </details>

      <dl className="mt-4 grid gap-3 text-xs text-muted-foreground sm:grid-cols-3">
        <div>
          <dt className="font-medium text-foreground">Publicação</dt>
          <dd className="mt-0.5 tabular-nums">{safeDate(item.publishedAt)}</dd>
        </div>
        <div>
          <dt className="font-medium text-foreground">Válido a partir de</dt>
          <dd className="mt-0.5 tabular-nums">{safeDate(item.validFrom)}</dd>
        </div>
        <div>
          <dt className="font-medium text-foreground">Válido até</dt>
          <dd className="mt-0.5 tabular-nums">
            {item.validUntil ? safeDate(item.validUntil) : "Sem término cadastrado"}
          </dd>
        </div>
      </dl>
    </li>
  );
}

function KnowledgePage() {
  const [search, setSearch] = useState("");
  const knowledge = useQuery({
    queryKey: fiscalKeys.knowledge,
    queryFn: () => fiscalService.listKnowledgeArticles(),
  });

  const articles = useMemo(() => knowledge.data ?? [], [knowledge.data]);
  const filteredArticles = useMemo(() => {
    const normalized = search.trim().toLocaleLowerCase("pt-BR");
    if (!normalized) return articles;
    return articles.filter((item) =>
      [
        item.canonicalQuestion,
        item.intentKey,
        item.taxScope,
        item.divergenceScope,
        item.answerBody,
      ].some((value) => value.toLocaleLowerCase("pt-BR").includes(normalized)),
    );
  }, [articles, search]);

  const publishedCount = articles.filter((item) => Boolean(item.publishedAt)).length;

  return (
    <div className="space-y-5 py-4">
      <HomologationBanner />

      <header>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Segundo Cérebro</h1>
          <Badge variant="outline" className="border-primary/30 bg-primary-soft text-primary">
            <ShieldCheck className="mr-1 size-3.5" aria-hidden />
            Conhecimento governado
          </Badge>
        </div>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Base versionada para consulta e apoio à revisão. O conteúdo não substitui a análise da
          autoridade fiscal nem produz lançamento, ciência ou prazo.
        </p>
      </header>

      <div className="grid gap-3 sm:grid-cols-2" aria-label="Resumo da base de conhecimento">
        <div className="surface-card flex items-center gap-4 p-4">
          <span className="grid size-10 shrink-0 place-items-center rounded-md bg-primary-soft text-primary">
            <LibraryBig className="size-5" aria-hidden />
          </span>
          <div>
            <p className="text-2xl font-semibold tabular-nums">
              {knowledge.isLoading ? "—" : articles.length}
            </p>
            <p className="text-xs text-muted-foreground">artigos reutilizáveis visíveis</p>
          </div>
        </div>
        <div className="surface-card flex items-center gap-4 p-4">
          <span className="grid size-10 shrink-0 place-items-center rounded-md bg-success-soft text-success">
            <BookOpenCheck className="size-5" aria-hidden />
          </span>
          <div>
            <p className="text-2xl font-semibold tabular-nums">
              {knowledge.isLoading ? "—" : publishedCount}
            </p>
            <p className="text-xs text-muted-foreground">com publicação registrada</p>
          </div>
        </div>
      </div>

      <SectionCard
        title="Biblioteca tributária"
        description="A pesquisa abaixo é local e não dispara IA, jobs ou consultas externas."
        action={
          <span className="hidden text-xs tabular-nums text-muted-foreground sm:inline">
            {filteredArticles.length} resultado(s)
          </span>
        }
      >
        <label htmlFor="busca-conhecimento" className="sr-only">
          Buscar na base de conhecimento
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

        {knowledge.isError ? (
          <ErrorState message="Não foi possível carregar a base de conhecimento." />
        ) : knowledge.isLoading ? (
          <SectionSkeleton rows={4} />
        ) : articles.length === 0 ? (
          <EmptyState message="Nenhum artigo governado está disponível para consulta." />
        ) : filteredArticles.length === 0 ? (
          <EmptyState message="Nenhum artigo corresponde aos termos pesquisados." />
        ) : (
          <ul className="space-y-3">
            {filteredArticles.map((item) => (
              <KnowledgeCard key={item.articleId} item={item} />
            ))}
          </ul>
        )}
      </SectionCard>
    </div>
  );
}
