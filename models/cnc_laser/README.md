# CNC Laser — GRBL

Origem: arquivo de demonstração gerado no repositório MultiCNC.
Licença: domínio público, CC0-1.0.
Formato: G-code textual (`.nc`), com potência GRBL `S0..1000`.

O arquivo `square_grbl_laser.nc` liga o laser com `M3 S1000`, grava um quadrado
em XY e desliga com `M5`. No SimuCNC, selecione **CNC Laser** e **GRBL**: a mesa
branca mostra em preto os trechos queimados. A potência e o avanço são apenas
valores de demonstração; nunca envie este arquivo sem conferir foco, potência,
material e regras de segurança do equipamento real.
