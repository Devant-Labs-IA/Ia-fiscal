const STATUS_LABELS: Record<string, string> = {
  active: "Ativa",
  accepted: "Revisão aprovada",
  attention: "Requer atenção",
  attention_required: "Intervenção necessária",
  approved: "Aprovada",
  available: "Disponível",
  blocked: "Bloqueada",
  changed: "Alteração detectada",
  changes_requested: "Ajustes solicitados",
  collected: "Coleta concluída",
  completed_changed: "Coleta concluída com mudança",
  completed_unchanged: "Coleta concluída sem mudança",
  current: "Vigente",
  draft: "Rascunho",
  error: "Falha na coleta",
  failed: "Falha na coleta",
  expired: "Vigência encerrada",
  healthy: "Operacional",
  inactive: "Inativa",
  not_collected: "Coleta não realizada",
  not_configured: "Coleta não configurada",
  not_checked: "Verificação não realizada",
  never_run: "Ainda não executada",
  pending: "Pendente",
  pending_review: "Aguardando revisão",
  processing: "Em processamento",
  queued: "Na fila",
  paused: "Pausada",
  published: "Publicada",
  rejected: "Rejeitada",
  ready: "Pronta",
  retired: "Substituída",
  revision_requested: "Ajustes solicitados",
  revoked: "Revogada",
  stale: "Desatualizada",
  success: "Coleta concluída",
  under_review: "Em revisão",
  unavailable: "Indisponível",
  unknown: "Estado não verificado",
  warning: "Requer atenção",
};

const SOURCE_TYPE_LABELS: Record<string, string> = {
  court_decision: "Decisão judicial",
  decree: "Decreto",
  instruction: "Instrução normativa",
  law: "Lei",
  official_guidance: "Orientação oficial",
  regulation: "Regulamento",
};

const CHANGE_TYPE_LABELS: Record<string, string> = {
  content_changed: "Conteúdo oficial alterado",
  first_version: "Primeira versão identificada",
  initial_document: "Primeiro documento identificado",
  legacy_import: "Documento oficial importado",
  metadata_changed: "Dados da fonte alterados",
  source_unavailable: "Fonte oficial indisponível",
  version_detected: "Nova versão identificada",
};

