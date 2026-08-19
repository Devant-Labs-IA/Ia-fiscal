# Runbook — ingestão governada de fontes oficiais (Fase 1)

> A operação de produção da Fase 2 substitui autenticação, extração, limites e
> ativação descritos abaixo. Use o
> [runbook da Fase 2](knowledge-phase2-release.md) para deploy, PDF, bloqueio
> temporário de DOCX, embeddings, scheduler e busca. Este documento permanece como histórico dos
> invariantes WORM e do bootstrap original.

Este runbook cobre a Fase 1 do conector `ia-fiscal-knowledge-ingest`. A função captura uma
evidência bruta de um endpoint previamente cadastrado, calcula o hash, preserva o artefato em
Storage privado e cria somente material pendente de processamento ou revisão. Ela **não publica
normas**, não cria orientação fiscal aprovada e não executa scripts ou instruções presentes nos
documentos.

## 1. Fronteira de confiança

- A Edge Function usa `verify_jwt = true`; o gateway valida a assinatura/expiração e, dentro do
  handler, o Bearer precisa ser exatamente o JWT legado configurado em
  `SUPABASE_SERVICE_ROLE_KEY`. A igualdade é feita sobre hashes SHA-256 sem saída antecipada.
- Não invoque a função pelo navegador e nunca inclua a service role em código cliente, logs,
  tickets ou screenshots.
- A entrada contém somente `endpoint_id` e `dry_run`; URL, município, fonte, MIME esperado e hosts
  permitidos vêm do cadastro governado no banco.
- Cada URL é HTTPS, sem credenciais, fragmento ou porta não padrão. Todo redirecionamento é tratado
  manualmente e revalidado antes do próximo acesso.
- A allowlist efetiva é a interseção entre a política versionada na Edge e os `allowed_hosts` do
  endpoint. Um cadastro de banco mais amplo não expande sozinho o acesso de rede.
- Endpoints `catalog_only` são preservados somente como artefato bruto, mesmo quando retornam HTML;
  não geram texto citável, versão candidata, seção ou chunk. Podem abrir um change set somente para
  representar mudança de hash bruto e saúde da fonte. A extração HTML só ocorre quando o cadastro
  ativo declara simultaneamente `content_mode=legal_body` e `citable_body=true`.
- HTML citável é convertido apenas em texto inerte, marcado como conteúdo externo não confiável.
  Scripts, estilos e templates são descartados sem renderização. O texto nunca é truncado: se a
  extração exceder o limite, a captura falha de forma fechada. PDF fica bruto, com extração pendente.
- Nenhum texto capturado deve ser tratado como instrução para agente, prompt de sistema ou comando.

## 2. Dependências de backend

Aplicar e validar primeiro a migration de conhecimento que fornece:

- bucket privado `legal-source-artifacts`;
- `public.ia_fiscal_get_knowledge_source_endpoints()`;
- `public.ia_fiscal_capture_knowledge_source(...)`;
- `public.ia_fiscal_stage_knowledge_sections(...)`;
- `public.ia_fiscal_record_knowledge_fetch_failure(...)`.

Os RPCs e o bucket são acessíveis somente pela service role. A captura valida fonte e URL
cadastradas, host final, MIME, tamanho, hash, path de Storage, status HTTP e correlação. Uma versão
nova nasce `under_review`; PDF sem extração nasce `requires_extraction`. Hash repetido retorna
`already_exists` e não cria outra versão lógica. Para HTML `legal_body`, a própria captura cria
versão, change set, seção integral e chunk na mesma transação. A Edge não chama
`ia_fiscal_stage_knowledge_sections`; se o staging interno falhar, toda a captura é revertida e a
Edge registra depois exatamente um fetch run `failed`, com
`safe_error_code=capture_rpc_failed`, usando a correlação original sem colidir com um fetch run
bem-sucedido. O RPC de staging permanece reservado ao extrator futuro de PDF e a retomadas manuais
governadas.

O RPC de endpoints retorna somente cadastros `active` e inclui `endpoint_status`, `content_mode`,
`citable_body` e `activation_blocker`. A Edge revalida essas capacidades e rejeita contrato
inconsistente. Todos os endpoints oficiais da Fase 1 estão em `catalog_only`, são não citáveis e
produzem fetch run + artefato imutável, com `processing_status=requires_extraction`. Uma mudança de
hash bruto pode abrir `change_set_id` sem criar `candidate_version_id`; isso alimenta saúde e
detecção de mudança, não conhecimento citável. Endpoints `legal_body` usados em validação devem ser
sintéticos e explicitamente marcados como citáveis até que uma fonte de corpo integral seja
comprovada e aprovada.

