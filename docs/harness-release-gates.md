# Harness operacional e gates de release

Status em 2 de agosto de 2026: **PARTIAL — snapshot consolidado; produção fechada**

## Objetivo

O harness define como contexto, ferramentas, decisões, segurança, observabilidade e avaliação envolvem o modelo e o restante do sistema. Nenhuma demo visual ou build verde substitui os gates de autorização e integridade fiscal.

## Matriz D/J/H

| Classe             | Responsável                     | Permitido                                       | Exemplos                                             | Evidência mínima                                  |
| ------------------ | ------------------------------- | ----------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------- |
| D — determinístico | código/regra versionada         | executar automaticamente em sandbox/homologação | datas, RBT12, Fator R, deduplicação, bloqueios       | versão, entrada, saída, hash, teste               |
| J — julgamento     | humano competente               | decidir e assinar                               | lançamento, autuação, controvérsia, ciência, exceção | identidade, competência, justificativa, timestamp |
| H — híbrido        | máquina propõe; humano confirma | priorizar e redigir sem efetivar                | classificação assistida, minuta, resposta inédita    | fontes, incerteza, revisor, decisão final         |

Regra de escalada: dúvida jurídica, fonte conflitante, baixa confiança, dado ausente, mudança normativa ou ação externa eleva o fluxo para J/H e bloqueia execução automática.

## Classes de risco

| Risco | Exemplo                                                | Autonomia                             |
| ----- | ------------------------------------------------------ | ------------------------------------- |
| R0    | leitura pública de legislação                          | automática com fonte/versionamento    |
| R1    | leitura interna autorizada                             | automática com RLS e auditoria        |
| R2    | cálculo/rascunho reversível                            | automático, mas revisável e sem envio |
| R3    | ato fiscal, exposição de sigilo ou comunicação externa | humano obrigatório; gate fechado hoje |

## Estado dos gates

| Gate                | Estado               | Motivo/evidência necessária                                         |
| ------------------- | -------------------- | ------------------------------------------------------------------- |
| fonte versionada    | PASS após publicação | verificar árvore e commit no repositório privado                    |
| build/lint/types    | PASS local           | repetir no CI do commit exato                                       |
| testes unitários    | PASS                 | 7 arquivos, 22 testes                                               |
| banco reproduzível  | PARTIAL              | 33/33 migrações reconciliadas; replay vazio ainda não executado     |
| RPC/RLS             | PARTIAL              | hardening e regressão remota passaram; matriz E2E completa pendente |
| autenticação E2E    | BLOCKED              | MFA/recuperação implementados; zero usuários reais de teste         |
| Edge/worker         | PARTIAL              | fonte em paridade e JWT ativo; runtime/observabilidade pendentes    |
| IA supervisionada   | BLOCKED              | faltam execução, revisão, rejeição e auditoria E2E                  |
| preview Vercel      | NOT RUN              | nenhum preview validado para o commit consolidado                   |
| comunicação externa | CLOSED               | proibida por escopo e por gate jurídico/operacional                 |
| produção            | CLOSED               | replay, E2E, restore, operação e aprovações ainda pendentes         |

O ledger inicial contém 31 itens: 11 PASS, 7 FAIL, 9 BLOCKED e 4 NOT_RUN, com quatro defeitos P1, dois P2 e um P3. A cópia imutável desse inventário está em [`qa/ledger-initial.json`](qa/ledger-initial.json). O estado posterior à consolidação está em [`qa/release-readiness-2026-08-02.md`](qa/release-readiness-2026-08-02.md).

## Baseline reconciliado do Supabase

O acesso ao projeto foi restabelecido e o histórico remoto passou a conter 33 migrações. Os corpos
SQL estão versionados em `supabase/migrations` e reconciliados por checksum. A correção de
autorização foi aplicada e passou na regressão SQL transacional.

Isso não fecha o gate de reconstrução: o replay completo em banco descartável e a comparação com
`supabase/baseline/catalog-fingerprint.json` continuam obrigatórios.

## Pipeline de evidência

```mermaid
flowchart TD
    C["Commit identificado"] --> S["CI estático"]
    S --> P["Preview isolado"]
    P --> H["Homologação por papel"]
    H --> A["Aprovações humanas"]
    A --> R["Release controlada"]
```

Qualquer falha retorna o release ao estágio anterior. Produção somente existe quando todos os gates críticos estão PASS no mesmo commit e no mesmo baseline de banco.

## Critérios por estágio

### Commit/CI

- lockfile íntegro e instalação com `npm ci`;
- lint, TypeScript, testes e build verdes;
- nenhum segredo administrativo no cliente ou repositório;
- documentação e ADR atualizados quando o contrato muda.

### Preview

- ambiente de preview, nunca domínio de produção;
- somente dados sintéticos ou tenant explicitamente autorizado;
- navegação mobile/tablet/desktop e estados loading/empty/error;
- sem fallback silencioso para mock quando `VITE_DATA_MODE=supabase`;
- cabeçalhos, logs e bundle revisados quanto a segredo/PII.

### Homologação integrada

- matriz de papéis: anônimo, fiscal, contribuinte, contador, worker e mantenedor;
- isolamento entre tenants e entre contribuintes;
- testes negativos das 19 funções privilegiadas;
- CRUD/transações/idempotência/concorrência onde aplicável;
- Edge Functions com JWT inválido, usuário sem vínculo e escopo cruzado;
- trilha ponta a ponta e correlação de logs;
- IA: resposta conhecida, inédita, rejeitada, fonte vencida e baixa confiança;
- nenhuma entrega externa.

### Produção

- os itens anteriores PASS em duas regressões críticas limpas consecutivas;
- backup e restore comprovados;
- observabilidade, alertas e on-call exercitados;
- documentação LGPD/jurídica aprovada;
- plano de implantação, rollback e janela aprovados;
- sign-off técnico, fiscal, segurança, jurídico e controlador de dados.

## Regras de waiver

- P0/P1 de autorização, sigilo, integridade fiscal, auditabilidade ou dados pessoais não aceitam waiver para produção.
- Bloqueio por ausência de evidência não vira PASS por decisão verbal.
- Waiver permitido deve ter proprietário, justificativa, risco residual, compensação, prazo e aprovador.
- Toda reabertura de gate atualiza o ledger; nunca sobrescrever a evidência inicial.

## Rollback

1. Desabilitar feature flag/rota afetada e congelar novas execuções.
2. Preservar logs, IDs e evidência; não apagar registros fiscais.
3. Reverter aplicação para artefato conhecido sem reescrever histórico.
4. Banco só reverte por migração compensatória revisada e testada; nunca executar os scripts históricos em massa.
5. Validar integridade, RLS e filas antes de reabrir.
6. Registrar causa, impacto e decisão no ledger e post-mortem.
