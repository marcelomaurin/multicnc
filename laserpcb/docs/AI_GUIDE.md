# LaserPCB - Guia para IA

## Finalidade
Preparacao de placas PCB para processo laser: layout, posicionamento, nesting, transformacoes, alinhamento, camera/calibracao e geracao do trabalho/G-code.

## Estrutura
- src/core/: tipos/job/perfil e projeto integrado LaserPCB.
- src/layout/: layout, nesting, transformacao e alinhamento.
- src/camera/: interface de camera.
- src/import/: SVG (parser reutilizado do LaserArt), Gerber e Excellon.
- src/geom/: pontos, caminhos e matrizes em mm, Y para cima.
- src/cam/: mascaras raster e geracao/recorte de trajetorias.
- src/export/: G-code.
- src/ui/: canvas LaserPCB.
- src/app/: executaveis LaserPCB e layout.
- docs/: arquitetura, posicionamento e alinhamento.
- tests/: job/layout/alinhamento, pipeline SVG/Gerber/Excellon/CAM e interface nativa.

## Limite com o LaserArt
Se a finalidade e fabricar PCB, use LaserPCB. Se e gravar/cortar imagem, logotipo, texto ou arte geral, use o LaserArt (pasta `laserart/` na raiz).

## Integracao
MultiPCB fornece dados de placa. LaserPCB prepara o job. MultiCNC executa a maquina laser.

Use a aplicacao principal para posicionar as placas reais. Previa e exportacao devem usar as mesmas trajetorias. Nao modifique a geometria importada ao espelhar Bottom; mantenha o diametro fisico do feixe apos escala. Recursos ignorados devem gerar avisos e bloquear exportacao. Parametros invalidos nunca devem criar ou sobrescrever um arquivo de G-code.

## Nao pertence aqui
Controle direto de porta serial/protocolo da maquina ou modelagem CAD mecanica.
