// @vitest-environment jsdom

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act } from "react";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { KnowledgeOperationsSnapshot } from "@/features/knowledge/knowledge-models";
import { Route } from "@/routes/segundo-cerebro";

const mocks = vi.hoisted(() => ({
  getSnapshot: vi.fn(),
  listArticles: vi.fn(),
  getArticleEvidence: vi.fn(),
  getCandidateEvidence: vi.fn(),
  getSourceEvidence: vi.fn(),
  searchKnowledge: vi.fn(),
  submitCandidate: vi.fn(),
  reviewArticle: vi.fn(),
  reviewCandidate: vi.fn(),
  reviewSource: vi.fn(),
}));

vi.mock("@/auth/AuthContext", () => ({
  useAuth: () => ({
    status: "ready",
    access: {
      role: "supervisor",
      municipalityId: "municipality-1",
      municipalityLabel: "Cordeirópolis/SP",
    },
    demo: false,
  }),
}));

vi.mock("@/services/fiscal-service", () => ({
  fiscalKeys: {
    knowledge: (municipalityId: string) => ["municipality", municipalityId, "knowledge"],
    knowledgeOperations: (municipalityId: string) => [
      "municipality",
      municipalityId,
      "knowledge",
      "operations",
    ],
    knowledgeReviewers: (municipalityId: string) => [
      "municipality",
      municipalityId,
      "knowledge",
      "reviewers",
    ],
    municipalityUsers: (municipalityId: string) => ["municipality", municipalityId, "users"],
    knowledgeSearch: (municipalityId: string, query: string) => [
      "municipality",
      municipalityId,
      "knowledge",
      "search",
      query,
    ],
  },
  fiscalService: {
    getKnowledgeOperationsSnapshot: mocks.getSnapshot,
    listKnowledgeArticles: mocks.listArticles,
    getKnowledgeArticleEvidence: mocks.getArticleEvidence,
    getKnowledgeCandidateEvidence: mocks.getCandidateEvidence,
    getLegalSourceChangeEvidence: mocks.getSourceEvidence,
    searchLegalKnowledge: mocks.searchKnowledge,
    submitKnowledgeCandidate: mocks.submitCandidate,
    reviewKnowledgeArticle: mocks.reviewArticle,
    reviewKnowledgeCandidate: mocks.reviewCandidate,
    reviewLegalSourceChange: mocks.reviewSource,
  },
}));

const citation = {
  citationId: "citation-1",
  citationLabel: "Art. 215",
  quotedExcerpt: "O recolhimento mensal do ISSQN observará a legislação municipal vigente.",
  sourceId: "source-1",
  sourceTitle: "Código Tributário de Cordeirópolis",
  officialIdentifier: "Lei Complementar nº 399/2024",
  officialUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
  sourceVersionId: "version-1",
  sourceVersionNumber: 1,
  sourceVersionStatus: "published",
  sourceSha256: "a".repeat(64),
  publicationDate: "2024-12-20",
  validFrom: "2025-01-01",
  validUntil: null,
  sectionId: "section-1",
  sectionKey: "artigo_215",
  sectionHeading: "Artigo 215",
  sectionContentSha256: "b".repeat(64),
  isValid: true,
  blockers: [],
};

const sourceEvidence = {
  verified: true,
  municipalityId: "municipality-1",
  changeSetId: "change-1",
  changeType: "initial_document",
  status: "detected",
  sourceId: "source-1",
  sourceTitle: "Código Tributário de Cordeirópolis",
  officialIdentifier: "Lei Complementar nº 399/2024",
  officialUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
  requestedUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
  capturedUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
  observedAt: "2026-08-17T11:00:00Z",
  rawContentSha256: "c".repeat(64),
  fromSha256: null,
  toSha256: "c".repeat(64),
  diffSha256: "d".repeat(64),
  artifactId: "artifact-1",
  artifactMimeType: "text/html",
  artifactByteSize: 512,
  candidateVersionId: "version-1",
  candidateVersionNumber: 1,
  candidateVersionStatus: "under_review",
  contentSha256: "a".repeat(64),
  contentText: "Art. 215. O recolhimento mensal do ISSQN observará a legislação municipal vigente.",
  contentOffset: 0,
  contentLimit: 82,
  contentTotalChars: 82,
  contentHasMore: false,
  diffSummary: "Primeiro documento oficial identificado.",
  publicationDate: "2024-12-20",
  validFrom: "2025-01-01",
  validUntil: null,
  sectionOffset: 0,
  sectionLimit: 1,
  sectionTotal: 1,
  sectionHasMore: false,
  sections: [
    {
      sectionId: "section-1",
      sectionKey: "artigo_215",
      heading: "Artigo 215",
      ordinal: 1,
      contentPreview:
        "Art. 215. O recolhimento mensal do ISSQN observará a legislação municipal vigente.",
      contentTotalChars: 82,
      contentSha256: "b".repeat(64),
      chunkCount: 1,
    },
  ],
  changeItems: [
    {
      ordinal: 1,
      itemKind: "document_hash",
      itemPath: "documento_oficial",
      beforeSha256: null,
      afterSha256: "c".repeat(64),
      beforeExcerpt: null,
      afterExcerpt: "Art. 215. O recolhimento mensal do ISSQN.",
      summary: "Documento oficial capturado pela primeira vez.",
    },
  ],
  changeItemOffset: 0,
  changeItemLimit: 25,
  changeItemTotal: 1,
  changeItemsHasMore: false,
  changeItemsFullSha256: "f".repeat(64),
  evidenceComplete: true,
  blockers: ["source_review_required"],
};

