# QA do frontend

O estado atual é separado em três artefatos:

- `ledger-initial.json`: evidência histórica anterior à consolidação; não editar retroativamente;
- `ledger-current.json`: estado executável e honesto do snapshot em desenvolvimento;
- `coverage-matrix-current.json`: contrato de rotas, papéis, viewports, estados e acessibilidade.

Execute o contrato estático com:

```bash
npm run qa:contract
```

O comando valida a paridade das onze rotas com a árvore gerada, o caso dinâmico da visão 360, os
limites de 767/768 px, a estrutura do ledger, contratos mínimos de acessibilidade e as fronteiras
estáticas de AAL2, papel fiscal e idempotência. Ele não abre navegador e não converte itens
`BLOCKED` ou `NOT_RUN` em `PASS`.

`evidence/browser-smoke-2026-08-02.json` permanece como evidência histórica: cobriu dez rotas em
Chromium, nos tamanhos 390 px e 1440 px, usando mocks. A próxima execução no navegador deve gerar
nova evidência, incluir `/contribuintes/tp-1` e não sobrescrever o arquivo anterior.

A tentativa desta fatia não produziu nova evidência: o automatizador local não pôde criar o socket
de controle no sandbox e o navegador em nuvem não acessa `127.0.0.1`. O item permanece `NOT_RUN`.
