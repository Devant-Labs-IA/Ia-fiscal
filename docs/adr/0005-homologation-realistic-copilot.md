# ADR 0005 — Operação assistida e Copiloto somente leitura

Status: aprovado  
Data original: 26 de agosto de 2026  
Revisão de nomenclatura: 16 de setembro de 2026

## Contexto

A reunião de requisitos definiu que o IA Fiscal deve permitir uso interno próximo do fluxo real:
dossiê do contribuinte, prévia da notificação, destinatários internos, histórico de conversa e
consultas assistidas. O SIGIS permanece como fonte de verdade transacional quando a API estiver
disponível.

O risco principal é liberar comunicação ou acesso amplo antes de validar qualidade dos dados,
autorização por CNPJ e isolamento municipal.

## Decisão

1. O fluxo interno usa allowlist derivada exclusivamente de usuários internos ativos.
2. O endereço original do contribuinte nunca é usado no envio interno.
3. A mensagem é validada deterministicamente e bloqueia link, anexo e valor.
4. A fila interna é separada da fila externa e nasce em `provider_pending`.
5. O 360 consome as views de histórico e comunicações.
6. O Copiloto opera somente em leitura e recebe contexto por RPC autorizadora.
7. O modelo não recebe SQL, credencial administrativa ou acesso livre a tabelas.
8. Sem chave ou modelo configurado, o Copiloto responde por síntese determinística e declara a
   limitação.
9. A API do SIGIS é acessada pelo gateway canônico `ia-fiscal-sigis-gateway`.
10. A nomenclatura oficial no produto, código novo e documentação é SIGIS.

## Consequências

- O fluxo pode ser usado por Diego, Narciso e demais usuários internos ativos.
- O domínio de e-mail será fornecido pelo SIGIS e precisa ser validado antes do envio.
- Dados inconsistentes permanecem como pendência; não são convertidos em conclusão fiscal.
- A ausência de resposta da API do SIGIS impede confirmação de pagamento ou conta corrente.
- Novos papéis, ferramentas de escrita e automações exigem decisão e revisão próprias.

## Gates do Gauntlet

1. **Executor:** código, migração e contratos compilam.
2. **Revisor:** política de e-mail, isolamento e estados de erro são testados.
3. **Segurança:** nenhuma chave no cliente; RLS e RPC autorizadora preservadas.
4. **Release:** lint, formatação, TypeScript, testes e build verdes no mesmo commit.
