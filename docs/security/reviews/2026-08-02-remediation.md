# IA Fiscal — Fechamento da remediação de segurança

> Status em 2 de agosto de 2026: correções implementadas e aplicadas no ambiente remoto tratado como homologação. A promoção para produção continua bloqueada pelos gates descritos neste documento.

## Identificação e escopo

| Campo                          | Valor                                                              |
| ------------------------------ | ------------------------------------------------------------------ |
| Projeto Supabase               | IA Fiscal (`qvgenxcrdrqyiyozxtdt`)                                 |
| Relatório de origem            | `docs/security/reviews/2026-08-02-pre-remediation.md`              |
| SHA-256 da evidência de origem | `9c543d1c74420970c08a7c4d21ea3e250f506cdc1c16c72dc058b8a6b80892af` |
| Migração canônica              | `20260802230147_harden_fiscal_authorization_boundaries.sql`        |
| Registro remoto                | versão `20260802230147`, aplicada                                  |
| Regressão de autorização       | `supabase/tests/authorization_regression.sql`                      |
| Estado de release              | **Produção bloqueada**                                             |

O relatório pré-remediação foi preservado sem alterações. Ele representa o snapshot e as limitações observadas antes das correções. Este documento registra a implementação posterior, a evidência disponível e os testes ainda obrigatórios.

## Conclusão executiva

Os cinco achados do relatório original receberam correção na migração canônica. Os controles agora se apoiam em vínculo municipal vigente, autorização por objeto e papel, AAL2 e transações idempotentes. A migração consta como aplicada no histórico remoto.

Também foram corrigidos riscos identificados durante a remediação: herança indevida de autoridade fiscal por administrador técnico da plataforma, escrita por vínculo somente leitura, reutilização de cache entre identidades, ausência de fluxo completo de MFA/recuperação e idempotência insuficiente no envio de perguntas.

Isso ainda não equivale a uma liberação de produção. A suíte SQL transacional passou no projeto remoto de homologação, sempre dentro de `BEGIN`/`ROLLBACK`, mas sua execução contra um banco descartável reconstruído do zero e a homologação real de MFA/e-mail permanecem pendentes.

## Matriz dos cinco achados

| ID   | Achado original                                                                | Severidade | Correção implementada                                                                                                                                                                                                        | Evidência de regressão                                                                                                                                                                          | Disposição                                                                                       |
| ---- | ------------------------------------------------------------------------------ | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| F-01 | Fiscal podia autoatribuir caso sigiloso ao assumir pergunta                    | Média      | `ia_claim_case_question` exige AAL2, membership municipal vigente e `can_view_case_staff` **antes** de criar atribuição ou alterar a pergunta. Fiscal não atribuído continua sem acesso a caso `restricted`/`fiscal_secret`. | A suíte tenta o claim por fiscal não atribuído, exige rejeição e confirma atomicidade: nenhuma atribuição, mudança de pergunta ou evento. Também confirma o fluxo legítimo do fiscal atribuído. | Implementado, aplicado e aprovado na regressão remota transacional; replay descartável pendente. |
| F-02 | RPC de publicação permitia alterar conhecimento sem papel de publicação        | Média      | `ia_publish_knowledge_article` exige AAL2, confirmação explícita `PUBLICAR` e membership **vigente** de `legal_reviewer`. Permanecem os gates de conteúdo aprovado, hash revisado e fontes jurídicas válidas.                | A suíte inspeciona a definição da função e exige a restrição `current legal reviewer role required`.                                                                                            | Implementado, aplicado e aprovado na regressão remota transacional; replay descartável pendente. |
| F-03 | Vínculo contábil não verificado liberava dados do caso                         | Média      | `can_access_case` agora exige `taxpayer_accountant_links` ativo, `linked`, `verified`, `verified_at`, acesso ao portal e janela de validade; o vínculo do usuário contador também precisa estar ativo, verificado e vigente. | A suíte nega o vínculo `proposed/unverified` e só aceita após `linked/verified`.                                                                                                                | Implementado, aplicado e aprovado na regressão remota transacional; replay descartável pendente. |
| F-04 | Fila fiscal expunha prévia de pergunta de caso sigiloso a fiscal não atribuído | Média      | A policy `fiscal_chat_inbox_select_staff` passou a usar `private.can_view_case_staff(municipality_id, case_id)`. A prévia pode existir na fila, mas sua leitura acompanha a autorização do caso.                             | A suíte exige que a policy use `can_view_case_staff`; os testes de caso também negam leitura ao fiscal não atribuído.                                                                           | Implementado, aplicado e aprovado na regressão remota transacional; replay descartável pendente. |
| F-05 | Membership vencido ou futuro podia revisar conhecimento fiscal                 | Baixa      | `ia_review_knowledge_article` resolve o revisor por `current_municipality_membership_id`, que exige status ativo e janela temporal vigente. Quando existe pergunta de origem, a função também exige `can_review_case`.       | A suíte rejeita memberships vencidos e futuros e verifica que a função de revisão usa o helper de vigência.                                                                                     | Implementado, aplicado e aprovado na regressão remota transacional; replay descartável pendente. |

