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

## Segundo Cérebro

- Tese visual: mesa de pesquisa jurídica municipal, onde a evidência oficial domina a resposta.
- Hierarquia obrigatória: pergunta, resultado ou recusa, citações com vigência e ação supervisionada.
- A assinatura da superfície é uma trilha de evidências numerada; ela conecta cada síntese ao dispositivo oficial sem adicionar cartões decorativos.
- A busca fecha com segurança: sem origem HTTPS, texto citado, versão vigente ou verificação do servidor, a interface apresenta recusa e não mostra uma resposta conclusiva.
- Respostas candidatas são sempre identificadas como propostas para revisão humana; nunca aparentam estar publicadas ou aprendidas automaticamente.
- A agenda de atualização e a cobertura do índice mostram estados humanos e horários de Brasília, sem expor expressões cron, nomes de RPC, modelos internos ou códigos técnicos.
- Em celular, resposta e evidências seguem a ordem de leitura; em desktop, podem ficar lado a lado sem reduzir a largura de leitura jurídica.
- Movimento é restrito a indicadores de carregamento e respeita `prefers-reduced-motion`.

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
