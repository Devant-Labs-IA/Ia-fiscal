# Runbook — Segundo Cérebro Fiscal Fase 2

## 1. Escopo e verdade operacional

A Fase 2 instala extração integral governada, embeddings `gte-small` de 384
dimensões, busca híbrida tenant-first, atualização agendada e revisão jurídica
supervisionada. Nenhuma etapa envia e-mail, notificação, mensagem ou ato fiscal
ao contribuinte. Coleta, revisão e publicação jurídica continuam separadas.

O rótulo público é **Cobertura inicial governada**. O primeiro release possui
somente dois corpos legais P0 comprováveis:

- Cordeirópolis: LC 399/2024 pela publicação oficial no Jornal do Município,
  edição 1645, 32 páginas;
- Araras: Lei 3.362/2001, anexo PDF Siscam 43123.

Os catálogos fiscais paginados descobrem outras fichas, anexos e relações. Uma
descoberta cria fonte `draft`, endpoint de ficha e candidato de extração; nunca
publica texto. `corpus_integral` só pode ser verdadeiro quando toda cobertura
com contagem esperada foi descoberta e publicada com evidência integral.

Bloqueios conhecidos no momento do release:

- Siscam Cordeirópolis pode responder 503;
- Legislação Digital pode responder 403;
- AssisTECH/Araras pode responder 502;
- LC 36/2013 tem RTF de 24,6 MiB, PDF de 136 MiB e DOC de 13,7 MiB. O PDF
  excede o limite e os formatos legados exigem extrator separado. A fonte fica
  bloqueada, nunca falsamente integral.

## 2. Componentes e contratos

### Migrações

1. `20260818232052_governed_official_knowledge_ingestion.sql` — raiz de
   evidência, WORM, revisão e publicação separadas.
2. `20260818232846_cover_governed_knowledge_foreign_keys.sql` — FKs compostas.
3. `20260819040404_knowledge_phase2_core.sql` — capability jurídica estreita,
   `halfvec(384)`, fila de embeddings, busca híbrida, agenda desabilitada,
   Vault e runtime gate.
4. `20260819042149_knowledge_phase2_catalog_coverage.sql` — descoberta
   paginada, identidade legal canônica, N:N de cobertura e cutover de anexos.
5. `20260819055931_governed_external_knowledge_ocr.sql` — fila privada de OCR,
   leases/retries, evidência por página e manifesto WORM, OIDC GitHub imutável,
   consolidação atômica somente em candidato `under_review` e gate próprio
   inicialmente fechado.
6. `supabase/release/activate_knowledge_phase2_schedule.sql` — somente depois, aplicado com timestamp remoto novo e posterior ao manifesto vigente
   das Edges e dos smokes: backfill idempotente, agenda global e ativação
   auditada de Cordeirópolis e Araras.

### Edge Functions