## Invariantes de autorização após a correção

A migração introduz `private.current_municipality_membership_id(...)` como primitiva para operações fiscais reguladas. Ela deriva a identidade de `auth.uid()`, fixa a prefeitura, exige status ativo e respeita `valid_from`/`valid_until`. O helper não concede exceção a administradores técnicos da plataforma.

| Papel                                          | Leitura de casos                                                              | Claim de pergunta                          | Revisão de caso                        | Publicação de conhecimento            |
| ---------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------ | -------------------------------------- | ------------------------------------- |
| `municipal_admin`                              | Casos e fila da própria prefeitura                                            | Não                                        | Não                                    | Não                                   |
| `supervisor`                                   | Casos internos e sigilosos da própria prefeitura                              | Sim, com AAL2                              | Sim, com AAL2                          | Não                                   |
| `legal_reviewer`                               | Casos internos e sigilosos da própria prefeitura                              | Sim, com AAL2                              | Sim, com AAL2                          | Sim, com AAL2 e confirmação explícita |
| `fiscal_auditor`                               | Internos por papel; `restricted`/`fiscal_secret` somente com atribuição ativa | Apenas quando já pode ver o caso, com AAL2 | Somente com atribuição ativa, com AAL2 | Não                                   |
| `platform_admin` sem membership fiscal vigente | Nenhuma autoridade fiscal por esse papel técnico                              | Não                                        | Não                                    | Não                                   |

Participantes externos continuam sujeitos a vínculo com o contribuinte. Leitura e escrita são decisões distintas: um vínculo `readonly` pode conservar leitura permitida por RLS, mas não pode enviar pergunta.

## Riscos adicionais corrigidos

### Administrador técnico não substitui autoridade fiscal

As funções sensíveis de leitura, revisão, claim e publicação deixaram de depender de qualquer bypass global de `platform_admin`. O teste cria um administrador técnico sem membership municipal e exige que `can_view_case_staff` e `can_review_case` retornem falso.

### Escrita bloqueada para vínculos somente leitura

`ia_submit_case_question` aceita contribuintes apenas com papel `owner`, `legal_representative` ou `authorized_user`. Para contadores, exige relação empresarial e vínculo de usuário ativos, verificados, vigentes e com papel `owner`, `accountant` ou `authorized_user`. `readonly` não satisfaz a autorização de escrita.

### Cache isolado entre identidades

`AuthProvider` limpa o React Query cache antes de mudanças de principal, logout, entrada/saída do modo demonstração e conclusão de recuperação de senha. Também invalida carregamentos de acesso concorrentes. Isso impede que dados carregados pelo principal A permaneçam disponíveis para o principal B ou para o modo demo.

Os testes `AuthContext.cache-isolation.test.tsx` cobrem logout, transição para/de demo e mudança de sessão.

### MFA TOTP e recuperação de senha

O frontend impede a renderização de conteúdo protegido enquanto a sessão estiver em AAL1. Ele oferece cadastro TOTP, challenge e verify para fator existente. O fluxo `PASSWORD_RECOVERY` entra em estado dedicado, aplica política de senha de 12 a 128 caracteres, encerra sessões globalmente após a troca e limpa o cache.

O pedido de recuperação usa redirecionamento com `?recovery=1`. Os testes unitários cobrem matrícula e desafio TOTP, bloqueio AAL1, recuperação, encerramento global e filtros de vigência dos vínculos.

### Idempotência vinculada a usuário e payload

`ia_submit_case_question` exige `client_request_id`, aplica advisory lock transacional por prefeitura/caso/chave e, em replay, compara o autor e o SHA-256 do conteúdo. A mesma chave com mesmo autor e payload retorna a pergunta existente; autor ou payload diferente é rejeitado. A operação grava mensagem, snapshot de acesso, pergunta e evento na mesma transação.

