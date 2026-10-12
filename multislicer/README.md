# MultiSlicer

Fatiador para impressão 3D integrado ao ecossistema MultiCNC.

> **Estado (12/10/2026, versão 0.0.6.0):** interface organizada por etapas,
> perfis de impressora e material, cena com múltiplos modelos, posicionamento,
> qualidade, suportes automáticos e manuais e aderência. As entregas até a etapa 6
> estão integradas ao executável `bin/multislicer.exe`. O detalhamento e as próximas
> etapas estão em [docs/PLANO_TAREFAS.md](docs/PLANO_TAREFAS.md).

## Capturas da interface

As capturas em `imgs` mostram a configuração do material e a prévia dos percursos
por camada. Os modelos e valores exibidos são exemplos.

| Material e modelo na mesa | Prévia por camada |
|---|---|
| ![MultiSlicer: filamento PLA, temperaturas e ventilação](../imgs/multislicer_material.png) | ![MultiSlicer: anel fatiado com saia, paredes e topo/fundo](../imgs/multislicer_previa.png) |

- [Configuração de material](../imgs/multislicer_material.png): seleção do filamento,
  temperaturas da primeira camada e das demais, ventilação e fluxo.
- [Prévia do fatiamento](../imgs/multislicer_previa.png): camada selecionada,
  legenda dos percursos, estimativas de tempo e consumo de filamento.

As capturas das entregas publicadas também estão em `screenshots`:

| Qualidade | Suportes e aderência |
|---|---|
| ![MultiSlicer: qualidade e perfis](../screenshots/multislicer_qualidade.png) | ![MultiSlicer: suportes e aderência](../screenshots/multislicer_suporte.png) |

[Modelo](../screenshots/multislicer_modelo.png) · [Mesa 3D](../screenshots/multislicer_mesa3d.png) · [Material](../screenshots/multislicer_material.png) · [Prévia](../screenshots/multislicer_previa.png)

[Índice completo das imagens da suíte](../imgs/README.md)

## Fluxo
STL/3MF -> malha -> orientação/escala -> camadas -> perímetros/infill/suportes -> preview -> G-code -> MultiCNC.

## Separação
MultiSlicer prepara o trabalho. MultiCNC conecta e controla a impressora.

## Primeira base (histórico)
- modelo geométrico de triângulos
- importação STL ASCII
- perfil de impressora/material
- cálculo de planos de camada
- interseção triângulo/plano
- segmentos 2D por camada
- exportação G-code inicial
- aplicação Lazarus inicial

Essa lista registra o ponto de partida. A versão 0.0.6.0 inclui contornos fechados, perímetros, preenchimento, suportes e retração, conforme o pipeline abaixo.

## Pipeline moderno (multislicer_pipeline)
`TModernSlicer.Slice(malha, configuração, saída)`:
- alturas fixas ou **adaptativas** (degrau máximo `CuspHeight` em superfícies inclinadas; camadas terminam exatamente nas faces planas);
- corte no meio da camada, contornos fechados com furos;
- perímetros (internos antes do externo), costura alinhada atrás, saia;
- topo/fundo sólidos retilíneos ±45° detectados por camada e infill **gyroid** (ou retilíneo);
- extrusão relativa (`M83`) pelo modelo de cordão arredondado, retração só quando o deslocamento cruza perímetros, *arc fitting* nos perímetros;
- sabores **Marlin** (`M73`, `M486`, `M900`) e **Klipper** (`EXCLUDE_OBJECT`, `SET_PRINT_STATS_INFO`, `SET_PRESSURE_ADVANCE`);
- cabeçalho `;TIME:` / `;Filament used:` reconhecido por OctoPrint, Moonraker, Mainsail e Fluidd.

Importação: STL binário/ASCII (`TSTLImporter.Load`) e **3MF** (`T3MFImporter`).

## Suportes e aderência

Na página **Suportes**, escolha automático, somente manual ou desligado. Ajuste o
ângulo de saliência, a densidade, as folgas XY/Z e as camadas de interface. A vista
3D destaca as saliências; **Adicionar hastes** permite clicar na peça para inserir
apoios manuais, e os bloqueadores excluem regiões do suporte automático.

Escolha **tocando a mesa** ou **em toda parte**, conforme a posição dos apoios.
Em aderência, selecione nenhuma, saia, aba (brim) ou jangada (raft). Depois de
alterar os parâmetros, refaça o fatiamento e confira os percursos na prévia antes
de exportar o G-code. Suportes em árvore permanecem previstos para uma fase posterior.
