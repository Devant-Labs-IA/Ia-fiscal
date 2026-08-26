# IA Fiscal

Plataforma de apoio à fiscalização tributária municipal, em operação assistida em Cordeirópolis/SP
(`3512407`). O produto cruza dados fiscais, aponta divergências, organiza casos e oferece consulta
supervisionada à base de conhecimento. Cálculos, elegibilidade e permissões são determinísticos;
decisões com efeito fiscal continuam sob responsabilidade humana.

> [!WARNING]
> [!IMPORTANT]
> Cordeirópolis está **ativa para trabalho interno assistido**. Comunicação externa, ciência fiscal,
geração de prazo legal e lançamento automatizado continuam bloqueados até a aprovação dos gates
descritos em [`docs/harness-release-gates.md`](docs/harness-release-gates.md).

## Estado atual

Estado verificado em 26 de agosto de 2026:

- Cordeirópolis está ativa para consultas e testes internos; Araras continua isolada;
- a homologação usa autenticação por senha, acesso por município e segregação de papéis; a produção
  deverá restaurar o gate explícito de MFA/AAL2;
- a Preview Vercel está conectada ao repositório canônico `Devant-Labs-IA/Ia-fiscal`;
- o primeiro acesso possui treinamento versionado e específico por perfil;
- o Contribuinte 360 consolida resumo, histórico, comunicações, débitos, divergências e
  procedimentos;
- o dossiê de notificação permite registrar testes somente para usuários internos ativos;
- a mensagem de teste bloqueia links, anexos e valores por regra determinística;
- o Copiloto IA Fiscal opera somente em leitura e nunca recebe acesso livre a SQL ou tabelas;
- a trava mestra de comunicação externa continua ativa e a fila externa permanece separada;
- ainda não existe provedor de e-mail habilitado para despachar a fila interna de teste;
- a API transacional do CIGIS ainda não está conectada, portanto pagamentos e conta corrente não
  podem ser confirmados pelo Copiloto;
- os dados fiscais atualmente carregados mantêm origem de teste e não devem ser descritos como
  lançamentos ou fatos fiscais definitivamente validados.

O painel “Preparar envios externos” continua informativo e fail-closed. A homologação realista usa
uma outbox separada, derivada de uma allowlist interna, e não altera a trava de comunicação externa.

## Escopo do MVP

- conta corrente e divergências de ISS;
- cruzamento SIGISSWEB × PGDAS-D para empresas do Simples Nacional;
- cálculo determinístico de anexo, base, RBT12, alíquota efetiva e Fator R;
- visão 360 do contribuinte;
- gestão de casos, destinatários candidatos e bloqueios de comunicação;
- dossiê de notificação e histórico de conversa;
- pesquisa na base de conhecimento e rascunhos assistidos por IA, sempre sujeitos às regras de
  supervisão;
- Copiloto global somente leitura, com contexto limitado pela sessão e pelo contribuinte autorizado.

Ficam fora do MVP atual: notificação formal por DTE/SIGISS, WhatsApp/SMS, captura de XML,
pagamentos, aplicativo móvel, decisão fiscal autônoma e módulos comerciais não fiscais.

## Arquitetura

| Camada     | Tecnologia                                     | Responsabilidade                                                                  |
| ---------- | ---------------------------------------------- | --------------------------------------------------------------------------------- |
| Web        | React 19, TanStack Start, TypeScript, Tailwind | interface autenticada e leitura dos contratos fiscais                             |
| Identidade | Supabase Auth                                  | sessão; o acesso efetivo depende de membership ou vínculo válido                  |
| Dados      | Supabase/PostgreSQL                            | RLS, views 360, funções determinísticas, allowlist e trilha de auditoria           |
| Edge       | Search, knowledge, worker e Copiloto           | pesquisa autenticada, processamento e síntese read-only                            |
| IA         | execução supervisionada                        | interpretação e rascunhos; nunca lançamento, autuação, envio ou decisão autônoma   |
| CIGIS      | API pendente                                   | fonte futura de verdade para conta corrente, pagamentos, regime e dados fiscais    |