const articleEvidence = {
  verified: true,
  municipalityId: "municipality-1",
  articleId: "article-2",
  revisionId: "revision-2",
  contentSha256: "e".repeat(64),
  canonicalQuestion: "Como conferir o vencimento do ISSQN?",
  answerBody: "O vencimento deve ser conferido na legislação municipal vigente.",
  answerLength: 64,
  citationCount: 1,
  citations: [citation],
  evidenceComplete: true,
  blockers: ["article_not_approved"],
};

const candidateEvidence = {
  verified: true,
  checkedAt: "2026-08-17T12:00:00Z",
  municipalityId: "municipality-1",
  candidateId: "candidate-1",
  question: "Qual é o prazo de recolhimento do ISSQN?",
  proposedAnswer:
    "O prazo deverá ser confirmado no dispositivo municipal vigente antes da aplicação.",
  contentSha256: "f".repeat(64),
  status: "pending_review",
  submittedAt: "2026-08-17T11:30:00Z",
  reviewedAt: null,
  citations: [
    {
      citationId: "version-1:section-1",
      sourceTitle: "Código Tributário de Cordeirópolis",
      officialIdentifier: "Lei Complementar nº 399/2024",
      officialUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
      sourceVersionId: "version-1",
      sectionId: "section-1",
      sectionKey: "artigo_215",
      sectionHeading: "Artigo 215",
      citationLabel: "Artigo 215",
      quotedExcerpt: "O recolhimento mensal observará a legislação vigente.",
      publicationDate: "2024-12-20",
      validFrom: "2025-01-01",
      validUntil: null,
      relevance: 0.92,
      isValid: true,
      blockers: [],
    },
  ],
  evidenceComplete: true,
  blockers: [],
  canReview: true,
  canPublish: false,
};

