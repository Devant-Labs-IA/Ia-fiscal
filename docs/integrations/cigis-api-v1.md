# Contrato CIGIS ↔ IA Fiscal — API v1

## Objetivo

O CIGIS permanece como fonte de verdade de contribuinte, regime, débitos, pagamentos, conta corrente e fiscalizações. O IA Fiscal recebe somente o contexto autorizado e consulta a API; nenhum token fica no navegador e a IA não acessa tabelas livremente.

## Informações que a equipe CIGIS precisa entregar

### Conectividade

- URL base do ambiente de teste, sempre HTTPS;
- documentação OpenAPI/Swagger ou exemplos completos de requisição e resposta;
- limites de requisição, timeout recomendado e política de indisponibilidade;
- necessidade de IP allowlist ou mTLS, quando aplicável.

### Autenticação máquina a máquina

O gateway já aceita um dos formatos:

1. **OAuth 2.0 Client Credentials — recomendado**
   - `CIGIS_TOKEN_URL`;
   - `CIGIS_CLIENT_ID`;
   - `CIGIS_CLIENT_SECRET`;
   - `CIGIS_SCOPE`, quando existir.

2. **API key restrita ao ambiente de teste**
   - `CIGIS_API_KEY`;
   - nome do cabeçalho, por exemplo `x-api-key`;
   - escopos e data de expiração da chave.

A credencial precisa ser somente leitura, limitada aos endpoints abaixo, com rotação e revogação.

### Contexto do usuário logado no CIGIS

Para abrir o Atendimento Online, o CIGIS deve entregar uma prova assinada de sessão. Contrato recomendado:

- JWT assinado pelo CIGIS;
- `iss`: identificador do CIGIS;
- `aud`: `ia-fiscal`;
- `sub`: identificador do usuário no CIGIS;
- `municipality_id` ou código IBGE;
- `tax_id`: CNPJ/CPF autorizado;
- `role`: contribuinte, contador ou perfil interno;
- `iat`, `exp`, `jti` e nonce de uso único;
- URL JWKS pública ou chave pública para validar assinatura.

O token não pode conter senha, chave de API ou dados fiscais completos. O backend do IA Fiscal resolve o contribuinte autorizado antes de qualquer consulta.

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
  "atualizado_em": "2026-08-26T12:00:00-03:00"
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
  "origem": "CIGIS"
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

Deve retornar a consolidação usada pelo CIGIS e os identificadores dos lançamentos que sustentam o saldo.

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
    "atualizado_em": "2026-08-26T12:00:00-03:00",
    "fonte": "CIGIS"
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

## Casos de teste que a equipe CIGIS deve fornecer

- um CNPJ de cada regime: informador, prestador e Simples Nacional;
- uma competência paga;
- uma competência em aberto;
- uma competência inexistente;
- um caso com divergência e fiscalização;
- um CNPJ que o usuário não pode acessar;
- resposta de API indisponível e limite excedido.

Para cada caso, enviar o resultado esperado para comparação automática.

## Configurações já previstas no backend

```text
CIGIS_BASE_URL
CIGIS_API_PREFIX=/api/v1
CIGIS_TOKEN_URL
CIGIS_CLIENT_ID
CIGIS_CLIENT_SECRET
CIGIS_SCOPE
```

Ou, para API key:

```text
CIGIS_API_KEY
CIGIS_API_KEY_HEADER=x-api-key
```

Nenhum desses valores deve ser enviado por mensagem comum ou salvo no GitHub. Eles devem ser cadastrados diretamente como secrets do backend.
