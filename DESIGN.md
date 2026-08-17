# IA Fiscal — contrato de design

## Princípios

- Interface profissional, sóbria e de alta densidade informacional, adequada ao trabalho fiscal municipal.
- Todo texto visível deve estar em português claro. Códigos internos, snake_case e nomes de regras nunca são apresentados diretamente.
- Situações e regras mostram nome humano e, quando necessário, uma descrição curta do significado operacional.
- Decisões fiscais e jurídicas permanecem humanas; automações são apresentadas como apoio ou triagem.
- Comunicação externa é fail-closed: o estado vem do banco e falhas de leitura aparecem como “estado não verificado”.

## Estrutura visual

- Navegação lateral azul-marinho, barra superior branca e área de trabalho em cinza muito claro.
- Cartões brancos com borda discreta; cor é reservada para prioridade, sucesso, atenção e bloqueio.
- Hierarquia tipográfica: título da página, explicação operacional, seção e metadados.
- Tabelas preservam leitura rápida e devem ter alternativa responsiva.

## Experiência orientada

- Primeiro acesso abre treinamento modal, acessível e obrigatório.
- O treinamento é específico por perfil, versionado e pode ser reaberto em “Ajuda”.
- Cada etapa declara se a função está Disponível, em Simulação, Bloqueada ou é apenas Orientação.
- O tutorial nunca promete envio ou resposta quando o pipeline real não está disponível.

## Segurança e operação

- MFA e isolamento municipal antecedem o conteúdo.
- “Preparar envios externos” apresenta um checklist real; não altera travas nem dispara mensagens.
- Não existe ação visual que contorne contato não verificado, modelo não aprovado ou canal ausente.
- Ações destrutivas ou de alto impacto exigem confirmação explícita e uma trilha auditável no backend.

## Acessibilidade

- Contraste mínimo AA, foco visível e navegação por teclado.
- Diálogos têm título, descrição, foco preso e conteúdo rolável em telas baixas.
- Animações respeitam `prefers-reduced-motion`.
- Estados de carregamento e erro são anunciados sem liberar navegação indevida.
