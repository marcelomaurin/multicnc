# Posicionamento na mesa Laser

## Implementado
- área útil da mesa
- margem e espaçamento
- múltiplos trabalhos
- X/Y
- rotação
- escala X/Y
- mirror X/Y
- trava de posição
- colisão por bounding box
- zonas proibidas/keep-out
- nesting inicial por linhas
- transformação das coordenadas do desenho para a mesa

## Fluxo
Arte -> dimensões -> posicionamento -> validar -> preview -> gerar trabalho -> MultiCNC -> Frame -> execução.

## Evolução
Canvas visual; drag/drop; zoom/pan; grid/snap; geometria real para colisão/nesting; câmera para alinhamento; fiduciais; origem configurável; rotação livre com bounding box correto; nesting otimizado; múltiplas chapas; reaproveitamento de retalhos.

O movimento físico, Frame e disparo do laser permanecem no MultiCNC.
