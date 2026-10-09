# 06 — MultiCNC Burn

## Finalidade

Criar e preparar trabalhos de gravação/queima a laser, com ferramentas de desenho simples e importação vetorial/raster. Projeto separado do PCB, compartilhando apenas componentes geométricos, perfis e pós-processamento quando aplicáveis.

## Fluxo e telas

Criar documento com dimensões → importar/desenhar → organizar camadas → escolher material e operação → gerar prévia → exportar trabalho.

Área de desenho, lista de camadas, painel de material/processo, visualização da ordem e resumo de dimensões/passes. Recursos iniciais: formas básicas, texto convertido em contornos, alinhamento, escala e rotação.

## Módulos

| Módulo | Escopo |
| --- | --- |
| Vetorial | SVG com subconjunto documentado; contornos e preenchimentos |
| Raster | PNG/JPEG, escala, contraste e conversão tonal |
| Operações | Gravação de contorno e gravação por varredura |
| Planejamento | Ordem de camadas, passes, intervalos e deslocamentos |
| Processo | Potência/velocidade por perfil e biblioteca de materiais |
| Prévia | Área ocupada, trajetória e representação tonal aproximada |

Corte a laser pode ser acrescentado após confirmação do escopo e validação do equipamento; não é condição do MVP de queima.

## Regras

Conversão tonal e dithering são alternativas explícitas, com algoritmo e parâmetros salvos. Não tratar prévia na tela como reprodução fiel da queima no material. Potência deve ser normalizada no projeto e convertida pelo perfil do controlador; não fixar uma escala numérica para todos os firmwares.

Movimentos de deslocamento devem ter emissão desativada conforme o protocolo escolhido. Estratégias de overscan e modulação dependem das capacidades do perfil e exigem teste. A aplicação de preparação nunca liga o laser para testar enquadramento; qualquer operação física pertence ao Control.

## Aceite

Testes com desenho vetorial e imagem em tons de cinza; dimensão física preservada; trajetórias e passes reproduzíveis; deslocamentos sem solicitação de emissão no resultado gerado; limite de área e recursos incompatíveis bloqueados. Ensaios de material e enquadramento pertencem à homologação de bancada.
