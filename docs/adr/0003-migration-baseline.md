# ADR 0003 — Scripts aplicados não são migrações replayáveis

- Status: substituído pelo [ADR 0004](0004-canonical-supabase-migrations.md)
- Data: 2 de agosto de 2026

## Contexto

No inventário inicial, o Supabase remoto registrava 32 migrações. O repositório continha scripts
históricos identificados entre `009` e `027`, mas não o baseline `001`–`008` nem um arquivo `022`,
e incluía um script supervisionado sem número. Naquele momento não havia correspondência
comprovada de nomes, ordem, checksums e dependências.

## Decisão

1. Manter os arquivos em `supabase/sql/applied/` como evidência histórica somente leitura.
2. Não tratá-los como `supabase/migrations/` nem executá-los em sequência.
3. Não criar artificialmente os arquivos ausentes.
4. Assim que o acesso remoto permitisse, reconciliar o histórico, obter os artefatos originais e
   verificar checksums.
5. Construir a futura cadeia reprodutível em mudança separada, revisada e testada em banco vazio e clone de homologação.

## Consequências

- não há reconstrução confiável do banco a partir deste commit;
- promoção e produção continuam bloqueadas;
- correções de banco devem ser preparadas, mas não aplicadas sem baseline e plano transacional;
- eventual divergência entre arquivo e remoto deve ser registrada, nunca “corrigida” por replay destrutivo.

## Resultado posterior

Em 2 de agosto de 2026, os corpos SQL das 33 migrações remotas foram recuperados, versionados e
reconciliados por checksum. A decisão de manter `supabase/sql/applied/` apenas como arquivo
histórico continua válida; a fonte canônica passou a ser `supabase/migrations/`.
