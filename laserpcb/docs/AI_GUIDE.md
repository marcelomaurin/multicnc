# LaserPCB - Guia para IA

## Finalidade
Preparacao de placas PCB para processo laser: layout, posicionamento, nesting, transformacoes, alinhamento, camera/calibracao e geracao do trabalho/G-code. Tambem gera a furacao para CNC Router e a marcacao a laser dos furos.

## Estrutura
- src/core/: tipos/job/perfil e projeto integrado LaserPCB.
- src/layout/: layout, nesting, transformacao e alinhamento.
- src/camera/: interface de camera.
- src/import/: SVG (parser reutilizado do LaserArt), Gerber e Excellon.
- src/geom/: pontos, caminhos e matrizes em mm, Y para cima.
- src/cam/: mascaras raster e geracao/recorte de trajetorias.
- src/drill/: plano de furacao, G-code de CNC Router, marcas a laser e pinos de registro.
- src/export/: G-code.
- src/ui/: canvas LaserPCB.
- src/app/: executaveis LaserPCB e layout.
- docs/: arquitetura, posicionamento, alinhamento e furacao.
- tests/: job/layout/alinhamento, pipeline SVG/Gerber/Excellon/CAM, furacao e interface nativa.

## Limite com o LaserArt
Se a finalidade e fabricar PCB, use LaserPCB. Se e gravar/cortar imagem, logotipo, texto ou arte geral, use o LaserArt (pasta `laserart/` na raiz).

## Integracao
MakePCB fornece dados de placa. LaserPCB prepara o job. MultiCNC executa a maquina laser e, para a furacao, o CNC Router.

Use a aplicacao principal para posicionar as placas reais. Previa e exportacao devem usar as mesmas trajetorias. Nao modifique a geometria importada ao espelhar Bottom; mantenha o diametro fisico do feixe apos escala. Recursos ignorados devem gerar avisos e bloquear exportacao. Parametros invalidos nunca devem criar ou sobrescrever um arquivo de G-code. Furos usam o mesmo WorldPoint das trajetorias; nao crie outro mapeamento.

## Nao pertence aqui
Controle direto de porta serial/protocolo da maquina ou modelagem CAD mecanica.
