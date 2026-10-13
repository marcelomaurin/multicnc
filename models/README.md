# Modelos públicos para teste

Esta pasta contém programas pequenos, gerados neste projeto, para testar o
MultiCNC e o SimuCNC sem depender de arquivos de terceiros. Os arquivos são
dedicados ao domínio público (CC0-1.0) e podem ser copiados, modificados e
redistribuídos.

Cada subpasta corresponde a um tipo de equipamento:

- `printer3d/`: trajetórias de impressão para Marlin.
- [`cnc_router/`](cnc_router/README.md): 12 programas GRBL para router, com catálogo visual, instruções e relatório de validação no MultiCNC.
- `cnc_laser/`: gravação vetorial para GRBL Laser, com potência `S`.

Os formatos são texto puro. Extensões `.gcode`, `.nc` e `.tap` são convenções
de arquivo; o protocolo real é definido pelo equipamento e pelo firmware.
Confira o README de cada subpasta antes de enviar um arquivo a uma máquina real.
