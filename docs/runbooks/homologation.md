# Runbook — homologação segura

Este runbook cobre execução local, CI, preview e validação integrada. Ele não autoriza produção nem comunicação externa.

## 1. Pré-condições

- [ ] commit/branch identificados e worktree compreendida;
- [ ] `.env.local` contém apenas valores públicos de homologação;
- [ ] `VITE_APP_ENV=homologation`;
- [ ] `VITE_DATA_MODE` definido conscientemente (`mock` para demo sintética; `supabase` para integração);
- [ ] `VITE_ALLOW_DEMO=false` em toda integração/Preview; `true` somente em mock local isolado;
- [ ] destinos externos, WhatsApp, SMS, DTE e e-mail desabilitados;
- [ ] usuário e tenant de teste autorizados, quando houver acesso real;
- [ ] ledger aberto e plano de evidência definido.

## 2. Validação local

```bash
cp .env.example .env.local
npm ci
npm run lint
npm run typecheck
npm test
npm run build
npm run dev
```

Verifique:

- login, recuperação e acesso pendente;
- ausência de segredo no console, HTML e bundle;
- modo Supabase não cai silenciosamente em fixtures;
- loading, vazio, erro e sucesso;
- navegação por teclado e viewports mobile/tablet/desktop;
- nenhuma ação de envio habilitada.

## 3. Preview Vercel

Somente criar preview depois do CI verde.

1. Usar canal autenticado que permita fixar equipe, projeto, diretório, variáveis e target `Preview`.
2. Configurar apenas variáveis públicas da `.env.example`.
3. Não associar domínio oficial nem promover para `Production`.
4. Registrar URL, deployment ID, commit e horário no ledger.
5. Executar smoke test sem dados reais ou com tenant expressamente autorizado.
6. Remover/invalidar previews com dados sensíveis ao fim da validação.

Estado atual: o time conectado não contém projeto e não há CLI/token autenticado com controles de
target e ambiente. O deploy amplo disponível não é seguro para o primeiro uso; o gate permanece
`BLOCKED` e nenhuma implantação Vercel foi criada.

## 4. Validação Supabase

1. Confirmar o project ref antes de qualquer ação.
2. Validar as 36 migrações aplicadas contra `supabase/baseline/remote-manifest.json`.
3. Executar `supabase/tests/authorization_regression.sql` e
   `supabase/tests/operational_boundary_regression.sql` somente com rollback ou em banco descartável.
4. Manter a revisão individual das 17 funções `SECURITY DEFINER` intencionais e confirmar que os
   RPCs de publicação manual/aprovada continuam sem grant para papéis da API.
5. Criar usuários temporários sintéticos de dois municípios para E2E.
6. Executar testes negativos de RLS antes dos positivos.
7. Registrar query, resultado sanitizado, papel, tenant e timestamp.

O runtime da Edge `ia-fiscal-search` v3 já possui evidência de JWT inválido, AAL1, AAL2 e tenant
incorreto em `docs/qa/evidence/edge-search-runtime-2026-08-03.json`. A proteção contra senhas
vazadas do Auth continua pendente de configuração administrativa.

Não execute `supabase/sql/applied/*.sql` em sequência. A cadeia canônica é
`supabase/migrations/*.sql`.

## 5. Matriz E2E mínima

| Papel                   | Deve comprovar                      | Deve negar                                     |
| ----------------------- | ----------------------------------- | ---------------------------------------------- |
| anônimo                 | tela de autenticação                | qualquer dado fiscal/RPC/Edge                  |
| autenticado sem vínculo | acesso pendente                     | dados de qualquer tenant                       |
| fiscal                  | tenant e funções autorizadas        | outro tenant e função administrativa indevida  |
| contribuinte            | próprios dados vinculados           | outro contribuinte, dados internos e auditoria |
| contador                | contribuintes com vínculo válido    | vínculo expirado/não verificado                |
| worker                  | fila/operações técnicas específicas | leitura ampla ou ação humana                   |
| mantenedor              | operação técnica autorizada         | decisão fiscal implícita                       |

## 6. Condições de parada

Interrompa imediatamente se houver:

- acesso cruzado entre tenant/contribuinte;
- segredo administrativo no cliente/log;
- envio ou tentativa externa não planejada;
- alteração de dado possivelmente real durante teste;
- RPC privilegiado sem checagem de identidade/escopo;
- divergência entre fonte normativa e cálculo;
- migração sem baseline/rollback;
- perda de correlação ou trilha de auditoria.

Siga o [runbook de incidente](incident-response.md) quando houver possível exposição, corrupção ou ação externa.

## 7. Encerramento

- atualizar o ledger sem apagar evidência anterior;
- anexar logs sanitizados, screenshots e IDs de deployment;
- remover usuários/fixtures temporários conforme política aprovada;
- confirmar filas zeradas e entrega externa desligada;
- registrar bloqueios, responsável e próximo passo;
- somente marcar PASS quando a evidência puder ser reproduzida.