Para HTML não vazio, a Edge atesta no metadata `extraction_complete=true`,
`content_truncated=false` e `extracted_char_count` igual à contagem Unicode do texto enviado. O
backend rejeita captura cujo texto e metadata não sejam coerentes.

O path imutável do artefato é:

```text
<municipality_slug>/<source_id>/<sha256>/artifact.<html|pdf>
```

Se o upload concluir e o RPC falhar, o objeto não é apagado automaticamente. O retry encontra o
mesmo path e conclui a captura idempotente. Qualquer limpeza de órfão deve ser separada, auditada e
baseada em reconciliação com o banco.

### Compatibilidade e migração de chaves

O modo atual é deliberadamente compatível com a chave legada JWT `service_role`. Não use
`auth.getClaims()` para validar essa chave: JWTs legados HS256 não têm `sub` e essa API recorre a
`getUser()`, que é voltada a sessões de usuário. A nova chave `sb_secret_...` não é JWT e não passa
por uma função com `verify_jwt = true`.

Antes de desativar as chaves legadas, faça uma migração atômica e testada: crie uma secret key
nomeada só para o coletor, altere a função para `verify_jwt = false`, valide o header `apikey`
dentro do handler com o modo `secret:<nome>` do SDK oficial `@supabase/server`, atualize todos os
callers e só então desative o JWT legado. Nunca aceite simultaneamente uma chave nova sem validação
e um Bearer arbitrário. Consulte a documentação oficial de
[migração de API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys).

## 3. Endpoints oficiais da Fase 1

| Município     | Host                                                        | Prefixos de path permitidos                     | Modo Fase 1    |
| ------------- | ----------------------------------------------------------- | ----------------------------------------------- | -------------- |
| Cordeirópolis | `cordeiropolis.siscam.com.br`                               | `/Documentos/Documento/`, `/arquivo`, `/index/` | `catalog_only` |
| Cordeirópolis | `cordeiropolis.sp.gov.br` e `www.cordeiropolis.sp.gov.br`   | `/jornal-do-municipio/`                         | `catalog_only` |
| Araras        | `araras.siscam.com.br`                                      | `/Documentos/Documento/`, `/arquivo`, `/index/` | `catalog_only` |
| Araras        | `www.legislacaodigital.com.br` e `legislacaodigital.com.br` | `/Araras-SP/`                                   | `catalog_only` |
| Araras        | `app.assistechpublicacoes.com.br`                           | `/diario-oficial/pmararassp`                    | `catalog_only` |
| Araras        | `ganhatempo.araras.sp.gov.br`                               | `/guiafacil/pesquisa-publica/servicos/`         | `catalog_only` |

Não adicione wildcard, domínio pai ou CDN por conveniência. Para um redirecionamento legítimo a
outro host, registre evidência da origem oficial, revise SSRF e altere juntos o endpoint e a política
versionada.

O download aceita `text/html`, `application/xhtml+xml` e `application/pdf`. Um endpoint PDF do
Siscam declara `application/octet-stream`; essa exceção só é aceita quando prevista no cadastro e o
conteúdo contém assinatura `%PDF-`, sendo então normalizado para `application/pdf`.

## 4. Limites operacionais

| Controle                         |      Valor da Fase 1 |
| -------------------------------- | -------------------: |
| Corpo da solicitação             |                4 KiB |
| Artefato após descompressão HTTP |               12 MiB |
| Timeout total do download        |                 20 s |
| Redirecionamentos                |                    3 |
| Texto HTML preservado            | 2.000.000 caracteres |

Documento acima do limite não deve ter o limite aumentado durante um incidente. Use um fluxo
offline aprovado, com antivírus/parser seguro, segmentação, hash e revisão humana, e só depois
proponha uma mudança versionada. Uma extração HTML com mais de 2.000.000 caracteres retorna
`source_extracted_text_too_large` (HTTP 413) antes de upload, captura ou staging; na execução real,
a tentativa bloqueada é registrada pelo RPC de falha. O dry-run retorna o mesmo erro sem mutação.

## 5. Dry-run

O dry-run acessa a fonte externa, valida redirects/MIME/tamanho e calcula o SHA-256. Ele testa a
extração HTML somente em endpoint `legal_body` citável; `catalog_only` permanece bruto. O dry-run
não grava Storage, captura, versão, change set nem linha de falha.

```bash
curl --fail-with-body \
  --request POST \
  --header "Authorization: Bearer ${IA_SERVICE_ROLE_JWT}" \
  --header "apikey: ${IA_PROJECT_ANON_KEY}" \
  --header "Content-Type: application/json" \
  --data '{"endpoint_id":"00000000-0000-4000-8000-000000000000","dry_run":true}' \
  "${IA_SUPABASE_URL}/functions/v1/ia-fiscal-knowledge-ingest"
```

