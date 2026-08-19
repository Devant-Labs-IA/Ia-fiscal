import { beforeEach, describe, expect, it, vi } from "vitest";

import { supabaseFiscalService } from "@/services/supabase-fiscal-service";

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  invoke: vi.fn(),
}));

vi.mock("@/lib/supabase", () => ({
  getSupabaseClient: () => ({
    from: mocks.from,
    rpc: mocks.rpc,
    functions: { invoke: mocks.invoke },
  }),
}));

function readChain(data: Record<string, unknown>[]) {
  const chain = {
    select: vi.fn(),
    eq: vi.fn(),
    in: vi.fn(),
    order: vi.fn(),
    limit: vi.fn(),
    abortSignal: vi.fn().mockResolvedValue({ data, error: null }),
  };
  chain.select.mockReturnValue(chain);
  chain.eq.mockReturnValue(chain);
  chain.in.mockReturnValue(chain);
  chain.order.mockReturnValue(chain);
  chain.limit.mockReturnValue(chain);
  return chain;
}

function rpcChain(data: unknown) {
  return {
    abortSignal: vi.fn().mockResolvedValue({ data, error: null }),
  };
}

function knowledgeCitationRow(overrides: Record<string, unknown> = {}) {
  return {
    citation_id: "citation-1",
    citation_label: "Artigo 215",
    quoted_excerpt: "Trecho oficial conferível.",
    source_id: "source-1",
    source_title: "Código Tributário Municipal",
    official_identifier: "Lei Complementar nº 399/2024",
    official_url: "https://cordeiropolis.sp.gov.br/legislacao",
    source_version_id: "version-1",
    source_version_number: 1,
    source_version_status: "published",
    source_sha256: "b".repeat(64),
    publication_date: "2024-12-20",
    valid_from: "2025-01-01",
    valid_until: null,
    section_id: "section-1",
    section_key: "artigo_215",
    section_heading: "Artigo 215",
    section_content_sha256: "c".repeat(64),
    is_valid: true,
    blockers: [],
    ...overrides,
  };
}

function knowledgeSearchEnvelope(confidence: number | null, answered = true) {
  return {
    contract_version: "knowledge-search-v1",
    correlation_id: "123e4567-e89b-42d3-a456-426614174000",
    data: {
      verified: true,
      municipality_id: "municipality-1",
      query: "Qual é o prazo do ISSQN?",
      answered,
      answer: answered ? "Trecho oficial localizado." : null,
      confidence,
      retrieval_mode: "hybrid",
      searched_at: "2026-08-17T12:30:00Z",
      citations: [
        {
          legal_section_id: "section-1",
          source_version_id: "version-1",
          source_title: "Código Tributário Municipal",
          official_identifier: "Lei Complementar nº 399/2024",
          official_url: "https://cordeiropolis.sp.gov.br/legislacao",
          section_key: "artigo_215",
          heading: "Artigo 215",
          excerpt: "O recolhimento observará a legislação municipal vigente.",
          publication_date: "2024-12-20",
          valid_from: "2025-01-01",
          valid_until: null,
          score: confidence ?? 0,
        },
      ],
      blockers: answered ? [] : ["insufficient_relevance"],
    },
  };
}

beforeEach(() => {
  mocks.from.mockReset();
  mocks.rpc.mockReset();
  mocks.invoke.mockReset();
});