- `ia-fiscal-knowledge-ingest`, contrato `knowledge-ingest-v2`:
  `verify_jwt=false`, mas toda chamada exige segredo do Vault, timestamp com
  janela de dois minutos e nonce de uso único. Extrai HTML inerte e PDF com
  `unpdf@1.8.0`; o texto continua limitado a 2.000.000 caracteres. DOCX fica
  apenas no catálogo e é recusado com `source_docx_disabled_edge_runtime`
  antes de qualquer parser ou descompressão. O Edge Runtime hospedado não
  oferece Web Worker nem `vm`, conforme os
  [limites oficiais](https://supabase.com/docs/guides/functions/limits), portanto
  não há como terminar Mammoth com isolamento confiável; `Promise.race`
  encerraria só a resposta, não o trabalho subjacente. Nunca promove ou
  publica.

A execução real chama somente
`ia_fiscal_capture_knowledge_source_v2`. Esse RPC mantém captura, versão
candidata, change set, seção `integral` e chunks na mesma transação. O staging
legado é diferido apenas dentro dessa transação e executado uma única vez com
o payload final; uma falha em seção/chunk reverte também fetch run, artefato,
versão e change set. Retry por SHA e replay por `correlation_id` retornam a
mesma identidade e as contagens persistidas, após comparar exatamente o
payload staged. O upload imutável no Storage ocorre antes do RPC e pode ficar
órfão se o banco recusar. Depois do rollback, a Edge registra em uma nova
transação exatamente um fetch run `failed`, com
`safe_error_code=capture_rpc_failed`, para a correlação; esse registro não é
evidência capturada e guarda bucket, path, SHA-256 e disposição
`preserved_for_reconciliation` do objeto órfão. A reconciliação é separada e
nunca o apaga durante o fluxo de ingestão. Falha posterior a uma captura já
confirmada não cria um segundo fetch run conflitante.

- `ia-fiscal-knowledge-embed`, contrato `knowledge-embed-v1`:
  mesma autenticação customizada; usa `Supabase.ai.Session('gte-small')`, 384
  dimensões, lease de dez minutos e dead-letter após cinco tentativas.
- `ia-fiscal-knowledge-search`, contrato `knowledge-search-v1`:
  `verify_jwt=true`, sessão humana AAL2 e tenant explícito. A Edge gera o vetor
  no runtime e o SQL filtra tenant/vigência/publicação antes do ranking.
- `ia-fiscal-knowledge-ocr`, contrato `ia-fiscal-knowledge-ocr/v1`:
  `verify_jwt=false` somente porque o gateway não valida o emissor externo. A
  própria Edge valida assinatura RS256 pelo JWKS oficial do GitHub, issuer,
  audience, IDs imutáveis do owner/repositório, subject com IDs, branch,
  environment, workflow/ref, commit do workflow, runner hospedado, evento e
  `jti` de uso único antes de criar o client service-role. O workflow nunca
  recebe `service_role`; recebe apenas URL assinada curta do PDF oficial. A
  conclusão relê páginas e manifesto do bucket privado, recalcula hashes,
  métricas e toolchain, e chama um RPC service-only atômico. Resultado possível:
  `under_review`/`not_published`, nunca aprovação ou publicação.

Busca não é resposta gerativa. Ela devolve trecho oficial com citações. O
limiar de liberação é `confidence >= 0.35`, calibrado pelo maior entre
`ts_rank_cd * 5` e `(similaridade_semântica - 0.55) / 0.35`, limitado a 0..1.
Hits abaixo do limite preservam citações, mas retornam `answered=false`,
`answer=null` e `insufficient_relevance`.
Cada busca concluída registra somente código de correlação, município, estado
da resposta, blockers seguros, quantidade de citações, modo e duração. Consulta,
trechos, resposta e identidade do usuário não são escritos no log.

### Capability de revisor jurídico

O grant não altera `municipality_memberships.role`. Somente
`municipal_admin`, `supervisor`, `fiscal_auditor` ou um `legal_reviewer` real
podem receber a capability; `support_readonly` e portais são recusados. Grant
próprio é recusado. A capability só abre RPCs do domínio knowledge e não libera
casos, atendimento, templates ou políticas. Toda revisão exige AAL2, tenant
esperado, prova vigente e proíbe autorrevisão. Aprovar candidato de aprendizado
não o publica. O cron de cinco minutos materializa grants cujo `valid_until`
passou como `expired` e grava exatamente um evento append-only com ator
`system`, na mesma transação. Lista administrativa, snapshot e nova concessão
também executam a transição de forma idempotente; portanto uma linha vencida
não permanece silenciosamente `active` até a próxima concessão.

## 3. Limites de extração

| Controle              |                                          Limite |
| --------------------- | ----------------------------------------------: |
| Corpo JSON da Edge    |                                           4 KiB |
| Artefato bruto        |                                          50 MiB |
| Texto extraído        |                            2.000.000 caracteres |
| PDF                   |                                     500 páginas |
| OCR externo v1        |  120 páginas; 8.000.000 caracteres consolidados |
| Imagem interna do PDF |                               16.777.216 pixels |
| Fetch HTTP            |                                            20 s |
| DOCX/ZIP              |      desabilitado antes de parser/descompressão |
| Chunks por versão     |                                           5.000 |
| Chunk                 | 80–8.000 para embedding; alvo 6.000/overlap 500 |

PDF precisa começar com `%PDF-`, ter extração não vazia e o número de páginas
extraídas precisa coincidir com o documento. O metadata persiste parser,
páginas, completude, contagem de caracteres e hashes. O banco aceita apenas uma
seção integral cujo texto/hash coincide exatamente com a versão candidata.
Links DOCX podem ser descobertos como metadado, mas endpoints ativos têm o MIME
removido da interface na Edge e respostas DOCX/ZIP nunca chegam ao extrator.
O limite de 500 páginas continua válido para o extrator PDF nativo. O OCR
externo v1 é deliberadamente menor: PDFs de 1–120 páginas podem entrar na fila;
acima de 120, o artefato bruto permanece preservado com blocker
`external_ocr_page_limit_exceeded` e exige revisão manual ou uma futura versão
paginada. Ele não entra em retries destinados a falhar e não é apresentado como
cobertura integral.

## 4. Ordem de release obrigatória

Não use `supabase db push` com a migration de ativação ainda presente no lote.
Ela deve ser aplicada isoladamente, depois das Edges e dos smokes.

### 4.1. Preparar e validar

1. Confirmar project ref, ambiente e backup/PITR.
2. Registrar SHA-256 de cada migration, função e teste.
3. Executar em branch de banco ou clone descartável, com parada no primeiro
   erro:

```bash
psql "${IA_DATABASE_URL}" -v ON_ERROR_STOP=1 --single-transaction \
  --file supabase/migrations/20260819040404_knowledge_phase2_core.sql
psql "${IA_DATABASE_URL}" -v ON_ERROR_STOP=1 --single-transaction \
  --file supabase/migrations/20260819042149_knowledge_phase2_catalog_coverage.sql
psql "${IA_DATABASE_URL}" -v ON_ERROR_STOP=1 --single-transaction \
  --file supabase/migrations/20260819055931_governed_external_knowledge_ocr.sql
psql "${IA_DATABASE_URL}" -v ON_ERROR_STOP=1 \
  --file supabase/tests/knowledge_phase2_regression.sql
```

Se as migrations Fase 1 ainda não estiverem no manifest remoto, aplique as duas
primeiras antes do core. Não reaplique arquivos já registrados.

Gates mínimos:

```bash
./node_modules/.bin/vitest run \
  supabase/functions/ia-fiscal-knowledge-ingest/*.test.ts \
  supabase/functions/ia-fiscal-knowledge-embed/*.test.ts \
  supabase/functions/ia-fiscal-knowledge-search/*.test.ts \
  supabase/functions/ia-fiscal-knowledge-ocr/*.test.ts \
  supabase/tests/knowledge_phase2_contract.test.ts

psql "${IA_DATABASE_URL}" -v ON_ERROR_STOP=1 \
  --file supabase/tests/knowledge_ocr_regression.sql

deno test --allow-env --allow-read \
  supabase/functions/ia-fiscal-knowledge-ingest/deno-tests/extraction_test.ts
deno check supabase/functions/ia-fiscal-knowledge-ingest/index.ts
deno check supabase/functions/ia-fiscal-knowledge-embed/index.ts
deno check supabase/functions/ia-fiscal-knowledge-search/index.ts
deno check supabase/functions/ia-fiscal-knowledge-ocr/index.ts
```

### 4.2. Implantar Edges sem ativar agenda

Implantar exatamente os quatro diretórios. A configuração efetiva deve ser:

```text
ingest verify_jwt=false
embed  verify_jwt=false
search verify_jwt=true
ocr    verify_jwt=false (GitHub OIDC validado integralmente pela própria Edge)
```

Não grave `service_role`, anon key ou segredo do scheduler em migration, Git,
log ou comando versionado. O segredo aleatório já nasce no Vault. Configure a
URL canônica do projeto pelo RPC service-only
`ia_fiscal_configure_knowledge_scheduler_project_url`.

### 4.3. Smokes de runtime

Antes do atestado:

1. ingest e embed sem segredo, com digest errado, timestamp expirado e nonce
   repetido devem retornar 403;
2. a origem Vercel oficial e o alias
   `https://ia-fiscal-homologacao.vercel.app` devem passar OPTIONS; origem
   arbitrária não recebe `Access-Control-Allow-Origin`;
3. search com JWT ausente, AAL1 ou tenant errado deve ser negada;
4. executar `official-pdf.smoke.ts`: validar `%PDF`, 32 páginas e marcador da
   LC 399; validar PDF 43123 e marcador da Lei 3.362;
5. executar dry-run das duas fontes sem Storage/banco e reter saída sanitizada;
6. executar uma captura real controlada e confirmar no mesmo retorno
   `staging_status=staged`, `staged_sections=1`, `staged_chunks>=1`, seção
   `integral`, embedding de 384 dimensões e status `under_review`, nunca
   `published`;
7. repetir com novo `correlation_id` e o mesmo SHA, depois repetir a mesma
   correlação; ambos devem retornar `already_staged`, a mesma versão/change set
   e as mesmas contagens, sem duplicar artefato, versão, seção ou chunk;
8. executar `knowledge_phase2_regression.sql` novamente no alvo de release.

Adicionalmente, force uma falha de staging em ambiente transacional de QA. Deve
permanecer exatamente um fetch run final `failed`, com
`safe_error_code=capture_rpc_failed`, para a correlação e
`orphaned_storage_artifact` apontando bucket, path e SHA-256 preservados;
repetir o registro da mesma falha precisa devolver o mesmo ID. Se permanecer
artefato de banco, versão, change set, seção ou chunk daquele SHA/correlação, ou
se houver mais de um fetch run, o gate P0 falhou e o deploy deve ser
interrompido. O objeto no Storage é WORM e fica para reconciliação controlada.

Se o PDF 43123 estiver indisponível por bloqueio do upstream, o smoke P0 não
passa. Registre `blocked_502/503` e não ateste nem aplique a ativação. Não use
notícia, carta, resumo ou texto manual como substituto.

Calcule um SHA-256 do pacote de evidências sanitizadas e um
`release_fingerprint` SHA-256 por Edge a partir do manifesto congelado (arquivos,
dependências e configuração). Não use o SHA bruto de um arquivo isolado e não
hardcode fingerprints antes do freeze. Registre também os três identificadores
de deployment retornados pelo Supabase. O `project_ref` deve ser exatamente o
da URL já configurada, e o atestado deve expirar em no máximo sete dias:

```text
ia_fiscal_attest_knowledge_runtime_ready(
  '<project_ref>',
  'knowledge-ingest-v2', '<ingest_deployment_id>', '<ingest_release_fingerprint>',
  'knowledge-embed-v1', '<embed_deployment_id>', '<embed_release_fingerprint>',
  'knowledge-search-v1', '<search_deployment_id>', '<search_release_fingerprint>',
  '<sha256-das-evidencias>',
  '<localizador-imutavel-do-manifesto-de-evidencias>',
  '<valid_until>',
  'ATESTAR RUNTIME SEGUNDO CEREBRO'
)
```

O RPC grava o gate e os eventos `attested`/`selected`, e atualiza o ponteiro
explícito do projeto. Ativação e configuração municipal consultam somente esse
gate exato/current; nunca escolhem “qualquer” atestado nem simplesmente o mais
recente. Para incidente ou deployment substituído, use
`ia_fiscal_revoke_knowledge_runtime_gate(..., 'REVOGAR RUNTIME SEGUNDO CEREBRO')`;
a revogação é append-only, remove o ponteiro se ele ainda apontar para o gate e
faz o runtime falhar fechado imediatamente. Gate expirado também falha fechado.
Dispatcher, claim de embeddings e RPC híbrida tomam lock no ponteiro e no gate
exatos antes de qualquer claim ou I/O; expiração ou revogação bloqueia inclusive
chamadas PostgREST diretas, não apenas a UI/Edge.

#### 4.3.1. Release e atestado do OCR externo

A ordem é fixa e não pode ser invertida:

1. aplicar uma única vez `20260819055931_governed_external_knowledge_ocr.sql`
   e executar `knowledge_ocr_regression.sql` em transação com `ON_ERROR_STOP`;
2. implantar `ia-fiscal-knowledge-ocr` com o bundle congelado, ainda sem gate;
3. publicar `.github/workflows/knowledge-ocr.yml` em `main`, com environment
   protegido `knowledge-ocr`, permissões apenas `contents: read` e
   `id-token: write`, e registrar o commit SHA-1 de 40 caracteres;
4. atestar um gate temporário curto com as evidências de build e smokes
   negativos, executar um único `workflow_dispatch` controlado e revogar o gate;
5. somente após validar a evidência positiva, atestar o gate final com novo
   SHA-256 do pacote de evidências, deployment/bundle exatos, mesmo commit do
   workflow e validade de no máximo sete dias.

O OIDC aceito é exatamente o repository
`AlmoreContabilidade/Ia-fiscal`, owner ID `296187202`, repository ID
`1320619695`, ref `refs/heads/main`, environment `knowledge-ocr`, workflow
`.github/workflows/knowledge-ocr.yml`, runner `github-hosted` e audience do
projeto. O `sub` usa os IDs imutáveis; o formato legado sem IDs é recusado. O
`workflow_sha` do JWT precisa coincidir com o commit atestado. Cada operação
usa JWT/JTI novo; não use token, chave ou segredo em logs/artefatos.

Smokes obrigatórios do OCR:

1. JWT ausente, assinatura/audience/subject/repository/ref/workflow/environment
   divergentes e JTI repetido são recusados antes de Storage/RPC;
2. sem o gate principal ou o gate OCR atual, `claim` falha fechado;
3. PDF sintético de 120 páginas entra na fila, 121 páginas não entra e aparece
   como revisão manual; `application/octet-stream` genérico é recusado;
4. upload repetido do mesmo part só é aceito quando bytes e SHA-256 coincidem;
5. baixa cobertura, confiança média menor que 550/1000, página ausente,
   manifesto/source/toolchain divergente e lease expirado são recusados;
6. perda simulada da resposta de `complete` retorna `already_completed` no
   replay exato, sem duplicar versão, seção, chunk ou resultado; replay
   divergente é recusado;
7. a Lei nº 3.362/2001 de Araras (PDF Siscam 43123) deve produzir um candidato
   integral `under_review`, com hashes e páginas conferidos, e permanecer
   `not_published`. Se o PDF oficial estiver indisponível, o smoke não passa;
8. confirmar contagens `queued/processing/completed/dead_letter`, blocker
   `blocked_page_limit`, `has_attention` e `auto_publish=false` no snapshot.

O gate é ativação de processamento, não de conteúdo. OCR nunca aprova nem
publica, inclusive no smoke. Para conter incidente, revogue imediatamente o
gate com `ia_fiscal_revoke_knowledge_ocr_runtime_gate` e a confirmação
governada, suspenda o schedule/workflow e preserve bucket, jobs, eventos,
páginas, resultados e candidatos para auditoria. Não tente apagar evidência
WORM. Rollback estrutural exige migration compensatória revisada ou restauração;
reativação requer novo deployment, novos smokes e novo atestado.

### 4.4. Ativar

Somente então:

```bash
psql "${IA_DATABASE_URL}" -v ON_ERROR_STOP=1 --single-transaction \
  --file supabase/release/activate_knowledge_phase2_schedule.sql
```

A migration falha se runtime, URL, segredo, municípios, endpoint de catálogo
ou corpo legal citável estiverem ausentes. O perfil de readiness é explícito:
Cordeirópolis deve continuar `active` e Araras deve continuar `homologation`.
A agenda é somente de conhecimento interno e **não promove** o status de Araras
nem habilita comunicação externa. Ela também falha se qualquer terceiro
município já estiver habilitado. O backfill e a ativação ficam restritos, por
`municipality_id`, a Cordeirópolis e Araras. Se passar, cria/recria o cron de
cinco minutos e habilita exatamente os dois municípios para 03:15 em
`America/Sao_Paulo`, com evento append-only por tenant ligado ao gate current,
ao status municipal observado e ao escopo `internal_knowledge_refresh_only`.

Verifique sem expor segredos:

- um cron `ia-fiscal-knowledge-refresh-v2`;
- `knowledge_automation_settings.enabled=true` somente para os dois tenants;
- dois eventos `phase2_release_enabled_official_refresh` ligados ao release
  gate;
- `schedule.runtime_verified=true`, `last_run_status='never_run'` antes da
  primeira rodada;
- catálogos bloqueados continuam visíveis com blocker e são controlados pelo
  circuit breaker;
- nenhuma fila de comunicação/notificação foi criada.

Depois regenere os tipos do Supabase e só então publique o frontend compatível.

## 5. Operação e incidente

O dispatcher usa como cursor somente o último fetch concluído com sucesso ou um
dispatch ainda pendente; uma tentativa terminal/falha nunca avança o cursor.
Cada `net.http_post` cria dispatch e evento `queued` imutáveis, com lease de dois
minutos. A rodada seguinte reconcilia `request_id` em `net._http_response` e
acrescenta exatamente um evento terminal (`succeeded`, `retry_scheduled`,
`circuit_opened` ou `failed`). Resposta 2xx de ingestão só é sucesso quando há
fetch concluído correspondente. No embed, somente HTTP 200 é sucesso; HTTP 207
indica lote parcial/falho e alimenta retry e circuit breaker. Timeout, resposta
ausente, 408/425/429 e 5xx
recebem retry exponencial; três falhas em 30 minutos abrem o circuito por 30
minutos; falha HTTP permanente aguarda 24 horas. O dispatcher usa
`FOR UPDATE SKIP LOCKED` e não repete trabalho com lease pendente.
Quando uma captura assíncrona descobre páginas, fichas ou anexos novos, ela
avança o cursor do tenant para o próximo lote de cinco minutos.
O claim de embeddings considera somente tenants com
`knowledge_automation_settings.enabled=true`, trava o gate atual e persiste um
cursor round-robin por revisão de modelo. A ordenação por `tenant_rank` mais o
cursor circular evita que o primeiro UUID volte a vencer após restart ou entre
batches quando há mais tenants que vagas. Tenant desabilitado não tem lease
recuperada, claim nem progresso de fila. Worker de embeddings recupera lease
expirada; quinta falha vai para dead-letter.

Busca, revisão e publicação só aceitam versões legais `published` e vigentes
que apontem para artefato imutável existente no bucket privado, fetch
`completed_changed`, extração integral com hash/contagem compatíveis e seção/
chunks completos. Conteúdo legado sem mapping/fetch/Storage nunca se torna
citável apenas por possuir linhas de seção e chunk.

Para conter a coleta sem perder evidência:

1. chamar `ia_configure_knowledge_schedule(..., false,
'DESATIVAR ATUALIZACAO OFICIAL')` para cada tenant;
2. `cron.unschedule` somente com autorização operacional;
3. preservar artefatos, fetch runs, hashes, revisões e eventos;
4. nunca apagar ou editar uma versão publicada; emitir nova versão/cutover;
5. rotacionar somente o segredo no Vault em caso de exposição.

Rollback estrutural não é automático: tabelas, `halfvec(384)`, índices, Vault,
triggers e evidência WORM são alterações amplas. Restaure a partir do backup ou
use uma migration compensatória revisada. Desativar agenda e Edges é a primeira
contenção reversível.
