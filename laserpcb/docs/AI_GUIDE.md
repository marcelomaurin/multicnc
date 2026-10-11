# LaserPCB - Guia para IA

## Finalidade
Preparacao de placas PCB para processo laser: layout, posicionamento, nesting, transformacoes, alinhamento, camera/calibracao e geracao do trabalho/G-code. A interface oferece marcacao, contornos e aneis de corte dos furos a laser; a furacao com broca pertence ao RouterPCB. As rotinas de drill compartilhadas continuam disponiveis para esse modulo.

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
MakePCB fornece Gerber/Excellon e a biblioteca de componentes. LaserPCB monta formas e prepara o job laser. MultiCNC executa a maquina; RouterPCB prepara a furacao com broca.

Reutilize makepcb_model, makepcb_library, makepcb_gallery e makepcb_fpeditor. laserpcb_components adapta pads/contornos/furos, sem redes, esquema ou roteamento. A biblioteca pessoal usa LPSharedLibraryFile, apontando ao mesmo arquivo AppData do MakePCB. A janela laserpcb_componentsform abre o criador existente e importa bibliotecas makepcb-library e conjuntos .mpcb.

Mesa reutiliza laserart_bedform e equipamentos laser de multicnc.json. Camadas preservam tratamento, potencia/percentual/watts, velocidade e passadas. Fontes da tabela em REFERENCIAS_LASER.md. Testes: test_components, test_board_ui, test_bed_equipment e test_laser_layers, alem das regressoes de CAM.

Use a aplicacao principal para posicionar as placas reais. Previa e exportacao devem usar as mesmas trajetorias. Nao modifique a geometria importada ao espelhar Bottom; mantenha o diametro fisico do feixe apos escala. Recursos ignorados devem gerar avisos e bloquear exportacao. Parametros invalidos nunca devem criar ou sobrescrever um arquivo de G-code. Furos usam o mesmo WorldPoint das trajetorias; nao crie outro mapeamento.

## Nao pertence aqui
Controle direto de porta serial/protocolo da maquina ou modelagem CAD mecanica.
