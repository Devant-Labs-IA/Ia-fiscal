# Reconciliação do histórico Supabase — 2 de agosto de 2026

## Resultado

O projeto remoto `IA Fiscal` (`qvgenxcrdrqyiyozxtdt`) registra 33 migrações, da versão `20260730025805` até `20260802230147`. Cada registro possui exatamente um corpo SQL não vazio em `supabase_migrations.schema_migrations.statements`.

Os 33 corpos SQL estão agora representados em `supabase/migrations/`, usando o timestamp e o nome registrados remotamente. Essa pasta passa a ser a fonte canônica de replay do esquema.

Esta reconciliação comprova a identidade dos artefatos de migração. Ela **não** comprova ainda que um banco vazio pode reproduzir o ambiente remoto nem que não existam mudanças de catálogo executadas fora do histórico.

## Evidência de integridade

O arquivo `supabase/baseline/remote-manifest.json` registra, por migração:

- versão e nome remotos;
- caminho do arquivo canônico;
- tamanho e SHA-256 do arquivo local;
- tamanho e SHA-256 do corpo SQL armazenado remotamente;
- relação exata entre os bytes locais e remotos.

Nas primeiras 32 migrações, o arquivo local contém o corpo remoto exato acrescido de um `LF` terminal. O manifesto mantém os dois hashes, evitando que normalização de texto seja confundida com alteração SQL. Na migração `20260802230147_harden_fiscal_authorization_boundaries`, arquivo local e corpo remoto são byte a byte idênticos e já terminam em `LF`.

Nenhuma das 33 migrações possui rollback registrado no histórico remoto.

## Reconciliação com o arquivo histórico

`supabase/sql/applied/` permanece como evidência histórica parcial. Essa pasta:

- não possui os artefatos originais `001` a `008`;
- não preserva uma correspondência individual para todas as migrações;
- contém três migrações concatenadas no antigo arquivo `013`;
- possui comentários e quebras adicionais em alguns arquivos;
- contém uma versão supervisionada com um bloco de 200 bytes que somente foi aplicado na migração remota seguinte;
- não deve ser usada por `db reset`, `db push`, CI ou qualquer processo de recuperação.

Não renomear, fracionar ou promover arquivos de `supabase/sql/applied/`. Para ordem e conteúdo de replay, usar exclusivamente `supabase/migrations/`.

## Estado de validação

| Controle                                          | Estado        |
| ------------------------------------------------- | ------------- |
| 33 versões e nomes reconciliados                  | concluído     |
| Hash e tamanho dos 33 arquivos locais             | concluído     |
| Hash do corpo SQL remoto das 33 migrações         | concluído     |
| Replay completo em banco vazio descartável        | não executado |
| Comparação de catálogo remoto versus reconstruído | não executada |
| Restore de dados e configurações externas         | não executado |

O Supabase CLI não estava instalado neste workspace durante a reconciliação. Nenhum banco foi criado, reinicializado ou alterado para realizar este trabalho.

## Riscos ainda abertos

1. SQL executado diretamente, sem entrada em `schema_migrations`, só será detectado por comparação de catálogo.
2. Auth, Storage, exposição da Data API, secrets e outras configurações de plataforma não são integralmente reconstruídas pelo histórico SQL.
3. Migrações incluem dados e fixtures de homologação; a execução em banco vazio precisa ser observada e validada.
4. Sem rollback, recuperação deve usar replay progressivo ou restauração de backup verificado.

O procedimento seguro para fechar esses riscos está em `docs/database/recovery-runbook.md`.
