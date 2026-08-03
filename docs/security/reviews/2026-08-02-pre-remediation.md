# Security Review: AlmoreContabilidade/Ia-fiscal

## Scope

Revisão estática integral do repositório IA Fiscal, incluindo frontend React, funções Edge, migrações SQL, políticas RLS, documentação operacional e pipeline.

- Scan mode: repository
- Target kind: git_worktree
- Target ID: local-workspace:sha256:b2dcb2c0bf3a1fd09cf6af23bb3e4229eb8031b26b4d0f3374a0fac75e57dccb
- Revision: 98630bab821759b920992f85bad64e427b56477c
- Snapshot digest: codex-security-snapshot/v1:sha256:313c81a962ab2bd6e1dd5af996cf1f6bac210e937d34bceeb2b08a3a66c36ed9
- Inventory strategy: repository
- Included paths: .
- Excluded paths: none
- Runtime or test status: TypeScript passou; 8/8 testes Vitest passaram; build de produção passou; npm audit encontrou 0 vulnerabilidades. O lint completo foi interrompido por duração excessiva e a execução restrita encontrou apenas formatação e avisos de Fast Refresh, sem defeito de segurança confirmado.
- Artifacts reviewed: 152 arquivos de origem e configuração, 101 tabelas e políticas representadas no arquivo SQL versionado, 2 Edge Functions, rotas, serviços Supabase, testes, CI e documentação de segurança
- Scan context: Snapshot local sujo contendo o frontend funcional, documentação e SQL histórico preparado para homologação; nenhuma ação de produção ou migração remota foi executada.

Limitations and exclusions:
- O conector remoto do Supabase está bloqueado por cota até 2026-08-08 00:48 America/Sao_Paulo.
- A definição de public.ia_submit_case_question não está no repositório versionado e ficou pendente de validação remota.
- Os achados refletem o snapshot local revisado; a paridade com o banco implantado deve ser confirmada antes da homologação.
- Excluded node_modules/\*\*: Dependências instaladas não são origem mantida; foram avaliadas pelo lockfile e npm audit.
- Excluded dist/\*\*: Saída gerada pelo build foi excluída da leitura fonte e verificada pela compilação de produção.
- Excluded .git/\*\*: Metadados de controle de versão não fazem parte da superfície executável.

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable findings | 5 |
| Severity mix | medium: 4, low: 1 |
| Confidence mix | high: 5 |
| Coverage | partial |
| Validation mode | single-pass repository scan with static source/control/sink validation and compact attack-path analysis |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

O principal objetivo é preservar sigilo fiscal, isolamento por prefeitura, autorização por papel e vínculo, supervisão humana das decisões fiscais e bloqueio de qualquer envio externo não homologado.

### Assets

- dados fiscais e cadastrais de contribuintes
- documentos, mensagens e eventos de processos fiscais
- conhecimento jurídico-fiscal governado
- credenciais e identidades de agentes públicos e participantes

### Trust Boundaries

- navegador autenticado para Supabase/RPC
- papéis e vínculos de uma prefeitura para objetos fiscais
- usuário comum para funções SECURITY DEFINER
- worker service_role para operações internas
- conteúdo assistido por IA para aprovação humana

### Attacker Capabilities

- conta autenticada de contribuinte ou contador
- conta fiscal legítima com papel inferior ou atribuição incompleta
- controle de UUIDs enviados pelo cliente
- abuso de estados de vínculo vencidos, futuros ou não verificados

### Security Objectives

- cada leitura e escrita deriva prefeitura e objeto de auth.uid()
- casos restricted/fiscal_secret exigem atribuição ou papel superior
- relações contábeis exigem vínculo e verificação válidos
- publicação e revisão de conhecimento exigem papel vigente e aprovação humana

### Assumptions

- a interface não é uma fronteira de segurança
- AAL2 reforça autenticação, mas não substitui autorização de objeto ou função
- o arquivo SQL versionado representa a intenção de segurança que será aplicada em homologação

## Findings

