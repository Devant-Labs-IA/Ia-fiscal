# ADR 0002 — Comunicação de cortesia não produz ciência fiscal

- Status: aceito para homologação
- Data: 2 de agosto de 2026

## Contexto

O piloto prevê avisar contribuintes sobre a existência de pendência para consulta em ambiente oficial. Ao mesmo tempo, não há evidência versionada suficiente de regulamentação operacional do DTE municipal nem autorização para envio externo.

## Decisão

1. Toda comunicação do MVP é classificada como alerta de cortesia.
2. O alerta não inicia prazo, não comprova ciência e não substitui instrumento formal.
3. A mensagem não contém débito, divergência, nota, competência ou documento fiscal.
4. O único conteúdo transacional permitido, após futura aprovação, será orientação para entrar no ambiente oficial autenticado.
5. Destinatário, e-mail, vínculo contribuinte–contador, template e autorização precisam ser revalidados imediatamente antes do envio.
6. Nesta entrega, e-mail, WhatsApp, SMS, DTE/SIGISS e demais destinos externos permanecem desabilitados.

## Consequências

- nenhum prazo legal pode ser calculado a partir da entrega do alerta;
- métricas devem usar “entrega de cortesia”, não “notificação” ou “ciência”;
- qualquer mudança para canal formal exige novo ADR, parecer jurídico, base normativa oficial, testes e aprovação de produção;
- falha de validação do destinatário bloqueia, não degrada para outro canal.
