# MultiSlicer - Arquitetura

Entrada (STL/3MF) -> conferência da malha -> cena -> fatiamento -> prévia -> G-code -> MultiCNC.

## Camadas do código

| Pasta | Unidades | Papel |
|---|---|---|
| `src/import` | `multislicer_stl`, `multislicer_3mf` | STL binário/ASCII e 3MF |
| `src/core` | `multislicer_types`, `multislicer_mesh` | tipos e malha de triângulos |
| | `multislicer_meshcheck` | malha aberta/não manifold, normais invertidas, escala (polegadas) |
| | `multislicer_scene` | peças na mesa: transformação, malha na mesa em cache, desfazer, organizar, hastes e bloqueadores |
| | `multislicer_pipeline` | `TModernSlicer`: camadas (varredura em Z), paredes, topo/fundo por regiões, gyroid/retilíneo, suportes, saia/aba/jangada, G-code Marlin/Klipper, progresso e cancelamento |
| | `multislicer_support` | saliência, coluna de suporte, folgas XY/Z, interface, hastes, bloqueadores |
| | `multislicer_clip` | ponte com a Clipper2 (`src/shared/clipper2`): booleanas, offsets, recorte de linhas |
| | `multislicer_infill` | gyroid e retilíneo (recorte em lote pela Clipper) |
| | `multislicer_printers`, `multislicer_materials`, `multislicer_quality`, `multislicer_userdata` | perfis prontos e do usuário em JSON |
| | `multislicer_machines` | catálogo por marca/modelo (Cura + fichas): volume, extrusora, limites, nivelamento, G-code inicial/final |
| | `multislicer_project` | projeto `.mslice` |
| `src/ui` | `multislicer_view3d` | mesa e peças em 3D (renderizador por software do MultiCAD) e modo prévia |
| | `multislicer_toolpath3d` | trajetórias como fitas por camada/papel |
| | `multislicer_view` | prévia 2D da camada (opção) |
| `src/app` | `multislicer_main` | tela no padrão da suíte, thread de fatiamento, projeto, equipamento do MultiCNC |

Compartilhado: `src/shared` (geometria, arc fitting, Clipper2), `src/core/multicnc_equipment`
(cadastro de equipamentos do MultiCNC), `multisuite/src/core` (controles, ícones, launcher).

## Regras

- Prévia e G-code saem do mesmo `TModernSlicer.Layers`: a camada N da prévia é o N-ésimo `;LAYER_CHANGE`.
- Qualquer mudança na cena ou nas configurações invalida o programa; exportar refaz o fatiamento.
- O fatiamento roda numa `TSliceThread` com cópia da malha; a tela só lê `Progress`/`Stage`
  e liga `CancelRequested`.
- O MultiSlicer não abre a porta da impressora: prepara o arquivo. O MultiCNC conecta e imprime.

## Testes (`tests/`, também no Centro de Testes da suíte)

`test_modern_slicer` (pipeline e contrato do G-code), `test_scene`, `test_support`
(inclui desempenho do suporte), `test_machines`, `test_meshcheck` e `test_slicer_app` (tela
completa: perfis, vista 3D, prévia, thread e cancelamento, projeto, malha, arrastar, equipamento).
