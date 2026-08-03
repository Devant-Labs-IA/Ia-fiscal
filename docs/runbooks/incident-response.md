# Runbook — resposta a incidentes

Aplica-se a vazamento ou acesso indevido, segredo exposto, corrupção de dado fiscal, cálculo incorreto em escala, quebra de RLS, envio externo indevido e indisponibilidade relevante.

## Severidade inicial

| Nível | Exemplo                                                                                         | Resposta                                                 |
| ----- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| SEV-1 | exposição de sigilo/dado pessoal, acesso entre tenants, ato fiscal/envio indevido               | contenção imediata e acionamento executivo/jurídico/LGPD |
| SEV-2 | falha de autorização sem exposição comprovada, corrupção recuperável, indisponibilidade crítica | conter em até a janela operacional definida              |
| SEV-3 | falha localizada sem dado sensível ou efeito fiscal                                             | corrigir no fluxo normal, preservando evidência          |

Na dúvida, classifique no nível mais alto até a triagem.

## 1. Detectar e registrar

- gerar ID do incidente e registrar horário em BRT/UTC;
- preservar request IDs, usuário, tenant, recurso, deployment e commit;
- registrar quem detectou e como, sem copiar dados fiscais desnecessários;
- iniciar linha do tempo imutável.

## 2. Conter

- desabilitar feature flag, rota, RPC ou Edge Function afetada;
- bloquear comunicação externa e pausar worker/filas quando relacionados;
- revogar sessão/token/chave comprometida e restringir grants;
- isolar preview/ambiente; não apagar dados nem logs;
- se a contenção exigir mudança destrutiva, obter aprovação do comandante do incidente.

## 3. Acionar responsáveis

Funções que precisam estar designadas antes da produção:

- comandante do incidente;
- responsável técnico/Supabase/Vercel;
- segurança da informação;
- encarregado de dados/controlador;
- Procuradoria/jurídico;
- autoridade fiscal responsável;
- comunicação institucional.

O repositório não contém nomes ou contatos pessoais. Mantenha a escala em canal privado operacional aprovado.

## 4. Avaliar impacto

- dados/campos e titulares afetados;
- tenants, contribuintes e períodos;
- acesso, alteração, perda ou envio;
- duração e possibilidade de persistência;
- impacto fiscal/jurídico e reversibilidade;
- risco ou dano relevante aos titulares;
- evidência de exploração e terceiros envolvidos.

## 5. Comunicar com governança

Somente controlador/encarregado/jurídico autorizam comunicação a ANPD, titulares, autoridade pública, imprensa ou terceiros. Para incidente com dado pessoal que possa acarretar risco ou dano relevante, considerar o prazo de três dias úteis da Resolução CD/ANPD nº 15/2024, ressalvada legislação específica.

Nunca inclua segredo, vulnerabilidade explorável ou dado fiscal além do necessário na comunicação.

## 6. Erradicar e recuperar

1. Corrigir a causa em branch revisada.
2. Rotacionar credenciais e encerrar sessões afetadas.
3. Validar integridade do banco, RLS, funções, filas e auditoria.
4. Restaurar de backup somente após teste e autorização.
5. Reexecutar testes negativos e regressão completa.
6. Reabrir gradualmente; comunicação externa continua fechada até aprovação própria.

## 7. Pós-incidente

Em até cinco dias úteis internos ou prazo menor definido pelo controlador:

- concluir linha do tempo, causa raiz e alcance;
- registrar controles que falharam e evidências;
- criar ações com responsável e prazo;
- atualizar ameaça, ADR, runbook e testes;
- revisar necessidade de comunicação complementar;
- guardar evidência conforme retenção/legal hold.

## Checklist rápido de vazamento de segredo

- [ ] revogar/rotacionar no provedor;
- [ ] procurar uso indevido em logs;
- [ ] remover do código sem reescrever histórico unilateralmente;
- [ ] tratar o valor anterior como comprometido mesmo após remoção;
- [ ] verificar forks, artefatos, caches e deployments;
- [ ] adicionar regra preventiva no CI;
- [ ] avaliar se o segredo dava acesso a dados pessoais/fiscais.