| Finding | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- |
| [Fiscal pode autoatribuir caso sigiloso ao assumir pergunta](#finding-1) | medium | high | inline below |
| [RPC de publicação permite alterar conhecimento fiscal sem papel de publicação](#finding-2) | medium | high | inline below |
| [Vínculo contábil não verificado libera dados do caso](#finding-3) | medium | high | inline below |
| [Fila fiscal expõe perguntas de casos sigilosos a fiscais não atribuídos](#finding-4) | medium | high | inline below |
| [Membership fora da vigência ainda pode revisar conhecimento fiscal](#finding-5) | low | high | inline below |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] Fiscal pode autoatribuir caso sigiloso ao assumir pergunta

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | O caminho completo está visível no SQL: a função omite a autorização de caso, insere a atribuição e o helper de leitura confia nessa atribuição para casos sigilosos. |
| Category | authorization-bypass |
| CWE | CWE-863 |
| Affected lines | supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:761-819, supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:29-44, supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1284-1285 |

#### Summary

A função `ia_claim_case_question` valida AAL2 e papel fiscal na mesma prefeitura, mas não exige visibilidade ou autorização prévia sobre o caso. Em seguida, ela cria uma atribuição `responsible_fiscal`, que é justamente a condição usada para liberar casos `restricted` e `fiscal_secret`.

#### Root Cause

A função de claim mistura duas decisões distintas: assumir o atendimento da pergunta e conceder acesso ao caso. Ela verifica apenas a função municipal do chamador e cria uma atribuição ativa antes de provar que o fiscal já podia ver ou revisar aquele caso.

**Claim valida papel municipal, mas não o caso** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:780-791`

O UUID fornecido seleciona a pergunta e a única autorização demonstrada é um papel ativo na prefeitura; nenhuma chamada a `can_view_case_staff` ou `can_review_case` precede a mutação.

```sql
select cq.* into strict v_question
from public.case_questions cq where cq.id=p_question_id for update;
...
select mm.* into strict v_membership
from public.municipality_memberships mm
where mm.municipality_id=v_question.municipality_id
  and mm.user_id=auth.uid()
  and mm.status='active'
  and mm.role in ('fiscal_auditor','supervisor','legal_reviewer')
limit 1;
```

**Claim cria a atribuição que faltava** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:798-810`

A função transforma o próprio chamador em responsável ativo pelo caso, criando a autorização que ele não possuía antes do claim.

```sql
if not exists (
  select 1 from public.case_assignments ca
  where ca.municipality_id=v_question.municipality_id
    and ca.case_id=v_question.case_id
    and ca.membership_id=v_membership.id
    and ca.status='active'
) then
  insert into public.case_assignments (
    municipality_id,case_id,membership_id,assignment_role,status,assigned_by
  ) values (
    v_question.municipality_id,v_question.case_id,v_membership.id,
    'responsible_fiscal','active',auth.uid()
  );
end if;
```

**Atribuição ativa libera casos sigilosos** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:29-44`

Para `restricted` e `fiscal_secret`, a atribuição ativa recém-criada satisfaz o helper que libera a leitura do caso.

```sql
fc.confidentiality = 'internal'
or exists (
  select 1
  from public.case_assignments ca
  join public.municipality_memberships mm
    on mm.municipality_id = ca.municipality_id
   and mm.id = ca.membership_id
  where ca.municipality_id = fc.municipality_id
    and ca.case_id = fc.id
    and ca.status = 'active'
    and mm.user_id = (select auth.uid())
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
)
```

#### Validation

A análise confirmou que um UUID de pergunta chega à RPC, que a RPC valida apenas papel/AAL2 e que a mutação cria a atribuição usada pelo controle de leitura sigilosa.

Validation method: static protected-action and authorization-transition trace

**Claim valida papel municipal, mas não o caso** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:780-791`

O UUID fornecido seleciona a pergunta e a única autorização demonstrada é um papel ativo na prefeitura; nenhuma chamada a `can_view_case_staff` ou `can_review_case` precede a mutação.

```sql
select cq.* into strict v_question
from public.case_questions cq where cq.id=p_question_id for update;
...
select mm.* into strict v_membership
from public.municipality_memberships mm
where mm.municipality_id=v_question.municipality_id
  and mm.user_id=auth.uid()
  and mm.status='active'
  and mm.role in ('fiscal_auditor','supervisor','legal_reviewer')
limit 1;
```

**Claim cria a atribuição que faltava** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:798-810`

A função transforma o próprio chamador em responsável ativo pelo caso, criando a autorização que ele não possuía antes do claim.

```sql
if not exists (
  select 1 from public.case_assignments ca
  where ca.municipality_id=v_question.municipality_id
    and ca.case_id=v_question.case_id
    and ca.membership_id=v_membership.id
    and ca.status='active'
) then
  insert into public.case_assignments (
    municipality_id,case_id,membership_id,assignment_role,status,assigned_by
  ) values (
    v_question.municipality_id,v_question.case_id,v_membership.id,
    'responsible_fiscal','active',auth.uid()
  );
end if;
```

**Atribuição ativa libera casos sigilosos** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:29-44`

Para `restricted` e `fiscal_secret`, a atribuição ativa recém-criada satisfaz o helper que libera a leitura do caso.

```sql
fc.confidentiality = 'internal'
or exists (
  select 1
  from public.case_assignments ca
  join public.municipality_memberships mm
    on mm.municipality_id = ca.municipality_id
   and mm.id = ca.membership_id
  where ca.municipality_id = fc.municipality_id
    and ca.case_id = fc.id
    and ca.status = 'active'
    and mm.user_id = (select auth.uid())
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
)
```

#### Dataflow

question_id -\> ia_claim_case_question -\> case_assignments -\> can_view_case_staff

- **Source:** UUID da pergunta

- **Sink:** atribuição `responsible_fiscal` ativa

- **Outcome:** acesso ao caso `restricted` ou `fiscal_secret`

**Claim valida papel municipal, mas não o caso** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:780-791`

O UUID fornecido seleciona a pergunta e a única autorização demonstrada é um papel ativo na prefeitura; nenhuma chamada a `can_view_case_staff` ou `can_review_case` precede a mutação.

```sql
select cq.* into strict v_question
from public.case_questions cq where cq.id=p_question_id for update;
...
select mm.* into strict v_membership
from public.municipality_memberships mm
where mm.municipality_id=v_question.municipality_id
  and mm.user_id=auth.uid()
  and mm.status='active'
  and mm.role in ('fiscal_auditor','supervisor','legal_reviewer')
limit 1;
```

**Claim cria a atribuição que faltava** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:798-810`

A função transforma o próprio chamador em responsável ativo pelo caso, criando a autorização que ele não possuía antes do claim.

```sql
if not exists (
  select 1 from public.case_assignments ca
  where ca.municipality_id=v_question.municipality_id
    and ca.case_id=v_question.case_id
    and ca.membership_id=v_membership.id
    and ca.status='active'
) then
  insert into public.case_assignments (
    municipality_id,case_id,membership_id,assignment_role,status,assigned_by
  ) values (
    v_question.municipality_id,v_question.case_id,v_membership.id,
    'responsible_fiscal','active',auth.uid()
  );
end if;
```

**Atribuição ativa libera casos sigilosos** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:29-44`

Para `restricted` e `fiscal_secret`, a atribuição ativa recém-criada satisfaz o helper que libera a leitura do caso.

```sql
fc.confidentiality = 'internal'
or exists (
  select 1
  from public.case_assignments ca
  join public.municipality_memberships mm
    on mm.municipality_id = ca.municipality_id
   and mm.id = ca.membership_id
  where ca.municipality_id = fc.municipality_id
    and ca.case_id = fc.id
    and ca.status = 'active'
    and mm.user_id = (select auth.uid())
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
)
```

#### Reachability

Requer conta fiscal legítima, AAL2, mesma prefeitura e pergunta não reclamada.

- **Attacker:** fiscal_auditor interno não atribuído

- **Entry point:** RPC autenticada `ia_claim_case_question`

- **Outcome:** atribuição persistente e leitura de caso sigiloso

#### Severity

**Medium** — A transição concede acesso persistente a caso fiscal sigiloso por meio de uma ação alcançável por fiscal interno não previamente atribuído. O requisito de conta legítima, mesma prefeitura, AAL2 e pergunta ainda não reclamada reduz a probabilidade.

Elevar se fiscais temporários ou terceiros receberem o papel, ou se os casos contiverem segredos legais de alto impacto; reduzir se houver aprovação externa obrigatória antes de a atribuição se tornar ativa.

#### Remediation

Antes de qualquer `INSERT` em `case_assignments`, exigir `private.can_view_case_staff` ou uma autorização explícita de despacho por supervisor. Separar o claim da concessão de atribuição e impedir que um fiscal comum crie para si a condição de acesso a casos `restricted` ou `fiscal_secret`.

Tests:
- Fiscal não atribuído recebe negação ao tentar assumir pergunta de caso `restricted` e `fiscal_secret`.
- Supervisor autorizado consegue despachar ou assumir conforme a política aprovada.
- Falha de claim não cria `case_assignments`, não altera a pergunta e não gera evento parcial.

Preventive controls:
- Centralizar a autorização de casos sigilosos em um único helper server-side.
- Testar toda RPC `SECURITY DEFINER` para transições que criam a própria permissão do chamador.

<a id="finding-2"></a>

### [2] RPC de publicação permite alterar conhecimento fiscal sem papel de publicação

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | O corpo completo e o grant estão versionados; nenhuma consulta de auth.uid() para membership ou papel aparece antes das atualizações. |
| Category | authorization-bypass |
| CWE | CWE-862, CWE-863 |
| Affected lines | supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1016-1054, supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1290-1291 |

#### Summary

A função `ia_publish_knowledge_article` é executável por qualquer usuário `authenticated`, aceita um UUID de artigo e altera os estados `retired` e `published`. Ela verifica AAL2, confirmação, aprovação, hash e citações, mas nunca comprova vínculo municipal vigente nem papel autorizado do chamador.

#### Root Cause

A implementação confundiu integridade do conteúdo com autorização do operador. Depois de garantir que o artigo foi aprovado e citado, a função executa a publicação sem validar quem é o chamador nem se seu vínculo está vigente para a prefeitura do artigo.

**EXECUTE é concedido a authenticated** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1290-1291`

O grant torna a função `SECURITY DEFINER` chamável por qualquer conta autenticada; a autorização fina precisa existir dentro da função, mas está ausente.

```sql
revoke all on function public.ia_publish_knowledge_article(uuid,text) from public,anon;
grant execute on function public.ia_publish_knowledge_article(uuid,text) to authenticated;
```

**Função valida conteúdo, mas não o publicador** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1029-1049`

Todos os controles são de autenticação forte ou integridade do artigo; nenhum associa `auth.uid()` à prefeitura e a um papel capaz de publicar.

```sql
if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
if p_confirmation <> 'PUBLICAR' then raise exception 'explicit publication confirmation required'; end if;
select ka.* into strict v_article from public.knowledge_articles ka where ka.id=p_article_id for update;
if v_article.is_test or v_article.approval_basis<>'fiscal_review' then raise exception 'test fixture cannot be promoted to live knowledge'; end if;
if v_article.status<>'approved' then raise exception 'knowledge article is not approved'; end if;
...
if exists (...) then raise exception 'one or more cited legal sources are not current and published'; end if;
```

**Função aposenta e publica artigos** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1050-1054`

A RPC realiza a transição editorial protegida e também aposenta o artigo atualmente publicado para o mesmo intent.

```sql
update public.knowledge_articles set status='retired'
 where municipality_id=v_article.municipality_id and intent_key=v_article.intent_key
   and id<>v_article.id and status='published' and not is_test;
update public.knowledge_articles set status='published',valid_from=coalesce(valid_from,now()),published_at=now()
 where municipality_id=v_article.municipality_id and id=v_article.id;
```

#### Validation

O grant amplo foi seguido até a função e às duas atualizações; os controles existentes foram classificados como integridade de conteúdo, não autorização do chamador.

Validation method: static source/control/sink trace of SECURITY DEFINER RPC

**EXECUTE é concedido a authenticated** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1290-1291`

O grant torna a função `SECURITY DEFINER` chamável por qualquer conta autenticada; a autorização fina precisa existir dentro da função, mas está ausente.

```sql
revoke all on function public.ia_publish_knowledge_article(uuid,text) from public,anon;
grant execute on function public.ia_publish_knowledge_article(uuid,text) to authenticated;
```

**Função valida conteúdo, mas não o publicador** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1029-1049`

Todos os controles são de autenticação forte ou integridade do artigo; nenhum associa `auth.uid()` à prefeitura e a um papel capaz de publicar.

```sql
if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
if p_confirmation <> 'PUBLICAR' then raise exception 'explicit publication confirmation required'; end if;
select ka.* into strict v_article from public.knowledge_articles ka where ka.id=p_article_id for update;
if v_article.is_test or v_article.approval_basis<>'fiscal_review' then raise exception 'test fixture cannot be promoted to live knowledge'; end if;
if v_article.status<>'approved' then raise exception 'knowledge article is not approved'; end if;
...
if exists (...) then raise exception 'one or more cited legal sources are not current and published'; end if;
```

**Função aposenta e publica artigos** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1050-1054`

A RPC realiza a transição editorial protegida e também aposenta o artigo atualmente publicado para o mesmo intent.

```sql
update public.knowledge_articles set status='retired'
 where municipality_id=v_article.municipality_id and intent_key=v_article.intent_key
   and id<>v_article.id and status='published' and not is_test;
update public.knowledge_articles set status='published',valid_from=coalesce(valid_from,now()),published_at=now()
 where municipality_id=v_article.municipality_id and id=v_article.id;
```

#### Dataflow

p_article_id -\> ia_publish_knowledge_article -\> updates de status

- **Source:** UUID de artigo aprovado fornecido pelo chamador

- **Sink:** estados `retired` e `published`

- **Outcome:** mudança do conhecimento fiscal vigente

**EXECUTE é concedido a authenticated** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1290-1291`

O grant torna a função `SECURITY DEFINER` chamável por qualquer conta autenticada; a autorização fina precisa existir dentro da função, mas está ausente.

```sql
revoke all on function public.ia_publish_knowledge_article(uuid,text) from public,anon;
grant execute on function public.ia_publish_knowledge_article(uuid,text) to authenticated;
```

**Função valida conteúdo, mas não o publicador** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1029-1049`

Todos os controles são de autenticação forte ou integridade do artigo; nenhum associa `auth.uid()` à prefeitura e a um papel capaz de publicar.

```sql
if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
if p_confirmation <> 'PUBLICAR' then raise exception 'explicit publication confirmation required'; end if;
select ka.* into strict v_article from public.knowledge_articles ka where ka.id=p_article_id for update;
if v_article.is_test or v_article.approval_basis<>'fiscal_review' then raise exception 'test fixture cannot be promoted to live knowledge'; end if;
if v_article.status<>'approved' then raise exception 'knowledge article is not approved'; end if;
...
if exists (...) then raise exception 'one or more cited legal sources are not current and published'; end if;
```

**Função aposenta e publica artigos** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1050-1054`

A RPC realiza a transição editorial protegida e também aposenta o artigo atualmente publicado para o mesmo intent.

```sql
update public.knowledge_articles set status='retired'
 where municipality_id=v_article.municipality_id and intent_key=v_article.intent_key
   and id<>v_article.id and status='published' and not is_test;
update public.knowledge_articles set status='published',valid_from=coalesce(valid_from,now()),published_at=now()
 where municipality_id=v_article.municipality_id and id=v_article.id;
```

#### Reachability

Requer conta AAL2, UUID de artigo aprovado e confirmação literal; não requer papel editorial.

- **Attacker:** usuário autenticado sem autoridade de publicação

- **Entry point:** RPC `ia_publish_knowledge_article`

- **Outcome:** publicação/aposentadoria não autorizada de conhecimento

#### Severity

**Medium** — A publicação governada fica diretamente alcançável por perfil autenticado inferior que conheça um UUID. Os controles que limitam a operação a conteúdo já aprovado reduzem o impacto de adulteração arbitrária.

Elevar se o conhecimento publicado produzir instrução operacional automática ou efeito externo; reduzir se um controle não versionado limitar EXECUTE a papel editorial específico.

#### Remediation

Dentro da função, localizar membership de `auth.uid()` para `v_article.municipality_id`, exigir vigência e um papel de publicação explicitamente aprovado, antes de qualquer update. Preferir revogar o grant amplo e expor uma RPC específica com autorização centralizada e auditoria.

Tests:
- Contribuinte, contador e fiscal sem papel editorial recebem negação mesmo com AAL2 e UUID válido.
- Publicador vigente da prefeitura correta publica artigo aprovado e audita o ator.
- Publicador de outra prefeitura e membership expirado são negados antes de qualquer update.

Preventive controls:
- Criar matriz obrigatória de autorização para toda RPC `SECURITY DEFINER` concedida a `authenticated`.
- Separar controles de integridade do recurso dos controles de autorização do ator.

<a id="finding-3"></a>

### [3] Vínculo contábil não verificado libera dados do caso

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | A condição incompleta e os consumidores RLS estão diretamente versionados; a própria migração define estados de relacionamento e verificação separados. |
| Category | authorization-bypass |
| CWE | CWE-863 |
| Affected lines | supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:82-101, supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:167-204, supabase/sql/applied/ia_fiscal_020_due_dates_relationships_and_notice_preflight.sql:1345-1386 |

#### Summary

O helper `private.can_access_case` trata vínculos legados `active` e `can_access_portal` como suficientes, mas omite `relationship_status='linked'`, `verification_status='verified'` e `verified_at`. As políticas de eventos, documentos e mensagens confiam nesse helper para liberar dados fiscais ao contador.

#### Root Cause

A autorização de participante ficou baseada no estado legado `active`, embora o domínio tenha introduzido estados separados de relacionamento e verificação. As políticas RLS posteriores reutilizam esse helper e ampliam o efeito da omissão para três classes de dados do caso.

**Helper usa apenas estados legados** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:82-101`

O helper autoriza o contador sem consultar os campos independentes que provam vínculo e verificação documental.

```sql
or exists (
  select 1
  from public.fiscal_cases fc
  join public.taxpayer_accountant_links tal
    on tal.municipality_id = fc.municipality_id
   and tal.taxpayer_id = fc.taxpayer_id
  join public.accountant_user_links aul
    on aul.municipality_id = tal.municipality_id
   and aul.accounting_firm_id = tal.accounting_firm_id
  where fc.municipality_id = p_municipality_id
    and fc.id = p_case_id
    and tal.status = 'active'
    and tal.can_access_portal
    and tal.valid_from <= now()
    and (tal.valid_until is null or tal.valid_until > now())
    and aul.user_id = (select auth.uid())
    and aul.status = 'active'
    and aul.valid_from <= now()
    and (aul.valid_until is null or aul.valid_until > now())
)
```

**RLS reutiliza o helper para objetos fiscais** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:167-204`

A decisão incompleta propaga-se para eventos, documentos disponíveis e mensagens publicadas do caso.

```sql
using (
  (select private.can_access_case(case_events.municipality_id, case_events.case_id))
  and (case_events.visibility = 'participants' or ...)
);
...
using (
  (select private.can_access_case(case_documents.municipality_id, case_documents.case_id))
  and (case_documents.status = 'available' or ...)
);
...
using (
  (select private.can_access_case(case_messages.municipality_id, case_messages.case_id))
  and ((case_messages.status = 'published' and case_messages.visibility = 'participants') or ...)
);
```

**Modelo exige relação vinculada e verificada** — `supabase/sql/applied/ia_fiscal_020_due_dates_relationships_and_notice_preflight.sql:1345-1386`

O próprio modelo separa status operacional de relação e verificação; portanto `status='active'` não implica os requisitos omitidos.

```sql
add column if not exists relationship_status text not null default 'proposed',
add column if not exists verification_status text not null default 'unverified',
add column if not exists delivery_status text not null default 'blocked';
...
check (
  delivery_status <> 'eligible'
  or (
    relationship_status = 'linked'
    and verification_status = 'verified'
    and status = 'active'
    and verified_at is not null
    and can_receive_initial_notice
  )
);
```

#### Validation

O predicado incompleto foi comparado com o modelo de estados e seguido até todas as políticas RLS que confiam nele.

Validation method: static authorization-helper and downstream RLS trace

**Helper usa apenas estados legados** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:82-101`

O helper autoriza o contador sem consultar os campos independentes que provam vínculo e verificação documental.

```sql
or exists (
  select 1
  from public.fiscal_cases fc
  join public.taxpayer_accountant_links tal
    on tal.municipality_id = fc.municipality_id
   and tal.taxpayer_id = fc.taxpayer_id
  join public.accountant_user_links aul
    on aul.municipality_id = tal.municipality_id
   and aul.accounting_firm_id = tal.accounting_firm_id
  where fc.municipality_id = p_municipality_id
    and fc.id = p_case_id
    and tal.status = 'active'
    and tal.can_access_portal
    and tal.valid_from <= now()
    and (tal.valid_until is null or tal.valid_until > now())
    and aul.user_id = (select auth.uid())
    and aul.status = 'active'
    and aul.valid_from <= now()
    and (aul.valid_until is null or aul.valid_until > now())
)
```

**Modelo exige relação vinculada e verificada** — `supabase/sql/applied/ia_fiscal_020_due_dates_relationships_and_notice_preflight.sql:1345-1386`

O próprio modelo separa status operacional de relação e verificação; portanto `status='active'` não implica os requisitos omitidos.

```sql
add column if not exists relationship_status text not null default 'proposed',
add column if not exists verification_status text not null default 'unverified',
add column if not exists delivery_status text not null default 'blocked';
...
check (
  delivery_status <> 'eligible'
  or (
    relationship_status = 'linked'
    and verification_status = 'verified'
    and status = 'active'
    and verified_at is not null
    and can_receive_initial_notice
  )
);
```

**RLS reutiliza o helper para objetos fiscais** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:167-204`

A decisão incompleta propaga-se para eventos, documentos disponíveis e mensagens publicadas do caso.

```sql
using (
  (select private.can_access_case(case_events.municipality_id, case_events.case_id))
  and (case_events.visibility = 'participants' or ...)
);
...
using (
  (select private.can_access_case(case_documents.municipality_id, case_documents.case_id))
  and (case_documents.status = 'available' or ...)
);
...
using (
  (select private.can_access_case(case_messages.municipality_id, case_messages.case_id))
  and ((case_messages.status = 'published' and case_messages.visibility = 'participants') or ...)
);
```

#### Dataflow

auth.uid() -\> accountant_user_links/taxpayer_accountant_links -\> can_access_case -\> RLS de objetos do caso

- **Source:** sessão de contador e vínculo ativo não verificado

- **Sink:** eventos, documentos e mensagens do caso

- **Outcome:** leitura de dados fiscais antes da verificação

**Helper usa apenas estados legados** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:82-101`

O helper autoriza o contador sem consultar os campos independentes que provam vínculo e verificação documental.

```sql
or exists (
  select 1
  from public.fiscal_cases fc
  join public.taxpayer_accountant_links tal
    on tal.municipality_id = fc.municipality_id
   and tal.taxpayer_id = fc.taxpayer_id
  join public.accountant_user_links aul
    on aul.municipality_id = tal.municipality_id
   and aul.accounting_firm_id = tal.accounting_firm_id
  where fc.municipality_id = p_municipality_id
    and fc.id = p_case_id
    and tal.status = 'active'
    and tal.can_access_portal
    and tal.valid_from <= now()
    and (tal.valid_until is null or tal.valid_until > now())
    and aul.user_id = (select auth.uid())
    and aul.status = 'active'
    and aul.valid_from <= now()
    and (aul.valid_until is null or aul.valid_until > now())
)
```

**RLS reutiliza o helper para objetos fiscais** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:167-204`

A decisão incompleta propaga-se para eventos, documentos disponíveis e mensagens publicadas do caso.

```sql
using (
  (select private.can_access_case(case_events.municipality_id, case_events.case_id))
  and (case_events.visibility = 'participants' or ...)
);
...
using (
  (select private.can_access_case(case_documents.municipality_id, case_documents.case_id))
  and (case_documents.status = 'available' or ...)
);
...
using (
  (select private.can_access_case(case_messages.municipality_id, case_messages.case_id))
  and ((case_messages.status = 'published' and case_messages.visibility = 'participants') or ...)
);
```

#### Reachability

Requer dois links ativos e portal habilitado, mas não requer exploração adicional nem violação entre prefeituras.

- **Attacker:** contador autenticado com relação ainda não verificada

- **Entry point:** consultas autenticadas às tabelas/views protegidas

- **Outcome:** acesso antecipado a dados fiscais do contribuinte

#### Severity

**Medium** — O caminho pode revelar eventos, documentos e mensagens fiscais a uma relação contábil não verificada. Ele depende de uma combinação específica de registros ativos, o que reduz a probabilidade em relação ao impacto potencial.

Elevar se vínculos forem criados automaticamente como active antes da verificação ou se houver volume relevante nesse estado; ignorar somente se constraint ou trigger remoto provar atomicamente que active e can_access_portal implicam linked, verified e verified_at.

#### Remediation

Exigir no ramo do contador `tal.relationship_status='linked'`, `tal.verification_status='verified'` e `tal.verified_at is not null`, além dos controles atuais. Considerar um helper único `private.has_verified_accountant_relationship` reutilizado por leitura e entrega.

Tests:
- Vínculo `active` e `unverified` não acessa eventos, documentos nem mensagens.
- Vínculo `linked`, `verified` e dentro da vigência acessa apenas o contribuinte autorizado.
- Expiração, rejeição ou remoção de `verified_at` revoga acesso imediatamente.

Preventive controls:
- Expressar invariantes de vínculo em uma função server-side única.
- Adicionar testes RLS de matriz de estados para contribuinte, firma e usuário contador.

<a id="finding-4"></a>

### [4] Fila fiscal expõe perguntas de casos sigilosos a fiscais não atribuídos

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | O SQL mostra a cópia do texto, a política municipal sem escopo de caso, a view concedida e o helper separado que exige atribuição para casos sigilosos. |
| Category | information-exposure |
| CWE | CWE-200, CWE-863 |
| Affected lines | supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:404-410, supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:456-489, supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1259-1275, supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:29-44 |

#### Summary

A fila `fiscal_chat_inbox` armazena os primeiros 500 caracteres da mensagem do participante e sua política de leitura exige apenas um papel fiscal na prefeitura. A view concedida a `authenticated` retorna a prévia e a identidade do contribuinte sem aplicar a atribuição exigida para casos `restricted` e `fiscal_secret`.

#### Root Cause

A implementação criou uma projeção paralela de mensagens de casos sem carregar o mesmo predicado de confidencialidade do objeto original. O texto entra na fila, a política autoriza apenas por papel municipal e a view o entrega sem checar a atribuição do caso.

**Trigger copia conteúdo da mensagem** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:476-489`

Texto controlado pelo participante é materializado na fila como `question_preview`, preservando até 500 caracteres do conteúdo fiscal.

```sql
insert into public.fiscal_chat_inbox (
  question_id, municipality_id, case_id, taxpayer_id,
  status, priority, question_preview, handling_mode, ...
)
values (
  new.id, new.municipality_id, new.case_id, v_case.taxpayer_id,
  ...,
  left(v_message.body, 500),
  new.handling_mode, ...
);
```

**Política verifica só papel municipal** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:404-410`

Qualquer `fiscal_auditor` da prefeitura satisfaz a política, mesmo sem atribuição ao caso da pergunta.

```sql
create policy fiscal_chat_inbox_select_staff
  on public.fiscal_chat_inbox for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));
```

**View retorna prévia e identidade** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1259-1275`

A view preserva `question_preview`, contribuinte e caso; `security_invoker` reaplica apenas a política ampla da fila.

```sql
create or replace view public.vw_fiscal_chat_inbox
with (security_invoker = true)
as
select
  fi.municipality_id,fi.question_id,fi.case_id,fc.case_number,fi.taxpayer_id,
  t.legal_name as taxpayer_name,fi.status,fi.priority,fi.question_preview, ...
from public.fiscal_chat_inbox fi
...;

grant select on public.vw_fiscal_chat_inbox to authenticated;
```

**Casos sigilosos exigem atribuição em outro helper** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:29-44`

O controle de caso estabelece a regra esperada: fiscal comum só vê confidencialidade superior quando possui atribuição ativa e vigente.

```sql
fc.confidentiality = 'internal'
or exists (
  select 1
  from public.case_assignments ca
  join public.municipality_memberships mm on ...
  where ca.municipality_id = fc.municipality_id
    and ca.case_id = fc.id
    and ca.status = 'active'
    and mm.user_id = (select auth.uid())
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
)
```

#### Validation

A análise conectou o corpo da mensagem à coluna de prévia, a política RLS à view autenticada e comparou o resultado com o controle esperado de casos sigilosos.

Validation method: static source/control/sink trace against repository policies

**Trigger copia conteúdo da mensagem** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:476-489`

Texto controlado pelo participante é materializado na fila como `question_preview`, preservando até 500 caracteres do conteúdo fiscal.

```sql
insert into public.fiscal_chat_inbox (
  question_id, municipality_id, case_id, taxpayer_id,
  status, priority, question_preview, handling_mode, ...
)
values (
  new.id, new.municipality_id, new.case_id, v_case.taxpayer_id,
  ...,
  left(v_message.body, 500),
  new.handling_mode, ...
);
```

**Política verifica só papel municipal** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:404-410`

Qualquer `fiscal_auditor` da prefeitura satisfaz a política, mesmo sem atribuição ao caso da pergunta.

```sql
create policy fiscal_chat_inbox_select_staff
  on public.fiscal_chat_inbox for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));
```

**View retorna prévia e identidade** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1259-1275`

A view preserva `question_preview`, contribuinte e caso; `security_invoker` reaplica apenas a política ampla da fila.

```sql
create or replace view public.vw_fiscal_chat_inbox
with (security_invoker = true)
as
select
  fi.municipality_id,fi.question_id,fi.case_id,fc.case_number,fi.taxpayer_id,
  t.legal_name as taxpayer_name,fi.status,fi.priority,fi.question_preview, ...
from public.fiscal_chat_inbox fi
...;

grant select on public.vw_fiscal_chat_inbox to authenticated;
```

**Casos sigilosos exigem atribuição em outro helper** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:29-44`

O controle de caso estabelece a regra esperada: fiscal comum só vê confidencialidade superior quando possui atribuição ativa e vigente.

```sql
fc.confidentiality = 'internal'
or exists (
  select 1
  from public.case_assignments ca
  join public.municipality_memberships mm on ...
  where ca.municipality_id = fc.municipality_id
    and ca.case_id = fc.id
    and ca.status = 'active'
    and mm.user_id = (select auth.uid())
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
)
```

#### Dataflow

case_messages.body -\> sync_fiscal_chat_inbox -\> question_preview -\> vw_fiscal_chat_inbox

- **Source:** mensagem do participante

- **Sink:** view autenticada da fila fiscal

- **Outcome:** divulgação de conteúdo e identidade a fiscal não atribuído

**Trigger copia conteúdo da mensagem** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:476-489`

Texto controlado pelo participante é materializado na fila como `question_preview`, preservando até 500 caracteres do conteúdo fiscal.

```sql
insert into public.fiscal_chat_inbox (
  question_id, municipality_id, case_id, taxpayer_id,
  status, priority, question_preview, handling_mode, ...
)
values (
  new.id, new.municipality_id, new.case_id, v_case.taxpayer_id,
  ...,
  left(v_message.body, 500),
  new.handling_mode, ...
);
```

**Política verifica só papel municipal** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:404-410`

Qualquer `fiscal_auditor` da prefeitura satisfaz a política, mesmo sem atribuição ao caso da pergunta.

```sql
create policy fiscal_chat_inbox_select_staff
  on public.fiscal_chat_inbox for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));
```

**View retorna prévia e identidade** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:1259-1275`

A view preserva `question_preview`, contribuinte e caso; `security_invoker` reaplica apenas a política ampla da fila.

```sql
create or replace view public.vw_fiscal_chat_inbox
with (security_invoker = true)
as
select
  fi.municipality_id,fi.question_id,fi.case_id,fc.case_number,fi.taxpayer_id,
  t.legal_name as taxpayer_name,fi.status,fi.priority,fi.question_preview, ...
from public.fiscal_chat_inbox fi
...;

grant select on public.vw_fiscal_chat_inbox to authenticated;
```

#### Reachability

Requer apenas conta `fiscal_auditor` válida na mesma prefeitura; não exige atribuição ao caso.

- **Attacker:** fiscal interno não atribuído

- **Entry point:** SELECT autenticado em `vw_fiscal_chat_inbox`

- **Outcome:** acesso a até 500 caracteres e identificação do caso/contribuinte

#### Severity

**Medium** — Há divulgação direta de conteúdo fiscal e identidade a fiscal interno não atribuído, com caminho simples. A restrição à mesma prefeitura e o recorte de 500 caracteres reduzem o impacto máximo.

Ignorar apenas se a política funcional aprovada conceder expressamente a todo fiscal_auditor acesso à fila de casos sigilosos; elevar se a fila armazenar anexos, texto integral ou dados de outras prefeituras.

#### Remediation

Aplicar a política de visibilidade do caso à fila: para `fiscal_auditor`, exigir `private.can_view_case_staff(municipality_id, case_id)`; manter visibilidade municipal ampla apenas para papéis explicitamente autorizados. Avaliar remover a prévia ou mascará-la até a atribuição.

Tests:
- Fiscal não atribuído não recebe linha nem prévia de caso `restricted` ou `fiscal_secret`.
- Fiscal atribuído recebe a linha esperada; supervisor e revisor jurídico seguem a política aprovada.
- Caso `internal` mantém o comportamento deliberado sem vazar para outra prefeitura.

Preventive controls:
- Reutilizar helpers de autorização do objeto original em toda tabela de projeção ou fila.
- Adicionar testes RLS negativos para cada combinação de papel, confidencialidade e atribuição.

<a id="finding-5"></a>

### [5] Membership fora da vigência ainda pode revisar conhecimento fiscal

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | high |
| Confidence rationale | A consulta de membership e a mudança de estado estão no mesmo corpo SQL, e outros helpers do repositório demonstram a checagem temporal esperada. |
| Category | authorization-bypass |
| CWE | CWE-863 |
| Affected lines | supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:985-1011, supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:39-44 |

#### Summary

A função `ia_review_knowledge_article` procura membership com `status='active'` e papel permitido, mas omite `valid_from` e `valid_until`. Uma linha futura ou expirada que ainda esteja ativa pode registrar decisão e alterar o estado do artigo.

#### Root Cause

A RPC de revisão reimplementa a seleção de membership e omite as duas condições temporais usadas por outros controles. Como a decisão do artigo confia nessa seleção, um vínculo ativo porém fora da vigência continua apto a revisar.

**Revisão omite janela de vigência** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:985-995`

A membership é considerada válida apenas por status e papel; artigos sem `source_question_id` também não passam pelo controle opcional de caso.

```sql
if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
...
select mm.id into strict v_membership_id from public.municipality_memberships mm
 where mm.municipality_id=v_article.municipality_id and mm.user_id=auth.uid()
   and mm.status='active' and mm.role in ('fiscal_auditor','supervisor','legal_reviewer') limit 1;
if v_article.source_question_id is not null and not private.can_review_case(...) then
  raise exception 'knowledge review access denied';
end if;
```

**Decisão altera o estado governado** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:999-1011`

A membership fora da vigência é registrada como revisora e sua decisão muda o estado do artigo.

```sql
insert into public.knowledge_article_reviews (
  municipality_id,article_id,revision_id,decision,reviewer_membership_id,notes,approved_content_sha256
) values (...);
update public.knowledge_articles set status=case when p_decision='approved' then 'approved'
  when p_decision='rejected' then 'rejected' else 'revision_requested' end
 where municipality_id=v_article.municipality_id and id=v_article.id;
```

**Outros controles exigem vigência temporal** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:39-44`

O padrão de autorização do próprio repositório trata status e janela de validade como condições independentes.

```sql
and ca.status = 'active'
and mm.user_id = (select auth.uid())
and mm.status = 'active'
and mm.valid_from <= now()
and (mm.valid_until is null or mm.valid_until > now())
```

#### Validation

A consulta incompleta foi seguida até o registro de revisão e o update do artigo e comparada com o padrão temporal presente em outro helper.

Validation method: static membership-validity and state-change trace

**Revisão omite janela de vigência** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:985-995`

A membership é considerada válida apenas por status e papel; artigos sem `source_question_id` também não passam pelo controle opcional de caso.

```sql
if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
...
select mm.id into strict v_membership_id from public.municipality_memberships mm
 where mm.municipality_id=v_article.municipality_id and mm.user_id=auth.uid()
   and mm.status='active' and mm.role in ('fiscal_auditor','supervisor','legal_reviewer') limit 1;
if v_article.source_question_id is not null and not private.can_review_case(...) then
  raise exception 'knowledge review access denied';
end if;
```

**Decisão altera o estado governado** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:999-1011`

A membership fora da vigência é registrada como revisora e sua decisão muda o estado do artigo.

```sql
insert into public.knowledge_article_reviews (
  municipality_id,article_id,revision_id,decision,reviewer_membership_id,notes,approved_content_sha256
) values (...);
update public.knowledge_articles set status=case when p_decision='approved' then 'approved'
  when p_decision='rejected' then 'rejected' else 'revision_requested' end
 where municipality_id=v_article.municipality_id and id=v_article.id;
```

**Outros controles exigem vigência temporal** — `supabase/sql/applied/ia_fiscal_024_taxpayer_360_access_and_core_views.sql:39-44`

O padrão de autorização do próprio repositório trata status e janela de validade como condições independentes.

```sql
and ca.status = 'active'
and mm.user_id = (select auth.uid())
and mm.status = 'active'
and mm.valid_from <= now()
and (mm.valid_until is null or mm.valid_until > now())
```

#### Dataflow

auth.uid() -\> membership status=active -\> ia_review_knowledge_article -\> review/update

- **Source:** sessão AAL2 com membership fora da vigência

- **Sink:** registro de revisão e estado do artigo

- **Outcome:** decisão fiscal por membro sem vigência atual

**Revisão omite janela de vigência** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:985-995`

A membership é considerada válida apenas por status e papel; artigos sem `source_question_id` também não passam pelo controle opcional de caso.

```sql
if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
...
select mm.id into strict v_membership_id from public.municipality_memberships mm
 where mm.municipality_id=v_article.municipality_id and mm.user_id=auth.uid()
   and mm.status='active' and mm.role in ('fiscal_auditor','supervisor','legal_reviewer') limit 1;
if v_article.source_question_id is not null and not private.can_review_case(...) then
  raise exception 'knowledge review access denied';
end if;
```

**Decisão altera o estado governado** — `supabase/sql/applied/ia_fiscal_supervised_knowledge_chat.sql:999-1011`

A membership fora da vigência é registrada como revisora e sua decisão muda o estado do artigo.

```sql
insert into public.knowledge_article_reviews (
  municipality_id,article_id,revision_id,decision,reviewer_membership_id,notes,approved_content_sha256
) values (...);
update public.knowledge_articles set status=case when p_decision='approved' then 'approved'
  when p_decision='rejected' then 'rejected' else 'revision_requested' end
 where municipality_id=v_article.municipality_id and id=v_article.id;
```

#### Reachability

Requer membership ainda ativa, papel permitido, AAL2 e identificadores do artigo/revisão.

- **Attacker:** ex-membro ou membro ainda não iniciado

- **Entry point:** RPC `ia_review_knowledge_article`

- **Outcome:** aprovação, rejeição ou pedido de revisão não autorizado temporalmente

#### Severity

**Low** — Um usuário futuro ou expirado pode influenciar conhecimento fiscal governado, mas precisa de credenciais válidas, AAL2, papel permitido e UUIDs. A revisão também passa por controles de citação.

Elevar se status permanecer active após expiração com frequência ou se a revisão causar publicação automática; ignorar se constraint ou trigger remoto impedir status=active fora de valid_from/valid_until.

#### Remediation

Adicionar `mm.valid_from <= now()` e `(mm.valid_until is null or mm.valid_until > now())` à seleção e reutilizar um helper central de membership vigente. Negar antes de inserir a revisão ou atualizar o artigo.

Tests:
- Membership futura e expirada recebem negação antes de qualquer insert ou update.
- Membership ativa e vigente com papel permitido revisa normalmente.
- Artigo sem `source_question_id` continua exigindo vigência municipal.

Preventive controls:
- Centralizar a definição de membership ativa e vigente.
- Adicionar testes de fronteira para `valid_from` e `valid_until` em toda RPC privilegiada.

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| Sigilo de casos, fila fiscal e atribuições | authorization and fiscal secrecy | Reported | Foram confirmadas exposição de prévia a fiscal não atribuído e autoatribuição por claim. Evidence: artifacts/02_discovery/in_scope_files.txt, artifacts/02_discovery/candidate_ledger.jsonl, artifacts/01_context/threat_model.md |
| Acesso de contribuinte e contador a casos | tenant and relationship authorization | Reported | O vínculo contábil não verificado foi confirmado; a submissão de pergunta por case_id ficou separadamente pendente. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/raw_candidates_platform.jsonl |
| Submissão de pergunta pelo portal | object-level write authorization | Needs follow-up | A RPC decisiva ia_submit_case_question não está versionada no snapshot. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/raw_candidates_app.jsonl |
| Revisão e publicação de conhecimento fiscal | privileged state transitions | Reported | Foram confirmadas falta de papel na publicação e falta de vigência na revisão. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/raw_candidates_app.jsonl |
| Edge Functions, worker e service_role | privileged backend execution | Rejected | Os candidatos de município controlado pelo cliente e health check foram neutralizados por controles server-side ou não atingiram impacto reportável. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/partition_app.txt, artifacts/02_discovery/partition_platform.txt |
| Rotas, telas e serviços do frontend | client trust boundary | Rejected | Os identificadores de rota revisados chegam a views/RPCs protegidas no servidor; a ausência de gate visual por papel é de UX, não uma barreira de segurança. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/partition_ui.txt |
| Erros, configuração, dependências e pipeline | information exposure and supply chain | Rejected | Nenhum segredo foi encontrado no repositório, o npm audit retornou zero vulnerabilidades e os caminhos de telemetria/configuração revisados não formaram exploração concreta. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/partition_platform.txt |

## Open Questions And Follow Up

- public.ia_submit_case_question deriva a autorização do caso de auth.uid() e rejeita UUID estrangeiro antes de gravar?
  - Follow-up prompt: Quando o acesso remoto voltar, obter pg_get_functiondef e os grants da RPC e executar testes negativos com contribuinte e contador contra caso estrangeiro.
- A definição e os grants de public.ia_submit_case_question não existem no histórico SQL disponível e o conector remoto do Supabase está temporariamente bloqueado por cota.
  - Follow-up prompt: Review deferred unit deferred_submit_case_question_definition and close its stated proof gap. Paths: src/routes/portal.tsx, src/services/supabase-fiscal-service.ts. Surfaces: surface_portal_question_submission.
