# Contrato de G-code da suíte (zero virtual e cabeçalho)

Estado: em uso (08/10/2026). O MakeRouter gera e o MultiCNC lê as linhas `; MS-...`; o RouterPCB
ainda usa só o texto livre. As ferramentas atuais seguem funcionando como estão, e a adoção é gradual.

## Princípio: zero virtual

As ferramentas de preparação (RouterPCB, MakeRouter, LaserPCB, LaserArt) geram o trabalho em
relação a um **ponto de zero da peça**, nunca em coordenadas da máquina. O **MultiCNC** é o
único que conhece a máquina:

1. o operador prende a peça e leva a ferramenta (ou o laser) ao ponto de zero indicado no
   cabeçalho;
2. **Zero Workpiece** grava o deslocamento de trabalho;
3. **Frame (Test)** percorre a caixa do trabalho em Z seguro para conferir a posição;
4. o MultiCNC confere se a caixa do trabalho, somada ao zero atual, cabe no curso da máquina;
5. o operador inicia.

A mesma peça pode ir para outra posição da mesa ou para outra máquina sem gerar o G-code de
novo.

## Regras para quem gera

- Apenas `G21 G90 G94`, `G0`, `G1`, `G2`/`G3`, `G4`, `M0`, `M2`, `M3`/`M4`/`M5` (laser:
  `M3`/`M4` com `S`) e `G38.2` só em programas de sondagem.
- Proibido: `G53`, `G28`/`G30` com coordenadas, `G54`..`G59` fixos, `G92` dentro do programa e
  ciclos fixos `G81`..`G89`.
- Ponto decimal sempre, linhas com no máximo 127 caracteres e sem caracteres de controle.
- O programa termina com Z seguro, spindle/laser desligado e retorno a X0 Y0 (zero virtual).

## Cabeçalho

As **primeiras linhas** são comentários. A linha 1 identifica a origem e a máquina; as linhas
`; MS-...` são legíveis por máquina (chave=valor, mm).

```text
; MakeRouter -> MultiCNC (CNC Router)
; MS-CONTRACT: 1
; MS-MACHINE: router            (router | laser)
; MS-DATUM: XY=BL Z=TOP         (XY: BL BC BR ML C MR TL TC TR | Z: TOP TABLE)
; MS-STOCK: W=500 H=190 T=18
; MS-BOUNDS: X0=-3 X1=503 Y0=-3 Y1=193 Z0=-18.5 Z1=5
; MS-TOOL: T1 "Fresa reta 6 mm" D=6
; MS-STAGE: 2/4 perfil          (etapa / total, para avisar o operador da sequencia)
; Zero: X/Y no canto inferior esquerdo do material, Z no topo do material
G21
...
```

- `MS-BOUNDS` é a caixa real dos movimentos, já com o raio da ferramenta. É ela que alimenta o
  Frame e a conferência de curso.
- Uma linha `; MS-...` desconhecida deve ser ignorada sem erro, para permitir evolução.

## Estado por ferramenta

| Ferramenta | Linha 1 | Zero | `MS-...` |
|---|---|---|---|
| RouterPCB | `; RouterPCB -> MultiCNC (CNC Router)` | canto inferior esquerdo da placa, Z no cobre | ainda não (texto livre) |
| LaserPCB (furação) | `; LaserPCB -> MultiCNC (CNC Router)` | coordenadas da mesa do laser | não |
| LaserPCB / LaserArt | `; LaserPCB -> MultiCNC` / `; LaserArt -> MultiCNC` | mesa do laser | não |
| MakeRouter | `; MakeRouter -> MultiCNC (CNC Router)` | 9 pontos do material, Z topo ou mesa | sim, desde o início |

## Trabalho no MultiCNC

- [feito] `OpenProgramFile`: qualquer `; X -> MultiCNC (CNC Router)` seleciona CNC Router.
- [feito] Lê `MS-DATUM`, `MS-STOCK` e `MS-BOUNDS` (`SuiteParseHeader`) e mostra no log o ponto
  de zero, o material e a caixa do trabalho.

Falta:
- Mostrar o ponto de zero ("leve a ferramenta ao canto inferior esquerdo, no topo do
  material") e um desenho pequeno do material com o ponto marcado.
- Usar `MS-BOUNDS` no Frame e conferir o curso: soft limits e posição atual + caixa.
- Avisar a troca de ferramenta entre arquivos (`MS-TOOL`, `MS-STAGE`).
- Teste automatizado: o analisador lê o cabeçalho e rejeita os comandos proibidos.
