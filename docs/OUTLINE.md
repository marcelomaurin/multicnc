# Outline — contorno para posicionamento do laser

Em CNC Laser, carregue o programa e conecte a controladora. O botão **Outline**
fica depois de **Resume** e antes de **Emergency Stop**. Ele calcula os extremos
X/Y e percorre um retângulo fechado, terminando no primeiro canto. A mesa deve
estar livre para o deslocamento. O laser fica desligado por M5 e Z não é movido.

A velocidade é automática e independente do avanço de gravação. O cálculo
inclui o perímetro e a distância da posição atual até o primeiro canto:
avanço em mm/min = distância total em mm × 60 / 8, arredondado para cima.
Por exemplo, uma área de 60 × 60 mm, com o cabeçote no primeiro canto,
solicita 1800 mm/min. A aproximação aumenta o avanço necessário.

O alvo nominal é no máximo oito segundos. Os limites de velocidade, aceleração,
overrides e atrasos da controladora podem aumentar o tempo físico. O aplicativo
não altera parâmetros do firmware para cumprir esse alvo.

São interpretados movimentos relativos, polegadas e arcos. Movimentos só em Z
e a origem presumida da primeira aproximação rápida não ampliam artificialmente
a área. Trajetórias com coordenadas desconhecidas, probes ou mudanças de origem
no meio do desenho são recusadas quando os limites não são confiáveis.

Outline exige máquina parada, comunicação pronta e programa carregado.
Pause, Resume e Emergency Stop continuam disponíveis durante a execução.
O programa original é preservado e volta a ficar pronto ao terminar.
O botão Frame (Test) existente mantém sua configuração separada.
