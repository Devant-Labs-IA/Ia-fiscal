import {
  AlertTriangle,
  ArrowRight,
  BookCheck,
  ChevronLeft,
  ChevronRight,
  CircleSlash2,
  Clock3,
  ExternalLink,
  FileSearch,
  Link2,
  LockKeyhole,
  RefreshCw,
  Scale,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useState, type FormEvent, type ReactNode } from "react";

import { EmptyState, SectionCard } from "@/components/common/SectionCard";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import {
  knowledgeBlockerLabel,
  knowledgeChangeTypeLabel,
  knowledgeFailureLabel,
  knowledgeSourceTypeLabel,
  knowledgeStatusLabel,
} from "@/features/knowledge/knowledge-labels";
import type {
  KnowledgeArticleEvidence,
  KnowledgeCandidateEvidence,
  KnowledgeCandidateReviewDecision,
  KnowledgeCitationEvidence,
  KnowledgeHealthStatus,
  KnowledgeOfficialSource,
  KnowledgeReviewDecision,
  KnowledgeReviewQueueItem,
  KnowledgeSearchCitation,
  KnowledgeSourceChange,
  KnowledgeSourceChangeEvidence,
  KnowledgeSourceEvidencePageRequest,
  LegalSourceReviewDecision,
  LegalSourceReviewMetadata,
} from "@/features/knowledge/knowledge-models";
import { knowledgeDivergenceScopeLabel, knowledgeTaxScopeLabel } from "@/lib/fiscal-labels";
import { cn } from "@/lib/utils";

function safeDateTime(value: string | null): string {
  if (!value || Number.isNaN(Date.parse(value))) return "Não registrada";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}

function safeDate(value: string | null): string {
  if (!value) return "Não informada";

  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (dateOnly) return `${dateOnly[3]}/${dateOnly[2]}/${dateOnly[1]}`;
  if (Number.isNaN(Date.parse(value))) return "Não informada";

  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}

function currentDateInSaoPaulo(): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function safeOfficialUrl(value: string | null): string | null {
  if (!value) return null;
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" ? parsed.href : null;
  } catch {
    return null;
  }
}

function statusTone(status: string): string {
  if (
    [
      "accepted",
      "active",
      "approved",
      "available",
      "collected",
      "completed_changed",
      "completed_unchanged",
      "healthy",
      "published",
      "success",
    ].includes(status)
  ) {
    return "border-success/40 bg-success-soft text-success";
  }
  if (["blocked", "error", "failed", "rejected", "revoked", "unavailable"].includes(status)) {
    return "border-critical/40 bg-critical-soft text-critical";
  }
  if (
    [
      "changed",
      "changes_requested",
      "attention",
      "attention_required",
      "paused",
      "pending",
      "pending_review",
      "stale",
      "under_review",
      "warning",
    ].includes(status)
  ) {
    return "border-warning/50 bg-warning-soft text-warning-foreground";
  }
  return "border-border bg-muted text-muted-foreground";
}

export function KnowledgeStateBadge({ status, label }: { status: string | null; label?: string }) {
  const normalized = status || "unknown";
  return (
    <Badge variant="outline" className={cn("font-medium", statusTone(normalized))}>
      {label ? `${label}: ` : ""}
      {knowledgeStatusLabel(normalized)}
    </Badge>
  );
}

