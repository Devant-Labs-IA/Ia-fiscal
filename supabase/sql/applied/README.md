# Arquivo histórico de SQL aplicado

> [!CAUTION]
> Estes arquivos são **histórico parcial** do ambiente de homologação. Eles não formam uma cadeia de migração replayável. Não execute esta pasta em lote, em ordem alfabética ou contra banco vazio/produção.

## O que esta pasta contém

- scripts numerados `009` a `021`;
- scripts numerados `023` a `027`;
- `ia_fiscal_supervised_knowledge_chat.sql`, sem número de migração;
- nenhum arquivo histórico `001`–`008`;
- nenhum arquivo histórico `022`.

O projeto remoto registra 33 migrações. Todas foram reconciliadas e estão em
`supabase/migrations/`; os checksums estão em `supabase/baseline/remote-manifest.json`.

## Por que não é seguro reproduzir

- esta pasta omite o baseline de schemas, extensões, tipos, tabelas, grants e policies;
- arquivos posteriores podem depender de objetos criados nas primeiras oito migrações;
- número no nome não comprova ordem, checksum ou identidade com o SQL implantado;
- alguns scripts podem ter sido reexecutados, substituídos ou registrados com outro nome;
- o inventário remoto contém mais migrações do que os artefatos locais numerados.

## Regra de uso

Use esta pasta apenas para auditoria, comparação e recuperação de contexto. Para qualquer mudança
nova:

1. crie uma nova migração forward-only em `supabase/migrations/`;
2. não altere nem renumere migrações já aplicadas;
3. teste a cadeia em banco descartável vazio;
4. compare o catálogo usando `supabase/baseline/verification.sql`;
5. documente divergências e atualize o manifesto após aplicação aprovada.

Não execute, renumere ou “complete” esta pasta histórica para alinhar o banco.

Decisão arquitetural: [`../../../docs/adr/0004-canonical-supabase-migrations.md`](../../../docs/adr/0004-canonical-supabase-migrations.md).
