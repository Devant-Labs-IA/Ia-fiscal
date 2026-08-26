# Configuração das integrações — e-mail, OpenAI e CIGIS

## 1. E-mail interno

Implementação preparada com Resend por API, sem SMTP no frontend.

### Secrets obrigatórios

```text
RESEND_API_KEY
EMAIL_FROM=IA Fiscal <avisos@dominio-verificado.com.br>
```

### Para receber respostas por e-mail

```text
RESEND_WEBHOOK_SECRET
EMAIL_INBOUND_DOMAIN=respostas.dominio-verificado.com.br
```

Opcional:

```text
EMAIL_REPLY_TO=atendimento@dominio-verificado.com.br
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

1. verificar o domínio remetente;
2. criar a API key com escopo mínimo de envio;
3. habilitar o domínio de recebimento, quando forem testadas respostas;
4. cadastrar o webhook apontando para:

```text
https://qvgenxcrdrqyiyozxtdt.supabase.co/functions/v1/ia-fiscal-email-webhook
```

5. habilitar eventos `email.sent`, `email.delivered`, `email.bounced`, `email.failed` e `email.received`;
6. cadastrar o signing secret como `RESEND_WEBHOOK_SECRET` no Supabase.

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

## 3. CIGIS

Configurações e contrato estão em `docs/integrations/cigis-api-v1.md`.

Obrigatório:

```text
CIGIS_BASE_URL
```

E um método de autenticação:

```text
CIGIS_TOKEN_URL
CIGIS_CLIENT_ID
CIGIS_CLIENT_SECRET
CIGIS_SCOPE
```

ou:

```text
CIGIS_API_KEY
CIGIS_API_KEY_HEADER=x-api-key
```

## 4. Deploy do backend

O workflow `.github/workflows/deploy-internal-test-backend.yml` valida aplicação, aplica migrações e publica as Edge Functions.

Secrets exigidos no environment `internal-test` do GitHub:

```text
SUPABASE_ACCESS_TOKEN
SUPABASE_DB_PASSWORD
```

O workflow não grava secrets no repositório. A ausência de qualquer secret interrompe a implantação antes de alterar o banco.

## 5. Ordem operacional

1. cadastrar `SUPABASE_ACCESS_TOKEN` e `SUPABASE_DB_PASSWORD` no GitHub;
2. executar o workflow de backend;
3. cadastrar os secrets de e-mail e OpenAI no Supabase;
4. testar envio para Diego ou Narciso;
5. habilitar domínio de recebimento e webhook;
6. receber a URL e credencial de teste do CIGIS;
7. executar os casos de pagamento, débito e isolamento de CNPJ;
8. somente depois avaliar envio para contribuintes reais.
