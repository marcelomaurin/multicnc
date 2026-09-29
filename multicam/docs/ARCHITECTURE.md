# MultiCAM Architecture

CAD/contorno -> stock -> operação CAM -> ferramenta -> passes Z -> toolpath -> validação -> G-code -> MultiCNC.

## Primeira implementação
Perfil retangular interno/externo por compensação do raio da ferramenta e múltiplos step-downs.

## Evolução necessária
- DXF/SVG/STL
- polígonos arbitrários
- offset robusto
- pockets
- drilling cycles
- facing
- engraving
- tabs
- lead-in/lead-out
- ramp/helical entry
- climb/conventional
- rest machining
- height map/probe
- 3D roughing/finishing
- simulação de remoção de material
- estimativa de tempo
- biblioteca ferramenta/material
- pós-processadores GRBL/FluidNC/grblHAL

Nunca inferir automaticamente feed/RPM/plunge como valores universais. Eles dependem de ferramenta, material, spindle e máquina.