export function KnowledgeBlockers({ blockers }: { blockers: string[] }) {
  const unique = [...new Set(blockers)];
  if (unique.length === 0) return null;
  return (
    <div className="rounded-md border border-warning/40 bg-warning-soft/60 p-3" role="status">
      <p className="flex items-center gap-2 text-xs font-semibold text-warning-foreground">
        <LockKeyhole className="size-3.5" aria-hidden />
        Pendência operacional
      </p>
      <ul className="mt-1.5 space-y-1 text-xs text-warning-foreground/90">
        {unique.map((blocker) => (
          <li key={blocker} className="flex gap-2">
            <span aria-hidden>•</span>
            <span>{knowledgeBlockerLabel(blocker)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function MetadataItem({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        {label}
      </dt>
      <dd className="mt-0.5 text-sm text-foreground">{children}</dd>
    </div>
  );
}

type ReviewDecision = KnowledgeReviewDecision | LegalSourceReviewDecision;

function citationHasVerifiableOrigin(citation: KnowledgeCitationEvidence): boolean {
  return Boolean(
    citation.isValid &&
    citation.blockers.length === 0 &&
    citation.quotedExcerpt.trim() &&
    safeOfficialUrl(citation.officialUrl),
  );
}

function articleEvidenceReady(evidence: KnowledgeArticleEvidence | null): boolean {
  return Boolean(
    evidence?.verified &&
    evidence.evidenceComplete &&
    evidence.answerBody.trim() &&
    Array.from(evidence.answerBody).length === evidence.answerLength &&
    evidence.citationCount > 0 &&
    evidence.citations.length === evidence.citationCount &&
    evidence.citations.every(citationHasVerifiableOrigin),
  );
}

function sourceEvidenceReady(evidence: KnowledgeSourceChangeEvidence | null): boolean {
  if (!evidence) return false;
  const expectedContentLength = Math.min(
    evidence.contentLimit,
    Math.max(evidence.contentTotalChars - evidence.contentOffset, 0),
  );
  const expectedSectionLength = Math.min(
    evidence.sectionLimit,
    Math.max(evidence.sectionTotal - evidence.sectionOffset, 0),
  );
  const expectedChangeItemLength = Math.min(
    evidence.changeItemLimit,
    Math.max(evidence.changeItemTotal - evidence.changeItemOffset, 0),
  );
  return Boolean(
    evidence.verified &&
    evidence.evidenceComplete &&
    safeOfficialUrl(evidence.officialUrl) &&
    safeOfficialUrl(evidence.capturedUrl) &&
    evidence.rawContentSha256 &&
    evidence.rawContentSha256 === evidence.toSha256 &&
    evidence.contentSha256 &&
    evidence.diffSha256 &&
    evidence.artifactId &&
    evidence.artifactMimeType &&
    evidence.artifactByteSize != null &&
    evidence.observedAt &&
    !Number.isNaN(Date.parse(evidence.observedAt)) &&
    evidence.diffSummary.trim() &&
    evidence.contentTotalChars > 0 &&
    Array.from(evidence.contentText).length === expectedContentLength &&
    evidence.sectionTotal > 0 &&
    evidence.sections.length === expectedSectionLength &&
    evidence.changeItemTotal > 0 &&
    evidence.changeItems.length === expectedChangeItemLength &&
    evidence.changeItemsFullSha256.trim(),
  );
}

export function KnowledgeCitationList({
  citations,
  heading = "Fundamentação oficial",
}: {
  citations: KnowledgeCitationEvidence[];
  heading?: string;
}) {
  return (
    <section className="mt-4" aria-label={heading}>
      <h4 className="text-sm font-semibold">{heading}</h4>
      {citations.length === 0 ? (
        <p className="mt-2 rounded-md border border-critical/30 bg-critical-soft p-3 text-xs text-critical">
          Nenhuma citação oficial verificável foi apresentada.
        </p>
      ) : (
        <ul className="mt-2 space-y-3">
          {citations.map((citation) => {
            const officialUrl = safeOfficialUrl(citation.officialUrl);
            const valid = citationHasVerifiableOrigin(citation);
            return (
              <li
                key={citation.citationId}
                className={cn(
                  "rounded-md border p-3",
                  valid ? "border-border bg-background" : "border-critical/30 bg-critical-soft/50",
                )}
              >
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <p className="text-sm font-semibold">{citation.sourceTitle}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {citation.officialIdentifier ?? "Identificação oficial não cadastrada"}
                    </p>
                  </div>
                  {officialUrl ? (
                    <Button asChild size="sm" variant="outline">
                      <a href={officialUrl} target="_blank" rel="noreferrer">
                        Conferir no portal oficial
                        <ExternalLink aria-hidden />
                      </a>
                    </Button>
                  ) : (
                    <Badge variant="outline" className="border-critical/30 text-critical">
                      Origem indisponível
                    </Badge>
                  )}
                </div>
                <p className="mt-3 text-xs font-medium">{citation.citationLabel}</p>
                <blockquote className="mt-1 whitespace-pre-wrap border-l-2 border-primary/40 pl-3 text-xs leading-relaxed text-muted-foreground">
                  {citation.quotedExcerpt}
                </blockquote>
                <dl className="mt-3 grid gap-2 border-t border-border pt-2 sm:grid-cols-3">
                  <MetadataItem label="Dispositivo">
                    {citation.sectionHeading ?? citation.citationLabel}
                  </MetadataItem>
                  <MetadataItem label="Publicação">
                    {safeDate(citation.publicationDate)}
                  </MetadataItem>
                  <MetadataItem label="Vigência">
                    <KnowledgeValidity
                      validFrom={citation.validFrom}
                      validUntil={citation.validUntil}
                    />
                  </MetadataItem>
                </dl>
                {!valid ? (
                  <div className="mt-3">
                    <KnowledgeBlockers
                      blockers={
                        citation.blockers.length > 0 ? citation.blockers : ["unverified_state"]
                      }
                    />
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function ArticleReviewEvidencePanel({ evidence }: { evidence: KnowledgeArticleEvidence }) {
  return (
    <section
      className="rounded-md border border-primary/25 bg-primary-soft/40 p-3"
      aria-labelledby="evidencia-artigo-titulo"
    >
      <h3 id="evidencia-artigo-titulo" className="text-sm font-semibold">
        Resposta integral e fundamentação
      </h3>
      <p className="mt-1 text-xs text-muted-foreground">
        Confira a resposta completa e cada dispositivo oficial antes de registrar sua decisão.
      </p>
      <div
        className="mt-3 max-h-64 overflow-y-auto whitespace-pre-wrap rounded border border-border bg-background p-3 text-sm leading-relaxed outline-none focus-visible:ring-2 focus-visible:ring-ring"
        role="region"
        aria-label="Resposta integral do artigo para revisão"
        tabIndex={0}
      >
        {evidence.answerBody}
      </div>
      <KnowledgeCitationList citations={evidence.citations} />
      {!evidence.evidenceComplete || evidence.blockers.length > 0 ? (
        <div className="mt-3">
          <KnowledgeBlockers
            blockers={evidence.blockers.length > 0 ? evidence.blockers : ["unverified_state"]}
          />
        </div>
      ) : null}
    </section>
  );
}

function SourceReviewEvidencePanel({
  evidence,
  loading,
  onPageChange,
}: {
  evidence: KnowledgeSourceChangeEvidence;
  loading: boolean;
  onPageChange(page: KnowledgeSourceEvidencePageRequest): void;
}) {
  const officialUrl = safeOfficialUrl(evidence.officialUrl);
  const capturedUrl = safeOfficialUrl(evidence.capturedUrl);
  const requestedUrl = safeOfficialUrl(evidence.requestedUrl);
  const contentLength = Array.from(evidence.contentText).length;
  const contentStart = evidence.contentTotalChars > 0 ? evidence.contentOffset + 1 : 0;
  const contentEnd = evidence.contentOffset + contentLength;
  const sectionStart = evidence.sectionTotal > 0 ? evidence.sectionOffset + 1 : 0;
  const sectionEnd = evidence.sectionOffset + evidence.sections.length;
  const changeItemStart = evidence.changeItemTotal > 0 ? evidence.changeItemOffset + 1 : 0;
  const changeItemEnd = evidence.changeItemOffset + evidence.changeItems.length;
  const currentPage: KnowledgeSourceEvidencePageRequest = {
    contentOffset: evidence.contentOffset,
    sectionOffset: evidence.sectionOffset,
    changeItemOffset: evidence.changeItemOffset,
  };
  return (
    <section
      className="rounded-md border border-primary/25 bg-primary-soft/40 p-3"
      aria-labelledby="evidencia-fonte-titulo"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 id="evidencia-fonte-titulo" className="text-sm font-semibold">
            Evidência oficial paginada e íntegra
          </h3>
          <p className="mt-1 text-xs text-muted-foreground">
            Navegue pelo conteúdo sem carregá-lo inteiro. A aprovação revalida no servidor o hash e
            a completude do conjunto oficial.
          </p>
        </div>
        {officialUrl ? (
          <Button asChild size="sm" variant="outline">
            <a href={officialUrl} target="_blank" rel="noreferrer">
              Abrir origem oficial
              <ExternalLink aria-hidden />
            </a>
          </Button>
        ) : null}
      </div>

      <div className="mt-3 rounded border border-border bg-background p-3">
        <p className="text-xs font-semibold">Resumo da mudança</p>
        <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{evidence.diffSummary}</p>
      </div>

      <dl className="mt-3 grid gap-3 rounded border border-border bg-background p-3 sm:grid-cols-2">
        <MetadataItem label="Documento oficial">
          {evidence.officialIdentifier ?? evidence.sourceTitle}
        </MetadataItem>
        <MetadataItem label="Tipo de mudança">
          {knowledgeChangeTypeLabel(evidence.changeType)}
        </MetadataItem>
        <MetadataItem label="Endereço efetivamente capturado">
          {capturedUrl ? (
            <a
              href={capturedUrl}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 break-all text-primary underline-offset-4 hover:underline"
            >
              {capturedUrl}
              <ExternalLink className="size-3.5 shrink-0" aria-hidden />
            </a>
          ) : (
            "Captura oficial não verificada"
          )}
        </MetadataItem>
        <MetadataItem label="Endereço solicitado na coleta">
          {requestedUrl ? (
            <a
              href={requestedUrl}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 break-all text-primary underline-offset-4 hover:underline"
            >
              {requestedUrl}
              <ExternalLink className="size-3.5 shrink-0" aria-hidden />
            </a>
          ) : (
            "Endereço solicitado não registrado"
          )}
        </MetadataItem>
        <MetadataItem label="Capturado em">{safeDateTime(evidence.observedAt)}</MetadataItem>
        <MetadataItem label="Arquivo capturado">
          {evidence.artifactMimeType ?? "Formato não verificado"}
          {evidence.artifactByteSize == null
            ? ""
            : ` · ${evidence.artifactByteSize.toLocaleString("pt-BR")} byte(s)`}
        </MetadataItem>
        <MetadataItem label="Registro do artefato">
          <code className="break-all text-[11px]">
            {evidence.artifactId ?? "Identificador indisponível"}
          </code>
        </MetadataItem>
        <MetadataItem label="Integridade do arquivo bruto">
          <code className="break-all text-[11px]">
            {evidence.rawContentSha256 ?? "Hash bruto indisponível"}
          </code>
        </MetadataItem>
        <MetadataItem label="Integridade do texto extraído">
          <code className="break-all text-[11px]">{evidence.contentSha256}</code>
        </MetadataItem>
        <MetadataItem label="Integridade do comparativo">
          <code className="break-all text-[11px]">{evidence.diffSha256}</code>
        </MetadataItem>
      </dl>

      {evidence.changeItems.length > 0 ? (
        <div className="mt-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs font-semibold">
              Itens alterados · {changeItemStart.toLocaleString("pt-BR")}–
              {changeItemEnd.toLocaleString("pt-BR")} de{" "}
              {evidence.changeItemTotal.toLocaleString("pt-BR")}
            </p>
            <div className="flex gap-2">
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={loading || evidence.changeItemOffset === 0}
                onClick={() =>
                  onPageChange({
                    ...currentPage,
                    changeItemOffset: Math.max(
                      0,
                      evidence.changeItemOffset - evidence.changeItemLimit,
                    ),
                  })
                }
              >
                <ChevronLeft aria-hidden />
                Itens anteriores
              </Button>
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={loading || !evidence.changeItemsHasMore}
                onClick={() =>
                  onPageChange({
                    ...currentPage,
                    changeItemOffset: evidence.changeItemOffset + evidence.changeItemLimit,
                  })
                }
              >
                Próximos itens
                <ChevronRight aria-hidden />
              </Button>
            </div>
          </div>
          <ul className="mt-2 space-y-2">
            {evidence.changeItems.map((item, index) => (
              <li
                key={`${item.itemKind}:${item.itemPath}:${index}`}
                className="rounded border border-border bg-background p-3 text-xs"
              >
                <p className="font-medium">{item.summary}</p>
                {item.beforeExcerpt ? (
                  <p className="mt-2 whitespace-pre-wrap text-muted-foreground">
                    <strong>Antes:</strong> {item.beforeExcerpt}
                  </p>
                ) : null}
                {item.afterExcerpt ? (
                  <p className="mt-2 whitespace-pre-wrap text-muted-foreground">
                    <strong>Depois:</strong> {item.afterExcerpt}
                  </p>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className="mt-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-xs font-semibold">
            Conteúdo extraído · caracteres {contentStart.toLocaleString("pt-BR")}–
            {contentEnd.toLocaleString("pt-BR")} de{" "}
            {evidence.contentTotalChars.toLocaleString("pt-BR")}
          </p>
          <div className="flex gap-2">
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={loading || evidence.contentOffset === 0}
              onClick={() =>
                onPageChange({
                  ...currentPage,
                  contentOffset: Math.max(0, evidence.contentOffset - evidence.contentLimit),
                })
              }
            >
              <ChevronLeft aria-hidden />
              Trecho anterior
            </Button>
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={loading || !evidence.contentHasMore}
              onClick={() =>
                onPageChange({
                  ...currentPage,
                  contentOffset: evidence.contentOffset + evidence.contentLimit,
                })
              }
            >
              Próximo trecho
              <ChevronRight aria-hidden />
            </Button>
          </div>
        </div>
        <div
          className="mt-2 max-h-72 overflow-y-auto whitespace-pre-wrap rounded border border-border bg-background p-3 text-xs leading-relaxed outline-none focus-visible:ring-2 focus-visible:ring-ring"
          role="region"
          aria-label="Trecho integral da fonte oficial para revisão"
          tabIndex={0}
        >
          {evidence.contentText}
        </div>
      </div>

      <div className="mt-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-xs font-semibold">
            Seções conferíveis · {sectionStart.toLocaleString("pt-BR")}–
            {sectionEnd.toLocaleString("pt-BR")} de {evidence.sectionTotal.toLocaleString("pt-BR")}
          </p>
          <div className="flex gap-2">
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={loading || evidence.sectionOffset === 0}
              onClick={() =>
                onPageChange({
                  ...currentPage,
                  sectionOffset: Math.max(0, evidence.sectionOffset - evidence.sectionLimit),
                })
              }
            >
              <ChevronLeft aria-hidden />
              Seções anteriores
            </Button>
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={loading || !evidence.sectionHasMore}
              onClick={() =>
                onPageChange({
                  ...currentPage,
                  sectionOffset: evidence.sectionOffset + evidence.sectionLimit,
                })
              }
            >
              Próximas seções
              <ChevronRight aria-hidden />
            </Button>
          </div>
        </div>
        <ul className="mt-2 space-y-2">
          {evidence.sections.map((section) => (
            <li key={section.sectionId}>
              <details className="rounded border border-border bg-background">
                <summary className="cursor-pointer px-3 py-2 text-xs font-medium">
                  {section.ordinal}. {section.heading ?? "Seção sem título"}
                </summary>
                <div className="border-t border-border px-3 py-3">
                  <p className="whitespace-pre-wrap text-xs leading-relaxed text-muted-foreground">
                    {section.contentPreview}
                  </p>
                  {section.contentTotalChars > Array.from(section.contentPreview).length ? (
                    <p className="mt-2 text-[11px] font-medium text-warning-foreground">
                      Prévia limitada a 2.000 caracteres; consulte a íntegra navegando pelas páginas
                      do conteúdo extraído.
                    </p>
                  ) : null}
                </div>
              </details>
            </li>
          ))}
        </ul>
      </div>

      <dl className="mt-3 grid gap-2 text-xs sm:grid-cols-2">
        <MetadataItem label="Versão candidata">
          Versão {evidence.candidateVersionNumber}
        </MetadataItem>
        <MetadataItem label="Vigência informada">
          <KnowledgeValidity validFrom={evidence.validFrom} validUntil={evidence.validUntil} />
        </MetadataItem>
      </dl>

      {!evidence.evidenceComplete ||
      evidence.blockers.length > 0 ||
      !officialUrl ||
      !capturedUrl ||
      !evidence.rawContentSha256 ? (
        <div className="mt-3">
          <KnowledgeBlockers
            blockers={evidence.blockers.length > 0 ? evidence.blockers : ["unverified_state"]}
          />
        </div>
      ) : null}
    </section>
  );
}

function candidateCitationReady(citation: KnowledgeSearchCitation): boolean {
  const today = currentDateInSaoPaulo();
  return Boolean(
    citation.isValid &&
    citation.blockers.length === 0 &&
    citation.quotedExcerpt.trim() &&
    safeOfficialUrl(citation.officialUrl) &&
    citation.publicationDate &&
    citation.publicationDate <= today &&
    citation.validFrom &&
    citation.validFrom <= today &&
    (!citation.validUntil || citation.validUntil >= today),
  );
}

function candidateEvidenceComplete(evidence: KnowledgeCandidateEvidence | null): boolean {
  return Boolean(
    evidence?.verified &&
    evidence.evidenceComplete &&
    !evidence.canPublish &&
    evidence.question.trim() &&
    evidence.proposedAnswer.trim() &&
    evidence.contentSha256.trim() &&
    evidence.citations.length > 0 &&
    evidence.citations.every(candidateCitationReady),
  );
}

function candidateApprovalReady(evidence: KnowledgeCandidateEvidence | null): boolean {
  return Boolean(candidateEvidenceComplete(evidence) && evidence?.canReview);
}

function CandidateEvidencePanel({ evidence }: { evidence: KnowledgeCandidateEvidence }) {
  return (
    <section
      className="rounded-md border border-primary/25 bg-primary-soft/40 p-3"
      aria-labelledby="evidencia-candidato-titulo"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 id="evidencia-candidato-titulo" className="text-sm font-semibold">
            Proposta e fundamentação integral
          </h3>
          <p className="mt-1 text-xs text-muted-foreground">
            A aprovação registra um sinal supervisionado. Ela não publica a resposta nem altera a
            base canônica automaticamente.
          </p>
        </div>
        <Badge
          variant="outline"
          className="border-warning/40 bg-warning-soft text-warning-foreground"
        >
          <Sparkles aria-hidden />
          Candidato não publicado
        </Badge>
      </div>

      <div className="mt-3 rounded border border-border bg-background p-3">
        <p className="text-xs font-medium text-muted-foreground">Pergunta</p>
        <p className="mt-1 text-sm font-semibold">{evidence.question}</p>
      </div>
      <div
        className="mt-3 max-h-64 overflow-y-auto whitespace-pre-wrap rounded border border-border bg-background p-3 text-sm leading-relaxed outline-none focus-visible:ring-2 focus-visible:ring-ring"
        role="region"
        aria-label="Resposta proposta do candidato para revisão"
        tabIndex={0}
      >
        {evidence.proposedAnswer}
      </div>

      <section className="mt-4" aria-label="Evidências oficiais do candidato">
        <h4 className="text-sm font-semibold">Dispositivos indicados</h4>
        {evidence.citations.length === 0 ? (
          <p className="mt-2 rounded-md border border-critical/30 bg-critical-soft p-3 text-xs text-critical">
            Nenhum dispositivo oficial foi vinculado à proposta.
          </p>
        ) : (
          <ol className="mt-2 space-y-2">
            {evidence.citations.map((citation, index) => {
              const officialUrl = safeOfficialUrl(citation.officialUrl);
              const ready = candidateCitationReady(citation);
              return (
                <li
                  key={citation.citationId}
                  className={cn(
                    "rounded border p-3",
                    ready
                      ? "border-border bg-background"
                      : "border-critical/30 bg-critical-soft/50",
                  )}
                >
                  <div className="flex items-start gap-3">
                    <span
                      className="grid size-6 shrink-0 place-items-center rounded-full bg-primary-soft text-xs font-semibold text-primary"
                      aria-hidden
                    >
                      {index + 1}
                    </span>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-start justify-between gap-2">
                        <div>
                          <p className="text-xs font-semibold">{citation.sourceTitle}</p>
                          <p className="mt-0.5 text-[11px] text-muted-foreground">
                            {citation.officialIdentifier ?? "Identificação oficial não informada"} ·{" "}
                            {citation.sectionHeading ?? citation.citationLabel}
                          </p>
                        </div>
                        {officialUrl ? (
                          <Button asChild size="sm" variant="outline">
                            <a href={officialUrl} target="_blank" rel="noreferrer">
                              Conferir origem
                              <ExternalLink aria-hidden />
                            </a>
                          </Button>
                        ) : null}
                      </div>
                      <blockquote className="mt-2 border-l-2 border-primary/40 pl-3 text-xs leading-relaxed text-muted-foreground">
                        {citation.quotedExcerpt}
                      </blockquote>
                      <p className="mt-2 text-[11px] text-muted-foreground">
                        Vigência:{" "}
                        <KnowledgeValidity
                          validFrom={citation.validFrom}
                          validUntil={citation.validUntil}
                        />
                      </p>
                      {!ready ? (
                        <div className="mt-2">
                          <KnowledgeBlockers
                            blockers={
                              citation.blockers.length > 0
                                ? citation.blockers
                                : ["unverified_state"]
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
        )}
      </section>

      <dl className="mt-3 grid gap-2 border-t border-border pt-3 text-xs sm:grid-cols-2">
        <MetadataItem label="Enviado para revisão">
          {safeDateTime(evidence.submittedAt)}
        </MetadataItem>
        <MetadataItem label="Evidência conferida em">
          {safeDateTime(evidence.checkedAt)}
        </MetadataItem>
      </dl>

      {!candidateEvidenceComplete(evidence) || evidence.blockers.length > 0 ? (
        <div className="mt-3">
          <KnowledgeBlockers
            blockers={evidence.blockers.length > 0 ? evidence.blockers : ["unverified_state"]}
          />
        </div>
      ) : null}
    </section>
  );
}

interface CandidateReviewDialogProps {
  item: KnowledgeReviewQueueItem;
  evidenceQueryKey: readonly unknown[];
  loadEvidence(): Promise<KnowledgeCandidateEvidence>;
  pending: boolean;
  onConfirm(
    decision: KnowledgeCandidateReviewDecision,
    notes: string,
    confirmation: string,
  ): Promise<void>;
}

function CandidateReviewDialog({
  item,
  evidenceQueryKey,
  loadEvidence,
  pending,
  onConfirm,
}: CandidateReviewDialogProps) {
  const [open, setOpen] = useState(false);
  const [decision, setDecision] = useState<KnowledgeCandidateReviewDecision>("approved");
  const [notes, setNotes] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const evidence = useQuery({
    queryKey: evidenceQueryKey,
    queryFn: loadEvidence,
    enabled: open,
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: false,
  });
  const approvalReady = candidateApprovalReady(evidence.data ?? null);
  const rejectionReady = notes.trim().length >= 10;
  const valid =
    confirmation === "REVISAR CANDIDATO" &&
    (decision === "approved" ? approvalReady : rejectionReady);

  function resetState() {
    setNotes("");
    setConfirmation("");
    setDecision("approved");
  }

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) resetState();
    setOpen(nextOpen);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || pending) return;
    try {
      await onConfirm(decision, notes.trim(), confirmation);
    } catch {
      return;
    }
    handleOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button type="button" size="sm" variant="outline">
          <Sparkles aria-hidden />
          Revisar candidato
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-4xl">
        <form onSubmit={submit} className="space-y-4">
          <DialogHeader>
            <DialogTitle>Revisar candidato de conhecimento</DialogTitle>
            <DialogDescription>
              Confira a proposta integral e os dispositivos oficiais. Aprovar significa validar o
              sinal supervisionado; não significa publicar uma orientação.
            </DialogDescription>
          </DialogHeader>

          {evidence.isLoading ? (
            <div className="py-8 text-center text-sm text-muted-foreground" role="status">
              Carregando proposta e evidências oficiais…
            </div>
          ) : evidence.isError || !evidence.data ? (
            <div
              className="rounded-md border border-critical/35 bg-critical-soft p-4 text-sm text-critical"
              role="alert"
            >
              A evidência integral não pôde ser verificada. A aprovação permanece bloqueada; ainda é
              possível rejeitar a proposta com justificativa.
            </div>
          ) : (
            <CandidateEvidencePanel evidence={evidence.data} />
          )}

          <div className="space-y-2">
            <Label htmlFor={`decisao-candidato-${item.itemId}`}>Decisão</Label>
            <Select
              value={decision}
              onValueChange={(value) => setDecision(value as KnowledgeCandidateReviewDecision)}
            >
              <SelectTrigger id={`decisao-candidato-${item.itemId}`}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="approved">Aprovar como sinal supervisionado</SelectItem>
                <SelectItem value="rejected">Rejeitar proposta</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor={`observacoes-candidato-${item.itemId}`}>
              Fundamentação da decisão {decision === "rejected" ? "(obrigatória)" : "(opcional)"}
            </Label>
            <Textarea
              id={`observacoes-candidato-${item.itemId}`}
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              maxLength={4_000}
              className="min-h-24"
              placeholder="Registre o motivo da aprovação ou os problemas que justificam a rejeição."
            />
            {decision === "rejected" && !rejectionReady ? (
              <p className="text-xs text-muted-foreground">
                Informe pelo menos 10 caracteres para rejeitar.
              </p>
            ) : null}
          </div>

          <div className="rounded-md border border-warning/40 bg-warning-soft/60 p-3">
            <Label htmlFor={`confirmacao-candidato-revisao-${item.itemId}`}>
              Digite REVISAR CANDIDATO para confirmar
            </Label>
            <Input
              id={`confirmacao-candidato-revisao-${item.itemId}`}
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
              onClick={() => handleOpenChange(false)}
              disabled={pending}
            >
              Cancelar
            </Button>
            <Button type="submit" disabled={!valid || pending}>
              {pending ? "Registrando revisão…" : "Registrar revisão supervisionada"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function CandidateEvidenceDialog({
  item,
  evidenceQueryKey,
  loadEvidence,
}: Pick<CandidateReviewDialogProps, "item" | "evidenceQueryKey" | "loadEvidence">) {
  const [open, setOpen] = useState(false);
  const evidence = useQuery({
    queryKey: evidenceQueryKey,
    queryFn: loadEvidence,
    enabled: open,
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: false,
  });
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button type="button" size="sm" variant="outline">
          <FileSearch aria-hidden />
          Ver proposta
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-4xl">
        <DialogHeader>
          <DialogTitle>Proposta candidata</DialogTitle>
          <DialogDescription>
            “{item.title}” permanece não canônica e não publicada. A consulta abaixo não concede
            poder de revisão.
          </DialogDescription>
        </DialogHeader>
        {evidence.isLoading ? (
          <div className="py-8 text-center text-sm text-muted-foreground" role="status">
            Carregando proposta e evidências oficiais…
          </div>
        ) : evidence.isError || !evidence.data ? (
          <div
            className="rounded-md border border-critical/35 bg-critical-soft p-4 text-sm text-critical"
            role="alert"
          >
            A proposta integral não pôde ser verificada.
          </div>
        ) : (
          <CandidateEvidencePanel evidence={evidence.data} />
        )}
      </DialogContent>
    </Dialog>
  );
}

interface GovernedReviewDialogProps {
  kind: "source" | "article";
  itemTitle: string;
  evidenceQueryKey: readonly unknown[];
  loadEvidence(
    page?: KnowledgeSourceEvidencePageRequest,
  ): Promise<KnowledgeArticleEvidence | KnowledgeSourceChangeEvidence>;
  pending: boolean;
  onConfirm(
    decision: ReviewDecision,
    notes: string,
    confirmation: string,
    metadata: LegalSourceReviewMetadata,
  ): Promise<void>;
}

interface GovernedEvidenceDialogProps {
  kind: "source" | "article";
  itemTitle: string;
  evidenceQueryKey: readonly unknown[];
  loadEvidence(
    page?: KnowledgeSourceEvidencePageRequest,
  ): Promise<KnowledgeArticleEvidence | KnowledgeSourceChangeEvidence>;
}

function initialSourceEvidencePage(): KnowledgeSourceEvidencePageRequest {
  return { contentOffset: 0, sectionOffset: 0, changeItemOffset: 0 };
}

function GovernedEvidenceDialog({
  kind,
  itemTitle,
  evidenceQueryKey,
  loadEvidence,
}: GovernedEvidenceDialogProps) {
  const [open, setOpen] = useState(false);
  const [page, setPage] = useState<KnowledgeSourceEvidencePageRequest>(initialSourceEvidencePage);
  const evidence = useQuery({
    queryKey:
      kind === "source"
        ? [...evidenceQueryKey, page.contentOffset, page.sectionOffset, page.changeItemOffset]
        : evidenceQueryKey,
    queryFn: () => loadEvidence(kind === "source" ? page : undefined),
    enabled: open,
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: false,
    placeholderData: (previousData) => previousData,
  });
  const articleEvidence =
    kind === "article" && evidence.data ? (evidence.data as KnowledgeArticleEvidence) : null;
  const sourceEvidence =
    kind === "source" && evidence.data ? (evidence.data as KnowledgeSourceChangeEvidence) : null;

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) setPage(initialSourceEvidencePage());
    setOpen(nextOpen);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button type="button" size="sm" variant="outline">
          <FileSearch aria-hidden />
          Ver evidências
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Evidências do conteúdo</DialogTitle>
          <DialogDescription>
            Confira a origem oficial e o conteúdo registrado para “{itemTitle}”. Esta consulta não
            registra uma decisão.
          </DialogDescription>
        </DialogHeader>

        {evidence.isPending || evidence.isFetching ? (
          <div className="rounded-md border border-border bg-muted/30 p-4" role="status">
            <p className="flex items-center gap-2 text-sm font-medium">
              <RefreshCw className="size-4 animate-spin motion-reduce:animate-none" aria-hidden />
              Carregando e verificando as evidências…
            </p>
          </div>
        ) : evidence.isError ? (
          <div className="rounded-md border border-critical/40 bg-critical-soft p-4 text-critical">
            <p className="flex items-start gap-2 text-sm font-medium" role="alert">
              <ShieldAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
              Não foi possível verificar as evidências neste momento.
            </p>
            <Button
              type="button"
              size="sm"
              variant="outline"
              className="mt-3 bg-background text-foreground"
              onClick={() => void evidence.refetch()}
            >
              Tentar carregar novamente
            </Button>
          </div>
        ) : articleEvidence ? (
          <ArticleReviewEvidencePanel evidence={articleEvidence} />
        ) : sourceEvidence ? (
          <SourceReviewEvidencePanel
            evidence={sourceEvidence}
            loading={evidence.isFetching}
            onPageChange={setPage}
          />
        ) : (
          <p className="rounded-md border border-critical/40 bg-critical-soft p-4 text-sm text-critical">
            Estado da evidência não verificado.
          </p>
        )}

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
            Fechar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function GovernedReviewDialog({
  kind,
  itemTitle,
  evidenceQueryKey,
  loadEvidence,
  pending,
  onConfirm,
}: GovernedReviewDialogProps) {
  const [open, setOpen] = useState(false);
  const [page, setPage] = useState<KnowledgeSourceEvidencePageRequest>(initialSourceEvidencePage);
  const [decision, setDecision] = useState<ReviewDecision>("approved");
  const [notes, setNotes] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [publicationDate, setPublicationDate] = useState("");
  const [validFrom, setValidFrom] = useState("");
  const [validUntil, setValidUntil] = useState("");
  const evidence = useQuery({
    queryKey:
      kind === "source"
        ? [...evidenceQueryKey, page.contentOffset, page.sectionOffset, page.changeItemOffset]
        : evidenceQueryKey,
    queryFn: () => loadEvidence(kind === "source" ? page : undefined),
    enabled: open,
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: false,
    placeholderData: (previousData) => previousData,
  });
  const notesRequired = decision !== "approved";
  const today = currentDateInSaoPaulo();
  const invalidValidity = Boolean(validFrom && validUntil && validUntil < validFrom);
  const sourceApprovalDatesValid =
    kind !== "source" ||
    decision !== "approved" ||
    Boolean(
      publicationDate &&
      publicationDate <= today &&
      validFrom &&
      validFrom <= today &&
      (!validUntil || validUntil >= today),
    );
  const articleEvidence =
    kind === "article" && evidence.data ? (evidence.data as KnowledgeArticleEvidence) : null;
  const sourceEvidence =
    kind === "source" && evidence.data ? (evidence.data as KnowledgeSourceChangeEvidence) : null;
  const hasVisibleEvidence =
    evidence.isSuccess &&
    !evidence.isError &&
    !evidence.isFetching &&
    (kind === "article"
      ? articleEvidenceReady(articleEvidence)
      : sourceEvidenceReady(sourceEvidence));
  const valid =
    confirmation === "REVISAR" &&
    (!notesRequired || notes.trim().length >= 10) &&
    !invalidValidity &&
    sourceApprovalDatesValid &&
    (decision !== "approved" || hasVisibleEvidence);

  function resetState() {
    setNotes("");
    setConfirmation("");
    setPublicationDate("");
    setValidFrom("");
    setValidUntil("");
    setDecision("approved");
    setPage(initialSourceEvidencePage());
  }

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) resetState();
    setOpen(nextOpen);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || pending) return;
    try {
      await onConfirm(decision, notes, confirmation, {
        publicationDate: publicationDate || null,
        validFrom: validFrom || null,
        validUntil: validUntil || null,
      });
    } catch {
      return;
    }
    handleOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button type="button" size="sm" variant="outline">
          <FileSearch aria-hidden />
          Revisar
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <form onSubmit={submit} className="space-y-4">
          <DialogHeader>
            <DialogTitle>Registrar revisão governada</DialogTitle>
            <DialogDescription>
              A decisão ficará vinculada ao conteúdo atual de “{itemTitle}”. Alterações posteriores
              exigirão uma nova revisão.
            </DialogDescription>
          </DialogHeader>

          {evidence.isPending || evidence.isFetching ? (
            <div
              className="rounded-md border border-border bg-muted/30 p-4"
              role="status"
              aria-live="polite"
            >
              <p className="flex items-center gap-2 text-sm font-medium">
                <RefreshCw className="size-4 animate-spin motion-reduce:animate-none" aria-hidden />
                Carregando a página da evidência e verificando sua integridade…
              </p>
            </div>
          ) : evidence.isError ? (
            <div
              className="rounded-md border border-critical/40 bg-critical-soft p-4 text-critical"
              role="alert"
            >
              <p className="flex items-start gap-2 text-sm font-medium">
                <ShieldAlert className="mt-0.5 size-4 shrink-0" aria-hidden />A evidência detalhada
                não pôde ser verificada. A aprovação permanece bloqueada; rejeitar ou solicitar
                ajustes continua disponível com justificativa.
              </p>
              <Button
                type="button"
                size="sm"
                variant="outline"
                className="mt-3 bg-background text-foreground"
                onClick={() => void evidence.refetch()}
              >
                Tentar carregar novamente
              </Button>
            </div>
          ) : articleEvidence ? (
            <ArticleReviewEvidencePanel evidence={articleEvidence} />
          ) : sourceEvidence ? (
            <SourceReviewEvidencePanel
              evidence={sourceEvidence}
              loading={evidence.isFetching}
              onPageChange={setPage}
            />
          ) : (
            <p className="rounded-md border border-critical/40 bg-critical-soft p-4 text-sm text-critical">
              Estado da evidência não verificado. A aprovação permanece bloqueada.
            </p>
          )}

          {!evidence.isPending && !evidence.isFetching && !hasVisibleEvidence ? (
            <p className="flex gap-2 text-xs font-medium text-critical" role="alert">
              <ShieldAlert className="size-4 shrink-0" aria-hidden />A aprovação está indisponível
              enquanto a integridade da evidência não puder ser comprovada. Ainda é possível
              rejeitar ou solicitar ajustes com justificativa.
            </p>
          ) : null}

          <div className="space-y-2">
            <Label htmlFor={`decisao-${kind}`}>Decisão</Label>
            <Select
              value={decision}
              onValueChange={(value) => setDecision(value as ReviewDecision)}
            >
              <SelectTrigger id={`decisao-${kind}`}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="approved">Aprovar conteúdo atual</SelectItem>
                <SelectItem value={kind === "source" ? "changes_requested" : "revision_requested"}>
                  Solicitar ajustes
                </SelectItem>
                <SelectItem value="rejected">Rejeitar conteúdo</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {kind === "source" ? (
            <fieldset className="rounded-md border border-border p-3">
              <legend className="px-1 text-sm font-medium">Datas da versão oficial</legend>
              <div className="mt-1 grid gap-3 sm:grid-cols-3">
                <div className="space-y-1.5">
                  <Label htmlFor="data-publicacao-fonte">Publicação</Label>
                  <Input
                    id="data-publicacao-fonte"
                    type="date"
                    max={today}
                    required={decision === "approved"}
                    value={publicationDate}
                    onChange={(event) => setPublicationDate(event.target.value)}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="inicio-vigencia-fonte">Início da vigência</Label>
                  <Input
                    id="inicio-vigencia-fonte"
                    type="date"
                    max={today}
                    required={decision === "approved"}
                    value={validFrom}
                    onChange={(event) => setValidFrom(event.target.value)}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="fim-vigencia-fonte">Fim da vigência</Label>
                  <Input
                    id="fim-vigencia-fonte"
                    type="date"
                    value={validUntil}
                    min={validFrom > today ? validFrom : today}
                    onChange={(event) => setValidUntil(event.target.value)}
                  />
                </div>
              </div>
              <p className="mt-2 text-xs text-muted-foreground">
                Para aprovar, informe publicação e início de vigência até hoje. Se houver fim de
                vigência, ele precisa ser igual ou posterior a hoje.
              </p>
              {decision === "approved" && !sourceApprovalDatesValid ? (
                <p className="mt-1 text-xs text-critical" role="alert">
                  Complete datas vigentes para concluir a aprovação.
                </p>
              ) : null}
              {invalidValidity ? (
                <p className="mt-1 text-xs text-critical" role="alert">
                  O fim da vigência não pode ser anterior ao início.
                </p>
              ) : null}
            </fieldset>
          ) : null}

          <div className="space-y-2">
            <Label htmlFor={`observacoes-${kind}`}>
              Observações {notesRequired ? "(obrigatórias)" : "(opcionais)"}
            </Label>
            <Textarea
              id={`observacoes-${kind}`}
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              maxLength={4_000}
              placeholder="Registre o fundamento da decisão e os ajustes necessários."
              className="min-h-24"
            />
            {notesRequired && notes.trim().length < 10 ? (
              <p className="text-xs text-muted-foreground">
                Informe pelo menos 10 caracteres para justificar a decisão.
              </p>
            ) : null}
          </div>

          <div className="rounded-md border border-warning/40 bg-warning-soft/60 p-3">
            <Label htmlFor={`confirmacao-${kind}`}>Digite REVISAR para confirmar</Label>
            <Input
              id={`confirmacao-${kind}`}
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
              onClick={() => handleOpenChange(false)}
              disabled={pending}
            >
              Cancelar
            </Button>
            <Button type="submit" disabled={!valid || pending}>
              {pending ? "Registrando…" : "Confirmar revisão"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

interface GovernedPublishDialogProps {
  subject: string;
  pending: boolean;
  onConfirm(confirmation: string): Promise<void>;
}

function GovernedPublishDialog({ subject, pending, onConfirm }: GovernedPublishDialogProps) {
  const [open, setOpen] = useState(false);
  const [confirmation, setConfirmation] = useState("");
  const valid = confirmation === "PUBLICAR";

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) setConfirmation("");
    setOpen(nextOpen);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || pending) return;
    try {
      await onConfirm(confirmation);
    } catch {
      return;
    }
    handleOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button type="button" size="sm">
          <BookCheck aria-hidden />
          Publicar
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="space-y-4">
          <DialogHeader>
            <DialogTitle>Confirmar publicação?</DialogTitle>
            <DialogDescription>
              “{subject}” poderá fundamentar consultas do Segundo Cérebro. A autorização será
              revalidada pelo servidor antes da publicação.
            </DialogDescription>
          </DialogHeader>
          <div className="rounded-md border border-critical/30 bg-critical-soft/60 p-3">
            <Label htmlFor="confirmacao-publicacao">Digite PUBLICAR para confirmar</Label>
            <Input
              id="confirmacao-publicacao"
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
              onClick={() => handleOpenChange(false)}
              disabled={pending}
            >
              Cancelar
            </Button>
            <Button type="submit" disabled={!valid || pending}>
              {pending ? "Publicando…" : "Publicar conteúdo"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function KnowledgeSourcesPanel({ sources }: { sources: KnowledgeOfficialSource[] }) {
  if (sources.length === 0) {
    return <EmptyState message="Nenhuma fonte oficial foi cadastrada para este município." />;
  }
  return (
    <ul className="space-y-3">
      {sources.map((source) => {
        const officialUrl = safeOfficialUrl(source.officialUrl);
        const failure = source.lastErrorCode ?? source.lastErrorDetail;
        return (
          <li key={source.sourceId} className="rounded-lg border border-border bg-card p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="secondary">{knowledgeSourceTypeLabel(source.sourceType)}</Badge>
                  <KnowledgeStateBadge status={source.status} label="Fonte" />
                  <KnowledgeStateBadge status={source.endpointStatus} label="Endereço" />
                  <KnowledgeStateBadge status={source.lastFetchStatus} label="Coleta" />
                </div>
                <h3 className="mt-2 text-base font-semibold">{source.title}</h3>
                <p className="mt-0.5 text-sm text-muted-foreground">
                  {source.officialIdentifier ?? "Identificação oficial não cadastrada"}
                </p>
              </div>
              {officialUrl ? (
                <Button asChild size="sm" variant="outline">
                  <a href={officialUrl} target="_blank" rel="noreferrer">
                    Abrir origem oficial
                    <ExternalLink aria-hidden />
                  </a>
                </Button>
              ) : (
                <Badge variant="outline" className="border-warning/40 bg-warning-soft">
                  Origem não verificada
                </Badge>
              )}
            </div>

            <dl className="mt-4 grid gap-3 border-t border-border pt-3 sm:grid-cols-2 lg:grid-cols-4">
              <MetadataItem label="Tributo">{knowledgeTaxScopeLabel(source.taxScope)}</MetadataItem>
              <MetadataItem label="Versão mais recente">
                {source.latestVersionNumber
                  ? `Versão ${source.latestVersionNumber}`
                  : "Não publicada"}
              </MetadataItem>
              <MetadataItem label="Situação da versão">
                {knowledgeStatusLabel(source.latestVersionStatus)}
              </MetadataItem>
              <MetadataItem label="Vigência">
                <KnowledgeValidity
                  validFrom={source.latestValidFrom}
                  validUntil={source.latestValidUntil}
                />
              </MetadataItem>
              <MetadataItem label="Última coleta">
                {safeDateTime(source.lastCheckedAt)}
              </MetadataItem>
              <MetadataItem label="Última mudança detectada">
                {safeDateTime(source.lastChangeDetectedAt)}
              </MetadataItem>
            </dl>

            {failure ? (
              <p className="mt-3 flex gap-2 rounded-md border border-critical/30 bg-critical-soft p-3 text-xs text-critical">
                <ShieldAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
                <span>
                  <strong>Falha registrada:</strong> {knowledgeFailureLabel(failure)}
                </span>
              </p>
            ) : null}
            <div className="mt-3">
              <KnowledgeBlockers blockers={source.blockers} />
            </div>
          </li>
        );
      })}
    </ul>
  );
}

interface KnowledgeChangesPanelProps {
  municipalityId: string;
  changes: KnowledgeSourceChange[];
  pendingAction: boolean;
  onLoadEvidence(
    change: KnowledgeSourceChange,
    page?: KnowledgeSourceEvidencePageRequest,
  ): Promise<KnowledgeSourceChangeEvidence>;
  onReview(
    change: KnowledgeSourceChange,
    decision: LegalSourceReviewDecision,
    notes: string,
    confirmation: string,
    metadata: LegalSourceReviewMetadata,
  ): Promise<void>;
  onPublish(change: KnowledgeSourceChange, confirmation: string): Promise<void>;
}

export function KnowledgeChangesPanel({
  municipalityId,
  changes,
  pendingAction,
  onLoadEvidence,
  onReview,
  onPublish,
}: KnowledgeChangesPanelProps) {
  if (changes.length === 0) {
    return <EmptyState message="Nenhuma mudança oficial aguarda tratamento." />;
  }
  return (
    <ul className="space-y-3">
      {changes.map((change) => (
        <li key={change.changeSetId} className="rounded-lg border border-border bg-card p-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="secondary">{knowledgeChangeTypeLabel(change.changeType)}</Badge>
                <KnowledgeStateBadge status={change.status} />
              </div>
              <h3 className="mt-2 text-base font-semibold">{change.sourceTitle}</h3>
              <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
                {change.diffSummary || "A comparação detalhada ainda não está disponível."}
              </p>
              {safeOfficialUrl(change.officialUrl) ? (
                <a
                  href={safeOfficialUrl(change.officialUrl) ?? undefined}
                  target="_blank"
                  rel="noreferrer"
                  className="mt-2 inline-flex items-center gap-1.5 text-xs font-medium text-primary underline-offset-4 hover:underline"
                >
                  Abrir origem oficial
                  <ExternalLink className="size-3.5" aria-hidden />
                </a>
              ) : null}
            </div>
            <div className="flex flex-wrap gap-2">
              {change.canReview ? (
                <GovernedReviewDialog
                  kind="source"
                  itemTitle={change.sourceTitle}
                  evidenceQueryKey={[
                    "knowledge-review-evidence",
                    municipalityId,
                    "source",
                    change.changeSetId,
                  ]}
                  loadEvidence={(page) => onLoadEvidence(change, page)}
                  pending={pendingAction}
                  onConfirm={(decision, notes, confirmation, metadata) =>
                    onReview(
                      change,
                      decision as LegalSourceReviewDecision,
                      notes,
                      confirmation,
                      metadata,
                    )
                  }
                />
              ) : change.candidateVersionId ? (
                <GovernedEvidenceDialog
                  kind="source"
                  itemTitle={change.sourceTitle}
                  evidenceQueryKey={[
                    "knowledge-review-evidence",
                    municipalityId,
                    "source",
                    change.changeSetId,
                  ]}
                  loadEvidence={(page) => onLoadEvidence(change, page)}
                />
              ) : null}
              {change.canPublish && change.candidateVersionId ? (
                <GovernedPublishDialog
                  subject={`${change.sourceTitle}, versão ${change.candidateVersionNumber ?? "atual"}`}
                  pending={pendingAction}
                  onConfirm={(confirmation) => onPublish(change, confirmation)}
                />
              ) : null}
            </div>
          </div>

          <dl className="mt-4 grid gap-3 border-t border-border pt-3 sm:grid-cols-2 lg:grid-cols-4">
            <MetadataItem label="Detectada em">{safeDateTime(change.detectedAt)}</MetadataItem>
            <MetadataItem label="Versão candidata">
              {change.candidateVersionNumber
                ? `Versão ${change.candidateVersionNumber}`
                : "Não gerada"}
            </MetadataItem>
            <MetadataItem label="Situação da candidata">
              {knowledgeStatusLabel(change.candidateVersionStatus)}
            </MetadataItem>
            <MetadataItem label="Vigência candidata">
              <KnowledgeValidity
                validFrom={change.candidateValidFrom}
                validUntil={change.candidateValidUntil}
              />
            </MetadataItem>
          </dl>
          {change.candidateContentPreview ? (
            <details className="mt-3 rounded-md border border-border bg-muted/30">
              <summary className="cursor-pointer px-3 py-2 text-xs font-medium">
                Conferir trecho coletado
              </summary>
              <p className="whitespace-pre-wrap border-t border-border px-3 py-3 text-xs leading-relaxed text-muted-foreground">
                {change.candidateContentPreview}
              </p>
            </details>
          ) : null}
          <div className="mt-3">
            <KnowledgeBlockers blockers={change.blockers} />
          </div>
        </li>
      ))}
    </ul>
  );
}

interface KnowledgeReviewsPanelProps {
  municipalityId: string;
  reviews: KnowledgeReviewQueueItem[];
  pendingAction: boolean;
  onLoadSourceEvidence(
    item: KnowledgeReviewQueueItem,
    page?: KnowledgeSourceEvidencePageRequest,
  ): Promise<KnowledgeSourceChangeEvidence>;
  onLoadArticleEvidence(item: KnowledgeReviewQueueItem): Promise<KnowledgeArticleEvidence>;
  onLoadCandidateEvidence(item: KnowledgeReviewQueueItem): Promise<KnowledgeCandidateEvidence>;
  onReviewSource(
    item: KnowledgeReviewQueueItem,
    decision: LegalSourceReviewDecision,
    notes: string,
    confirmation: string,
    metadata: LegalSourceReviewMetadata,
  ): Promise<void>;
  onPublishSource(item: KnowledgeReviewQueueItem, confirmation: string): Promise<void>;
  onReviewArticle(
    item: KnowledgeReviewQueueItem,
    decision: KnowledgeReviewDecision,
    notes: string,
    confirmation: string,
    metadata: LegalSourceReviewMetadata,
  ): Promise<void>;
  onPublishArticle(item: KnowledgeReviewQueueItem, confirmation: string): Promise<void>;
  onReviewCandidate(
    item: KnowledgeReviewQueueItem,
    decision: KnowledgeCandidateReviewDecision,
    notes: string,
    confirmation: string,
  ): Promise<void>;
}

export function KnowledgeReviewsPanel({
  municipalityId,
  reviews,
  pendingAction,
  onLoadSourceEvidence,
  onLoadArticleEvidence,
  onLoadCandidateEvidence,
  onReviewSource,
  onPublishSource,
  onReviewArticle,
  onPublishArticle,
  onReviewCandidate,
}: KnowledgeReviewsPanelProps) {
  if (reviews.length === 0) {
    return <EmptyState message="Nenhum conteúdo aguarda revisão ou publicação." />;
  }
  return (
    <ul className="space-y-3">
      {reviews.map((item) => {
        const isArticle = item.queueKind === "knowledge_article";
        const isCandidate = item.queueKind === "learning_candidate";
        const preview = item.proposedAnswerPreview ?? item.answerPreview;
        return (
          <li
            key={`${item.queueKind}:${item.itemId}`}
            className="rounded-lg border border-border bg-card p-4"
          >
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="secondary">
                    {isCandidate
                      ? "Candidato de aprendizado"
                      : isArticle
                        ? "Orientação fiscal"
                        : "Versão de fonte oficial"}
                  </Badge>
                  <KnowledgeStateBadge status={item.status} />
                  {item.isTest ? (
                    <Badge variant="outline" className="border-warning/40 bg-warning-soft">
                      Conteúdo de teste
                    </Badge>
                  ) : null}
                </div>
                <h3 className="mt-2 text-base font-semibold">{item.title}</h3>
                {preview ? (
                  <p className="mt-2 max-w-4xl whitespace-pre-wrap text-sm leading-relaxed text-muted-foreground">
                    {preview}
                  </p>
                ) : null}
                {!isArticle && !isCandidate && safeOfficialUrl(item.officialUrl) ? (
                  <a
                    href={safeOfficialUrl(item.officialUrl) ?? undefined}
                    target="_blank"
                    rel="noreferrer"
                    className="mt-2 inline-flex items-center gap-1.5 text-xs font-medium text-primary underline-offset-4 hover:underline"
                  >
                    Abrir origem oficial
                    <ExternalLink className="size-3.5" aria-hidden />
                  </a>
                ) : null}
              </div>
              <div className="flex flex-wrap gap-2">
                {isCandidate && item.canReview ? (
                  <CandidateReviewDialog
                    item={item}
                    evidenceQueryKey={[
                      "knowledge-review-evidence",
                      municipalityId,
                      "candidate",
                      item.candidateId,
                    ]}
                    loadEvidence={() => onLoadCandidateEvidence(item)}
                    pending={pendingAction}
                    onConfirm={(decision, notes, confirmation) =>
                      onReviewCandidate(item, decision, notes, confirmation)
                    }
                  />
                ) : isCandidate ? (
                  <CandidateEvidenceDialog
                    item={item}
                    evidenceQueryKey={[
                      "knowledge-review-evidence",
                      municipalityId,
                      "candidate",
                      item.candidateId,
                    ]}
                    loadEvidence={() => onLoadCandidateEvidence(item)}
                  />
                ) : item.canReview ? (
                  <GovernedReviewDialog
                    kind={isArticle ? "article" : "source"}
                    itemTitle={item.title}
                    evidenceQueryKey={[
                      "knowledge-review-evidence",
                      municipalityId,
                      isArticle ? "article" : "source",
                      item.itemId,
                      item.revisionId,
                    ]}
                    loadEvidence={(page) =>
                      isArticle ? onLoadArticleEvidence(item) : onLoadSourceEvidence(item, page)
                    }
                    pending={pendingAction}
                    onConfirm={(decision, notes, confirmation, metadata) =>
                      isArticle
                        ? onReviewArticle(
                            item,
                            decision as KnowledgeReviewDecision,
                            notes,
                            confirmation,
                            metadata,
                          )
                        : onReviewSource(
                            item,
                            decision as LegalSourceReviewDecision,
                            notes,
                            confirmation,
                            metadata,
                          )
                    }
                  />
                ) : (isArticle && item.articleId && item.revisionId) ||
                  (!isArticle && item.changeSetId && item.candidateVersionId) ? (
                  <GovernedEvidenceDialog
                    kind={isArticle ? "article" : "source"}
                    itemTitle={item.title}
                    evidenceQueryKey={[
                      "knowledge-review-evidence",
                      municipalityId,
                      isArticle ? "article" : "source",
                      item.itemId,
                      item.revisionId,
                    ]}
                    loadEvidence={(page) =>
                      isArticle ? onLoadArticleEvidence(item) : onLoadSourceEvidence(item, page)
                    }
                  />
                ) : null}
                {!isCandidate && item.canPublish ? (
                  <GovernedPublishDialog
                    subject={item.title}
                    pending={pendingAction}
                    onConfirm={(confirmation) =>
                      isArticle
                        ? onPublishArticle(item, confirmation)
                        : onPublishSource(item, confirmation)
                    }
                  />
                ) : null}
              </div>
            </div>

            <dl className="mt-4 grid gap-3 border-t border-border pt-3 sm:grid-cols-2 lg:grid-cols-5">
              <MetadataItem label="Enviado para revisão">
                {safeDateTime(item.submittedAt)}
              </MetadataItem>
              <MetadataItem label="Última decisão">
                {safeDateTime(item.lastReviewedAt)}
              </MetadataItem>
              <MetadataItem label="Revisão">
                {isCandidate
                  ? "Sinal supervisionado"
                  : item.revisionNumber
                    ? `Revisão ${item.revisionNumber}`
                    : "Não se aplica"}
              </MetadataItem>
              <MetadataItem label="Citações oficiais">
                {item.citationCount == null
                  ? "Não se aplica"
                  : item.citationCount.toLocaleString("pt-BR")}
              </MetadataItem>
              <MetadataItem label="Vigência">
                <KnowledgeValidity validFrom={item.validFrom} validUntil={item.validUntil} />
              </MetadataItem>
            </dl>
            {isCandidate ? (
              <div className="mt-3 rounded-md border border-warning/35 bg-warning-soft/50 p-3 text-xs text-warning-foreground">
                Mesmo após aprovação, este candidato não será publicado nem usado como resposta
                canônica automaticamente.
              </div>
            ) : isArticle ? (
              <div className="mt-3 flex flex-wrap gap-2">
                {item.taxScope ? (
                  <Badge variant="outline">{knowledgeTaxScopeLabel(item.taxScope)}</Badge>
                ) : null}
                {item.divergenceScope ? (
                  <Badge variant="outline">
                    {knowledgeDivergenceScopeLabel(item.divergenceScope)}
                  </Badge>
                ) : null}
              </div>
            ) : null}
            <div className="mt-3">
              <KnowledgeBlockers blockers={item.blockers} />
            </div>
          </li>
        );
      })}
    </ul>
  );
}

function HealthMetric({ icon, value, label }: { icon: ReactNode; value: string; label: string }) {
  return (
    <div className="rounded-md border border-border bg-muted/30 p-3">
      <div className="flex items-center gap-2 text-muted-foreground">
        {icon}
        <span className="text-xs font-medium">{label}</span>
      </div>
      <p className="mt-2 text-lg font-semibold tabular-nums">{value}</p>
    </div>
  );
}

export function KnowledgeHealthPanel({ health }: { health: KnowledgeHealthStatus }) {
  const healthy = health.status === "healthy";
  const blocked = health.status === "blocked";
  return (
    <div className="space-y-4">
      <div
        className={cn(
          "rounded-lg border p-4",
          healthy
            ? "border-success/40 bg-success-soft/60"
            : blocked
              ? "border-critical/40 bg-critical-soft/60"
              : "border-warning/40 bg-warning-soft/60",
        )}
      >
        <div className="flex items-start gap-3">
          {healthy ? (
            <ShieldCheck className="mt-0.5 size-5 text-success" aria-hidden />
          ) : blocked ? (
            <CircleSlash2 className="mt-0.5 size-5 text-critical" aria-hidden />
          ) : (
            <AlertTriangle className="mt-0.5 size-5 text-warning-foreground" aria-hidden />
          )}
          <div>
            <h3 className="font-semibold">
              {healthy
                ? "Base verificada e operacional"
                : blocked
                  ? "Base bloqueada para publicação"
                  : "Base requer atenção antes de publicar"}
            </h3>
            <p className="mt-1 text-sm text-muted-foreground">
              A consulta continua em modo seguro. Conteúdo sem fonte vigente, revisão ou coleta
              válida não é liberado como conhecimento reutilizável.
            </p>
          </div>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <HealthMetric
          icon={<Clock3 className="size-4" aria-hidden />}
          value={health.staleSources.toLocaleString("pt-BR")}
          label="fontes desatualizadas"
        />
        <HealthMetric
          icon={<ShieldAlert className="size-4" aria-hidden />}
          value={health.failedSources.toLocaleString("pt-BR")}
          label="fontes com falha"
        />
        <HealthMetric
          icon={<LockKeyhole className="size-4" aria-hidden />}
          value={health.blockedSources.toLocaleString("pt-BR")}
          label="fontes bloqueadas"
        />
        <HealthMetric
          icon={<RefreshCw className="size-4" aria-hidden />}
          value={safeDateTime(health.lastSuccessfulFetchAt)}
          label="última coleta concluída"
        />
      </div>

      <KnowledgeBlockers blockers={health.blockers} />

      <SectionCard
        title="Cadeia de confiança"
        description="Cada etapa precisa estar concluída para o conteúdo apoiar uma resposta fiscal."
      >
        <ol className="grid gap-3 text-sm lg:grid-cols-4 lg:gap-8">
          {[
            { icon: Link2, title: "Origem oficial", detail: "Portal público identificado" },
            { icon: RefreshCw, title: "Coleta íntegra", detail: "Versão e mudança registradas" },
            { icon: Scale, title: "Revisão humana", detail: "Conteúdo e vigência conferidos" },
            { icon: BookCheck, title: "Publicação", detail: "Disponível com citação" },
          ].map((step, index) => (
            <li key={step.title} className="relative">
              <div className="h-full rounded-md border border-border bg-muted/30 p-3">
                <step.icon className="size-4 text-primary" aria-hidden />
                <p className="mt-2 font-medium">{step.title}</p>
                <p className="mt-0.5 text-xs text-muted-foreground">{step.detail}</p>
              </div>
              {index < 3 ? (
                <ArrowRight
                  className="absolute -right-6 top-1/2 hidden size-4 -translate-y-1/2 text-muted-foreground lg:block"
                  aria-hidden
                />
              ) : null}
            </li>
          ))}
        </ol>
      </SectionCard>
    </div>
  );
}

export function KnowledgeValidity({
  validFrom,
  validUntil,
}: {
  validFrom: string | null;
  validUntil: string | null;
}) {
  if (!validFrom) return <span>Vigência não informada</span>;

  return (
    <span>
      {safeDate(validFrom)} a {validUntil ? safeDate(validUntil) : "prazo indeterminado"}
    </span>
  );
}
