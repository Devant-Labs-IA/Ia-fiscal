# ADR 0001 — Fronteiras entre regra, IA e decisão humana

- Status: aceito para homologação
- Data: 2 de agosto de 2026

## Contexto

O sistema combina cálculo tributário determinístico, recuperação de conhecimento e geração assistida. Tratar todos esses resultados como equivalentes criaria risco de erro fiscal, falta de explicabilidade e delegação indevida de competência.

## Decisão

1. Cálculos, elegibilidade, prazos técnicos, deduplicação e permissões usam regra versionada e testável.
2. IA limita-se a interpretar, resumir, priorizar e elaborar rascunhos com fontes e incerteza.
3. Resposta inédita de IA exige revisão fiscal. Reuso automático só é permitido para conteúdo exatamente igual a versão aprovada, publicada e vigente.
4. Lançamento, autuação, penalidade, controvérsia, ciência e comunicação R3 exigem decisão humana competente e auditada.
5. Dado ausente, fonte conflitante, regra vencida ou baixa confiança bloqueiam a automação.

## Consequências

- o produto precisa armazenar versão da regra/fonte, entrada, saída e revisão;
- a UI deve distinguir cálculo, hipótese e decisão;
- prompts não substituem controles de autorização;
- testes devem cobrir escalada e recusa, não apenas respostas bem-sucedidas;
- a latência de revisão é aceita como controle de segurança jurídica.

## Alternativas rejeitadas

- decisão autônoma pelo LLM: não determinística e incompatível com a competência fiscal;
- revisão apenas por amostragem para conteúdo inédito: insuficiente para um ato de alto impacto;
- regra tributária implementada somente em prompt: não versionável/reproduzível o bastante.
