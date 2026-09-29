# Probe Z / Height-map para PCB

A fresagem de isolamento exige profundidade consistente mesmo quando a placa não está perfeitamente plana.

## Implementado
- plano de pontos de probe em grade
- transformação dos pontos para a posição real da PCB
- armazenamento X/Y/Z
- validação mínima
- interpolação IDW para estimar Z entre pontos
- visualização dos pontos planejados no canvas

## Separação de responsabilidades
MultiPCB planeja a grade e aplica a compensação geométrica ao trabalho.
MultiCNC deverá executar os movimentos de probe, receber os valores Z e aplicar os limites de segurança.

## Evolução
Interpolação bilinear por células da grade; import/export do mapa; rejeição de outliers; limite máximo de correção Z; preview de superfície; aplicação da compensação aos segmentos de isolamento; fluxo guiado para probe real.