No portal, uma submissão lógica mantém a mesma chave para duplo clique ou retry do mesmo caso e corpo normalizado. A chave é preservada após erro, descartada após sucesso e rotacionada quando caso ou conteúdo mudam; os controles ficam desabilitados durante `pending`.

A suíte SQL exige uma única mensagem para o replay legítimo e rejeita a reutilização da chave com payload diferente. Os testes `-portal-submission.test.ts` e `-portal.integration.test.tsx` cobrem o comportamento do cliente e o bloqueio de segundo disparo.

## Evidências e resultados reproduzíveis

### Estado do banco

- O histórico remoto do Supabase registra a migração `20260802230147_harden_fiscal_authorization_boundaries` como aplicada.

- A fonte canônica está em `supabase/migrations/20260802230147_harden_fiscal_authorization_boundaries.sql`.

- A suíte `supabase/tests/authorization_regression.sql` usa identidades sintéticas dentro de `BEGIN`/`ROLLBACK`; nenhuma fixture ou mutação deve persistir.

- Antes da correção, a suíte reproduziu a falha de claim confidencial no esquema vulnerável.

- A migração concatenada com a suíte passou em transação com rollback; depois da aplicação registrada, a suíte passou novamente sozinha no esquema implantado.

- A execução remota terminou com rollback e a verificação posterior confirmou zero usuários, memberships ou administradores sintéticos persistidos.

- A suíte ainda não foi executada contra uma reconstrução descartável criada a partir de banco vazio.

### Estado do frontend

Verificações reproduzíveis executadas após as correções:

| Verificação                                        | Resultado                                                                                                                          |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `npm exec tsc -- --noEmit`                         | Passou                                                                                                                             |
| `npm exec vitest -- run`                           | Passou: 7 arquivos, 22 testes                                                                                                      |
| `npm run build`                                    | Passou; alvo Vercel/Nitro `nodejs24.x`. Foi executado antes do ajuste final de replay no portal e deve ser repetido no gate final. |
| ESLint no escopo alterado de autenticação e portal | 0 erros; 0 avisos                                                                                                                  |

O build emitiu apenas aviso de chunk acima de 500 kB. Esse aviso é de desempenho e não reabre os achados de autorização.

## Como executar a regressão SQL com segurança

Pré-requisitos:

- banco **descartável** reconstruído pelas migrações versionadas;

- migrações/fixtures canônicas que forneçam um caso confidencial sem atribuição e um vínculo contábil do mesmo contribuinte; os usuários e memberships da prova são criados pela própria suíte e revertidos;

- operador autorizado, sem reutilizar credenciais de produção;

- confirmação de que o destino não é produção.

Execução recomendada a partir da raiz do repositório:

```bash
psql "$IA_FISCAL_DISPOSABLE_DATABASE_URL" \
  --set=ON_ERROR_STOP=1 \
  --file=supabase/tests/authorization_regression.sql
```

O resultado esperado é saída sem exceção e `ROLLBACK` ao final. Qualquer `raise exception` da suíte representa regressão ou fixture incompatível e deve manter o gate fechado.

Não execute todas as migrações históricas em lote sobre o projeto remoto já migrado. O replay deve ocorrer em banco novo e descartável.

## Gates pendentes antes de produção

1. **Replay descartável do banco:** reconstruir um banco vazio com todas as migrações canônicas e executar `authorization_regression.sql` com `ON_ERROR_STOP=1`.

2. **Homologação real de MFA:** cadastrar TOTP com usuário de teste, validar challenge/verify, bloqueio AAL1, troca de usuário e expiração de sessão.

3. **Homologação de recuperação por e-mail:** validar entrega, template, redirect allowlist, deep link `?recovery=1`, troca de senha e encerramento das sessões existentes.

4. **Matriz de papéis ponta a ponta:** provar em navegador e RPC as combinações de prefeitura, papel, confidencialidade, atribuição, vínculo expirado/futuro e vínculo não verificado.

5. **Inventário de bypass legado:** revisar usos remanescentes de helpers genéricos que reconheçam `platform_admin` e confirmar que nenhum deles chega a leitura ou decisão fiscal regulada.

6. **Gate operacional:** manter envios externos, notificações reais, decisões fiscais automáticas e promoção para produção desabilitados até evidência e aprovação humana.

## Critério de encerramento

Os cinco achados estão **remediados e verificados transacionalmente no ambiente remoto de homologação**. Eles só podem ser encerrados para release de produção quando o replay descartável e as homologações de MFA/e-mail forem aprovados e anexados a este registro.

Até lá, o estado correto é: **homologação em andamento; produção não autorizada**.
