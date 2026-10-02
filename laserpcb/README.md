# LaserPCB

Aplicação independente para preparar fabricação de PCB com laser.

## Responsabilidades
- importar arte PCB (SVG e Gerber, com importadores evolutivos)
- selecionar Top/Bottom
- espelhar Bottom
- configurar spot, potência, velocidade e passadas
- gerar preview lógico
- gerar G-code para MultiCNC
- preservar perfis de máquina/material

O LaserPCB prepara o trabalho. O MultiCNC controla a máquina.

## Segurança
Parâmetros de potência/velocidade não são universais. Devem ser calibrados para a máquina, material e processo. O LaserPCB não habilita laser automaticamente.

## Raster moderno (laserart_rasterizer)
Independente da LCL (`TGrayImage`): ajustes de brilho/contraste/gama, sete algoritmos de dithering (Floyd-Steinberg, Jarvis, Stucki, Atkinson, Sierra, Burkes, Bayer) com varredura serpentina, ou escala de cinza com potência variável entre `PowerMin` e `PowerMax`. O G-code usa `M4` (potência acompanha a velocidade real), runs de mesma potência em uma linha, overscan com `S0`, varredura bidirecional e salto de áreas brancas. O exportador de jobs (`laserpcb_gcode`) também passou a gerar saída modal.
