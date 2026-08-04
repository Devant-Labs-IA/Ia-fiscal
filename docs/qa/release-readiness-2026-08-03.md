# IA Fiscal — prontidão de homologação

Data: 3 de agosto de 2026 (Brasília)

Ambiente: Supabase de homologação

Produção: **CLOSED**

## Resultado executivo

O backend e a Edge de busca estão homologados para a fatia supervisionada de assumir atendimento
e pesquisar conteúdo autorizado. O snapshot ainda não pode ser declarado homologado ponta a ponta
porque não existe uma Preview Vercel controlada para os testes reais de navegador. `main`, domínio
de produção e comunicação externa permanecem intocados.

## Gates comprovados

| Gate                       | Estado  | Evidência                                                                 |
| -------------------------- | ------- | ------------------------------------------------------------------------- |
| Histórico Supabase         | PASS    | 36/36 versões, bytes e SHA-256 reconciliados                              |
| Migrações 34–36            | PASS    | duas provas pré-aplicação e regressões pós-aplicação                      |
| Autorização SQL            | PASS    | AAL2, tenant, replay, terminalidade e semântica de assignment             |
| Fronteira operacional      | PASS    | idempotência, reserva de divergência, locks ordenados, ACL e zero entrega |
| Edge `ia-fiscal-search` v3 | PASS    | JWT inválido, AAL1, AAL2 autorizado e tenant incorreto                    |
| Tipos/baseline             | PASS    | catálogo/manifesto recapturados; duas colunas tipadas e validadas         |
| CI do commit final         | PENDING | exige publicação do snapshot atualizado no PR #1                          |
| Vercel Preview             | BLOCKED | nenhum projeto e nenhum canal autenticado com target/env explícitos       |
| Browser E2E                | BLOCKED | depende da Preview e de redirect/CORS exatos                              |
| Produção/entrega externa   | CLOSED  | fora do escopo autorizado                                                 |

## Alertas e riscos residuais

- 17 RPCs `SECURITY DEFINER` continuam expostos intencionalmente a `authenticated`; todos foram
  revisados quanto a `search_path`, papel, AAL2, tenant e finalidade. A matriz web completa ainda é
  obrigatória antes de produção.
- A proteção do Supabase Auth contra senhas vazadas está desabilitada e requer configuração por
  canal administrativo autenticado.
- `ia_rebuild_simple_national_effective_rates` ainda aceita `p_is_test=false` para supervisor
  autenticado sem um gate explícito de estado do município; não contorna tenant nem dispara entrega,
  mas precisa ficar fail-closed antes de qualquer produção.
- O replay das 36 migrações em banco vazio e backup/restore ainda não foram executados.
- A seleção de múltiplas identidades contribuinte/contador é determinística, mas ainda não possui
  seletor explícito de produto.
- O cliente usa o relógio do navegador para antecipar a validade visual do vínculo; o banco usa
  `now()` e nega a operação, portanto o risco residual é uma UI otimista, não bypass de dados.

## Próxima liberação permitida

Somente uma Preview isolada, com Node 22, oito variáveis públicas escopadas a `Preview`, demo
desabilitada, URL exata adicionada ao Auth Redirect e ao CORS da Edge. O primeiro deploy não pode
usar integração Git automática nem target de produção.

## Decisão

`NO-GO` para merge, produção, resposta ao contribuinte ou comunicação externa. `GO` apenas para
publicar o snapshot no PR privado, exigir CI verde e, quando houver autenticação Vercel controlada,
criar a Preview e executar a matriz E2E.
