# Contrato SIGIS ↔ IA Fiscal — API v1

## Objetivo

O SIGIS permanece como fonte de verdade de contribuinte, regime, débitos, pagamentos, conta corrente e fiscalizações. O IA Fiscal recebe somente o contexto autorizado e consulta a API; nenhum token fica no navegador e a IA não acessa tabelas livremente.

## Informações que a equipe SIGIS precisa entregar

### 1. Conectividade

- URL base HTTPS do ambiente de integração;
- URL base HTTPS do ambiente de produção, quando aprovada;
- documentação OpenAPI/Swagger ou exemplos completos de requisição e resposta;
- limites de requisição, timeout recomendado e política de indisponibilidade;
- necessidade de IP allowlist, VPN ou mTLS, quando aplicável;
- contato técnico responsável por incidentes e mudança de contrato.

### 2. Autenticação máquina a máquina

O gateway aceita um dos formatos:

1. **OAuth 2.0 Client Credentials — recomendado**
   - `SIGIS_TOKEN_URL`;
   - `SIGIS_CLIENT_ID`;
   - `SIGIS_CLIENT_SECRET`;
   - `SIGIS_SCOPE`, quando existir.

2. **API key somente leitura**
   - `SIGIS_API_KEY`;
   - nome do cabeçalho, por exemplo `x-api-key`;
   - escopos, data de expiração, rotação e revogação da chave.

A credencial deve ser somente leitura e limitada aos endpoints documentados neste contrato.

### 3. Contexto do usuário logado no SIGIS

Para abrir o Atendimento Online, o SIGIS deve entregar uma prova assinada de sessão. Contrato recomendado:

- JWT assinado pelo SIGIS;
- `iss`: identificador do SIGIS;
- `aud`: `ia-fiscal`;
- `sub`: identificador estável do usuário;
- `municipality_id` ou código IBGE;
- `tax_id`: CNPJ/CPF autorizado;
- `role`: contribuinte, contador ou perfil interno;
- `iat`, `exp`, `jti` e nonce de uso único;
- URL JWKS pública ou chave pública para validação da assinatura.

O token não pode conter senha, chave de API ou dados fiscais completos. O backend do IA Fiscal resolve o município, o usuário e o contribuinte autorizado antes de qualquer consulta.

### 4. Domínio de e-mail fornecido pelo SIGIS

A equipe SIGIS deve informar:

- domínio ou subdomínio exclusivo para envio, por exemplo `avisos.sigis.exemplo.br`;
- endereço remetente aprovado, por exemplo `IA Fiscal <avisos@avisos.sigis.exemplo.br>`;
- subdomínio de recebimento de respostas, por exemplo `respostas.sigis.exemplo.br`;
- acesso ao DNS ou responsável que publicará os registros;
- política de retenção e responsável pelo domínio.

O provedor de e-mail entregará os registros DNS necessários. Normalmente serão publicados registros de autenticação de remetente e roteamento de respostas. Nenhum e-mail será liberado antes da validação do domínio e do teste de entrega para a allowlist interna.

## Endpoints mínimos esperados

Prefixo padrão implementado: `/api/v1`. O prefixo pode ser alterado por configuração.

### 1. Contribuinte

`GET /api/v1/contribuintes/{cnpj}`

Resposta mínima:

```json
{
  "cnpj": "00000000000000",
  "inscricao_municipal": "12345",
  "razao_social": "Empresa Exemplo Ltda.",
  "nome_fantasia": "Empresa Exemplo",
  "situacao_cadastral": "ativa",
  "atualizado_em": "2026-09-16T12:00:00-03:00"
}
```

### 2. Regime fiscal

`GET /api/v1/contribuintes/{cnpj}/regime`

```json
{
  "codigo": "simples_nacional",
  "descricao": "Simples Nacional",
  "vigencia_inicio": "2026-01-01",
  "vigencia_fim": null,
  "origem": "SIGIS"
}
```

Códigos iniciais aceitos: `simples_nacional`, `prestador`, `informador`, `nao_informado`.

