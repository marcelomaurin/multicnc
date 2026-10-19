# Modelos públicos para teste

Esta pasta contém programas e projetos pequenos, gerados neste projeto, para testar e aprender
os programas da suíte MultiCNC sem depender de arquivos de terceiros. Os arquivos são
dedicados ao domínio público (CC0-1.0) e podem ser copiados, modificados e
redistribuídos.

Cada subpasta corresponde a um tipo de equipamento ou a um programa da suíte:

Programas G-code prontos:

- [`printer3d/`](printer3d/README.md): peças STL e trajetórias de impressão para Marlin.
- [`cnc_router/`](cnc_router/README.md): 12 programas GRBL para router, com catálogo visual, instruções e relatório de validação no MultiCNC.
- [`cnc_laser/`](cnc_laser/README.md): gravação vetorial para GRBL Laser, com potência `S`.
- `components/`: modelos de componentes mecânicos usados nas montagens.

Exercícios por programa (arquivo de projeto + passo a passo):

| Pasta | Programa | Exercícios |
|---|---|---|
| [`multicnc/`](multicnc/README.md) | MultiCNC | `quadrado.nc` do manual (cap. 27) |
| [`laserart/`](laserart/README.md) | LaserArt | caixa com encaixes, placa gravada, engrenagem |
| [`makepcb/`](makepcb/README.md) | MakePCB | pisca 555: esquema → trilhas → Gerber |
| [`routerpcb/`](routerpcb/README.md) | RouterPCB | fresar a placa do pisca 555 |
| [`laserpcb/`](laserpcb/README.md) | LaserPCB | gravar a placa do pisca 555 |
| [`makerouter/`](makerouter/README.md) | MakeRouter | porta-copos, projeto de demonstração |
| [`multicam/`](multicam/README.md) | MultiCAM | perfil retangular |
| [`multicad/`](multicad/README.md) | MultiCAD | placa com furos, cantoneira (→ STL) |
| [`multislicer/`](multislicer/README.md) | MultiSlicer | cubo de calibração, anel, cantoneira |
| [`multiassembly/`](multiassembly/README.md) | MultiAssembly | CNC de demonstração (→ MultiPhysics) |
| [`multiphysics/`](multiphysics/README.md) | MultiPhysics | viga, suporte térmico, casco, circuitos |

Os arquivos de projeto são gerados por [`tools/exercises`](../tools/exercises/README.md). Na
instalação, esta pasta fica em `documentation\models`.

Os formatos são texto puro. Extensões `.gcode`, `.nc` e `.tap` são convenções
de arquivo; o protocolo real é definido pelo equipamento e pelo firmware.
Confira o README de cada subpasta antes de enviar um arquivo a uma máquina real.
