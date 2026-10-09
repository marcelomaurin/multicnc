# 04 — MultiCNC Slice

## Finalidade e escopo

Aplicação exclusiva de preparação para impressão 3D. Proposta inicial: processo FDM/FFF; impressão em resina fica fora da primeira versão até confirmação do equipamento. Não controla a porta serial.

## Fluxo e telas

Biblioteca de projetos → importar malha → posicionar na mesa → escolher impressora/material/qualidade → configurar suportes → fatiar → inspecionar camadas → exportar trabalho.

Editor com vista da mesa, lista de objetos e transformações; painel de perfis; visualizador de camadas; resumo de material e estimativa de duração. Estimativas devem ser identificadas como tais.

## Módulos

| Módulo | Entrega |
| --- | --- |
| Importação | STL no primeiro marco; 3MF em evolução, com testes de unidades/metadados |
| Preparação | Mover, rotacionar, escalar, duplicar e distribuir peças |
| Perfis | Impressora, bico, filamento, temperaturas, camada e velocidades |
| Fatiamento | Camadas, perímetros, preenchimento, suportes, retração e adesão |
| Visualização | Camada, tipo de trajetória e alertas de volume útil |
| Exportação | G-code com pós-processador e pacote de trabalho compatível |

## Estratégia de implementação

Integrar inicialmente um motor de fatiamento existente por processo externo, com versão fixada, parâmetros reproduzíveis, progresso, timeout e cancelamento. Selecionar o motor após avaliar licença, redistribuição, formato de configuração e equipamentos suportados. Não prometer equivalência entre motores ou desenvolver um motor completo como requisito do MVP.

O projeto guarda arquivos de origem, transformações e snapshots dos perfis. O pacote guarda a versão do motor e do pós-processador. Alterar o projeto depois de exportado não modifica trabalhos já enviados.

## Validações e falhas

Detectar arquivo inválido, unidade ambígua, peça fora da mesa, parâmetros incompatíveis e falha do motor. Destacar defeitos de malha quando detectáveis; não afirmar reparação automática completa. Trechos de início/fim de impressão fazem parte do perfil versionado e passam pela validação de compatibilidade.

## Aceite

Importar um modelo de referência, configurar perfil, gerar camadas reproduzíveis e exportar pacote aceito pelo Control. Cancelar fatiamento sem travar a interface; recusar peça fora do volume configurado; registrar motor e perfis utilizados. Execução real depende de homologação serial da impressora.
