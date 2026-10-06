# LaserPCB - Guia para IA

## Finalidade
Preparacao de placas PCB para processo laser: layout, posicionamento, nesting, transformacoes, alinhamento, camera/calibracao e geracao do trabalho/G-code.

## Estrutura
- src/core/: tipos/job/perfil LaserPCB.
- src/layout/: layout, nesting, transformacao e alinhamento.
- src/camera/: interface de camera.
- src/import/: SVG.
- src/export/: G-code.
- src/ui/: canvas LaserPCB.
- src/app/: executaveis LaserPCB e layout.
- docs/: arquitetura, posicionamento e alinhamento.
- tests/: job/layout/alinhamento.

## Limite com o LaserArt
Se a finalidade e fabricar PCB, use LaserPCB. Se e gravar/cortar imagem, logotipo, texto ou arte geral, use o LaserArt (pasta `laserart/` na raiz).

## Integracao
MultiPCB fornece dados de placa. LaserPCB prepara o job. MultiCNC executa a maquina laser.

## Nao pertence aqui
Controle direto de porta serial/protocolo da maquina ou modelagem CAD mecanica.
