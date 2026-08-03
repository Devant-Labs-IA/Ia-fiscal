# Runbook de reconstrução e recuperação do banco

## Objetivo e fronteira

Validar que `supabase/migrations/` consegue reconstruir o banco IA Fiscal e detectar qualquer diferença entre o catálogo reconstruído e o projeto remoto.

Este runbook não autoriza reset, repair, push ou replay no projeto `qvgenxcrdrqyiyozxtdt`. Todos os testes devem ocorrer em ambiente descartável, sem dados reais e sem canais externos habilitados.

## Pré-condições

1. Trabalhar a partir de um commit identificado e sem alterações não revisadas.
2. Validar `supabase/baseline/remote-manifest.json` contra as 33 migrações aplicadas e conferir o
   hash da 34ª migração pendente na evidência de autorização.
3. Instalar uma versão aprovada do Supabase CLI e registrar `supabase --version` na evidência do teste.
4. Descobrir a sintaxe vigente com `supabase --help`, `supabase db --help` e `supabase migration --help`; não presumir flags de outra versão.
5. Criar um projeto ou branch descartável com custo e autorização explícitos.
6. Confirmar que nenhuma Edge Function, webhook, e-mail, fila ou integração externa pode entregar mensagens.
7. Usar somente fixtures anonimizadas de homologação.

## Etapa 1 — Verificar os artefatos, sem banco

1. Confirmar que existem exatamente 34 arquivos `*.sql` em `supabase/migrations/`: 33 aplicados e
   um pendente.
2. Para os 33 aplicados, recalcular tamanho e SHA-256 e confrontar com `local_bytes` e
   `local_sha256` do manifesto. Para o pendente, confrontar o SHA-256 com
   `docs/qa/evidence/supabase-authorization-regression-2026-08-03.json`.
3. Para versões com `byte_relation = remote_plus_terminal_lf`, remover apenas o último byte em memória e comparar com `remote_statement_bytes` e `remote_statement_sha256`.
4. Para `byte_relation = byte_identical`, comparar diretamente o arquivo inteiro.
5. Falhar o processo diante de arquivo extra, versão duplicada, nome divergente ou checksum diferente.

Não modificar arquivos para fazer um checksum passar. Toda divergência deve gerar uma nova reconciliação documentada.

## Etapa 2 — Preparar o ambiente descartável

1. Confirmar por identificação visual e por project ref que o destino não é produção nem o projeto remoto de origem.
2. Registrar região, versão do PostgreSQL, extensões disponíveis e configurações relevantes.
3. Manter entrega externa desabilitada e credenciais reais ausentes.
4. Registrar o identificador do ambiente, responsável e horário de início em Brasília.

## Etapa 3 — Replay da cadeia canônica

1. Aplicar somente `supabase/migrations/`, em ordem lexicográfica pelos timestamps.
2. Capturar stdout, stderr, versão do CLI e a migração exata em caso de falha.
3. Não pular, renumerar ou marcar manualmente migrações como aplicadas para contornar erro.
4. Se uma migração depender de configuração de plataforma, registrar a dependência e reconstruí-la explicitamente; não inserir objetos fictícios no SQL histórico.
5. Ao final, confirmar que o histórico do ambiente descartável contém as 34 versões e nomes.

Estado atual: **replay ainda não executado**.

## Etapa 4 — Comparar catálogos

Produzir inventários determinísticos no projeto remoto e no ambiente reconstruído, incluindo pelo menos:

- schemas, extensões e tipos;
- tabelas, colunas, defaults e identidades;
- chaves, constraints e índices;
- views e materialized views;
- funções, assinaturas, segurança e `search_path`;
- triggers;
- RLS e policies;
- grants de schema, tabela, sequência e função;
- publicações Realtime e objetos de Storage relevantes.

Normalizar somente atributos comprovadamente voláteis, como OIDs. Não ocultar owners, grants ou diferenças de definição. Classificar cada divergência como:

- mudança externa ao histórico;
- diferença de plataforma/versão;
- dado ou fixture esperado;
- defeito de reconstrução.

O catálogo só pode ser declarado equivalente após revisão humana das diferenças.

## Etapa 5 — Validar comportamento e segurança

1. Executar advisors de segurança e desempenho no ambiente descartável.
2. Validar RLS com usuários de municípios diferentes e confirmar negação cruzada.
3. Verificar RPCs privilegiados, AAL2, papéis fiscais e funções `SECURITY DEFINER`.
4. Executar a suíte de validação do backend e os casos de homologação.
5. Confirmar que notificações, e-mails e ações com efeito fiscal continuam bloqueados por aprovação humana e idempotência.
6. Confirmar que nenhum dado real foi copiado ou produzido durante o teste.

## Etapa 6 — Configurações fora das migrações

Inventariar e documentar separadamente:

- configurações de Auth e URLs permitidas;
- schemas expostos pela Data API e grants associados;
- buckets e políticas de Storage;
- Edge Functions, `verify_jwt` e versões implantadas;
- nomes de secrets necessários, sem gravar valores no repositório;
- webhooks, cron, filas e integrações externas;
- política de backup, retenção e restauração.

Esses itens não devem ser declarados recuperáveis apenas porque o replay SQL passou.

## Critérios de aprovação

O baseline só muda para `reproduzível` quando, no mesmo commit:

1. os 33 checksums do baseline aplicado e o hash da migração pendente passam;
2. o replay em banco descartável termina sem intervenção artificial;
3. as 34 versões aparecem no histórico reconstruído;
4. a comparação de catálogo é equivalente ou possui exceções aprovadas e documentadas;
5. testes de RLS, autorização, funções privilegiadas e harness passam;
6. configurações externas possuem inventário e procedimento de restauração;
7. a evidência do teste está arquivada com data, responsável, versões e destino descartável.

Até lá, o estado permanece **baseline reconciliado, replay não comprovado**.

## Recuperação real

Em incidente real, priorizar restore de backup validado quando o objetivo for recuperar dados. Usar replay das migrações para reconstruir estrutura ou criar ambiente limpo, seguido pela restauração controlada de dados e configurações externas.

Não executar `reset`, `repair` ou comandos destrutivos sem resolver o alvo exato, confirmar backup recuperável e obter autorização específica.
