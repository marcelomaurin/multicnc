# Impressora 3D — Marlin

Origem: arquivo de demonstração gerado no repositório MultiCNC.
Licença: domínio público, CC0-1.0.
Formato: G-code textual (`.gcode`), compatível com o perfil Marlin do SimuCNC.

O arquivo `cube_marlin.gcode` faz homing, aquece o hotend, cria duas camadas
quadradas e encerra com `M104 S0`. Ele foi reduzido para teste visual e não é
um perfil de fatiamento pronto para uma impressora específica.

## Pecas STL para impressao

Modelos em milimetros, CC0-1.0, com base plana em Z=0 e malhas fechadas.
Importe o STL no fatiador e gere o G-code com o perfil da sua impressora,
bico e material. Os STL nao incluem temperaturas nem comandos de maquina.

| Arquivo | Medidas nominais | Finalidade |
| --- | --- | --- |
| `cubo_calibracao_20mm.stl` | 20 x 20 x 20 mm | Conferir dimensoes X/Y/Z e qualidade das paredes. |
| `anel_diametros_20x12mm.stl` | Diametro externo 20 mm, interno 12 mm, altura 10 mm | Conferir diametros, circularidade e acabamento do furo. |
| `cantoneira_esquadro_30mm.stl` | 30 x 30 x 10 mm, paredes de 5 mm | Conferir esquadro, cantos internos e espessura. |

Posicao de impressao: manter a base plana sobre a mesa, como nos arquivos.
As tres pecas foram desenhadas para dispensar suportes nessa orientacao.
Como ponto de partida, use camada de 0,20 mm, tres perimetros e 15-20% de
preenchimento; temperaturas, velocidade e adesao devem seguir seu perfil.
O anel usa 96 segmentos na circunferencia. Meça as pecas apos esfriarem.

Validacao dos arquivos: triangulos sem area nula, duas faces por aresta,
orientacao consistente, volume positivo e dimensoes nominais verificadas.

## Novos exemplos G-code Marlin

- `quadrado_20mm_marlin.gcode`: contorno quadrado de 20 x 20 mm.
- `anel_20x12mm_marlin.gcode`: contornos circulares com diametros de 20 e 12 mm.
- `cantoneira_30mm_marlin.gcode`: contorno em L de 30 x 30 mm, bracos de 5 mm.

Seguem o formato do exemplo original: homing, hotend a 200 graus Celsius,
duas camadas em Z=0,20 e Z=0,40 mm, desligamento do hotend e motores.
Declaram milimetros (G21), coordenadas absolutas (G90) e extrusao absoluta
(M82). A extrusao e estimada para filamento de 1,75 mm e linha de 0,45 mm.
Sao demonstracoes de trajetoria, sem preenchimento nem perfil especifico;
nao produzem as pecas completas dos STL. Confira temperatura, material,
homing e area util antes de qualquer execucao na impressora.