const snapshot = {
  verified: true,
  municipalityId: "municipality-1",
  municipalityName: "Cordeirópolis",
  municipalitySlug: "cordeiropolis-sp",
  checkedAt: "2026-08-17T12:00:00Z",
  capabilities: {
    canView: true,
    canSearch: true,
    canSubmitCandidates: true,
    canReviewCandidates: true,
    canReviewSourceVersions: true,
    canReviewArticles: true,
    canPublishSourceVersions: false,
    canPublishArticles: false,
  },
  summary: {
    officialSources: 1,
    totalSourceVersions: 1,
    publishedSourceVersions: 0,
    pendingSourceReviews: 1,
    pendingSourceExtractions: 1,
    pendingSourcePublications: 0,
    pendingArticleReviews: 1,
    pendingCandidates: 0,
    pendingEmbeddings: 0,
    eligibleSections: 24,
    indexedSections: 24,
    indexedChunks: 31,
    lastIndexedAt: "2026-08-17T11:00:00Z",
    openChanges: 1,
    failedFetches24h: 0,
  },
  sources: [
    {
      sourceId: "source-1",
      title: "Código Tributário de Cordeirópolis",
      officialIdentifier: "Lei Complementar nº 399/2024",
      sourceType: "law",
      taxScope: "ISSQN",
      status: "active",
      officialUrl: "https://cordeiropolis.sp.gov.br/",
      trustTier: "primary_publication",
      endpointStatus: "active",
      lastFetchStatus: "completed_unchanged",
      lastCheckedAt: "2026-08-17T11:00:00Z",
      lastChangeDetectedAt: "2026-08-17T11:00:00Z",
      lastErrorCode: null,
      lastErrorDetail: null,
      latestVersionId: "version-1",
      latestVersionNumber: 1,
      latestVersionStatus: "under_review",
      latestValidFrom: "2025-01-01",
      latestValidUntil: null,
      blockers: ["Existe uma mudança aguardando revisão humana."],
      canReview: false,
      canPublish: false,
    },
  ],
  changes: [
    {
      changeSetId: "change-1",
      sourceId: "source-1",
      sourceTitle: "Código Tributário de Cordeirópolis",
      changeType: "initial_document",
      status: "detected",
      detectedAt: "2026-08-17T11:00:00Z",
      fromSha256: null,
      toSha256: "hash",
      candidateVersionId: "version-1",
      candidateVersionNumber: 1,
      candidateVersionStatus: "under_review",
      candidateValidFrom: "2025-01-01",
      candidateValidUntil: null,
      officialUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
      candidateContentPreview:
        "Art. 215. O recolhimento mensal do ISSQN observará a legislação municipal vigente.",
      sectionCount: 24,
      diffSummary: "Primeiro documento oficial identificado.",
      blockers: ["Revisão jurídica necessária."],
      canReview: true,
      canPublish: false,
    },
  ],
  reviews: [
    {
      queueKind: "knowledge_article",
      itemId: "article-2",
      title: "Como conferir o vencimento do ISSQN?",
      status: "under_review",
      contentSha256: "hash",
      submittedAt: "2026-08-17T11:00:00Z",
      lastReviewedAt: null,
      blockers: ["O artigo ainda não possui aprovação vigente."],
      canReview: true,
      canPublish: false,
      sourceId: null,
      changeSetId: null,
      candidateVersionId: null,
      articleId: "article-2",
      revisionId: "revision-2",
      revisionNumber: 1,
      answerPreview: "O vencimento deve ser conferido na legislação municipal vigente.",
      citationCount: 1,
      isTest: false,
      taxScope: "ISSQN",
      divergenceScope: "current_account_balance",
      validFrom: null,
      validUntil: null,
      officialUrl: null,
      candidateContentPreview: null,
      sectionCount: null,
    },
  ],
  health: {
    status: "attention",
    staleSources: 0,
    failedSources: 0,
    blockedSources: 1,
    lastSuccessfulFetchAt: "2026-08-17T11:00:00Z",
    blockers: ["1 fonte bloqueada exige intervenção."],
  },
  schedule: {
    enabled: true,
    cadenceLabel: "A cada 6 horas",
    timeZone: "America/Sao_Paulo",
    nextRunAt: "2026-08-17T18:00:00Z",
    lastRunAt: "2026-08-17T12:00:00Z",
    lastRunStatus: "never_run",
    runtimeVerified: true,
    blockers: [],
  },
  index: {
    status: "healthy",
    indexedSections: 24,
    eligibleSections: 24,
    embeddingModel: "gte-small",
    lastIndexedAt: "2026-08-17T11:00:00Z",
    blockers: [],
  },
  ocr: {
    contractVersion: "ia-fiscal-knowledge-ocr/v1",
    policyVersion: "ia-fiscal-knowledge-ocr-policy/v1",
    runtimeVerified: true,
    hasAttention: false,
    state: "queued",
    jobs: {
      queued: 1,
      processing: 0,
      completed: 0,
      deadLetter: 0,
      blockedPageLimit: 0,
    },
    lastEventAt: "2026-08-17T12:05:00Z",
    limits: {
      maxPages: 120,
      maxPageCharacters: 1_000_000,
      maxTotalCharacters: 8_000_000,
      abovePageLimit: "manual_review_required",
    },
    candidateStatus: "under_review",
    autoPublish: false,
    blockers: [],
  },
  reviewer: {
    verified: true,
    configured: true,
    activeCount: 1,
    currentUserCanReview: true,
    blockers: [],
  },
  coverage: [
    {
      coverageKey: "siscam.classification.424",
      title: "Pesquisa fiscal Siscam — classificação 424",
      expected: null,
      discovered: 0,
      identityVerified: 0,
      extractionQueued: 0,
      reviewable: 0,
      published: 0,
      corpusIntegral: false,
      upstreamStatus: "blocked_503",
      blocker: "upstream_siscam_503",
    },
  ],
  coverageLabel: "Cobertura inicial governada",
  corpusIntegral: false,
};

beforeEach(() => {
  vi.stubGlobal(
    "ResizeObserver",
    class ResizeObserver {
      observe() {}
      unobserve() {}
      disconnect() {}
    },
  );
  Element.prototype.scrollIntoView = vi.fn();
  mocks.getSnapshot.mockReset().mockResolvedValue(snapshot);
  mocks.listArticles.mockReset().mockResolvedValue([
    {
      municipalityId: "municipality-1",
      articleId: "article-1",
      revisionId: "revision-1",
      intentKey: "consulta_debito",
      semanticVersion: 1,
      canonicalQuestion: "Como consultar a composição do débito?",
      taxScope: "ISSQN",
      divergenceScope: "current_account_balance",
      answerBody: "Consulte a composição no ambiente autenticado.",
      validFrom: "2025-01-01",
      validUntil: null,
      publishedAt: "2026-08-17T10:00:00Z",
      isTest: false,
      citations: [citation],
    },
  ]);
  mocks.getSourceEvidence.mockReset().mockResolvedValue(sourceEvidence);
  mocks.getArticleEvidence.mockReset().mockResolvedValue(articleEvidence);
  mocks.getCandidateEvidence.mockReset().mockResolvedValue(candidateEvidence);
  mocks.searchKnowledge.mockReset().mockImplementation((_municipalityId, query) =>
    Promise.resolve({
      verified: true,
      correlationId: "123e4567-e89b-42d3-a456-426614174000",
      municipalityId: "municipality-1",
      query,
      answered: true,
      answer: "O prazo deve ser conferido no dispositivo municipal vigente.",
      confidence: 0.92,
      retrievalMode: "hybrid",
      searchedAt: "2026-08-17T12:30:00Z",
      citations: [
        {
          citationId: "version-1:section-1",
          sourceTitle: "Código Tributário de Cordeirópolis",
          officialIdentifier: "Lei Complementar nº 399/2024",
          officialUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
          sourceVersionId: "version-1",
          sectionId: "section-1",
          sectionKey: "artigo_215",
          sectionHeading: "Artigo 215",
          citationLabel: "Artigo 215",
          quotedExcerpt: "O recolhimento mensal do ISSQN observará a legislação municipal vigente.",
          publicationDate: "2024-12-20",
          validFrom: "2025-01-01",
          validUntil: null,
          relevance: 0.92,
          isValid: true,
          blockers: [],
        },
      ],
      blockers: [],
    }),
  );
  mocks.submitCandidate.mockReset().mockResolvedValue("candidate-1");
  mocks.reviewArticle.mockReset().mockResolvedValue("review-article-1");
  mocks.reviewCandidate.mockReset().mockResolvedValue("review-candidate-1");
  mocks.reviewSource.mockReset().mockResolvedValue("review-source-1");
});

