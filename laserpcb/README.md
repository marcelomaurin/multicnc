# LaserPCB

Aplicação independente para preparar fabricação de PCB com laser.

## Responsabilidades
- importar arte PCB (SVG e Gerber, com importadores evolutivos)
- selecionar Top/Bottom
- espelhar Bottom
- configurar spot, potência, velocidade e passadas
- gerar preview lógico
- gerar G-code para MultiCNC
- preservar perfis de máquina/material

O LaserPCB prepara o trabalho. O MultiCNC controla a máquina.

## Segurança
Parâmetros de potência/velocidade não são universais. Devem ser calibrados para a máquina, material e processo. O LaserPCB não habilita laser automaticamente.
