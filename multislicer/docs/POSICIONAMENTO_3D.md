# Posicionamento 3D

Feito por `multislicer_scene` (núcleo, sem tela) e pela etapa **Modelo** da janela.

- várias peças na mesa; cada uma entra num lugar livre, apoiada em Z = 0;
- mover (arrastar na vista ou campos X/Y), girar em X/Y/Z (campos ou +90), escalar por eixo
  ou uniforme (% ou mm), espelhar;
- **deitar na mesa**: automático (maior face plana) ou escolhendo a face na vista;
- duplicar com N cópias, organizar a mesa, centralizar, travar peça;
- desfazer/refazer (Ctrl+Z / Ctrl+Y) de posição, rotação, escala e espelho;
- validação: peça fora do volume fica vermelha e reprova o trabalho;
- **Polegadas para mm (x 25,4)** para arquivos exportados em polegadas;
- a caixa envolvente é recalculada pela malha transformada (vale para qualquer rotação).

As hastes de apoio ficam presas à peça (seguem ao arrastar) e deixam de valer se a peça
muda de forma (girar, escalar, espelhar).
