# LaserPCB Architecture

Input -> Importer -> Normalized Job -> Transform -> Preview -> G-code -> MultiCNC

## Separação
LaserPCB não abre COM e não controla hardware. Isso pertence ao MultiCNC.

## Transformações
- escala e origem
- Top/Bottom
- espelhamento
- compensação futura de spot
- múltiplas passadas

## Evolução
- parser SVG completo
- parser Gerber RS-274X
- rasterização de máscara
- offset/compensação geométrica
- calibração por matriz
- preview gráfico
- integração direta por arquivo/job com MultiCNC
