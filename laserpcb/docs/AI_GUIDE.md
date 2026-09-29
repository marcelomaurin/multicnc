# LaserPCB e LaserArt - Guia para IA

## Duas ferramentas no mesmo modulo

### LaserPCB
Especializada em preparacao de placas PCB para processo laser: layout, posicionamento, nesting, transformacoes, alinhamento, camera/calibracao e geracao do trabalho/G-code.

### LaserArt
Especializada em conteudo grafico geral para laser: imagens, logos, arte raster/vetorial, efeitos, materiais, calibracao e construcao do job.

## Estrutura
- src/core/: tipos/job/perfil LaserPCB.
- src/layout/: layout, nesting, transformacao e alinhamento.
- src/camera/: interface de camera.
- src/import/: SVG.
- src/export/: G-code.
- src/art/: documento LaserArt, raster, vector, image effects, materiais, calibracao e job builder.
- src/ui/: canvas LaserPCB e LaserArt.
- src/app/: executaveis LaserPCB, layout e LaserArt.
- docs/: arquitetura, posicionamento e alinhamento.
- tests/: job/layout/alinhamento/calibracao.

## Limite entre elas
Se a finalidade e fabricar PCB, prefira LaserPCB. Se e gravar/cortar imagem, logotipo, texto ou arte geral, use LaserArt.

## Integracao
MultiPCB fornece dados de placa. LaserPCB/LaserArt preparam o job. MultiCNC executa a maquina laser.

## Nao pertence aqui
Controle direto de porta serial/protocolo da maquina ou modelagem CAD mecanica.
