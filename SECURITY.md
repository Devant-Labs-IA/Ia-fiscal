# Política de segurança

O IA Fiscal trata dados pessoais e informações protegidas por sigilo fiscal. Não abra issue pública com vulnerabilidade, credencial, CNPJ associado a débito, documento fiscal ou evidência de exploração.

## Como reportar

Use o canal privado de segurança definido pela organização mantenedora e inclua:

- descrição e impacto potencial;
- ambiente, commit/deployment e horário;
- passos mínimos para reproduzir sem dados reais;
- request/trace IDs sanitizados;
- sugestão de contenção, se houver.

Se o canal privado ainda não estiver configurado, interrompa a divulgação e solicite ao administrador da organização a abertura de um canal confidencial. Não envie segredo ou dado fiscal por e-mail comum, chat público ou issue.

## Resposta

O time deve seguir [`docs/runbooks/incident-response.md`](docs/runbooks/incident-response.md). Incidentes envolvendo dado pessoal podem exigir avaliação e comunicação sob a Resolução CD/ANPD nº 15/2024.

## Escopo atual

Cordeirópolis está em operação assistida para consultas, cadastro e testes internos autenticados.
Comunicação externa, ciência fiscal e geração de prazo legal permanecem bloqueadas até que provedor,
canal, modelos, contatos e aprovações sejam verificados. O bloqueio é aplicado no banco e não pode
ser removido por uma alteração apenas visual no cliente web.
