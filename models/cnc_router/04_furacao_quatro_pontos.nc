; MultiCNC - modelo de teste original - CC0-1.0
; 04 - furacao em quatro pontos sem ciclos G81 G83
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
G0 X20 Y20
G1 Z-0.25 F80
G0 Z2
G1 Z-0.5 F80
G0 Z2
G1 Z-0.75 F80
G0 Z2
G1 Z-1 F80
G0 Z2
G0 Z5
G0 Z5
G0 X60 Y20
G1 Z-0.25 F80
G0 Z2
G1 Z-0.5 F80
G0 Z2
G1 Z-0.75 F80
G0 Z2
G1 Z-1 F80
G0 Z2
G0 Z5
G0 Z5
G0 X60 Y60
G1 Z-0.25 F80
G0 Z2
G1 Z-0.5 F80
G0 Z2
G1 Z-0.75 F80
G0 Z2
G1 Z-1 F80
G0 Z2
G0 Z5
G0 Z5
G0 X20 Y60
G1 Z-0.25 F80
G0 Z2
G1 Z-0.5 F80
G0 Z2
G1 Z-0.75 F80
G0 Z2
G1 Z-1 F80
G0 Z2
G0 Z5
G90
G0 Z5
M5
G0 X0 Y0
M30