const BLOCKER_LABELS: Record<string, string> = {
  aal2_required: "Autenticação em duas etapas necessária",
  active_membership_required: "Vínculo municipal ativo necessário",
  article_not_approved: "O artigo ainda não foi aprovado",
  citation_required: "É necessária ao menos uma citação oficial",
  collection_failed: "A última coleta falhou",
  collection_not_verified: "A coleta da fonte ainda não foi verificada",
  current_legal_reviewer_role_required: "Papel atual de revisor jurídico necessário",
  expired_source: "A fonte citada está fora da vigência",
  legal_reviewer_required: "Revisão jurídica necessária",
  legal_body_extraction_required:
    "O texto integral da norma ainda precisa ser extraído e conferido",
  legacy_recapture_required: "A versão anterior precisa ser recapturada pela esteira oficial",
  missing_official_url: "Endereço oficial não cadastrado",
  no_eligible_legal_sections:
    "Nenhum dispositivo oficial publicado e vigente está disponível para indexação",
  no_published_source_version: "Nenhuma versão oficial publicada",
  source_hash_changed: "O conteúdo oficial mudou após a revisão",
  source_not_published: "A fonte citada ainda não foi publicada",
  source_not_current: "A fonte oficial não está vigente para publicação",
  source_review_required: "A versão da fonte precisa de revisão jurídica",
  source_publication_required: "A versão aprovada aguarda publicação explícita",
  stale_source: "A fonte oficial precisa de nova verificação",
  endpoint_unavailable: "O endereço oficial não respondeu à verificação",
  fetch_failed: "A coleta automática não foi concluída",
  candidate_version_missing: "A alteração ainda não gerou uma versão candidata",
  approved_review_required: "É necessária uma revisão jurídica aprovada",
  hash_mismatch: "O conteúdo mudou depois da revisão",
  test_content: "Conteúdo de teste não pode ser publicado",
  unverified_state: "Estado operacional não verificado",
  knowledge_index_pending: "Há dispositivos oficiais aguardando indexação para a busca inteligente",
  knowledge_index_incomplete:
    "Há dispositivos oficiais vigentes ainda não disponíveis na busca inteligente",
  knowledge_index_inconsistent:
    "A contagem do índice é incompatível com os dispositivos oficiais elegíveis",
  knowledge_runtime_not_verified:
    "O ambiente de execução da atualização automática ainda não foi verificado",
  knowledge_ocr_runtime_not_verified: "O ambiente seguro de OCR jurídico ainda não foi atestado",
  knowledge_ocr_jobs_failed:
    "Há documentos digitalizados que exigem intervenção antes de uma nova tentativa",
  knowledge_ocr_page_limit_exceeded:
    "Há documentos acima do limite de 120 páginas desta versão e que exigem tratamento manual",
  knowledge_schedule_timezone_not_verified:
    "O fuso horário da agenda automática não pôde ser validado",
  knowledge_schedule_next_run_not_verified:
    "A próxima execução da agenda automática não pôde ser validada",
  legal_reviewer_not_configured: "Nenhum revisor jurídico ativo foi configurado",
  reviewer_state_not_verified: "A configuração dos revisores jurídicos não foi verificada",
  demo_runtime_simulated: "A atualização automática está apenas simulada neste ambiente",
  upstream_siscam_503: "O catálogo oficial Siscam respondeu com indisponibilidade temporária (503)",
  upstream_http_403: "O portal oficial recusou a coleta automatizada (403)",
  upstream_http_502: "O portal oficial respondeu com falha temporária (502)",
  upstream_http_503: "O portal oficial respondeu com indisponibilidade temporária (503)",
  upstream_fetch_failed: "Não foi possível consultar o catálogo no portal oficial",
  large_or_legacy_attachment_extractor_required:
    "O anexo oficial exige um extrator específico para arquivos grandes ou antigos",
  validated_cutover_required:
    "O novo anexo oficial aguarda captura e validação integral antes de substituir a fonte atual",
  insufficient_relevance:
    "Os dispositivos encontrados não têm aderência suficiente para sustentar uma resposta",
  answer_generation_failed:
    "A síntese não pôde ser gerada com segurança; as evidências permanecem disponíveis para análise",
};

const HEALTH_LABELS: Record<string, string> = {
  article_citations: "Citações dos artigos",
  collection: "Coleta das fontes oficiais",
  embeddings: "Índice de busca inteligente",
  legal_sources: "Fontes legais vigentes",
  publication: "Publicação governada",
  source_freshness: "Atualização das fontes",
};

export function knowledgeStatusLabel(value: string | null | undefined): string {
  if (!value) return "Estado não verificado";
  return STATUS_LABELS[value] ?? "Estado não reconhecido";
}

export function knowledgeSourceTypeLabel(value: string): string {
  return SOURCE_TYPE_LABELS[value] ?? "Documento oficial";
}

export function knowledgeChangeTypeLabel(value: string): string {
  return CHANGE_TYPE_LABELS[value] ?? "Alteração oficial detectada";
}

export function knowledgeBlockerLabel(value: string): string {
  const known = BLOCKER_LABELS[value];
  if (known) return known;
  return "Bloqueio operacional não classificado";
}

export function knowledgeHealthLabel(key: string, fallback: string): string {
  return HEALTH_LABELS[key] ?? (fallback || "Verificação operacional");
}

export function knowledgeReviewDecisionLabel(value: string): string {
  if (value === "approved") return "Aprovar conteúdo";
  if (value === "revision_requested") return "Solicitar ajustes";
  if (value === "rejected") return "Rejeitar conteúdo";
  return "Revisar conteúdo";
}

export function knowledgeFailureLabel(value: string | null): string {
  if (!value) return "Nenhuma falha registrada";
  if (/timeout/i.test(value)) return "O portal oficial demorou além do limite de coleta";
  if (/not_found|404/i.test(value)) return "O documento oficial não foi localizado";
  if (/forbidden|unauthorized|401|403/i.test(value)) {
    return "O portal oficial recusou a consulta automatizada";
  }
  if (/network|connection|fetch/i.test(value)) return "Falha de conexão com o portal oficial";
  if (/hash|content_changed/i.test(value)) return "O conteúdo oficial mudou e requer revisão";
  return "A coleta não foi concluída; a fonte permanece bloqueada para publicação";
}
