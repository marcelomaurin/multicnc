# Arquitetura LaserPCB

Arquivos -> importadores -> projeto em mm -> máscaras/CAM -> posicionamento -> prévia -> validação -> G-code -> MultiCNC.

- laserpcb_project conecta SVG, camadas Gerber, Excellon, máscaras, processos e cópias na mesa.
- laserpcb_svg adapta o parser do LaserArt, mantendo unidades, viewBox, curvas e coordenadas de PCB sem o deslocamento automático do editor.
- laserpcb_raster compõe Gerber com polaridade e furos; o contorno da placa usa preenchimento par/ímpar para preservar recortes internos.
- laserpcb_cam produz isolação, remoção e preenchimento. O recorte divide segmentos em cada cruzamento da grade, preservando furos e trechos externos.
- laserpcb_layout aplica espelhos, escalas e rotação com X/Y no canto inferior esquerdo da caixa envolvente resultante. Nesting reserva placas travadas e keep-outs e restaura posições se falhar.
- A compensação do feixe ocorre após escala. Cada cópia possui trajetórias calculadas para sua escala; o espelho Bottom é aplicado no mapeamento final, sem alterar dados importados.
- laserpcb_preview mostra máscaras, furos e as mesmas trajetórias usadas para formar o job; laserpcb_main usa os controles e ícones comuns da MultiSuite.
- laserpcb_drill agrupa os furos por broca, otimiza o percurso e gera o G-code de CNC Router, as marcas a laser e os pinos de registro. O projeto mapeia os furos com WorldPoint, como as trajetorias. Veja [FURACAO.md](FURACAO.md).
- laserpcb_gcode verifica os parâmetros antes de escrever; emite G21/G90/G94, M5 antes dos rápidos e ao final, e M4/S nos cortes.

O LaserPCB não conecta à máquina. O MultiCNC reconhece o cabeçalho LaserPCB: a furação ("(CNC Router)") abre em CNC Router; os demais arquivos abrem em modo laser e mantém as passadas/potência já definidas no G-code.

Limites: raster com precisão configurável e teto de 16 milhões de pixels; nesting por caixas; câmera sem implementação física; SVG com recursos ignorados bloqueia exportação. Consulte o [fluxo de uso](../README.md).