Use variáveis efêmeras no shell seguro. Não salve o comando com valores reais no histórico.
`IA_SERVICE_ROLE_JWT` deve ser exatamente a chave legada configurada em
`SUPABASE_SERVICE_ROLE_KEY`; uma sessão de usuário, mesmo válida, deve receber 403.
Confirme no retorno:

- `status = validated` e `mode = dry_run`;
- município, fonte e host esperados;
- MIME e tamanho plausíveis;
- `content_sha256` com 64 caracteres hexadecimais;
- `requires_extraction` para PDF ou qualquer endpoint `catalog_only`; `plain_text_untrusted` apenas
  para HTML `legal_body` citável;
- `correlation_id` presente.

## 6. Captura real

Repita a chamada com `"dry_run":false` somente depois do dry-run aprovado. O resultado esperado é:

- HTTP 201 e `status=captured` para hash novo; ou
- HTTP 200 e `status=already_exists` para replay/hash já conhecido;
- `processing_status=under_review` para HTML `legal_body` extraído; ou
- `processing_status=requires_extraction` para PDF ou endpoint `catalog_only` bruto.
- para HTML `legal_body`, `staging_status=staged`, `staged_sections=1` e
  `staged_chunks>=1`; o retorno atômico expõe as contagens realmente
  persistidas;
- para PDF ou `catalog_only`, `staging_status=not_applicable`, `candidate_version_id=null` e nenhum
  texto, versão candidata, seção ou chunk; `change_set_id` pode existir somente para representar a
  mudança de hash do artefato bruto.

Uma captura bem-sucedida ainda não autoriza o conteúdo para cálculo, resposta ao contribuinte ou
decisão fiscal. O fluxo posterior deve extrair com parser seguro, comparar mudanças e obter revisão
humana antes de qualquer publicação.

## 7. Observabilidade e diagnóstico

Os logs JSON contêm somente correlação, IDs técnicos, slug municipal, host, MIME, tamanho, contagem
de redirects, duração e códigos controlados. Não contêm URL completa, query string, conteúdo,
headers, JWT, service key nem mensagem bruta do upstream/banco.

Eventos principais:

- `knowledge_ingest_dry_run_completed`;
- `knowledge_ingest_completed`;
- `knowledge_ingest_failed`;
- `knowledge_ingest_failure_record_failed`.

Erros depois da resolução do endpoint são registrados por RPC com `error_code` sanitizado e sem
detalhe bruto. Em investigação, correlacione Edge log, `fetch_run_id`, `artifact_id` e
`correlation_id`; nunca copie o documento integral para o log.

Condições de parada imediata:

- redirect ou resolução para host fora da allowlist;
- MIME divergente, PDF sem assinatura, corpo vazio ou excesso de tamanho;
- bucket público ou acesso ao artefato por usuário comum;
- versão capturada aparecendo como publicada/aprovada;
- conteúdo de documento tratado como comando por qualquer etapa posterior;
- resposta/log contendo segredo, URL sensível ou conteúdo legal integral.

## 8. Validação antes do deploy

```bash
./node_modules/.bin/vitest run \
  supabase/functions/ia-fiscal-knowledge-ingest/policy.test.ts

deno check \
  --config supabase/functions/ia-fiscal-knowledge-ingest/deno.json \
  supabase/functions/ia-fiscal-knowledge-ingest/index.ts
```

O segundo comando exige Deno instalado. Depois, em ambiente descartável:

1. testar ausência/invalidade de JWT e JWT de usuário — deve negar;
2. testar endpoint inexistente — deve negar antes de qualquer fetch;
3. executar dry-run de um HTML e de um PDF;
4. capturar o mesmo endpoint duas vezes e comprovar `captured` seguido de `already_exists`;
5. confirmar que a captura atômica do HTML possui exatamente a seção `integral` e ao menos um
   chunk; uma falha interna não pode deixar capture/version/change set parciais e deve registrar,
   em transação posterior ao rollback, exatamente um fetch run `failed` com
   `safe_error_code=capture_rpc_failed` para a correlação;
6. confirmar bucket privado e path determinístico;
7. confirmar que a versão permanece em revisão e que PDF não recebeu texto inventado;
8. testar redirect externo, MIME inesperado, timeout e tamanho excedido;
9. revisar logs por ausência de conteúdo e segredos.

O deploy da Edge Function só deve ocorrer depois da migration do backend e desses gates. Esta fase
não cria cron, não ativa coleta periódica e não promove conhecimento automaticamente.