### 3. Débitos

`GET /api/v1/contribuintes/{cnpj}/debitos?competencia=YYYY-MM`

Cada item deve informar:

- identificador estável;
- competência;
- regime;
- origem;
- vencimento;
- situação;
- valor constituído, pago e saldo, somente na resposta autenticada da API;
- data de atualização.

### 4. Pagamentos

`GET /api/v1/contribuintes/{cnpj}/pagamentos?competencia=YYYY-MM`

Cada pagamento deve informar identificador, competência, data, valor, situação, documento de origem e data de atualização. A ausência de registro deve ser diferenciada de indisponibilidade da API.

### 5. Conta corrente

`GET /api/v1/contribuintes/{cnpj}/conta-corrente?competencia=YYYY-MM`

Deve retornar a consolidação usada pelo SIGIS e os identificadores dos lançamentos que sustentam o saldo.

### 6. Histórico

`GET /api/v1/contribuintes/{cnpj}/historico?data_inicial=YYYY-MM-DD&data_final=YYYY-MM-DD`

Itens mínimos: tipo, título, resumo, data/hora, identificador do processo e visibilidade.

### 7. Fiscalizações

`GET /api/v1/contribuintes/{cnpj}/fiscalizacoes`

Itens mínimos: número do processo, situação, abertura, atualização, resumo, referência da divergência e indicador de revisão fiscal.

## Padrão de resposta

Toda resposta deve incluir:

```json
{
  "data": {},
  "meta": {
    "request_id": "uuid-ou-id-rastreavel",
    "atualizado_em": "2026-09-16T12:00:00-03:00",
    "fonte": "SIGIS"
  }
}
```

Erros mínimos:

- `400` parâmetro inválido;
- `401` credencial inválida;
- `403` CNPJ/escopo não autorizado;
- `404` registro inexistente;
- `409` estado inconsistente;
- `429` limite excedido;
- `503` serviço indisponível.

Nunca retornar `200` com dados inventados ou vazios para esconder indisponibilidade.

## Casos de teste que a equipe SIGIS deve fornecer

- um CNPJ de cada regime: informador, prestador e Simples Nacional;
- uma competência paga;
- uma competência em aberto;
- uma competência inexistente;
- um caso com divergência e fiscalização;
- um CNPJ que o usuário não pode acessar;
- resposta de API indisponível;
- resposta de limite excedido;
- usuário com mais de um CNPJ, quando esse cenário existir.

Para cada caso, enviar o resultado esperado para comparação automática.

## Configurações previstas no backend

```text
SIGIS_BASE_URL
SIGIS_API_PREFIX=/api/v1
SIGIS_TOKEN_URL
SIGIS_CLIENT_ID
SIGIS_CLIENT_SECRET
SIGIS_SCOPE
```

Ou, para API key:

```text
SIGIS_API_KEY
SIGIS_API_KEY_HEADER=x-api-key
```

Para a sessão embutida no SIGIS:

```text
SIGIS_SESSION_ISSUER
SIGIS_SESSION_AUDIENCE=ia-fiscal
SIGIS_JWKS_URL
```

Nenhum desses valores deve ser enviado por mensagem comum ou salvo no GitHub. Eles devem ser cadastrados diretamente como secrets do backend.

## Critérios de aceite da integração

1. Usuário autorizado consulta somente o próprio CNPJ ou o escopo permitido ao seu perfil.
2. Usuário não autorizado recebe `403`, sem revelar a existência dos dados.
3. Pagamento e conta corrente são informados somente quando a API do SIGIS retorna evidência.
4. Indisponibilidade do SIGIS produz resposta explícita, sem inferência da IA.
5. Toda chamada registra correlação, usuário, município, CNPJ mascarado, endpoint, tempo e resultado técnico.
6. Tokens e chaves não aparecem no navegador, logs ou respostas.
7. O e-mail inicial não contém link, anexo ou valor e é enviado apenas à allowlist interna enquanto o fluxo externo estiver bloqueado.
