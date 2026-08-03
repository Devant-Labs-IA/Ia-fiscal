# IA Fiscal — prontidão do snapshot consolidado

Data: 2 de agosto de 2026
Ambiente: homologação/sandbox
Produção: **CLOSED**

## Resultado executivo

O snapshot está apto a ser versionado, recuperado como código e usado na continuação da
homologação. Ele não está autorizado para produção, ciência fiscal, comunicação externa ou decisão
automatizada.

O ledger inicial em `docs/qa/ledger-initial.json` foi preservado como evidência do estado antes da
consolidação. Este documento registra o estado posterior às correções.

## Gates concluídos neste snapshot

| Gate                                | Resultado                  | Evidência                                                                           |
| ----------------------------------- | -------------------------- | ----------------------------------------------------------------------------------- |
| TypeScript                          | PASS                       | `npm run typecheck`                                                                 |
| Testes frontend                     | PASS                       | 7 arquivos, 22 testes                                                               |
| Smoke visual em homologação         | PASS                       | 10/10 rotas; desktop e 390 px; zero erro, falha de rede ou overflow                 |
| Build de produção                   | PASS                       | Vite/Nitro, preset Vercel                                                           |
| Dependências de runtime             | PASS                       | `npm audit --omit=dev --audit-level=high`: 0 vulnerabilidades                       |
| Segredos administrativos no cliente | PASS                       | varredura sem `service_role`, `sb_secret_` ou chave privada em paths web            |
| Migrações versionadas               | PASS                       | 33/33 nomes, tamanhos e SHA-256 reconciliados                                       |
| Correções de autorização            | PASS em homologação        | migração `20260802230147` aplicada                                                  |
| Regressão SQL de autorização        | PASS em homologação        | teste transacional com rollback e zero identidades sintéticas persistidas           |
| Catálogo remoto                     | CAPTURED                   | fingerprints de colunas, constraints, funções, grants, índices, policies e triggers |
| Edge Functions                      | PASS estático              | 2/2 fontes locais em paridade com versões implantadas; JWT obrigatório              |
| Remediação de segurança             | PASS para os cinco achados | 4 médios e 1 baixo corrigidos; nenhum alto/crítico                                  |

O lint pode emitir avisos de Fast Refresh em componentes utilitários existentes. O critério do gate
é zero erro. O build pode emitir aviso de chunk principal acima de 500 kB; isso é débito de
performance, não falha de autorização.

## Controles implementados

- sessão vinculada a membership ou vínculo ativo, verificado e dentro da janela temporal;
- MFA TOTP obrigatório antes de resolver e renderizar acesso protegido;
- recuperação de senha dedicada, com encerramento global de sessões;
- limpeza do cache ao trocar usuário, entrar/sair da demonstração ou encerrar sessão;
- autorização por caso e por papel sem herança fiscal de administrador técnico;
- publicação de conhecimento restrita a `legal_reviewer` vigente com AAL2;
- escrita proibida para vínculos `readonly`;
- idempotência no banco por usuário, caso, chave e hash do payload;
- idempotência no portal para duplo clique e retry;
- renderização sem dependência de fonte externa e sem chamadas de rede no modo de demonstração;
- nenhuma ação externa sem revisão e confirmação humana.

## Gates ainda fechados

| Gate                          | Estado  | O que falta                                                                          |
| ----------------------------- | ------- | ------------------------------------------------------------------------------------ |
| Replay em banco vazio         | BLOCKED | criar ambiente descartável autorizado, aplicar as 33 migrações e comparar o catálogo |
| Restore de dados              | BLOCKED | backup/restore testado e evidência de RPO/RTO                                        |
| Autenticação E2E              | BLOCKED | usuário de teste, enrollment/challenge TOTP e expiração de sessão                    |
| Recuperação por e-mail E2E    | BLOCKED | template, entrega, redirect allowlist e logout global reais                          |
| Matriz multi-tenant por papel | BLOCKED | navegador + RPC com usuários sintéticos de dois municípios                           |
| Edge runtime                  | BLOCKED | JWT inválido, escopo cruzado, retries e observabilidade em ambiente isolado          |
| IA supervisionada             | BLOCKED | ciclos de proposta, revisão, rejeição e auditoria                                    |
| Performance                   | OPEN    | code splitting e avaliação dos índices sinalizados pelo advisor                      |
| Preview Vercel                | NOT RUN | vincular projeto/ambiente de homologação e validar o commit exato                    |
| Comunicação externa           | CLOSED  | proibida até aprovação operacional e jurídica                                        |
| Produção                      | CLOSED  | todos os gates críticos e sign-offs formais                                          |

## Artefatos de recuperação

- `supabase/migrations/`: cadeia canônica;
- `supabase/baseline/remote-manifest.json`: checksums das 33 migrações;
- `supabase/baseline/catalog-fingerprint.json`: fingerprint do catálogo implantado;
- `supabase/baseline/verification.sql`: consulta determinística de comparação;
- `supabase/baseline/platform-inventory.json`: extensões, buckets, Realtime e Edge;
- `src/types/database.generated.ts`: contrato TypeScript gerado do banco;
- `docs/database/recovery-runbook.md`: procedimento de reconstrução;
- `docs/security/reviews/2026-08-02-remediation.md`: fechamento de segurança.
- `docs/qa/evidence/browser-smoke-2026-08-02.json`: evidência do smoke visual local.

## Decisão

Autorizar somente a publicação deste snapshot no repositório privado e sua continuidade em
homologação controlada. Não autorizar deploy de produção, envio a contribuinte, geração de prazo,
lançamento, autuação ou qualquer ato com efeito jurídico.
