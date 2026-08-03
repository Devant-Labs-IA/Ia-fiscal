# IA Fiscal — Entrega técnica do back-end

Data da entrega: 30/07/2026
Projeto Supabase: `IA Fiscal` (`qvgenxcrdrqyiyozxtdt`)
Tenant de homologação: Cordeirópolis-SP (`3512407`)

## Migrações aplicadas

- `simple_national_effective_rates_v2`
  - Arquivo: `ia_fiscal_021_simple_national_effective_rates.sql`
  - SHA-256: `7718bc36da4fd80d4a564b7b82bf10862a8980a46f03bae645f5d3e0e8af19df`
- `due_dates_relationships_notice_preflight_v2`
  - Arquivo: `ia_fiscal_020_due_dates_relationships_and_notice_preflight.sql`
  - SHA-256: `eb6df192029e849af3c801e977277503159aad0a9cf38c9ebef8f9ccf979ffd1`

## Estado operacional validado

- 72 lançamentos de débito com classificação e vencimento confirmados.
- 72 lançamentos vencidos na data da validação.
- 43 vínculos contribuinte–contador ativos para consulta.
- Os 43 vínculos continuam não verificados e bloqueados para entrega.
- 86 candidatos de destinatário preparados: 43 contribuintes e 43 contadores.
- Zero candidato apto para envio enquanto contato, vínculo e autorização não forem validados.
- Template v2 criado em estado `draft`.
- Zero tentativa de entrega externa.

## Vencimentos

- Prestador e Tomador: dia 15 do mês seguinte, com ajuste pelo calendário municipal aplicável.
- Simples Nacional/DAS: dia 20 do mês seguinte, com ajuste por dia útil bancário federal.
- Exceções de sociedade profissional, profissional autônomo e regime especial ficam bloqueadas até classificação própria.

## Simples Nacional

- 30 faixas versionadas dos Anexos I a V.
- Fórmula: `(RBT12 × alíquota nominal − parcela a deduzir) / RBT12`.
- RBT12, RBT12 proporcional, FS12 e Fator R calculados de forma determinística.
- Fator R `>= 0,28`: Anexo III; abaixo de `0,28`: Anexo V, quando aplicável.
- Precisão histórica do PGDAS-D: arredondamento até março/2018 e truncamento a partir de abril/2018.
- Limite efetivo de ISS de 5% nas sextas faixas dos Anexos III, IV e V.
- Estado de homologação: 26 resultados atuais, 2 calculados e 24 bloqueados por dados obrigatórios ausentes.
- Casos calculados de referência:
  - Anexo III: RBT12 120.000, Fator R 0,35, alíquota efetiva 6%, ISS 2,01%.
  - Anexo V: RBT12 120.000, Fator R 0,20, alíquota efetiva 15,5%, ISS 2,17%.

## Segurança e validação

- RLS habilitado em todas as sete novas tabelas.
- Views novas e alteradas usam `security_invoker`.
- Rebuild idempotente: 26 inserções na primeira execução e zero na repetição idêntica.
- Retificações removidas deixam de aparecer como versão corrente.
- Importação posterior da folha corrente gera nova chave determinística e promove o resultado correto.
- Harness final: 6 PASS, 0 FAIL, 0 BLOCK.
- Suíte persistente: 13 PASS, 0 FAIL e 1 bloqueio esperado para configuração futura da ancoragem externa de auditoria.

## Fontes normativas

- Lei Complementar municipal nº 399/2024, arts. 213, 215, 216, 217, 218 e 282.
- Decreto municipal nº 7.096/2025, calendário administrativo de 2026.
- Lei Complementar federal nº 123/2006, texto consolidado.
- Manual do PGDAS-D 2018, versão 4.
- Lei federal nº 14.759/2023, feriado nacional de 20 de novembro.
- Agenda Tributária da Receita Federal de abril de 2026.

Legislação estadual não foi acoplada porque o fluxo atual trata ISS e Simples Nacional e não calcula ICMS nem outra obrigação estadual.

## Pendências deliberadamente bloqueadas

- Reconciliação dos e-mails e vínculos com cadastro oficial.
- Data verificada de início de atividade para os 24 casos sem base suficiente.
- Aprovação do template e autorização expressa de comunicação.
- Configuração do destino externo para ancoragem da trilha de auditoria.
- Nova versão normativa para competências posteriores a 2026.
