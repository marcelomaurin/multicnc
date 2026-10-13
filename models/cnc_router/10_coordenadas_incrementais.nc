; MultiCNC - modelo de teste original - CC0-1.0
; 10 - coordenadas incrementais e retorno ao absoluto
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
G0 X10 Y10
G1 Z-0.25 F100
G91
G1 X40 F350
G1 Y40
G1 X-40
G1 Y-40
G90
G0 Z5
G0 X65 Y10
G1 Z-0.25 F100
G91
G1 X15 F350
G1 Y15
G1 X-15
G1 Y-15
G90
G0 Z5
G90
G0 Z5
M5
G0 X0 Y0
M30
