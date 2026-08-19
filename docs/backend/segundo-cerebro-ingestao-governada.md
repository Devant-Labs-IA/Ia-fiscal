# Segundo Cérebro Fiscal — ingestão governada

> Estado atual: a Fase 2 acrescenta PDF integral, descoberta catalográfica de
> DOCX, embeddings, busca híbrida, catálogos paginados e agenda com runtime
> gate. A sequência de release e os limites atuais estão em
> [knowledge-phase2-release.md](../runbooks/knowledge-phase2-release.md).

## Objetivo

Esta fase cria a esteira de entrada das fontes oficiais de Cordeirópolis e
Araras. A coleta automática registra evidências e prepara versões para revisão;
ela não aprova, não publica e não transforma respostas de IA em conhecimento.

O fluxo é:

1. O coletor consulta somente os endereços HTTPS cadastrados na allowlist
   privada.
2. O arquivo bruto é salvo no bucket privado `legal-source-artifacts`.
3. O banco registra execução, hash, metadados HTTP e artefato imutáveis.
4. Hash bruto novo cria um conjunto de mudanças. Endpoints de catálogo não
   criam versão, seção ou chunk e permanecem com
   `legal_body_extraction_required`.
5. Somente um endpoint previamente promovido para `legal_body` e
   `citable_body=true`, após parser e smoke test específicos, pode fornecer
   texto. Nesse caso o RPC v2 cria, na mesma transação, a versão `under_review`,
   a seção integral e os chunks determinísticos em `legal_sections` e
   `private.legal_chunks`.
6. Um `legal_reviewer` do mesmo município, autenticado em AAL2, registra a
   decisão e a vigência.
7. A aprovação não publica. Uma segunda ação, com confirmação literal
   `PUBLICAR`, publica a versão revisada.

## Limites de segurança

- `service_role` pode listar endpoints, registrar coleta/falha e preparar
  seções por RPC. Não possui escrita direta nas tabelas legais e não pode
  executar revisão ou publicação.
- Funções humanas exigem usuário autenticado, AAL2, vínculo municipal ativo e
  papel compatível. Administração da plataforma não substitui autoridade
  jurídica municipal.
- `municipal_admin` pode consultar a biblioteca e suas citações no próprio
  município em AAL2, mas não pode revisar nem publicar conhecimento ou norma.
- Redirecionamentos são aceitos apenas quando o host final consta na allowlist
  do endpoint.
- DOCX não é extraído nesta release. O Edge Runtime hospedado não oferece Web
  Worker nem `vm`, e `Promise.race` não cancela o parser subjacente. Por isso o
  MIME é removido da interface de endpoints ativos; respostas DOCX declaradas
  são canceladas antes da leitura e ZIP recebido como octet-stream é recusado
  antes de parser/descompressão com `source_docx_disabled_edge_runtime`. Links
  DOCX continuam apenas como descoberta catalográfica; mesmo um cadastro que
  ainda liste esse MIME é filtrado pela Edge antes da coleta.
- Artefatos, execuções, itens de diferença e revisões são append-only. Linhas e
  objetos do bucket são WORM: nem `service_role` pode atualizar, apagar ou
  truncar a evidência bruta.
- Os privilégios de `TRUNCATE` do esquema Storage pertencem ao papel interno do
  serviço e não podem ser revogados pelo executor de migrações. Por isso,
  triggers `BEFORE TRUNCATE` bloqueiam em tempo de execução o esvaziamento
  global de `storage.objects` e `storage.buckets`, inclusive por
  `service_role`.
- URL/identidade da fonte, texto, hash, versão, seções e chunks são imutáveis;
  triggers conferem `SHA-256(texto) = content_sha256` em toda nova escrita.
- Uma mudança de conteúdo nunca altera a versão publicada. Ela cria uma nova
  versão em revisão.
- Conteúdo de homologação (`knowledge_articles.is_test`) foi excluído da view
  reutilizável e da fila operacional.
- Ausência de vigência, publicação, seções, chunks ou revisão correspondente ao
  hash mantém a publicação bloqueada.
- Uma fonte com vigência futura ou já encerrada não pode fundamentar artigo
  reutilizável, ainda que a versão esteja publicada.
- Revisão e publicação recusam publicação futura, vigência futura, vigência
  encerrada e fonte aposentada antes de substituir qualquer versão vigente.
- Datas legais usam o fuso configurado no município, e não o `current_date` UTC
  do banco. `valid_until` é inclusiva: a norma continua vigente no último dia.
- Publicações são serializadas pela identidade compartilhada da fonte ou do
  `intent_key`, com unicidade parcial para impedir duas versões ativas em uma
  corrida concorrente.

## Contrato do coletor

### Listar endpoints

`ia_fiscal_get_knowledge_source_endpoints()` — somente `service_role`.

Retorna somente endpoints `active`, com `endpoint_id`, município, fonte, URL
exata, nível de confiança, tipo e situação do endpoint, `content_mode`,
`citable_body`, `activation_blocker`, parser sugerido, tipos MIME aceitos e
hosts permitidos. Há no máximo um endpoint ativo por fonte; representações
secundárias ficam catalogadas como `paused`.

