# IA Fiscal

Plataforma de apoio à fiscalização tributária municipal, em operação assistida em Cordeirópolis/SP
(`3512407`). O produto cruza dados fiscais, aponta divergências, organiza casos e oferece consulta
supervisionada à base de conhecimento. Cálculos, elegibilidade e permissões são determinísticos;
decisões com efeito fiscal continuam sob responsabilidade humana.

> [!IMPORTANT]
> Cordeirópolis está ativa para trabalho interno assistido. O envio permanece restrito à allowlist
> interna até a conclusão da integração com o SIGIS, validação do domínio de e-mail e aprovação dos
> gates descritos em [`docs/harness-release-gates.md`](docs/harness-release-gates.md).

## Estado atual

Estado atualizado em 16 de setembro de 2026:

- autenticação por senha, acesso por município e segregação de papéis estão ativos;
- o frontend está conectado ao repositório canônico `Devant-Labs-IA/Ia-fiscal` e publicado pela Vercel;
- o Contribuinte 360 consolida resumo, histórico, comunicações, débitos, divergências e procedimentos;
- o dossiê de notificação apresenta contexto, histórico, conversa e destinatário interno;
- links, anexos e valores são bloqueados no e-mail inicial por regra determinística;
- o contato original do contribuinte nunca é utilizado no fluxo interno;
- o Copiloto IA Fiscal opera somente em leitura e não recebe acesso livre a SQL ou tabelas;
- o gateway canônico `ia-fiscal-sigis-gateway` está preparado para a API do SIGIS;
- envio e recebimento de e-mail estão preparados para domínio fornecido pelo SIGIS;
- pagamentos e conta corrente só poderão ser confirmados após resposta válida da API do SIGIS;
- decisões fiscais continuam sujeitas à validação humana.

## Escopo do MVP

- conta corrente e divergências de ISS;
- cruzamento SIGISSWEB × PGDAS-D para empresas do Simples Nacional;
- cálculo determinístico de anexo, base, RBT12, alíquota efetiva e Fator R;
- visão 360 do contribuinte;
- gestão de casos, destinatários candidatos e bloqueios de comunicação;
- dossiê de notificação e histórico de conversa;
- envio e recebimento de e-mail interno com trilha de auditoria;
- pesquisa na base de conhecimento e rascunhos assistidos por IA, sujeitos à supervisão;
- Copiloto global somente leitura, limitado pela sessão e pelo contribuinte autorizado;
- gateway SIGIS para contribuinte, regime, débitos, pagamentos, conta corrente, histórico e fiscalizações.

Ficam fora do MVP atual: decisão fiscal autônoma, envio irrestrito para contribuintes, WhatsApp/SMS,
captura de XML, aplicativo móvel e módulos comerciais não fiscais.

## Arquitetura

| Camada     | Tecnologia                                     | Responsabilidade                                                                  |
| ---------- | ---------------------------------------------- | --------------------------------------------------------------------------------- |
| Web        | React 19, TanStack Start, TypeScript, Tailwind | interface autenticada e leitura dos contratos fiscais                             |
| Identidade | Supabase Auth                                  | sessão; o acesso efetivo depende de membership ou vínculo válido                  |
| Dados      | Supabase/PostgreSQL                            | RLS, views 360, funções determinísticas, allowlist e trilha de auditoria           |
| Edge       | Search, knowledge, e-mail, SIGIS e Copiloto   | integração autenticada, processamento e síntese somente leitura                   |
| IA         | execução supervisionada                        | interpretação e rascunhos; nunca lançamento, autuação ou decisão autônoma          |
| SIGIS      | API externa                                    | fonte de verdade para conta corrente, pagamentos, regime e dados fiscais           |

Detalhes:

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/integrations/runtime-integrations.md`](docs/integrations/runtime-integrations.md)
- [`docs/integrations/sigis-api-v1.md`](docs/integrations/sigis-api-v1.md)

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

O modo padrão usa a operação assistida no Supabase. O modo de demonstração usa apenas dados
fictícios e não habilita escrita ou comunicação externa.

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
variáveis `VITE_*`. Segredos da OpenAI, do provedor de e-mail e do SIGIS pertencem exclusivamente
ao backend.

## Verificações locais

```bash
npm run lint
npm run format:check
npm run typecheck
npm test
npm run build
```

Um build verde comprova integridade estática e de empacotamento; não substitui testes de RLS,
autorização, papéis, Edge Functions ou fluxos ponta a ponta.

## Banco e Edge Functions

[`supabase/migrations`](supabase/migrations) é a fonte canônica de replay. Os arquivos em
[`supabase/sql/applied`](supabase/sql/applied) são apenas arquivo histórico parcial e nunca devem
ser executados como cadeia. Antes de qualquer reconstrução, siga o
[`runbook de recuperação`](docs/database/recovery-runbook.md).

## Documentação operacional

- [Arquitetura e contratos](docs/architecture.md)
- [Integrações de runtime](docs/integrations/runtime-integrations.md)
- [Contrato SIGIS ↔ IA Fiscal](docs/integrations/sigis-api-v1.md)
- [Reconciliação atual do banco](docs/database/reconciliation-2026-08-03.md)
- [Runbook de reconstrução e recuperação](docs/database/recovery-runbook.md)
- [Segurança, LGPD e limites jurídicos](docs/security-lgpd-legal.md)
- [Harness e gates de release](docs/harness-release-gates.md)
- [Resposta a incidentes](docs/runbooks/incident-response.md)

## Contribuição e publicação

Trabalhe em branch, mantenha os gates verdes e preserve o histórico já publicado. O repositório é
conectado ao Lovable; não faça force push, rebase destrutivo, amend ou squash de commits já enviados.

Nenhuma licença pública foi concedida.