Detalhes: [`docs/architecture.md`](docs/architecture.md) e
[`docs/adr/0005-homologation-realistic-copilot.md`](docs/adr/0005-homologation-realistic-copilot.md).

## Desenvolvimento local

### Pré-requisitos

- Node.js `22.x`;
- npm compatível com o `package-lock.json`;
- acesso autorizado ao município quando for consultar a base assistida.

### Instalação

```bash
git clone https://github.com/Devant-Labs-IA/Ia-fiscal.git
cd Ia-fiscal
cp .env.example .env.local
npm ci
npm run dev
```

Abra a URL informada pelo Vite. O modo padrão usa a operação assistida no Supabase. O modo de
demonstração usa apenas dados fictícios e não habilita escrita ou comunicação externa.

### Variáveis públicas

| Variável                        | Uso                          | Padrão local               |
| ------------------------------- | ---------------------------- | -------------------------- |
| `VITE_APP_ENV`                  | rótulo operacional           | `assisted_operation`       |
| `VITE_DATA_MODE`                | `supabase` ou `mock`         | `supabase`                 |
| `VITE_ALLOW_DEMO`               | permite sessão demonstrativa | `false`                    |
| `VITE_SUPABASE_URL`             | URL pública do projeto       | projeto IA Fiscal          |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | chave publicável do cliente  | chave `sb_publishable_...` |
| `VITE_MUNICIPALITY_LABEL`       | rótulo do tenant             | `Cordeirópolis/SP`         |
| `VITE_MUNICIPALITY_IBGE`        | código IBGE                  | `3512407`                  |
| `VITE_APP_TIMEZONE`             | timezone civil               | `America/Sao_Paulo`        |

Nunca exponha `service_role`, chaves `sb_secret_`, senha de banco ou tokens de provedores em
variáveis `VITE_*`. `OPENAI_API_KEY` e `OPENAI_MODEL` pertencem exclusivamente aos secrets da Edge
Function do Copiloto.

## Verificações locais

```bash
npm run lint
npm run format:check
npm run typecheck
npm test
npm run build
```

Um build verde comprova integridade estática e de empacotamento; não substitui testes de RLS,
autorização, papéis, Edge Functions ou fluxos E2E.

## Banco e Edge Functions

[`supabase/migrations`](supabase/migrations) é a única fonte canônica de replay. As diferenças
históricas de `LF` terminal são documentadas no manifesto de checksums.

Os arquivos em [`supabase/sql/applied`](supabase/sql/applied) são apenas um **arquivo histórico
parcial** e nunca devem ser executados como cadeia. Antes de qualquer reconstrução, siga o
[`runbook de recuperação`](docs/database/recovery-runbook.md) e confira
[`remote-manifest.json`](supabase/baseline/remote-manifest.json).

## Documentação operacional

- [Arquitetura e contratos](docs/architecture.md)
- [ADR da homologação realista e Copiloto](docs/adr/0005-homologation-realistic-copilot.md)
- [Reconciliação atual do banco](docs/database/reconciliation-2026-08-03.md)
- [Runbook de reconstrução e recuperação](docs/database/recovery-runbook.md)
- [Segurança, LGPD e limites jurídicos](docs/security-lgpd-legal.md)
- [Fechamento da remediação de segurança](docs/security/reviews/2026-08-02-remediation.md)
- [Harness e gates de release](docs/harness-release-gates.md)
- [Runbook de homologação](docs/runbooks/homologation.md)
- [Resposta a incidentes](docs/runbooks/incident-response.md)
- [ADRs](docs/adr)

## Contribuição e publicação

Trabalhe em branch, mantenha os gates verdes e preserve o histórico já publicado. O repositório é
conectado ao Lovable; não faça force push, rebase destrutivo, amend ou squash de commits já enviados.
Nenhuma mudança deve ser promovida a produção enquanto o gate de produção permanecer fechado.

Nenhuma licença pública foi concedida.