### Registrar captura

`ia_fiscal_capture_knowledge_source_v2(...)` — somente `service_role`. A
assinatura de captura da Fase 1 fica revogada após a migration do core v2.

O documento deve ser enviado antes ao bucket privado, no prefixo:

```text
<municipality_slug>/<source_id>/<sha256>/<nome-seguro>
```

Retorno:

```json
{
  "fetch_run_id": "uuid",
  "artifact_id": "uuid",
  "status": "captured | already_exists",
  "processing_status": "under_review | requires_extraction",
  "change_set_id": "uuid | null",
  "candidate_version_id": "uuid | null",
  "staging_status": "staged | already_staged | not_applicable",
  "staged_sections": 1,
  "staged_chunks": 2
}
```

A correlação e o hash tornam a operação idempotente. Repetir a mesma captura
não cria outra versão nem outro conjunto de mudanças e devolve os identificadores
e contagens existentes para que um processamento interrompido possa ser
retomado. O RPC compara o payload de seção/chunks à evidência já persistida e
recusa replay divergente. Um novo
artefato bruto que produz exatamente o mesmo hash de texto é associado à versão
canônica existente, sem criar uma falsa mudança semântica. Mudança realmente
nova encerra como `superseded` a pendência anterior da mesma fonte.

Captura, fetch run, artefato, versão, change set, seção e chunks são uma única
transação de banco. O staging grosseiro da Fase 1 é diferido somente dentro
dessa chamada e o payload final é gravado uma vez. Se qualquer chunk falhar,
nenhuma dessas linhas da tentativa de captura permanece. O upload WORM ocorre
antes do RPC; portanto, uma recusa do banco pode deixar o objeto órfão. Quando
o staging atômico falha, a Edge grava em transação separada exatamente um fetch
run final `failed`, com `safe_error_code=capture_rpc_failed`, idempotente pela
correlação, bucket, path, SHA-256 e disposição
`preserved_for_reconciliation`. Não há artefato de banco, versão, change set,
seção ou chunk parcial. Bloqueios anteriores ao RPC continuam terminais como
`blocked`. Falha posterior a uma captura confirmada preserva o run concluído e
não tenta gravar outro run conflitante.

O RPC exige que o objeto já exista no bucket, que metadados MIME/tamanho sejam
coerentes e que a extração declare explicitamente completude, ausência de
truncamento e contagem exata de caracteres. O banco nunca aceita texto em um
endpoint `catalog_only`.

### Registrar falha

`ia_fiscal_record_knowledge_fetch_failure(...)` — somente `service_role`.

Recebe apenas código e detalhe sanitizados. Falhas de host, caminho, redirect,
MIME, tamanho ou integridade são classificadas como `blocked`.

### Preparar seções

`ia_fiscal_stage_knowledge_sections(p_change_set_id, p_sections)` permanece
service-only para retomada governada. A implementação legada subjacente não é
executável pela API; a Edge de ingestão não chama o staging separadamente.

Cada item contém `section_key`, `heading`, `ordinal`, `content_text` e,
opcionalmente, `chunks`. Se chunks não forem enviados, o próprio conteúdo da
seção é cadastrado como um único trecho lexical. Uma repetição idêntica retorna
`already_staged`; evidência diferente é recusada. Cada seção precisa ser um
trecho exato do candidato, cada chunk precisa pertencer à sua seção e ao menos
uma seção integral deve coincidir com o texto/hash completo da versão. Revisão,
evidência e publicação repetem essa verificação, impedindo que texto fabricado
por um parser se torne raiz de confiança.

## Contrato humano

### Revisar mudança

```text
ia_review_legal_source_change(
  p_change_set_id,
  p_decision,             -- approved | rejected | changes_requested
  p_review_notes,
  p_confirmation,         -- REVISAR
  p_valid_from?,
  p_valid_until?,
  p_publication_date?
)
```

Exige AAL2 e `legal_reviewer` ativo no mesmo município. A revisão guarda o hash
e as datas conferidas. Para aprovar, publicação e início da vigência precisam
existir e já ser efetivos; vigência encerrada é recusada. Aprovação deixa a
versão em `approved`, nunca em `published`. Importações legadas sem artefato
recebem `legacy_recapture_required`, ficam fora da fila revisável e só podem ser
substituídas por uma nova captura oficial comprovada.

### Publicar versão legal

`ia_publish_legal_source_version(p_source_version_id, 'PUBLICAR')`.

Exige a mesma autoridade jurídica, datas de publicação e início de vigência,
revisão aprovada para o hash atual, e pelo menos uma seção com chunk.

### Snapshot operacional

`ia_get_knowledge_operations_snapshot(p_municipality_id)` — somente staff do
tenant em AAL2.

Retorna `verified`, município, capacidades efetivas, resumo, fontes, mudanças,
fila de revisão e saúde. Campos de capacidade e `blockers` são calculados no
backend; o frontend deve continuar fail-closed quando o RPC falhar ou o shape
for inválido.