afterEach(() => cleanup());

async function renderPage() {
  const Page = Route.options.component;
  if (!Page) throw new Error("segundo-cerebro route component is required");
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  await act(() => {
    render(
      <QueryClientProvider client={queryClient}>
        <Page />
      </QueryClientProvider>,
    );
  });
}

describe("Segundo Cérebro operacional", () => {
  it("apresenta biblioteca, fontes, mudanças e revisões em português", async () => {
    await renderPage();

    fireEvent.mouseDown(
      await screen.findByRole("tab", { name: "Biblioteca" }, { timeout: 3_000 }),
      {
        button: 0,
        ctrlKey: false,
      },
    );
    expect(
      await screen.findByText("Como consultar a composição do débito?", {}, { timeout: 3_000 }),
    ).toBeTruthy();
    expect(screen.getByText("Art. 215")).toBeTruthy();
    expect(screen.getByText("Cordeirópolis/SP")).toBeTruthy();

    fireEvent.mouseDown(screen.getByRole("tab", { name: "Fontes oficiais" }), {
      button: 0,
      ctrlKey: false,
    });
    expect(await screen.findByText("Código Tributário de Cordeirópolis")).toBeTruthy();
    expect(screen.getByText("Lei Complementar nº 399/2024")).toBeTruthy();
    expect(document.body.textContent).toContain("01/01/2025 a prazo indeterminado");

    fireEvent.mouseDown(screen.getByRole("tab", { name: /Mudanças/ }), {
      button: 0,
      ctrlKey: false,
    });
    expect(await screen.findByText("Primeiro documento oficial identificado.")).toBeTruthy();
    expect(
      (screen.getByRole("link", { name: /Abrir origem oficial/ }) as HTMLAnchorElement).href,
    ).toBe("https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario");
    fireEvent.click(screen.getByRole("button", { name: "Revisar" }));
    const reviewDialog = await screen.findByRole("dialog");
    expect(await within(reviewDialog).findByText(/Conteúdo extraído · caracteres/)).toBeTruthy();
    expect(
      within(reviewDialog).getAllByText(/Art\. 215\. O recolhimento mensal do ISSQN/).length,
    ).toBeGreaterThan(0);
    expect(
      within(reviewDialog)
        .getByRole("region", { name: "Trecho integral da fonte oficial para revisão" })
        .getAttribute("tabindex"),
    ).toBe("0");
    expect(within(reviewDialog).getByRole("link", { name: /Abrir origem oficial/ })).toBeTruthy();
    fireEvent.click(within(reviewDialog).getByRole("button", { name: "Cancelar" }));

    fireEvent.mouseDown(screen.getByRole("tab", { name: /Revisões/ }), {
      button: 0,
      ctrlKey: false,
    });
    expect(await screen.findByText("Como conferir o vencimento do ISSQN?")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Revisar" })).toBeTruthy();
    expect(document.body.textContent).not.toContain("under_review");
    expect(document.body.textContent).not.toContain("current_account_balance");
  }, 15_000);

  it("responde uma consulta somente com evidência oficial verificável", async () => {
    await renderPage();

    fireEvent.change(await screen.findByLabelText("O que você precisa confirmar na legislação?"), {
      target: { value: "Qual é o prazo de recolhimento do ISSQN?" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Consultar base" }));

    expect(await screen.findByText("Trecho oficial mais relevante")).toBeTruthy();
    expect(
      screen.getByText("O prazo deve ser conferido no dispositivo municipal vigente."),
    ).toBeTruthy();
    expect(screen.getByText("Evidências oficiais")).toBeTruthy();
    expect(screen.getByText("Vigente e verificável")).toBeTruthy();
    expect(screen.getByText("123e4567-e89b-42d3-a456-426614174000")).toBeTruthy();
    expect(
      (screen.getByRole("link", { name: /Conferir no portal oficial/ }) as HTMLAnchorElement).href,
    ).toBe("https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario");
  });

  it.each([0.35, 0.6499])(
    "libera o trecho no limiar seguro e o rotula como aderência suficiente (%s)",
    async (confidence) => {
      mocks.searchKnowledge.mockImplementationOnce((_municipalityId, query) =>
        Promise.resolve({
          verified: true,
          correlationId: "123e4567-e89b-42d3-a456-426614174010",
          municipalityId: "municipality-1",
          query,
          answered: true,
          answer: "Trecho oficial no limiar de segurança.",
          confidence,
          retrievalMode: "hybrid",
          searchedAt: "2026-08-17T12:30:00Z",
          citations: [citation],
          blockers: [],
        }),
      );
      await renderPage();

      fireEvent.change(
        await screen.findByLabelText("O que você precisa confirmar na legislação?"),
        { target: { value: "Qual é o prazo de recolhimento do ISSQN?" } },
      );
      fireEvent.click(screen.getByRole("button", { name: "Consultar base" }));

      expect(await screen.findByText("Trecho oficial mais relevante")).toBeTruthy();
      expect(screen.getByText("Evidência com aderência suficiente")).toBeTruthy();
    },
  );

  it("recusa um resultado marcado como respondido abaixo do limiar seguro", async () => {
    mocks.searchKnowledge.mockImplementationOnce((_municipalityId, query) =>
      Promise.resolve({
        verified: true,
        correlationId: "123e4567-e89b-42d3-a456-426614174011",
        municipalityId: "municipality-1",
        query,
        answered: true,
        answer: "Trecho que não pode ser liberado.",
        confidence: 0.3499,
        retrievalMode: "hybrid",
        searchedAt: "2026-08-17T12:30:00Z",
        citations: [citation],
        blockers: [],
      }),
    );
    await renderPage();

    fireEvent.change(await screen.findByLabelText("O que você precisa confirmar na legislação?"), {
      target: { value: "Qual é o prazo de recolhimento do ISSQN?" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Consultar base" }));

    expect(await screen.findByText("Resposta não liberada")).toBeTruthy();
    expect(document.body.textContent).not.toContain("Trecho que não pode ser liberado.");
  });

  it("recusa uma conclusão quando a busca não encontra evidência suficiente", async () => {
    mocks.searchKnowledge.mockImplementationOnce((_municipalityId, query) =>
      Promise.resolve({
        verified: true,
        correlationId: "123e4567-e89b-42d3-a456-426614174001",
        municipalityId: "municipality-1",
        query,
        answered: false,
        answer: null,
        confidence: null,
        retrievalMode: "lexical",
        searchedAt: "2026-08-17T12:30:00Z",
        citations: [],
        blockers: ["citation_required"],
      }),
    );
    await renderPage();

    fireEvent.change(await screen.findByLabelText("O que você precisa confirmar na legislação?"), {
      target: { value: "Existe uma isenção específica para este caso?" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Consultar base" }));

    expect(await screen.findByText("Resposta não liberada")).toBeTruthy();
    expect(screen.getByText("A base oficial não sustenta uma resposta segura")).toBeTruthy();
    expect(screen.getByText("É necessária ao menos uma citação oficial")).toBeTruthy();
    expect(document.body.textContent).not.toContain("O prazo deve ser conferido");
  });

  it("envia aprendizado somente como candidato sujeito à revisão jurídica", async () => {
    await renderPage();

    fireEvent.change(await screen.findByLabelText("O que você precisa confirmar na legislação?"), {
      target: { value: "Qual é o prazo de recolhimento do ISSQN?" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Consultar base" }));
    await screen.findByText("Trecho oficial mais relevante");
    fireEvent.click(screen.getByRole("button", { name: "Enviar proposta para revisão" }));

    const dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Resposta proposta"), {
      target: {
        value:
          "O prazo deverá ser confirmado no artigo oficial e aplicado conforme a competência analisada.",
      },
    });
    fireEvent.change(within(dialog).getByLabelText("Digite ENVIAR PARA REVISÃO para confirmar"), {
      target: { value: "ENVIAR PARA REVISÃO" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Enviar para revisão jurídica" }));

    await waitFor(() =>
      expect(mocks.submitCandidate).toHaveBeenCalledWith("municipality-1", {
        question: "Qual é o prazo de recolhimento do ISSQN?",
        proposedAnswer:
          "O prazo deverá ser confirmado no artigo oficial e aplicado conforme a competência analisada.",
        citationSectionIds: ["section-1"],
        confirmation: "ENVIAR PARA REVISÃO",
      }),
    );
  });

  it("aprova candidato apenas como sinal supervisionado, sem oferecer publicação", async () => {
    const candidateSnapshot = structuredClone(snapshot) as unknown as KnowledgeOperationsSnapshot;
    candidateSnapshot.reviews = [
      {
        queueKind: "learning_candidate",
        itemId: "candidate-1",
        candidateId: "candidate-1",
        title: "Qual é o prazo de recolhimento do ISSQN?",
        question: "Qual é o prazo de recolhimento do ISSQN?",
        proposedAnswerPreview:
          "O prazo deverá ser confirmado no dispositivo municipal vigente antes da aplicação.",
        status: "pending_review",
        contentSha256: "f".repeat(64),
        submittedAt: "2026-08-17T11:30:00Z",
        lastReviewedAt: null,
        blockers: ["legal_reviewer_required"],
        canReview: true,
        canPublish: false,
        sourceId: null,
        changeSetId: null,
        candidateVersionId: null,
        articleId: null,
        revisionId: null,
        revisionNumber: null,
        answerPreview: null,
        citationCount: 1,
        isTest: false,
        taxScope: null,
        divergenceScope: null,
        validFrom: null,
        validUntil: null,
        officialUrl: null,
        candidateContentPreview: null,
        sectionCount: null,
      },
    ];
    mocks.getSnapshot.mockResolvedValue(candidateSnapshot);
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: /Revisões/ }), {
      button: 0,
      ctrlKey: false,
    });
    expect(await screen.findByText("Candidato de aprendizado")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Publicar" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Revisar candidato" }));

    const dialog = await screen.findByRole("dialog");
    expect(await within(dialog).findByText("Proposta e fundamentação integral")).toBeTruthy();
    expect(within(dialog).getByText("Candidato não publicado")).toBeTruthy();
    fireEvent.change(within(dialog).getByLabelText("Digite REVISAR CANDIDATO para confirmar"), {
      target: { value: "REVISAR CANDIDATO" },
    });
    fireEvent.click(
      within(dialog).getByRole("button", { name: "Registrar revisão supervisionada" }),
    );

    await waitFor(() =>
      expect(mocks.reviewCandidate).toHaveBeenCalledWith(
        "municipality-1",
        "candidate-1",
        "approved",
        "",
        "REVISAR CANDIDATO",
      ),
    );
  });

  it("mantém biblioteca e ações fechadas quando o snapshot não pode ser verificado", async () => {
    mocks.getSnapshot.mockRejectedValue(new Error("fiscal_data_error:42501"));
    await renderPage();

    expect(await screen.findByText("Estado da base não verificado")).toBeTruthy();
    expect(screen.queryByRole("tab", { name: "Biblioteca" })).toBeNull();
    expect(mocks.listArticles).not.toHaveBeenCalled();
  });

  it("explica a falta de permissão sem iniciar a busca", async () => {
    const restrictedSnapshot = structuredClone(snapshot);
    restrictedSnapshot.capabilities.canSearch = false;
    restrictedSnapshot.capabilities.canSubmitCandidates = false;
    mocks.getSnapshot.mockResolvedValue(restrictedSnapshot);
    await renderPage();

    expect(await screen.findByText("Consulta não disponível para este acesso")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Consultar base" })).toBeNull();
    expect(mocks.searchKnowledge).not.toHaveBeenCalled();
  });

  it("mostra agenda e cobertura da atualização em linguagem operacional", async () => {
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: "Saúde" }), {
      button: 0,
      ctrlKey: false,
    });

    expect(await screen.findByText("Atualização automática")).toBeTruthy();
    expect(screen.getByText("A cada 6 horas")).toBeTruthy();
    expect(screen.getByText("OCR jurídico governado")).toBeTruthy();
    expect(screen.getAllByText("Na fila")).toHaveLength(2);
    expect(screen.getByText("Acima de 120 páginas")).toBeTruthy();
    expect(screen.getByText("Até 120 páginas por documento")).toBeTruthy();
    expect(screen.getByText("Sempre encaminhada para revisão jurídica")).toBeTruthy();
    expect(screen.getByText("Cobertura da busca inteligente")).toBeTruthy();
    expect(screen.getByText("24 de 24 dispositivo(s) elegível(is) indexado(s).")).toBeTruthy();
    expect(screen.getByText("Ainda não executada")).toBeTruthy();
    expect(screen.getByText("Cobertura inicial governada")).toBeTruthy();
    expect(screen.getByText("Pesquisa fiscal Siscam — classificação 424")).toBeTruthy();
    expect(screen.getByText("Não confirmado")).toBeTruthy();
    expect(
      screen.getByText(
        "O catálogo oficial Siscam respondeu com indisponibilidade temporária (503)",
      ),
    ).toBeTruthy();
    expect(document.body.textContent).not.toContain("cron");
    expect(document.body.textContent).not.toContain("gte-small");
  });

  it("bloqueia a cobertura quando o índice informa mais itens que os elegíveis", async () => {
    const inconsistentSnapshot = structuredClone(
      snapshot,
    ) as unknown as KnowledgeOperationsSnapshot;
    inconsistentSnapshot.index = {
      ...inconsistentSnapshot.index,
      status: "blocked",
      indexedSections: 25,
      eligibleSections: 24,
      blockers: ["knowledge_index_inconsistent"],
    };
    mocks.getSnapshot.mockResolvedValue(inconsistentSnapshot);
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: "Saúde" }), {
      button: 0,
      ctrlKey: false,
    });
    expect(await screen.findByText("Não verificada")).toBeTruthy();
    expect(
      screen.getByText(
        "A contagem do índice é incompatível com os dispositivos oficiais elegíveis",
      ),
    ).toBeTruthy();
    expect(document.body.textContent).not.toContain("104%");
  });

  it("explica documentos acima do limite seguro do OCR sem prometer processamento", async () => {
    const limitedSnapshot = structuredClone(snapshot) as unknown as KnowledgeOperationsSnapshot;
    limitedSnapshot.ocr = {
      ...limitedSnapshot.ocr,
      hasAttention: true,
      state: "attention_required",
      jobs: {
        ...limitedSnapshot.ocr.jobs,
        blockedPageLimit: 1,
      },
      blockers: ["knowledge_ocr_page_limit_exceeded"],
    };
    mocks.getSnapshot.mockResolvedValue(limitedSnapshot);
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: "Saúde" }), {
      button: 0,
      ctrlKey: false,
    });

    expect(await screen.findAllByText("Intervenção necessária")).toHaveLength(2);
    expect(
      screen.getByText(
        "Há documentos acima do limite de 120 páginas desta versão e que exigem tratamento manual",
      ),
    ).toBeTruthy();
    expect(screen.getByText("Até 120 páginas por documento")).toBeTruthy();
  });

  it("permite consultar evidências sem conceder poder de revisão", async () => {
    const readOnlySnapshot = structuredClone(snapshot);
    readOnlySnapshot.changes[0]!.canReview = false;
    mocks.getSnapshot.mockResolvedValue(readOnlySnapshot);
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: /Mudanças/ }), {
      button: 0,
      ctrlKey: false,
    });
    expect(screen.queryByRole("button", { name: "Revisar" })).toBeNull();
    fireEvent.click(await screen.findByRole("button", { name: "Ver evidências" }));

    const evidenceDialog = await screen.findByRole("dialog");
    expect(await within(evidenceDialog).findByText("Evidências do conteúdo")).toBeTruthy();
    expect(await within(evidenceDialog).findByText(/Conteúdo extraído · caracteres/)).toBeTruthy();
    expect(mocks.reviewSource).not.toHaveBeenCalled();
  });

  it("não permite aprovar uma fonte sem evidência oficial visível", async () => {
    mocks.getSourceEvidence.mockRejectedValue(new Error("evidence_unavailable"));
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: /Mudanças/ }), {
      button: 0,
      ctrlKey: false,
    });
    fireEvent.click(await screen.findByRole("button", { name: "Revisar" }));
    const reviewDialog = await screen.findByRole("dialog");
    fireEvent.change(within(reviewDialog).getByLabelText("Digite REVISAR para confirmar"), {
      target: { value: "REVISAR" },
    });

    expect(
      await within(reviewDialog).findByText(/evidência detalhada não pôde ser verificada/i),
    ).toBeTruthy();
    expect(
      (
        within(reviewDialog).getByRole("button", {
          name: "Confirmar revisão",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });

  it("mantém solicitação de ajustes disponível quando a evidência falha", async () => {
    mocks.getSourceEvidence.mockRejectedValue(new Error("evidence_unavailable"));
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: /Mudanças/ }), {
      button: 0,
      ctrlKey: false,
    });
    fireEvent.click(await screen.findByRole("button", { name: "Revisar" }));
    const reviewDialog = await screen.findByRole("dialog");
    await within(reviewDialog).findByText(/evidência detalhada não pôde ser verificada/i);

    fireEvent.click(within(reviewDialog).getByRole("combobox", { name: "Decisão" }));
    fireEvent.click(await screen.findByRole("option", { name: "Solicitar ajustes" }));
    fireEvent.change(within(reviewDialog).getByLabelText(/Observações/), {
      target: { value: "Recolher a fonte oficial e conferir novamente." },
    });
    fireEvent.change(within(reviewDialog).getByLabelText("Digite REVISAR para confirmar"), {
      target: { value: "REVISAR" },
    });

    const confirm = within(reviewDialog).getByRole("button", { name: "Confirmar revisão" });
    expect((confirm as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(confirm);

    await waitFor(() =>
      expect(mocks.reviewSource).toHaveBeenCalledWith(
        "municipality-1",
        "change-1",
        "changes_requested",
        "Recolher a fonte oficial e conferir novamente.",
        "REVISAR",
        { publicationDate: null, validFrom: null, validUntil: null },
      ),
    );
  });

  it("exige datas vigentes antes de aprovar uma fonte oficial", async () => {
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: /Mudanças/ }), {
      button: 0,
      ctrlKey: false,
    });
    fireEvent.click(await screen.findByRole("button", { name: "Revisar" }));
    const reviewDialog = await screen.findByRole("dialog");
    await within(reviewDialog).findByText(/Conteúdo extraído · caracteres/);
    fireEvent.change(within(reviewDialog).getByLabelText("Digite REVISAR para confirmar"), {
      target: { value: "REVISAR" },
    });

    const confirm = within(reviewDialog).getByRole("button", { name: "Confirmar revisão" });
    expect((confirm as HTMLButtonElement).disabled).toBe(true);

    fireEvent.change(within(reviewDialog).getByLabelText("Publicação"), {
      target: { value: "2024-12-20" },
    });
    fireEvent.change(within(reviewDialog).getByLabelText("Início da vigência"), {
      target: { value: "2025-01-01" },
    });

    expect((confirm as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(confirm);

    await waitFor(() =>
      expect(mocks.reviewSource).toHaveBeenCalledWith(
        "municipality-1",
        "change-1",
        "approved",
        "",
        "REVISAR",
        { publicationDate: "2024-12-20", validFrom: "2025-01-01", validUntil: null },
      ),
    );
  });

  it("não permite aprovar artigo sem resposta integral e citações verificadas", async () => {
    mocks.getArticleEvidence.mockResolvedValue({
      ...articleEvidence,
      citationCount: 0,
      citations: [],
      evidenceComplete: false,
      blockers: ["citation_required"],
    });
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: /Revisões/ }), {
      button: 0,
      ctrlKey: false,
    });
    fireEvent.click(await screen.findByRole("button", { name: "Revisar" }));
    const reviewDialog = await screen.findByRole("dialog");
    expect(await within(reviewDialog).findByText("Resposta integral e fundamentação")).toBeTruthy();
    fireEvent.change(within(reviewDialog).getByLabelText("Digite REVISAR para confirmar"), {
      target: { value: "REVISAR" },
    });

    expect(
      (
        within(reviewDialog).getByRole("button", {
          name: "Confirmar revisão",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });

  it("pagina a evidência oficial sob demanda sem materializar o documento inteiro", async () => {
    const firstPage = {
      ...sourceEvidence,
      contentText: "ABCDE",
      contentOffset: 0,
      contentLimit: 5,
      contentTotalChars: 10,
      contentHasMore: true,
    };
    const secondPage = {
      ...firstPage,
      contentText: "FGHIJ",
      contentOffset: 5,
      contentHasMore: false,
    };
    mocks.getSourceEvidence.mockImplementation(
      (_municipalityId, _changeSetId, page?: { contentOffset: number }) =>
        Promise.resolve(page?.contentOffset === 5 ? secondPage : firstPage),
    );
    await renderPage();

    fireEvent.mouseDown(await screen.findByRole("tab", { name: /Mudanças/ }), {
      button: 0,
      ctrlKey: false,
    });
    fireEvent.click(await screen.findByRole("button", { name: "Revisar" }));
    const dialog = await screen.findByRole("dialog");
    expect(await within(dialog).findByText("ABCDE")).toBeTruthy();
    fireEvent.click(within(dialog).getByRole("button", { name: "Próximo trecho" }));

    expect(await within(dialog).findByText("FGHIJ")).toBeTruthy();
    expect(mocks.getSourceEvidence).toHaveBeenLastCalledWith("municipality-1", "change-1", {
      contentOffset: 5,
      sectionOffset: 0,
      changeItemOffset: 0,
    });
  });

  it("limpa a confirmação e o conteúdo do modal ao fechar e reabrir", async () => {
    await renderPage();
    fireEvent.change(await screen.findByLabelText("O que você precisa confirmar na legislação?"), {
      target: { value: "Qual é o prazo de recolhimento do ISSQN?" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Consultar base" }));
    await screen.findByText("Trecho oficial mais relevante");
    fireEvent.click(screen.getByRole("button", { name: "Enviar proposta para revisão" }));
    let dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Resposta proposta"), {
      target: { value: "Resposta proposta suficientemente longa para revisão jurídica." },
    });
    fireEvent.change(within(dialog).getByLabelText("Digite ENVIAR PARA REVISÃO para confirmar"), {
      target: { value: "ENVIAR PARA REVISÃO" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancelar" }));
    fireEvent.click(screen.getByRole("button", { name: "Enviar proposta para revisão" }));
    dialog = await screen.findByRole("dialog");

    expect((within(dialog).getByLabelText("Resposta proposta") as HTMLTextAreaElement).value).toBe(
      "",
    );
    expect(
      (
        within(dialog).getByLabelText(
          "Digite ENVIAR PARA REVISÃO para confirmar",
        ) as HTMLInputElement
      ).value,
    ).toBe("");
    expect(
      (
        within(dialog).getByRole("button", {
          name: "Enviar para revisão jurídica",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });

  it("não envia uma busca acima de 500 caracteres", async () => {
    await renderPage();
    fireEvent.change(await screen.findByLabelText("O que você precisa confirmar na legislação?"), {
      target: { value: "x".repeat(501) },
    });
    expect(
      (screen.getByRole("button", { name: "Consultar base" }) as HTMLButtonElement).disabled,
    ).toBe(true);
    expect(mocks.searchKnowledge).not.toHaveBeenCalled();
  });
});
