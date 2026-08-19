import { describe, expect, it } from "vitest";

import {
  knowledgeBlockerLabel,
  knowledgeSourceTypeLabel,
  knowledgeStatusLabel,
} from "@/features/knowledge/knowledge-labels";

describe("rótulos operacionais do Segundo Cérebro", () => {
  it("traduz situações e tipos sem expor nomes técnicos", () => {
    expect(knowledgeStatusLabel("under_review")).toBe("Em revisão");
    expect(knowledgeSourceTypeLabel("official_guidance")).toBe("Orientação oficial");
    expect(knowledgeBlockerLabel("citation_required")).toBe(
      "É necessária ao menos uma citação oficial",
    );
    expect(knowledgeBlockerLabel("legal_body_extraction_required")).toBe(
      "O texto integral da norma ainda precisa ser extraído e conferido",
    );
    expect(knowledgeBlockerLabel("legacy_recapture_required")).toBe(
      "A versão anterior precisa ser recapturada pela esteira oficial",
    );
    expect(knowledgeBlockerLabel("source_not_current")).toBe(
      "A fonte oficial não está vigente para publicação",
    );
    expect(knowledgeBlockerLabel("source_publication_required")).toBe(
      "A versão aprovada aguarda publicação explícita",
    );
    expect(knowledgeBlockerLabel("validated_cutover_required")).toBe(
      "O novo anexo oficial aguarda captura e validação integral antes de substituir a fonte atual",
    );
    expect(knowledgeStatusLabel("attention")).toBe("Requer atenção");
    expect(knowledgeStatusLabel("never_run")).toBe("Ainda não executada");
    expect(knowledgeStatusLabel("queued")).toBe("Na fila");
    expect(knowledgeBlockerLabel("knowledge_ocr_runtime_not_verified")).toBe(
      "O ambiente seguro de OCR jurídico ainda não foi atestado",
    );
    expect(knowledgeBlockerLabel("knowledge_ocr_page_limit_exceeded")).toBe(
      "Há documentos acima do limite de 120 páginas desta versão e que exigem tratamento manual",
    );
  });

  it("fecha com segurança códigos desconhecidos", () => {
    expect(knowledgeStatusLabel("internal_status_v9")).toBe("Estado não reconhecido");
    expect(knowledgeSourceTypeLabel("internal_source_v9")).toBe("Documento oficial");
    expect(knowledgeBlockerLabel("internal_blocker_v9")).toBe(
      "Bloqueio operacional não classificado",
    );
    expect(knowledgeBlockerLabel("Mensagem arbitrária enviada pelo servidor")).toBe(
      "Bloqueio operacional não classificado",
    );
  });
});
