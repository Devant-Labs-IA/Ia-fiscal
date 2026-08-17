# Reconciliação do Supabase — 3 de agosto de 2026

Projeto: `qvgenxcrdrqyiyozxtdt` (`IA Fiscal`)

Ambiente: homologação

## Resultado

O histórico remoto e `supabase/migrations/` contêm as mesmas 36 migrações. As três versões
acrescentadas nesta rodada são byte a byte idênticas ao corpo registrado em
`supabase_migrations.schema_migrations.statements[1]`:

| Versão           | Nome                                         |  Bytes | SHA-256                                                            |
| ---------------- | -------------------------------------------- | -----: | ------------------------------------------------------------------ |
| `20260803234455` | `enforce_aal2_and_idempotent_question_claim` | 12.596 | `18126bce373b8202bef8887bec14c14c4ff9f77c8b92925034e3c4d2f05c0fa9` |
| `20260804002339` | `harden_batch_and_response_boundaries`       | 24.435 | `bceb09b9619caf45816c73dbe07920825cdf113af1c7f2073e50d4eee5e5a7f1` |
| `20260804004659` | `revalidate_case_assignment_roles`           | 12.096 | `68a292e493af9b519d7e53778d67fe024482ec1076fe8a4fee0441ee113cb6ee` |

O catálogo implantado foi recapturado em `supabase/baseline/catalog-fingerprint.json`. O manifesto
com as 36 versões, tamanhos e hashes está em `supabase/baseline/remote-manifest.json`.

## Validações executadas

- duas passagens limpas da migração 36 e da regressão operacional em transações com `ROLLBACK`;
- regressão operacional pós-aplicação com `ROLLBACK`;
- regressão completa de autorização pós-aplicação com `ROLLBACK`;
- zero usuários, vínculos, atribuições, lotes, jobs ou tentativas de entrega sintéticos deixados
  pelas regressões;
- `ia-fiscal-search` v3 ativa e aprovada para JWT inválido, AAL1, AAL2 e tenant incorreto;
- advisor de segurança recapturado: 18 avisos informativos deny-all, 17 RPCs
  `SECURITY DEFINER` intencionais e um aviso de proteção contra senhas vazadas desativada.

## Limites deste fechamento

Esta reconciliação prova o estado do catálogo existente; não substitui replay em banco vazio nem
backup/restore. A proteção contra senhas vazadas e as configurações exatas de redirect/CORS da
futura Preview exigem um canal administrativo autenticado. Produção e entrega externa continuam
fechadas.
