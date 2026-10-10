; MultiCNC public test model - CC0-1.0
; Posicione a ferramenta na origem da peca antes de iniciar (G92 abaixo).
G21
G90
G92 X0 Y0 Z0
M3 S8000
G0 Z5 F500
G0 X20 Y20 F3000
G1 Z-0.5 F300
G1 X80 Y20 F900
G1 X80 Y80
G1 X20 Y80
G1 X20 Y20
G0 Z5 F500
M5
M30
