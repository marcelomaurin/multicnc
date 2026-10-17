# Biblioteca de componentes do MultiAssembly

`mec/<categoria>/<item>.json` — cada pasta é uma categoria no catálogo da aba
**Componentes** do MultiAssembly. Os arquivos são gerados por
[`tools/components/generate_components.py`](../../tools/components/generate_components.py):
altere o gerador e rode `python tools/components/generate_components.py` em vez
de editar os JSON à mão.

Dimensões seguem as normas citadas em `standard` (DIN/ISO/NEMA) ou datasheets
típicos dos fabricantes. Confira o datasheet do item comprado antes de usinar
furações.

## Campos

| Campo | Uso |
|---|---|
| `name`, `model`, `category`, `kind`, `material`, `color` | identificação, tipo eletromecânico (`ack*`) e cor TColor (BGR) |
| `size` | caixa envolvente real da peça em mm (calculada da geometria) |
| `ports` | portas elétricas/mecânicas usadas pelo ERC e pelo esquema |
| `description`, `standard`, `mass_g`, `specs` | dados técnicos para consulta e BOM |
| `geometry` | primitivas 3D desenhadas na vista mecânica |

## Geometria

Coordenadas em mm no sistema local da peça; o canto mínimo da envolvente é
`(0, 0, 0)`. Cores em `#RRGGBB`.

| Tipo | Campos |
|---|---|
| `box` | `at` (canto mínimo), `size` |
| `cyl` | `axis`, `at` (centro da base), `r`, `h`; opcionais `ri` (tubo), `r2` (raio do topo, cone), `seg`, `rot` (fase em graus), `arc` `[início, fim]` (setor), `caps: false` (sem tampas) |
| `prism` | `axis`, `at` (origem), `h`, `poly` `[[u, v], ...]` extrudado ao longo do eixo |
| `disk` | `axis`, `at` (centro), `r`, `seg`, `rot` — decalque (furo, LED, etiqueta): não entra na envolvente |

Eixos (mapeamento cíclico): `z`: u→X, v→Y, w→Z · `x`: u→Y, v→Z, w→X ·
`y`: u→Z, v→X, w→Y.

Convenções: motores com eixo em +Z; spindles com a ferramenta em −Z; perfis,
fusos, eixos e trilhos com o comprimento em Z (trilhos com a altura em Y).

Componentes sem `geometry` (projetos antigos ou criados no programa) recebem uma
forma gerada pelo tipo (`kind`) e pelo `size`. Ao abrir um projeto antigo, o
MultiAssembly recupera a geometria pelo arquivo de origem (`source_ref`).

## Conferência visual

`multiassembly/tests/render_preview.lpi` abre a vista 3D com um item, uma
categoria ou a CNC de demonstração:

```
render_preview item models/components/mec/motores/motor_passo_nema17_42mm.json 35 30
render_preview catalogo motores 35 25 models/components/mec 2.6
render_preview demo 45 28
```
