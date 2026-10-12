# MultiSlicer

Fatiador para impressão 3D integrado ao ecossistema MultiCNC.

> **Estado (12/10/2026, versão 0.0.7.0):** perfis de impressora e material,
> cena com múltiplos modelos, posicionamento, qualidade, suportes e aderência,
> prévia 3D por camada e fatiamento em segundo plano com progresso e cancelamento.
> As entregas até a etapa 7 estão integradas ao executável `bin/multislicer.exe`.
> O detalhamento e as próximas etapas estão em
> [docs/PLANO_TAREFAS.md](docs/PLANO_TAREFAS.md).

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

## Fatiamento e prévia 3D na versão 0.0.7.0

Selecione a impressora no campo de equipamento no topo da janela. As impressoras
salvas no MultiCNC aparecem nessa lista; marca e modelo completam o perfil pelo
catálogo. A opção **Ajuste manual** permite configurar uma impressora personalizada.

Depois de posicionar o modelo e ajustar material, qualidade e suportes, clique em
**Fatiar**. A barra no rodapé informa a fase e o progresso. O processamento ocorre
em segundo plano; **Cancelar** ou Esc interrompe o cálculo e preserva a prévia
anterior. Ao mudar parâmetros, refaça o fatiamento antes de usar a saída.

Na etapa **Prévia**, use o deslizante para selecionar a camada. A vista 3D usa a
mesma câmera da mesa e diferencia paredes, preenchimento, superfícies sólidas e
suportes por cores. Ative a opção de mostrar somente a camada para inspecionar seu
interior. A prévia e a exportação usam o mesmo resultado do fatiamento. O deslizante
de movimento dentro da camada e as marcas de retração ainda estão previstos.

| Trajetórias acumuladas com suportes | Inspeção de uma camada |
|---|---|
| ![Prévia 3D dos percursos e suportes](../imgs/ms_preview3d.png) | ![Camada isolada com preenchimento e suportes](../imgs/ms_preview3d_layer.png) |

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

Essa lista registra o ponto de partida. A versão 0.0.7.0 inclui contornos fechados, perímetros, preenchimento, suportes e retração, conforme o pipeline abaixo.

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
