# ADR 0005 — Homologação realista e Copiloto read-only

Status: aprovado para implementação em homologação  
Data: 26 de agosto de 2026

## Contexto

A reunião de requisitos definiu que o IA Fiscal deve permitir testes internos mais próximos do
fluxo real: dossiê do contribuinte, prévia da notificação, destinatários internos, histórico de
conversa e consultas assistidas. O CIGIS continuará sendo a fonte de verdade transacional quando a
API estiver disponível.

O risco principal é liberar comunicação ou acesso amplo antes de validar qualidade dos dados,
autorização por CNPJ e isolamento municipal.

## Decisão

1. A homologação recebe uma allowlist derivada exclusivamente de usuários internos ativos.
2. O endereço original do contribuinte nunca é usado na fila de teste.
3. A mensagem de homologação é validada deterministicamente e bloqueia link, anexo e valor.
4. A fila de teste é separada da fila externa e nasce em `provider_pending`; esta entrega não
   habilita provedor nem comunicação externa.
5. O 360 passa a consumir as views existentes de histórico e comunicações.
6. O Copiloto opera somente em leitura e recebe contexto através de uma RPC autorizadora.
7. O modelo não recebe SQL, credencial administrativa ou acesso livre a tabelas.
8. Sem chave/modelo de IA configurados, o Copiloto responde por síntese determinística e declara a
   limitação.
9. A API do CIGIS será conectada posteriormente atrás do mesmo contrato de ferramentas.

## Consequências

- O fluxo pode ser testado com Diego, Narciso e demais usuários internos ativos.
- Nenhum envio real é prometido enquanto o provedor não estiver configurado.
- Dados inconsistentes continuam visíveis como pendência; não são convertidos em conclusão fiscal.
- A ausência da API do CIGIS impede confirmação de pagamento ou conta corrente.
- Novos papéis, ferramentas de escrita e automações exigem ADR e nova aprovação.

## Gates do Gauntlet

1. **Executor:** código, migração e contratos compilam.
2. **Revisor:** política de e-mail, isolamento e estados de erro são testados.
3. **Segurança:** nenhuma chave no cliente; RLS e RPC autorizadora preservadas.
4. **Release:** lint, formatação, TypeScript, testes e build verdes no mesmo commit.