describe("contrato Supabase do atendimento", () => {
  it("consulta o relatório operacional agregado por município", async () => {
    const chain = rpcChain({ taxpayer_count: 3, open_balance_total: "151.40" });
    mocks.rpc.mockReturnValue(chain);

    await expect(
      supabaseFiscalService.getOperationalReport("municipality-1"),
    ).resolves.toMatchObject({
      taxpayerCount: 3,
      openBalanceTotal: 151.4,
    });
    expect(mocks.rpc).toHaveBeenCalledWith("ia_operational_report", {
      p_municipality_id: "municipality-1",
    });
    expect(chain.abortSignal).toHaveBeenCalledTimes(1);
  });

  it("consulta e mapeia o estado de segurança da comunicação externa", async () => {
    const chain = rpcChain({
      verified: true,
      external_delivery_blocked: true,
      master_lock: true,
      external_email_enabled: false,
      open_email_channel: false,
      automatic_notice_enabled: false,
      pending_external_jobs: 0,
      checked_at: "2026-08-13T12:00:00Z",
    });
    mocks.rpc.mockReturnValue(chain);

    await expect(
      supabaseFiscalService.getAssistedOperationSafetyStatus("municipality-1"),
    ).resolves.toEqual({
      verified: true,
      externalDeliveryBlocked: true,
      masterLock: true,
      externalEmailEnabled: false,
      openEmailChannel: false,
      automaticNoticeEnabled: false,
      pendingExternalJobs: 0,
      checkedAt: "2026-08-13T12:00:00Z",
    });
    expect(mocks.rpc).toHaveBeenCalledWith("ia_get_assisted_operation_safety_status", {
      p_municipality_id: "municipality-1",
    });
    expect(chain.abortSignal).toHaveBeenCalledTimes(1);
  });

  it("consulta o snapshot governado do Segundo Cérebro e valida o município retornado", async () => {
    const snapshotPayload = {
      verified: true,
      checked_at: "2026-08-17T12:00:00Z",
      municipality: { id: "municipality-1", slug: "cordeiropolis-sp", name: "Cordeirópolis" },
      capabilities: {
        can_view: true,
        can_search: true,
        can_submit_candidates: true,
        can_review_candidates: true,
        can_review_source_versions: false,
        can_review_articles: true,
        can_publish_source_versions: false,
        can_publish_articles: false,
      },
      summary: {
        official_sources: 0,
        total_source_versions: 0,
        published_source_versions: 0,
        pending_source_reviews: 1,
        pending_source_extractions: 1,
        pending_source_publications: 1,
        pending_article_reviews: 0,
        pending_candidates: 2,
        pending_embeddings: 3,
        eligible_sections: 24,
        indexed_sections: 21,
        indexed_chunks: 29,
        last_indexed_at: "2026-08-17T11:30:00Z",
        open_changes: 1,
        failed_fetches_24h: 0,
      },
      sources: [],
      changes: [
        {
          change_set_id: "change-1",
          source_id: "source-1",
          source_title: "Código Tributário de Cordeirópolis",
          change_type: "initial_document",
          status: "pending_review",
          detected_at: "2026-08-17T11:00:00Z",
          from_sha256: null,
          to_sha256: "hash-1",
          candidate_version_id: "version-1",
          candidate_version_number: 1,
          candidate_version_status: "under_review",
          candidate_valid_from: "2025-01-01",
          candidate_valid_until: null,
          official_url: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
          candidate_content_preview: "Art. 215. O recolhimento mensal do ISSQN.",
          section_count: 24,
          diff_summary: "Primeiro documento oficial identificado.",
          blockers: ["source_review_required"],
          can_review: true,
          can_publish: false,
        },
      ],
      reviews: [
        {
          queue_kind: "learning_candidate",
          item_id: "candidate-1",
          candidate_id: "candidate-1",
          title: "Qual é o prazo do ISSQN?",
          question: "Qual é o prazo do ISSQN?",
          proposed_answer_preview: "O prazo deve ser conferido na lei vigente.",
          status: "pending_review",
          content_sha256: "f".repeat(64),
          submitted_at: "2026-08-17T11:30:00Z",
          last_reviewed_at: null,
          blockers: ["legal_reviewer_required"],
          can_review: true,
          can_publish: false,
          source_id: null,
          change_set_id: null,
          candidate_version_id: null,
          article_id: null,
          revision_id: null,
          revision_number: null,
          answer_preview: null,
          citation_count: 1,
          is_test: false,
          tax_scope: null,
          divergence_scope: null,
          valid_from: null,
          valid_until: null,
          official_url: null,
          candidate_content_preview: null,
          section_count: null,
        },
      ],
      health: {
        status: "healthy",
        stale_sources: 0,
        failed_sources: 0,
        blocked_sources: 0,
        last_successful_fetch_at: null,
        blockers: [],
      },
      schedule: {
        enabled: true,
        cadence: "A cada 6 horas",
        next_run_at: "2026-08-17T18:00:00Z",
        last_run_at: "2026-08-17T12:00:00Z",
        last_run_status: null,
        timezone: "America/Sao_Paulo",
        runtime_verified: true,
        runtime_blocker: null,
      },
      ocr: {
        contract_version: "ia-fiscal-knowledge-ocr/v1",
        policy_version: "ia-fiscal-knowledge-ocr-policy/v1",
        runtime_verified: true,
        has_attention: false,
        runtime_blocker: null,
        state: "queued",
        jobs: {
          queued: 1,
          processing: 0,
          completed: 0,
          dead_letter: 0,
          blocked_page_limit: 0,
        },
        last_event_at: "2026-08-17T12:05:00Z",
        limits: {
          max_pages: 120,
          max_page_characters: 1000000,
          max_total_characters: 8000000,
          above_page_limit: "manual_review_required",
        },
        candidate_status: "under_review",
        auto_publish: false,
      },
      reviewer: {
        verified: true,
        configured: true,
        active_count: 1,
        current_user_can_review: true,
        blockers: [],
      },
      coverage: [
        {
          coverage_key: "siscam.classification.424",
          title: "Pesquisa fiscal Siscam — classificação 424",
          expected: null,
          discovered: 0,
          identity_verified: 0,
          extraction_queued: 0,
          reviewable: 0,
          published: 0,
          corpus_integral: false,
          upstream_status: "blocked_503",
          blocker: "upstream_siscam_503",
        },
      ],
      coverage_label: "Cobertura inicial governada",
      corpus_integral: false,
    };
    const chain = rpcChain(snapshotPayload);
    mocks.rpc.mockReturnValue(chain);

    await expect(
      supabaseFiscalService.getKnowledgeOperationsSnapshot("municipality-1"),
    ).resolves.toMatchObject({
      verified: true,
      municipalityId: "municipality-1",
      municipalityName: "Cordeirópolis",
      capabilities: {
        canSearch: true,
        canSubmitCandidates: true,
        canReviewCandidates: true,
      },
      summary: {
        pendingSourceExtractions: 1,
        pendingSourcePublications: 1,
        pendingCandidates: 2,
        pendingEmbeddings: 3,
        eligibleSections: 24,
        indexedSections: 21,
      },
      health: { status: "healthy" },
      schedule: {
        enabled: true,
        cadenceLabel: "A cada 6 horas",
        lastRunStatus: "never_run",
        runtimeVerified: true,
      },
      index: { status: "attention", indexedSections: 21, eligibleSections: 24 },
      ocr: {
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
        autoPublish: false,
      },
      coverage: [
        expect.objectContaining({
          coverageKey: "siscam.classification.424",
          upstreamStatus: "blocked_503",
        }),
      ],
      corpusIntegral: false,
      reviews: [
        expect.objectContaining({
          queueKind: "learning_candidate",
          candidateId: "candidate-1",
          canPublish: false,
        }),
      ],
      changes: [
        expect.objectContaining({
          officialUrl: "https://cordeiropolis.sp.gov.br/legislacao/codigo-tributario",
          candidateContentPreview: "Art. 215. O recolhimento mensal do ISSQN.",
          sectionCount: 24,
        }),
      ],
    });
    expect(mocks.rpc).toHaveBeenCalledWith("ia_get_knowledge_operations_snapshot", {
      p_municipality_id: "municipality-1",
    });

    snapshotPayload.ocr.state = "ready";
    mocks.rpc.mockReturnValue(rpcChain(snapshotPayload));
    await expect(
      supabaseFiscalService.getKnowledgeOperationsSnapshot("municipality-1"),
    ).rejects.toThrow("knowledge_ocr_status_invalid");
  });

  it("rejeita snapshot do Segundo Cérebro com município divergente", async () => {
    mocks.rpc.mockReturnValue(
      rpcChain({
        verified: true,
        checked_at: "2026-08-17T12:00:00Z",
        municipality: { id: "municipality-2", slug: "araras-sp", name: "Araras" },
        capabilities: {},
        summary: {},
        sources: [],
        changes: [],
        reviews: [],
        health: {},
      }),
    );

    await expect(
      supabaseFiscalService.getKnowledgeOperationsSnapshot("municipality-1"),
    ).rejects.toThrow("knowledge_snapshot_tenant_mismatch");
  });

  it("carrega o diretório administrativo de revisores sem PII pelo contrato governado", async () => {
    mocks.rpc.mockReturnValue(
      rpcChain({
        verified: true,
        municipality_id: "municipality-1",
        pii_exposed: false,
        checked_at: "2026-08-17T12:00:00Z",
        active_grants: [
          {
            grant_id: "grant-1",
            membership_id: "membership-2",
            role: "fiscal_auditor",
            status: "active",
            valid_from: "2026-08-17T12:00:00Z",
            valid_until: null,
            is_current: true,
          },
        ],
        eligible_staff: [
          {
            membership_id: "membership-3",
            role: "supervisor",
            already_configured: false,
          },
        ],
      }),
    );

    await expect(
      supabaseFiscalService.listKnowledgeReviewerCapabilities("municipality-1"),
    ).resolves.toMatchObject({
      verified: true,
      piiExposed: false,
      activeGrants: [expect.objectContaining({ grantId: "grant-1", isCurrent: true })],
      eligibleStaff: [expect.objectContaining({ membershipId: "membership-3" })],
    });
  });

  it("exige as confirmações exatas antes de alterar capacidade de revisor", async () => {
    await expect(
      supabaseFiscalService.grantKnowledgeReviewerCapability(
        "municipality-1",
        "membership-2",
        null,
        "Designação jurídica necessária",
        "CONFIRMAR",
      ),
    ).rejects.toThrow("knowledge_reviewer_confirmation_required");
    await expect(
      supabaseFiscalService.revokeKnowledgeReviewerCapability(
        "grant-1",
        "Revogação jurídica necessária",
        "REVOGAR",
      ),
    ).rejects.toThrow("knowledge_reviewer_revocation_confirmation_required");
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it("consulta a busca jurídica autenticada e aceita somente resposta com citação oficial", async () => {
    mocks.invoke.mockResolvedValue({
      data: {
        contract_version: "knowledge-search-v1",
        correlation_id: "123e4567-e89b-42d3-a456-426614174000",
        data: {
          verified: true,
          municipality_id: "municipality-1",
          query: "Qual é o prazo do ISSQN?",
          answered: true,
          answer: "O prazo deve ser conferido no artigo vigente.",
          confidence: 0.91,
          retrieval_mode: "hybrid",
          searched_at: "2026-08-17T12:30:00Z",
          citations: [
            {
              legal_section_id: "section-1",
              source_version_id: "version-1",
              source_title: "Código Tributário Municipal",
              official_identifier: "Lei Complementar nº 399/2024",
              official_url: "https://cordeiropolis.sp.gov.br/legislacao",
              section_key: "artigo_215",
              heading: "Artigo 215",
              excerpt: "O recolhimento observará a legislação municipal vigente.",
              publication_date: "2024-12-20",
              valid_from: "2025-01-01",
              valid_until: null,
              score: 0.91,
            },
          ],
          blockers: [],
        },
      },
      error: null,
    });

    await expect(
      supabaseFiscalService.searchLegalKnowledge("municipality-1", "  Qual é o prazo do ISSQN?  "),
    ).resolves.toMatchObject({
      verified: true,
      municipalityId: "municipality-1",
      answered: true,
      citations: [
        expect.objectContaining({
          sectionId: "section-1",
          sectionKey: "artigo_215",
          isValid: true,
        }),
      ],
    });
    expect(mocks.invoke).toHaveBeenCalledWith(
      "ia-fiscal-knowledge-search",
      expect.objectContaining({
        body: {
          municipality_id: "municipality-1",
          query: "Qual é o prazo do ISSQN?",
          limit: 8,
        },
      }),
    );
  });

  it("bloqueia resposta jurídica quando a função não entrega origem HTTPS verificável", async () => {
    mocks.invoke.mockResolvedValue({
      data: {
        contract_version: "knowledge-search-v1",
        correlation_id: "123e4567-e89b-42d3-a456-426614174000",
        data: {
          verified: true,
          municipality_id: "municipality-1",
          query: "Qual é o prazo do ISSQN?",
          answered: true,
          answer: "Resposta sem origem segura.",
          confidence: 0.9,
          retrieval_mode: "hybrid",
          searched_at: "2026-08-17T12:30:00Z",
          citations: [
            {
              legal_section_id: "section-1",
              source_version_id: "version-1",
              source_title: "Código Tributário Municipal",
              official_identifier: "Lei Complementar nº 399/2024",
              official_url: "http://portal-inseguro.example",
              section_key: "artigo_215",
              heading: "Artigo 215",
              excerpt: "Trecho sem origem segura.",
              publication_date: "2024-12-20",
              valid_from: "2025-01-01",
              valid_until: null,
              score: 0.9,
            },
          ],
          blockers: [],
        },
      },
      error: null,
    });

    await expect(
      supabaseFiscalService.searchLegalKnowledge("municipality-1", "Qual é o prazo do ISSQN?"),
    ).rejects.toThrow("knowledge_search_evidence_unverified");
  });

  it.each([0.3499, null])(
    "recusa envelope respondido abaixo do limiar de confiança (%s)",
    async (confidence) => {
      mocks.invoke.mockResolvedValue({
        data: knowledgeSearchEnvelope(confidence),
        error: null,
      });

      await expect(
        supabaseFiscalService.searchLegalKnowledge("municipality-1", "Qual é o prazo do ISSQN?"),
      ).rejects.toThrow("knowledge_search_evidence_unverified");
    },
  );

  it("aceita exatamente o limiar seguro e preserva a correlação", async () => {
    mocks.invoke.mockResolvedValue({
      data: knowledgeSearchEnvelope(0.35),
      error: null,
    });

    await expect(
      supabaseFiscalService.searchLegalKnowledge("municipality-1", "Qual é o prazo do ISSQN?"),
    ).resolves.toMatchObject({
      answered: true,
      confidence: 0.35,
      correlationId: "123e4567-e89b-42d3-a456-426614174000",
    });
  });

  it("rejeita localmente consultas com 501 caracteres", async () => {
    await expect(
      supabaseFiscalService.searchLegalKnowledge("municipality-1", "x".repeat(501)),
    ).rejects.toThrow("invalid_knowledge_search_query");
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it("envia aprendizado como candidato com confirmação explícita e citações deduplicadas", async () => {
    mocks.rpc.mockResolvedValue({ data: "candidate-1", error: null });

    await expect(
      supabaseFiscalService.submitKnowledgeCandidate("municipality-1", {
        question: "Qual é o prazo do ISSQN?",
        proposedAnswer:
          "O prazo deverá ser confirmado no dispositivo municipal vigente antes da aplicação.",
        citationSectionIds: ["section-1", "section-1"],
        confirmation: "ENVIAR PARA REVISÃO",
      }),
    ).resolves.toBe("candidate-1");
    expect(mocks.rpc).toHaveBeenCalledWith("ia_submit_knowledge_candidate", {
      p_municipality_id: "municipality-1",
      p_question: "Qual é o prazo do ISSQN?",
      p_proposed_answer:
        "O prazo deverá ser confirmado no dispositivo municipal vigente antes da aplicação.",
      p_citation_section_ids: ["section-1"],
      p_confirmation: "ENVIAR PARA REVISÃO",
    });
  });

  it("carrega a proposta candidata integral e preserva a proibição de publicação", async () => {
    mocks.rpc.mockReturnValue(
      rpcChain({
        verified: true,
        checked_at: "2026-08-17T12:00:00Z",
        municipality_id: "municipality-1",
        candidate_id: "candidate-1",
        question: "Qual é o prazo do ISSQN?",
        proposed_answer: "O prazo deve ser conferido no dispositivo municipal vigente.",
        content_sha256: "f".repeat(64),
        status: "pending_review",
        submitted_at: "2026-08-17T11:30:00Z",
        reviewed_at: null,
        citations: [
          {
            legal_section_id: "section-1",
            source_version_id: "version-1",
            source_title: "Código Tributário Municipal",
            official_identifier: "Lei Complementar nº 399/2024",
            official_url: "https://cordeiropolis.sp.gov.br/legislacao",
            section_key: "artigo_215",
            heading: "Artigo 215",
            excerpt: "O recolhimento observará a legislação municipal vigente.",
            publication_date: "2024-12-20",
            valid_from: "2025-01-01",
            valid_until: null,
            score: 0.91,
            is_valid: true,
            blockers: [],
          },
        ],
        evidence_complete: true,
        blockers: [],
        can_review: true,
        can_publish: false,
      }),
    );

    await expect(
      supabaseFiscalService.getKnowledgeCandidateEvidence("municipality-1", "candidate-1"),
    ).resolves.toMatchObject({
      candidateId: "candidate-1",
      evidenceComplete: true,
      canReview: true,
      canPublish: false,
      citations: [expect.objectContaining({ sectionId: "section-1", isValid: true })],
    });
    expect(mocks.rpc).toHaveBeenCalledWith("ia_get_knowledge_candidate_evidence", {
      p_municipality_id: "municipality-1",
      p_candidate_id: "candidate-1",
    });
  });

  it("registra decisão supervisionada do candidato sem promover ou publicar", async () => {
    mocks.rpc.mockResolvedValue({ data: "candidate-review-1", error: null });

    await expect(
      supabaseFiscalService.reviewKnowledgeCandidate(
        "municipality-1",
        "candidate-1",
        "approved",
        "",
        "REVISAR CANDIDATO",
      ),
    ).resolves.toBe("candidate-review-1");
    expect(mocks.rpc).toHaveBeenCalledWith("ia_review_knowledge_candidate", {
      p_expected_municipality_id: "municipality-1",
      p_candidate_id: "candidate-1",
      p_decision: "approved",
      p_notes: null,
      p_confirmation: "REVISAR CANDIDATO",
    });
  });

  it("carrega resposta integral e citações da revisão com escopo municipal explícito", async () => {
    const answerBody = "Resposta integral fundamentada.";
    mocks.rpc.mockReturnValue(
      rpcChain({
        verified: true,
        municipality_id: "municipality-1",
        article_id: "article-1",
        revision_id: "revision-1",
        content_sha256: "a".repeat(64),
        canonical_question: "Qual é a orientação aplicável?",
        answer_body: answerBody,
        answer_length: Array.from(answerBody).length,
        citation_count: 1,
        citations: [knowledgeCitationRow()],
        evidence_complete: true,
        blockers: ["article_not_approved"],
      }),
    );

    await expect(
      supabaseFiscalService.getKnowledgeArticleEvidence(
        "municipality-1",
        "article-1",
        "revision-1",
      ),
    ).resolves.toMatchObject({
      verified: true,
      municipalityId: "municipality-1",
      answerBody,
      citationCount: 1,
      citations: [expect.objectContaining({ sourceTitle: "Código Tributário Municipal" })],
    });
    expect(mocks.rpc).toHaveBeenCalledWith("ia_get_knowledge_article_evidence", {
      p_municipality_id: "municipality-1",
      p_article_id: "article-1",
      p_revision_id: "revision-1",
    });
  });

  it("carrega uma página de evidência da fonte e valida a integridade da paginação", async () => {
    const contentText = "x".repeat(20_000);
    mocks.rpc.mockReturnValue(
      rpcChain({
        verified: true,
        municipality_id: "municipality-1",
        change_set_id: "change-1",
        change_type: "initial_document",
        status: "detected",
        source_id: "source-1",
        source_title: "Código Tributário Municipal",
        official_identifier: "Lei Complementar nº 399/2024",
        official_url: "https://cordeiropolis.sp.gov.br/legislacao",
        requested_url: "https://cordeiropolis.sp.gov.br/legislacao",
        captured_url: "https://cordeiropolis.sp.gov.br/legislacao",
        observed_at: "2026-08-17T12:00:00Z",
        artifact_id: "artifact-1",
        artifact_mime_type: "text/html",
        artifact_byte_size: 512,
        raw_content_sha256: "a".repeat(64),
        from_sha256: null,
        to_sha256: "a".repeat(64),
        diff_sha256: "b".repeat(64),
        diff_summary: "Primeiro documento oficial identificado.",
        change_items: [
          {
            ordinal: 1,
            item_kind: "document_hash",
            item_path: "documento_oficial",
            before_sha256: null,
            after_sha256: "a".repeat(64),
            before_excerpt: null,
            after_excerpt: "Conteúdo oficial integral.",
            summary: "Documento capturado pela primeira vez.",
          },
        ],
        change_item_offset: 0,
        change_item_limit: 25,
        change_item_total: 1,
        change_items_has_more: false,
        change_items_full_sha256: "e".repeat(64),
        candidate_version_id: "version-1",
        candidate_version_number: 1,
        candidate_version_status: "under_review",
        content_sha256: "c".repeat(64),
        publication_date: "2024-12-20",
        valid_from: "2025-01-01",
        valid_until: null,
        content_text: contentText,
        content_offset: 0,
        content_limit: 20000,
        content_total_chars: Array.from(contentText).length + 1,
        content_has_more: true,
        sections: [
          {
            section_id: "section-1",
            section_key: "documento_integral",
            heading: "Documento oficial",
            ordinal: 1,
            content_preview: contentText,
            content_total_chars: Array.from(contentText).length,
            content_sha256: "d".repeat(64),
            chunk_count: 1,
          },
        ],
        section_offset: 0,
        section_limit: 25,
        section_total: 1,
        section_has_more: false,
        evidence_complete: true,
        blockers: ["source_review_required"],
      }),
    );

    await expect(
      supabaseFiscalService.getLegalSourceChangeEvidence("municipality-1", "change-1"),
    ).resolves.toMatchObject({
      verified: true,
      contentText,
      contentHasMore: true,
      sectionHasMore: false,
      sections: [expect.objectContaining({ heading: "Documento oficial" })],
    });
    expect(mocks.rpc).toHaveBeenCalledWith("ia_get_legal_source_change_evidence", {
      p_municipality_id: "municipality-1",
      p_change_set_id: "change-1",
      p_content_offset: 0,
      p_content_limit: 20000,
      p_section_offset: 0,
      p_section_limit: 25,
      p_change_item_offset: 0,
      p_change_item_limit: 25,
    });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
  });

  it("trata resposta incompleta de segurança como estado inválido", async () => {
    mocks.rpc.mockReturnValue(rpcChain({ verified: true }));

    await expect(
      supabaseFiscalService.getAssistedOperationSafetyStatus("municipality-1"),
    ).rejects.toThrow("safety_status_invalid");
  });

  it("compartilha o relatório enquanto a mesma consulta municipal está em andamento", async () => {
    let release: ((value: { data: unknown; error: null }) => void) | undefined;
    const pending = new Promise<{ data: unknown; error: null }>((resolve) => {
      release = resolve;
    });
    mocks.rpc.mockReturnValue({ abortSignal: vi.fn(() => pending) });

    const first = supabaseFiscalService.getOperationalReport("municipality-dedup");
    const second = supabaseFiscalService.getOperationalReport("municipality-dedup");

    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    release?.({ data: { taxpayer_count: 2 }, error: null });
    await expect(Promise.all([first, second])).resolves.toEqual([
      expect.objectContaining({ taxpayerCount: 2 }),
      expect.objectContaining({ taxpayerCount: 2 }),
    ]);
  });

  it("mapeia regra explicativa e motivos de bloqueio em JSON", async () => {
    const chain = readChain([
      {
        municipality_id: "municipality-1",
        divergence_id: "divergence-1",
        rule_code: "CURRENT_ACCOUNT_BALANCE_HOMOLOGATION_V1",
        rule_name: "Conferência do saldo da conta corrente",
        rule_description: "Compara lançamentos, pagamentos e saldo em aberto.",
        block_reasons: '[{"code":"unverification"}]',
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.listDivergences("municipality-1")).resolves.toEqual([
      expect.objectContaining({
        ruleName: "Conferência do saldo da conta corrente",
        ruleDescription: "Compara lançamentos, pagamentos e saldo em aberto.",
        blockReasons: ["unverification"],
      }),
    ]);
  });

  it("exclui conteúdo de teste da biblioteca produtiva", async () => {
    const chain = readChain([]);
    mocks.from.mockReturnValue(chain);

    await supabaseFiscalService.listKnowledgeArticles("municipality-1");

    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(chain.eq).toHaveBeenCalledWith("is_test", false);
  });

  it("mapeia a biblioteca somente com citação oficial verificável do mesmo município", async () => {
    const chain = readChain([
      {
        municipality_id: "municipality-1",
        article_id: "article-1",
        revision_id: "revision-1",
        intent_key: "consulta_debito",
        semantic_version: 1,
        canonical_question: "Como consultar a composição do débito?",
        tax_scope: "ISSQN",
        divergence_scope: "current_account_balance",
        answer_body: "Consulte a composição no ambiente autenticado.",
        valid_from: "2025-01-01",
        valid_until: null,
        published_at: "2026-08-17T10:00:00Z",
        is_test: false,
        citations: [knowledgeCitationRow()],
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(
      supabaseFiscalService.listKnowledgeArticles("municipality-1"),
    ).resolves.toMatchObject([
      {
        municipalityId: "municipality-1",
        revisionId: "revision-1",
        citations: [
          expect.objectContaining({
            sourceTitle: "Código Tributário Municipal",
            officialUrl: "https://cordeiropolis.sp.gov.br/legislacao",
          }),
        ],
      },
    ]);
  });

  it("bloqueia artigo da biblioteca quando a origem da citação não é HTTPS", async () => {
    const chain = readChain([
      {
        municipality_id: "municipality-1",
        article_id: "article-1",
        revision_id: "revision-1",
        intent_key: "consulta_debito",
        semantic_version: 1,
        canonical_question: "Como consultar a composição do débito?",
        tax_scope: "ISSQN",
        divergence_scope: "current_account_balance",
        answer_body: "Consulte a composição no ambiente autenticado.",
        valid_from: "2025-01-01",
        valid_until: null,
        published_at: "2026-08-17T10:00:00Z",
        is_test: false,
        citations: [knowledgeCitationRow({ official_url: "http://portal-inseguro.example" })],
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.listKnowledgeArticles("municipality-1")).rejects.toThrow(
      "knowledge_article_evidence_unverified",
    );
  });

  it("registra revisão de fonte somente pela RPC governada com confirmação e vigência", async () => {
    mocks.rpc.mockResolvedValue({ data: "review-1", error: null });

    await expect(
      supabaseFiscalService.reviewLegalSourceChange(
        "municipality-1",
        "change-1",
        "approved",
        "Conferência jurídica concluída.",
        "REVISAR",
        { publicationDate: "2024-12-20", validFrom: "2025-01-01", validUntil: null },
      ),
    ).resolves.toBe("review-1");

    expect(mocks.rpc).toHaveBeenCalledWith("ia_review_legal_source_change", {
      p_expected_municipality_id: "municipality-1",
      p_change_set_id: "change-1",
      p_decision: "approved",
      p_review_notes: "Conferência jurídica concluída.",
      p_confirmation: "REVISAR",
      p_publication_date: "2024-12-20",
      p_valid_from: "2025-01-01",
      p_valid_until: null,
    });
  });

  it("envia REVISAR à RPC governada de revisão do artigo", async () => {
    mocks.rpc.mockResolvedValue({ data: "review-article-1", error: null });

    await expect(
      supabaseFiscalService.reviewKnowledgeArticle(
        "municipality-1",
        "article-1",
        "revision-1",
        "approved",
        "Fundamentação conferida.",
        "REVISAR",
      ),
    ).resolves.toBe("review-article-1");
    expect(mocks.rpc).toHaveBeenCalledWith("ia_review_knowledge_article", {
      p_expected_municipality_id: "municipality-1",
      p_article_id: "article-1",
      p_revision_id: "revision-1",
      p_decision: "approved",
      p_notes: "Fundamentação conferida.",
      p_confirmation: "REVISAR",
    });
  });

  it("publica versão legal somente com o município esperado explícito", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: null });

    await expect(
      supabaseFiscalService.publishLegalSourceVersion(
        "municipality-1",
        "source-version-1",
        "PUBLICAR",
      ),
    ).resolves.toBeUndefined();
    expect(mocks.rpc).toHaveBeenCalledWith("ia_publish_legal_source_version", {
      p_expected_municipality_id: "municipality-1",
      p_source_version_id: "source-version-1",
      p_confirmation: "PUBLICAR",
    });
  });

  it("publica artigo somente com o município esperado explícito", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: null });

    await expect(
      supabaseFiscalService.publishKnowledgeArticle("municipality-1", "article-1", "PUBLICAR"),
    ).resolves.toBeUndefined();
    expect(mocks.rpc).toHaveBeenCalledWith("ia_publish_knowledge_article", {
      p_expected_municipality_id: "municipality-1",
      p_article_id: "article-1",
      p_confirmation: "PUBLICAR",
    });
  });

  it.each([
    [
      "resumos de contribuinte",
      "vw_taxpayer_360_summary",
      () => supabaseFiscalService.listTaxpayerSummaries("municipality-1"),
    ],
    [
      "períodos de débito",
      "vw_taxpayer_360_debts",
      () => supabaseFiscalService.listDebtPeriods("municipality-1"),
    ],
    [
      "divergências",
      "vw_taxpayer_360_divergences",
      () => supabaseFiscalService.listDivergences("municipality-1"),
    ],
    [
      "casos fiscais",
      "vw_taxpayer_360_cases",
      () => supabaseFiscalService.listFiscalCaseRows("municipality-1"),
    ],
    [
      "destinatários",
      "vw_notification_recipient_candidates",
      () => supabaseFiscalService.listNotificationRecipients("municipality-1"),
    ],
    [
      "conhecimento",
      "vw_reusable_knowledge_articles",
      () => supabaseFiscalService.listKnowledgeArticles("municipality-1"),
    ],
    [
      "portal",
      "vw_case_portal_home",
      () => supabaseFiscalService.listPortalCases("municipality-1"),
    ],
    ["eventos", "case_events", () => supabaseFiscalService.listAuditEvents("municipality-1")],
  ])("fixa municipality_id em %s", async (_label, table, run) => {
    const chain = readChain([]);
    mocks.from.mockReturnValue(chain);

    await run();

    expect(mocks.from).toHaveBeenCalledWith(table);
    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
  });

  it("mantém a saúde do worker como leitura global sem coluna municipal", async () => {
    const chain = readChain([]);
    mocks.from.mockReturnValue(chain);

    await supabaseFiscalService.listProcessingHealth();

    expect(mocks.from).toHaveBeenCalledWith("api_worker_health");
    expect(chain.eq).not.toHaveBeenCalled();
  });

  it("apresenta o status do worker em português", async () => {
    const chain = readChain([
      {
        worker_name: "divergence-worker",
        status: "unhealthy",
        pending_jobs: 4,
        dead_letter_jobs: 2,
        last_success_at: "2026-08-11T15:30:00Z",
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.listProcessingHealth()).resolves.toEqual([
      expect.objectContaining({
        label: "Processador de divergências fiscais",
        status: "critico",
        detail: "Situação: Crítico · Pendentes: 4 · Falhas definitivas: 2",
        metric: expect.stringMatching(/^Último processamento: 11\/08\/2026/),
      }),
    ]);
  });

  it("traduz o tipo e a visibilidade dos eventos", async () => {
    const chain = readChain([
      {
        id: 10,
        event_type: "case_question_claimed",
        visibility: "staff",
        occurred_at: "2026-08-11T12:00:00Z",
      },
    ]);
    mocks.from.mockReturnValue(chain);

    await expect(supabaseFiscalService.listAuditEvents("municipality-1")).resolves.toEqual([
      expect.objectContaining({
        title: "Atendimento assumido pela equipe fiscal",
        description: "Evento auditável visível para equipe fiscal.",
      }),
    ]);
  });

  it("normaliza finalidade e bloqueio das notificações do dashboard", async () => {
    const recipientChain = readChain([
      {
        municipality_id: "municipality-1",
        taxpayer_id: "taxpayer-1",
        candidate_id: "candidate-1",
        proposed_for: "initial_notice",
        candidate_status: "blocked_unverified",
        delivery_block_reason: "relationship_unverified;external_delivery_not_authorized",
        safe_for_delivery: false,
      },
    ]);
    const summaryChain = readChain([
      {
        municipality_id: "municipality-1",
        taxpayer_id: "taxpayer-1",
        legal_name: "Comercial Cordeirópolis Ltda.",
        tax_id: "12345678000190",
        municipal_registration: "12345",
      },
    ]);
    mocks.from.mockImplementation((table: string) => {
      if (table === "vw_notification_recipient_candidates") return recipientChain;
      if (table === "vw_taxpayer_360_summary") return summaryChain;
      throw new Error(`Tabela inesperada no teste: ${table}`);
    });

    await expect(
      supabaseFiscalService.listNotificationCandidates("municipality-1"),
    ).resolves.toEqual([
      expect.objectContaining({
        taxpayerName: "Comercial Cordeirópolis Ltda.",
        cnpj: "12345678000190",
        templateName: "Aviso inicial de conferência",
        blockedReason:
          "Vínculo com o contribuinte ainda não verificado · Envio externo não autorizado",
      }),
    ]);
    expect(recipientChain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(summaryChain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
  });

  it("usa fallback claro sem expor o identificador interno quando não há cadastro visível", async () => {
    const recipientChain = readChain([
      {
        municipality_id: "municipality-1",
        taxpayer_id: "taxpayer-internal-uuid",
        candidate_id: "candidate-1",
        proposed_for: "initial_notice",
      },
    ]);
    const summaryChain = readChain([]);
    mocks.from.mockImplementation((table: string) =>
      table === "vw_notification_recipient_candidates" ? recipientChain : summaryChain,
    );

    const [candidate] = await supabaseFiscalService.listNotificationCandidates("municipality-1");

    expect(candidate).toMatchObject({
      taxpayerName: "Cadastro do contribuinte não disponível",
      cnpj: "Inscrição não disponível",
    });
    expect(JSON.stringify(candidate)).not.toContain("taxpayer-internal-uuid");
  });

  it("rejeita leitura municipal sem contexto explícito", async () => {
    await expect(supabaseFiscalService.listTaxpayerSummaries(" ")).rejects.toThrow(
      "invalid_municipality_id",
    );
    expect(mocks.from).not.toHaveBeenCalled();
  });

  it("mapeia a fila com vínculo de caso e prioridade operacional pelo SLA", async () => {
    const chain = readChain([
      {
        question_id: "question-1",
        municipality_id: "municipality-1",
        case_id: "case-1",
        case_number: "FIS-001",
        taxpayer_name: "Contribuinte protegido",
        question_preview: "Pergunta",
        created_at: "2026-08-01T10:00:00-03:00",
        sla_due_at: "2020-01-01T00:00:00Z",
        status: "submitted",
        handling_mode: null,
        assigned_membership_id: null,
        claimed_at: null,
      },
    ]);
    mocks.from.mockReturnValue(chain);

    const result = await supabaseFiscalService.listChatQueue("municipality-1");

    expect(mocks.from).toHaveBeenCalledWith("vw_fiscal_chat_inbox");
    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(chain.in).toHaveBeenCalledWith("status", ["waiting", "claimed"]);
    expect(chain.order).toHaveBeenCalledWith("operational_priority", { ascending: false });
    expect(chain.order).toHaveBeenCalledWith("sla_due_at", {
      ascending: true,
      nullsFirst: false,
    });
    expect(result[0]).toMatchObject({
      id: "question-1",
      municipalityId: "municipality-1",
      caseId: "case-1",
      caseNumber: "FIS-001",
      priority: "critico",
      handlingMode: "unassigned",
      assignedMembershipId: null,
    });
  });

  it("consulta somente a conversa do caso solicitado", async () => {
    const chain = readChain([
      {
        id: "message-newest",
        case_id: "case-1",
        body: "Mensagem mais recente",
        sender_type: "fiscal",
        source_type: "manual",
        status: "published",
        visibility: "participants",
        created_at: "2026-08-01T11:00:00-03:00",
        published_at: "2026-08-01T11:00:00-03:00",
      },
      {
        id: "message-1",
        case_id: "case-1",
        body: "Mensagem autorizada",
        sender_type: "taxpayer",
        source_type: "portal",
        status: "published",
        visibility: "participants",
        created_at: "2026-08-01T10:00:00-03:00",
        published_at: "2026-08-01T10:00:00-03:00",
      },
    ]);
    mocks.from.mockReturnValue(chain);

    const result = await supabaseFiscalService.listCaseMessages("municipality-1", "case-1");

    expect(mocks.from).toHaveBeenCalledWith("case_messages");
    expect(chain.eq).toHaveBeenCalledWith("municipality_id", "municipality-1");
    expect(chain.eq).toHaveBeenCalledWith("case_id", "case-1");
    expect(chain.order).toHaveBeenCalledWith("created_at", { ascending: false });
    expect(result.map((message) => message.body)).toEqual([
      "Mensagem autorizada",
      "Mensagem mais recente",
    ]);
  });

  it("chama somente a RPC de atribuição humana e exige membership no retorno", async () => {
    mocks.rpc.mockResolvedValue({ data: "membership-1", error: null });

    await expect(
      supabaseFiscalService.claimCaseQuestion(
        "question-1",
        "municipality-1",
        "membership-1",
        "human",
      ),
    ).resolves.toBe("membership-1");
    expect(mocks.rpc).toHaveBeenCalledWith("ia_claim_case_question", {
      p_question_id: "question-1",
      p_expected_municipality_id: "municipality-1",
      p_expected_membership_id: "membership-1",
      p_handling_mode: "human",
    });
  });
});
