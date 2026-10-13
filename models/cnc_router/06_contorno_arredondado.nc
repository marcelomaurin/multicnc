; MultiCNC - modelo de teste original - CC0-1.0
; 06 - retangulo arredondado R10
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
G0 X20 Y10
G1 Z-0.25 F100
G1 X80 F350
G3 X90 Y20 I0 J10
G1 Y50
G3 X80 Y60 I-10 J0
G1 X20
G3 X10 Y50 I0 J-10
G1 Y20
G3 X20 Y10 I10 J0
G0 Z5
G0 Z5
G0 X20 Y10
G1 Z-0.5 F100
G1 X80 F350
G3 X90 Y20 I0 J10
G1 Y50
G3 X80 Y60 I-10 J0
G1 X20
G3 X10 Y50 I0 J-10
G1 Y20
G3 X20 Y10 I10 J0
G0 Z5
G90
G0 Z5
M5
G0 X0 Y0
M30
