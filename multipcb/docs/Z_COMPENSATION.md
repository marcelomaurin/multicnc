# Compensação Z da usinagem de PCB

A compensação combina a profundidade nominal da ferramenta com a superfície medida pelo probe.

Formula:

CorrectedZ = NominalZ + (SurfaceZ - ReferenceZ)

## Regras
- somente movimentos de corte são compensados
- movimentos rapid/safe-Z permanecem inalterados
- existe limite MaxCorrection
- ausência de height-map ou correção acima do limite aborta a geração
- a operação é não destrutiva: gera um novo job

## Fluxo
Probe -> Height-map -> trajetória nominal -> compensador Z -> trajetória corrigida -> validação -> MultiCNC.

O valor de MaxCorrection deve ser configurado conforme máquina/processo; não existe valor universal seguro.
