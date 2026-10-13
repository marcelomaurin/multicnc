; MultiCNC - modelo de teste original - CC0-1.0
; 03 - circulos G2 e G3 com centros I J
; Referencia: MultiCNC 0.1.0.3 / GRBL 1.1 / unidades mm
; Ver README.md antes de usar. Parametros sao demonstrativos.
; Zero de trabalho: X0 Y0 no canto; Z0 na superficie.
; Nao altera o zero salvo nem executa homing.
M5
G21 G17 G90 G94 G54
G91.1
G0 Z5
M3 S8000
G4 P2
G0 Z5
G0 X60 Y40
G1 Z-0.3 F100
G2 X40 Y40 I-10 J0 F350
G2 X60 Y40 I10 J0
G0 Z5
G0 Z5
G0 X65 Y40
G1 Z-0.3 F100
G3 X35 Y40 I-15 J0 F350
G3 X65 Y40 I15 J0
G0 Z5
G0 Z5
G0 X70 Y40
G1 Z-0.3 F100
G2 X30 Y40 I-20 J0 F350
G2 X70 Y40 I20 J0
G0 Z5
G90
G0 Z5
M5
G0 X0 Y0
M30
