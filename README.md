# IA Fiscal

Plataforma de apoio à fiscalização tributária municipal, em operação assistida em Cordeirópolis/SP
(`3512407`). O produto cruza dados fiscais, aponta divergências, organiza casos e oferece consulta
supervisionada à base de conhecimento. Cálculos, elegibilidade e permissões são determinísticos;
decisões com efeito fiscal continuam sob responsabilidade humana.

> [!WARNING]
> [!IMPORTANT]
> Cordeirópolis está **ativa para trabalho interno assistido**. Comunicação externa, ciência fiscal,
> geração de prazo legal e lançamento automatizado continuam bloqueados até a aprovação dos gates
> descritos em [`docs/harness-release-gates.md`](docs/harness-release-gates.md).

## Estado atual

Estado verificado em 13 de agosto de 2026:

- Cordeirópolis está ativa para consultas e testes internos; Araras continua isolada;
- autenticação por senha e TOTP, acesso por município e segregação de papéis permanecem obrigatórios;
- o primeiro acesso possui treinamento versionado e específico por perfil;
- códigos técnicos são convertidos em nomes e explicações em português na camada de apresentação;
- a trava mestra de comunicação externa está ativa e a fila externa está vazia;
- ainda não existem provedor de e-mail, canal ativo, modelo aprovado nem contatos verificados para
  envio real;
- os dados fiscais atualmente carregados mantêm origem de teste e não devem ser descritos como
  lançamentos ou fatos fiscais definitivamente validados.

O painel “Preparar envios externos” é informativo e fail-closed: apresenta o checklist real, mas
não cria jobs nem altera travas. A ativação futura exige infraestrutura de entrega, aprovações,
auditoria e testes ponta a ponta.

## Escopo do MVP

- conta corrente e divergências de ISS;
- cruzamento SIGISSWEB × PGDAS-D para empresas do Simples Nacional;
- cálculo determinístico de anexo, base, RBT12, alíquota efetiva e Fator R;
- visão 360 do contribuinte;
- gestão de casos, destinatários candidatos e bloqueios de comunicação;
- pesquisa na base de conhecimento e rascunhos assistidos por IA, sempre sujeitos às regras de supervisão.

Ficam fora do MVP: notificação formal por DTE/SIGISS, WhatsApp/SMS, chat externo, captura de XML, pagamentos, aplicativo móvel e módulos comerciais não fiscais.

## Arquitetura

| Camada     | Tecnologia                                     | Responsabilidade                                                        |
| ---------- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| Web        | React 19, TanStack Start, TypeScript, Tailwind | interface autenticada e leitura dos contratos fiscais                   |
| Identidade | Supabase Auth                                  | sessão; o acesso efetivo depende de membership ou vínculo válido        |
| Dados      | Supabase/PostgreSQL                            | RLS, views 360, funções determinísticas e trilha de auditoria           |
| Edge       | `ia-fiscal-search`, `ia-fiscal-worker`         | pesquisa fiscal e processamento assíncrono em sandbox                   |
| IA         | execução supervisionada                        | interpretação e rascunhos; nunca lançamento, autuação ou envio autônomo |

Detalhes: [`docs/architecture.md`](docs/architecture.md).

## Desenvolvimento local

### Pré-requisitos

- Node.js `22.x`;
- npm compatível com o `package-lock.json`;
- acesso autorizado ao município quando for consultar a base assistida.

### Instalação

```bash
git clone https://github.com/AlmoreContabilidade/Ia-fiscal.git
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

Nunca exponha `service_role`, chaves `sb_secret_`, senha de banco ou tokens de provedores em variáveis `VITE_*`.

## Verificações locais

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

O mesmo conjunto é executado no CI. Um build verde comprova integridade estática e de empacotamento; não substitui testes de RLS, autorização, papéis ou fluxos E2E.

## Banco e Edge Functions

[`supabase/migrations`](supabase/migrations) é a única fonte canônica de replay. Os 36 arquivos
representam as versões e os corpos SQL registrados remotamente. As diferenças históricas de `LF`
terminal são documentadas no manifesto de checksums.

Os arquivos em [`supabase/sql/applied`](supabase/sql/applied) são apenas um **arquivo histórico
parcial** e nunca devem ser executados como cadeia. Antes de qualquer reconstrução, siga o
[`runbook de recuperação`](docs/database/recovery-runbook.md) e confira
[`remote-manifest.json`](supabase/baseline/remote-manifest.json).

## Documentação operacional

- [Arquitetura e contratos](docs/architecture.md)
- [Reconciliação atual do banco](docs/database/reconciliation-2026-08-03.md)
- [Runbook de reconstrução e recuperação](docs/database/recovery-runbook.md)
- [Segurança, LGPD e limites jurídicos](docs/security-lgpd-legal.md)
- [Fechamento da remediação de segurança](docs/security/reviews/2026-08-02-remediation.md)
- [Harness e gates de release](docs/harness-release-gates.md)
- [Runbook de homologação](docs/runbooks/homologation.md)
- [Resposta a incidentes](docs/runbooks/incident-response.md)
- [ADRs](docs/adr)

## Contribuição e publicação

Trabalhe em branch, mantenha os gates verdes e preserve o histórico já publicado. O repositório é conectado ao Lovable; não faça force push, rebase destrutivo, amend ou squash de commits já enviados. Nenhuma mudança deve ser promovida a produção enquanto o gate de produção permanecer fechado.

O projeto é privado. Nenhuma licença pública foi concedida.
