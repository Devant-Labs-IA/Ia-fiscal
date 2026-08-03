# Segurança, LGPD e limites jurídicos

Status: **gate de produção fechado**
Escopo: IA Fiscal em homologação/sandbox
Última revisão técnica: 2 de agosto de 2026

> Este documento é um controle de engenharia e governança. Ele não substitui parecer da Procuradoria, do encarregado de dados ou da autoridade fiscal competente.

## Regras inegociáveis

1. A IA não lança crédito, autua, aplica penalidade, decide controvérsia nem gera ciência.
2. E-mail e portal são, por enquanto, canais de cortesia; não iniciam prazo legal.
3. E-mail não contém débito, divergência, documento fiscal ou outro detalhe protegido. Ele pode apenas orientar o acesso a ambiente oficial autenticado.
4. WhatsApp, SMS, DTE/SIGISS e demais entregas externas permanecem desabilitados.
5. Dados reais não podem ser usados em demonstrações, screenshots, fixtures ou logs.
6. Nenhum segredo administrativo pode chegar ao navegador. Variáveis `VITE_*` são públicas.
7. Retenção e descarte dependem de tabela de temporalidade, obrigação legal e `legal hold`; não implementar hard-delete automático.

## Situação de segurança conhecida

| Controle                   | Evidência atual                                         | Gate                                                             |
| -------------------------- | ------------------------------------------------------- | ---------------------------------------------------------------- |
| RLS                        | habilitada nas 101 tabelas inventariadas                | parcial: políticas por papel não foram testadas E2E              |
| schemas privados/auditoria | 18 tabelas com RLS sem policy                           | bloqueado até confirmar grants e comportamento deny-all          |
| RPCs privilegiados         | 19 `SECURITY DEFINER`; fluxos de maior risco corrigidos | parcial: matriz E2E individual ainda pendente                    |
| Edge Functions             | worker e search em paridade, `verify_jwt=true`          | parcial: autorização funcional ainda precisa de testes negativos |
| usuários reais de teste    | zero usuários/memberships/vínculos validados            | **BLOCKED**                                                      |
| auditoria                  | 949 eventos e zero âncoras no inventário inicial        | **BLOCKED** até verificar integridade/imutabilidade              |
| segredos web               | scanner sem segredo administrativo em path web          | manter scanner no CI e revisar bundle                            |
| entrega externa            | zero tentativas; destino externo desabilitado           | manter fechado                                                   |

O hardening de autorização foi aplicado na migração `20260802230147` e passou na regressão SQL
transacional de homologação. O relatório e os gates remanescentes estão em
[`security/reviews/2026-08-02-remediation.md`](security/reviews/2026-08-02-remediation.md).

## Auditoria obrigatória dos RPCs `SECURITY DEFINER`

Para cada uma das 19 funções sinalizadas:

- identificar owner, assinatura, `search_path`, `EXECUTE` grants e chamadores;
- revogar `PUBLIC` e `authenticated` quando não forem indispensáveis;
- validar identidade com `auth.uid()` dentro da função, sem confiar em IDs fornecidos pelo cliente;
- derivar tenant, papel e escopo a partir de tabelas autorizativas;
- qualificar objetos ou fixar `search_path` seguro;
- testar usuário anônimo, autenticado sem vínculo, fiscal de outro tenant, contribuinte, contador, worker e mantenedor;
- confirmar idempotência, transação e trilha de auditoria;
- registrar evidência e decisão no ledger de QA.

Uma função não é segura apenas por usar `SECURITY DEFINER`; essa opção amplia privilégio e exige justificativa explícita.

## Identidade e autorização

- Autenticação prova a sessão, não o direito aos dados.
- Membership municipal ativa é requisito para equipe interna.
- Contribuinte e contador exigem vínculo ativo, verificado e limitado ao contribuinte.
- Manutenção técnica não concede poder fiscal.
- Contas compartilhadas são proibidas.
- Contas de teste devem ter dados sintéticos, MFA quando suportado e expiração definida.
- Elevação de privilégio, exportação e comunicação exigem autenticação recente e auditoria.

## Dados pessoais, sigilo fiscal e LGPD

### Finalidade e minimização

Tratar apenas o necessário para fiscalização, atendimento e cumprimento de obrigação legal/política pública formalmente mapeada. Cada dataset precisa registrar finalidade, origem, controlador, operador, base legal confirmada, campos pessoais, retenção e consumidores.

Antes da produção, o controlador deve aprovar:

- inventário/registro das operações de tratamento;
- hipótese legal aplicável ao Poder Público e finalidade pública específica;
- Relatório de Impacto à Proteção de Dados quando indicado pelo risco;
- regras de compartilhamento, transparência e atendimento a titulares;
- tabela de temporalidade e procedimento de suspensão por litígio/auditoria;
- encarregado, canal de incidentes e responsáveis pelo acionamento.

### Classificação mínima

| Classe          | Exemplos                                  | Tratamento                                         |
| --------------- | ----------------------------------------- | -------------------------------------------------- |
| público         | legislação publicada                      | cache e exibição permitidos, com versão/fonte      |
| interno         | métricas operacionais sem dado fiscal     | acesso por função; logs limitados                  |
| pessoal         | nome, e-mail, vínculo                     | criptografia, minimização e acesso auditado        |
| fiscal restrito | débitos, notas, divergências, declarações | menor privilégio, sem e-mail, sem logs de conteúdo |
| segredo         | JWT, senha, service role, chave privada   | cofre de segredos; nunca cliente/repositório/log   |

## Limites tributários e de comunicação

- Pelo art. 142 do CTN, a constituição do crédito tributário compete à autoridade administrativa. A automação pode calcular e organizar evidência, mas o ato fiscal exige agente competente.
- ISS devido e recolhido dentro do Simples Nacional não pode ser duplicado por guia municipal. A regra aplicável deve considerar retenções, exceções e a LC 123/2006 antes de gerar qualquer orientação.
- A LC municipal nº 399/2024 prevê disciplina local, porém não há no repositório evidência jurídica versionada suficiente de regulamentação operacional do DTE. Até validação formal, nenhum canal digital do projeto produz ciência ou prazo.
- O primeiro contato do piloto, se futuramente aprovado, será alerta de cortesia sem conteúdo fiscal, com link para ambiente oficial autenticado, destinatário e vínculo previamente revalidados e registro de aprovação humana.
- A obrigatoriedade do Emissor Nacional de NFS-e para ME/EPP optantes pelo Simples Nacional inicia em 1º de setembro de 2026. Qualquer integração futura deve ficar atrás de feature flag e validação normativa; ela está fora do MVP atual.

Decisão detalhada: [`adr/0002-communication-classification.md`](adr/0002-communication-classification.md).

## Comunicação de incidente

Incidente com dado pessoal que possa acarretar risco ou dano relevante deve ser avaliado imediatamente. A Resolução CD/ANPD nº 15/2024 estabelece comunicação à ANPD e aos titulares em três dias úteis, ressalvada legislação específica. O prazo regulatório não elimina a necessidade de contenção imediata, preservação de evidência e acionamento jurídico/encarregado.

Use o runbook [`runbooks/incident-response.md`](runbooks/incident-response.md). Nenhuma pessoa técnica deve comunicar titulares, imprensa ou autoridade isoladamente.

## Gate obrigatório antes de produção

- [ ] completar a matriz E2E individual das 19 funções privilegiadas;
- [ ] testes negativos de RLS por papel e tenant;
- [ ] usuários e vínculos sintéticos de teste;
- [ ] E2E completo com evidências;
- [ ] baseline de banco reprodutível e restore testado;
- [ ] scanner de segredo e revisão do bundle web;
- [ ] retenção, legal hold e descarte aprovados;
- [ ] RIPD/registro de tratamento e parecer LGPD quando aplicáveis;
- [ ] Procuradoria/fiscal validou os atos permitidos e os vedados;
- [ ] canal, template e destinatários aprovados, se houver piloto;
- [ ] monitoramento, alertas, on-call e runbook exercitados;
- [ ] aprovação formal do gate de produção.

## Fontes oficiais

- [Código Tributário Nacional — Lei nº 5.172/1966](https://www.planalto.gov.br/ccivil_03/leis/l5172compilado.htm)
- [Lei Complementar nº 123/2006 — Simples Nacional](https://www.planalto.gov.br/ccivil_03/leis/lcp/lcp123.htm)
- [Lei Complementar nº 116/2003 — ISS](https://www.planalto.gov.br/ccivil_03/leis/lcp/lcp116.htm)
- [LGPD — Lei nº 13.709/2018](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)
- [ANPD — Comunicação de Incidente de Segurança](https://www.gov.br/anpd/pt-br/assuntos/comunicacao-de-incidentes-de-seguranca-cis)
- [Portal Nacional NFS-e — Resolução CGSN nº 189/2026](https://www.gov.br/nfse/pt-br/noticias/nfs-e-e-simples-nacional-obrigatoriedade-de-emissao-atraves-do-emissor-nacional)

A Lei Complementar municipal nº 399/2024 e eventuais decretos devem ser anexados à base normativa a partir da publicação oficial municipal, com hash, vigência e revisão jurídica antes do uso em produção.
