# ADR 0004 — Migrações Supabase canônicas e verificáveis

- Status: aceito
- Data: 2 de agosto de 2026
- Substitui: [ADR 0003](0003-migration-baseline.md)

## Contexto

O projeto remoto registra 33 migrações. Os 32 corpos anteriores e a migração de hardening
`20260802230147` estão disponíveis em `supabase_migrations.schema_migrations` e foram reconciliados
com os arquivos do repositório por versão, nome, tamanho e SHA-256.

## Decisão

1. `supabase/migrations/` é a única fonte canônica de replay.
2. `supabase/baseline/remote-manifest.json` registra os checksums remotos e locais, inclusive a
   normalização de `LF` terminal.
3. `supabase/sql/applied/` permanece imutável como evidência histórica parcial e nunca participa
   de reset, push, CI ou recuperação.
4. Novas mudanças de DDL devem ser migrações forward-only revisadas; não se altera arquivo já
   aplicado.
5. A equivalência do baseline só será aprovada depois de replay em banco vazio e comparação pelo
   fingerprint versionado.

## Consequências

- o histórico SQL implantado agora é recuperável do repositório;
- alterações fora de migração podem ser detectadas por comparação de catálogo;
- produção permanece bloqueada porque replay vazio, restore e configurações externas ainda não
  foram comprovados;
- rollback de banco ocorre por restore validado ou migração compensatória, nunca por reescrita do
  histórico.