`blockers` contém somente códigos estáveis (por exemplo,
`source_review_required`, `legal_body_extraction_required`,
`legacy_recapture_required`, `source_not_current`, `collection_failed` e
`citation_required`), nunca
mensagens de apresentação. Mudanças e revisões de fonte trazem a URL oficial,
uma prévia limitada do texto candidato e a contagem de seções. O snapshot não
expõe caminho nem conteúdo do bucket privado.

### Evidência de uma mudança legal

```text
ia_get_legal_source_change_evidence(
  p_municipality_id,
  p_change_set_id,
  p_content_offset?,       -- >= 0
  p_content_limit?,        -- 1..50000
  p_section_offset?,       -- >= 0
  p_section_limit?         -- 1..100
)
```

Exige staff do tenant em AAL2. Retorna em `snake_case` a URL oficial cadastrada,
a URL final realmente capturada, instante da coleta, hash do artefato bruto,
hash do texto candidato, hash/detalhes do diff, conteúdo paginado e seções
ordenadas. O caminho privado do Storage nunca é retornado. `evidence_complete`
só é verdadeiro quando artefato, execução, mapeamento de versão, seção e chunk
formam uma prova consistente.

### Evidência e decisão de um artigo

`ia_get_knowledge_article_evidence(p_municipality_id, p_article_id,
p_revision_id)` devolve a resposta integral limitada a 20 mil caracteres e até
100 citações. Cada citação contém fonte, URL oficial, versão, hash, vigência,
dispositivo, trecho e bloqueios verificáveis.

```text
ia_review_knowledge_article(
  p_article_id,
  p_revision_id,
  p_decision,       -- approved | rejected | revision_requested
  p_notes,
  p_confirmation    -- REVISAR
)
```

A assinatura antiga, sem confirmação explícita, é removida. Rejeição ou pedido
de ajuste exige justificativa com pelo menos 10 caracteres. Aprovação exige
citação vigente, publicada, íntegra e apontando para trecho presente na seção.
Publicação continua em etapa separada:
`ia_publish_knowledge_article(p_article_id, 'PUBLICAR')`, restrita a
`legal_reviewer` em AAL2.

## Catálogo inicial

O seed contém apenas URLs e metadados oficiais verificáveis. Não inclui corpo
legal inventado e **não constitui um corpus jurídico pronto**. Todos os
endpoints reais da Fase 1 nascem `catalog_only`/não citáveis; as páginas Siscam,
índices, jornais e ficha do Ganha Tempo são catálogo/evidência de coleta até que
um parser de corpo integral seja validado. O catálogo inicial aponta para:

- Cordeirópolis: LC 399/2024, LC 404/2025, Decreto 6.910/2024, catálogo Siscam
  e Jornal do Município.
- Araras: Lei 3.362/2001, LC 36/2013, catálogo Siscam, versão consolidada da
  Legislação Digital, Diário Oficial e serviço de emissão de guia de ITBI no
  Ganha Tempo.

O Diário Oficial é a evidência primária de publicação. Portais consolidados e
guias operacionais auxiliam pesquisa e comparação, mas não substituem a
publicação oficial.

Cada fonte mantém uma única representação canônica ativa. PDF ou espelho
alternativo fica `paused` com um `activation_blocker`; isso impede que duas
representações do mesmo ato gerem versões falsas entre si. Esta fase não cria
cron nem agenda coleta automática.

### Pré-requisito para promover um endpoint na Fase 2

Não basta alterar `content_mode`/`citable_body`. Um artefato capturado enquanto
era catálogo é imutável e não pode ser reinterpretado por retry. Antes da
promoção, deve existir um fluxo governado de conclusão de extração que:

1. valide parser e smoke test contra o corpo integral oficial;
2. preserve o artefato bruto WORM e registre o hash do texto extraído;
3. crie uma nova versão artifact-backed, seções e chunks;
4. encerre a pendência de catálogo/legado e abra uma revisão humana nova;
5. mantenha publicação em ação AAL2 separada.

Até esse fluxo ser implementado e testado, endpoints reais permanecem
`catalog_only` e nenhum conteúdo coletado pode fundamentar resposta fiscal.

## Verificação

O teste transacional
`supabase/tests/knowledge_ingestion_governance_regression.sql` cobre:

- separação service/staff;
- negação em AAL1, papel incorreto e outro município;
- idempotência por correlação e por hash;
- captura + seção + chunks atômicos, contagens exatas, retry/replay e rollback
  integral quando o staging falha;
- impossibilidade de autopublicação;
- confirmação explícita e vigência;
- imutabilidade das evidências;
- WORM do objeto/bucket, inclusive contra `service_role` e `TRUNCATE`;
- catálogo não citável, supersessão de mudanças e recaptura de legado;
- deduplicação semântica de artefatos brutos equivalentes;
- códigos estáveis de bloqueio e evidência segura para decisão;
- prova completa do artefato antes de aprovar uma fonte;
- bloqueio de artigo fundamentado por norma com vigência futura;
- cutover temporal seguro para fonte e artigo, preservando o publicado vigente;
- leitura da biblioteca por `municipal_admin`, sem permissão de revisar ou
  publicar;
- exclusão de artigos de teste do conhecimento reutilizável.
