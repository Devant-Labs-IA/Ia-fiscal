# Configuração das integrações — e-mail, OpenAI e SIGIS

## 1. E-mail interno

Implementação preparada com Resend por API, sem SMTP ou segredo no frontend.

### Informações do domínio fornecido pelo SIGIS

A equipe SIGIS deve fornecer:

- domínio ou subdomínio remetente;
- endereço `From` aprovado;
- subdomínio de recebimento de respostas;
- responsável por publicar os registros DNS.

### Secrets obrigatórios

```text
RESEND_API_KEY
EMAIL_FROM=IA Fiscal <avisos@dominio-fornecido-pelo-sigis.com.br>
```

### Para receber respostas por e-mail

```text
RESEND_WEBHOOK_SECRET
EMAIL_INBOUND_DOMAIN=respostas.dominio-fornecido-pelo-sigis.com.br
```

Opcional:

```text
EMAIL_REPLY_TO=atendimento@dominio-fornecido-pelo-sigis.com.br
```

### Regras aplicadas

- somente destinatários da allowlist interna;
- endereço original do contribuinte nunca é usado;
- mensagem somente texto, sem link, anexo ou valor;
- idempotência por outbox;
- registro de enviado, entregue, falha e devolução;
- resposta recebida somente de remetente interno autorizado;
- anexos recebidos ficam rejeitados nesta fase;
- resposta aceita entra no histórico do processo.

### Configuração no Resend

1. adicionar o domínio fornecido pelo SIGIS;
2. publicar no DNS todos os registros exibidos pelo provedor;
3. aguardar a validação do domínio;
4. criar a API key com escopo mínimo de envio;
5. habilitar o domínio de recebimento, quando forem testadas respostas;
6. cadastrar o webhook apontando para:

```text
https://qvgenxcrdrqyiyozxtdt.supabase.co/functions/v1/ia-fiscal-email-webhook
```

7. habilitar eventos `email.sent`, `email.delivered`, `email.bounced`, `email.failed` e `email.received`;
8. cadastrar o signing secret como `RESEND_WEBHOOK_SECRET` no Supabase.

## 2. OpenAI

### Secrets obrigatórios

```text
OPENAI_API_KEY
```

O modelo possui padrão operacional, mas pode ser definido explicitamente:

```text
OPENAI_MODEL=gpt-5.4-mini
OPENAI_PROJECT_ID=proj_...
```

### Controles aplicados

- chamada somente no backend;
- `store: false`;
- contexto autorizado antes da chamada;
- nenhuma ferramenta de escrita;
- fallback determinístico quando o provedor falha;
- mensagens e documentos são tratados como dados não confiáveis;
- resposta informativa, sem veredito fiscal.

## 3. SIGIS

Configurações e contrato estão em `docs/integrations/sigis-api-v1.md`.

Obrigatório:

```text
SIGIS_BASE_URL
SIGIS_API_PREFIX=/api/v1
```

E um método de autenticação:

```text
SIGIS_TOKEN_URL
SIGIS_CLIENT_ID
SIGIS_CLIENT_SECRET
SIGIS_SCOPE
```

ou:

```text
SIGIS_API_KEY
SIGIS_API_KEY_HEADER=x-api-key
```

Para a sessão aberta dentro do SIGIS:

```text
SIGIS_SESSION_ISSUER
SIGIS_SESSION_AUDIENCE=ia-fiscal
SIGIS_JWKS_URL
```

## 4. Deploy do backend

O workflow `.github/workflows/deploy-internal-test-backend.yml` valida a aplicação, aplica migrações e publica as Edge Functions.

Secrets exigidos no environment `internal-test` do GitHub:

```text
SUPABASE_ACCESS_TOKEN
SUPABASE_DB_PASSWORD
```

O workflow não grava secrets no repositório. A ausência de qualquer secret interrompe a implantação antes de alterar o banco.

## 5. Ordem operacional

1. aplicar as migrações no Supabase;
2. publicar `ia-fiscal-sigis-gateway`, Copiloto e funções de e-mail;
3. cadastrar os secrets de e-mail e OpenAI no Supabase;
4. receber o domínio fornecido pelo SIGIS e validar o DNS;
5. testar envio para Diego ou Narciso;
6. habilitar domínio de recebimento e webhook;
7. receber URL, credencial e sessão assinada do SIGIS;
8. executar os casos de pagamento, débito e isolamento de CNPJ;
9. somente depois avaliar envio para contribuintes reais.
