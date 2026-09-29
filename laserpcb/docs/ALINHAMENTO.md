# Alinhamento da mesa Laser

## Fiduciais
O núcleo suporta alinhamento 2D usando dois pontos conhecidos:
- coordenada do ponto no desenho
- coordenada medida/identificada na máquina

O solver calcula escala uniforme, rotação e deslocamento X/Y.

## Câmera
Foi criada uma interface ILaserCamera. A implementação padrão não simula uma câmera: retorna indisponível.
Uma implementação física futura deve fornecer Open/Close/CaptureFrame e identificação do dispositivo.

## Segurança
A imagem da câmera e o alinhamento alteram apenas a preparação geométrica. Nenhum movimento ou disparo do laser é feito pelo módulo de câmera.
