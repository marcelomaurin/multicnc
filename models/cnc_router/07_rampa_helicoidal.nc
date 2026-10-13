; MultiCNC - modelo de teste original - CC0-1.0
; 07 - rampa helicoidal em quatro voltas
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
G0 X60 Y40
G1 Z0 F100
G3 X40 Y40 Z-0.125 I-10 J0 F300
G3 X60 Y40 Z-0.25 I10 J0 F300
G3 X40 Y40 Z-0.375 I-10 J0 F300
G3 X60 Y40 Z-0.5 I10 J0 F300
G3 X40 Y40 Z-0.625 I-10 J0 F300
G3 X60 Y40 Z-0.75 I10 J0 F300
G3 X40 Y40 Z-0.875 I-10 J0 F300
G3 X60 Y40 Z-1 I10 J0 F300
G3 X40 Y40 I-10 J0 F300
G3 X60 Y40 I10 J0
G0 Z5
G90
G0 Z5
M5
G0 X0 Y0
M30
