# MultiSlicer - Guia para IA

## Missao
MultiSlicer prepara modelos 3D para impressao 3D.

## Estrutura atual
- core/multislicer_types.pas: tipos.
- core/multislicer_mesh.pas: malha (cresce em blocos).
- core/multislicer_scene.pas: cena com varias pecas, transformacoes e malha unica para fatiar.
- core/multislicer_engine.pas: motor de slicing.
- core/multislicer_profile.pas: perfil base do pipeline.
- core/multislicer_printers.pas / multislicer_materials.pas: perfis de impressora e filamento (prontos + JSON do usuario).
- core/multislicer_machines.pas: catalogo por marca/modelo (volume, extrusora, limites de temperatura, nivelamento, velocidades, retracao, G-code inicial/final). O combo 'SavedEquipment' no topo le as impressoras 3D do cadastro do MultiCNC (multicnc_equipment) e completa o perfil; teste: tests/test_machines.
- ui/multislicer_toolpath3d.pas: previa 3D das trajetorias (fitas por camada/papel, montadas sob demanda); a TSlicerView3D mostra no modo PreviewMode, a 2D (multislicer_view) fica como opcao.
- core/multislicer_project.pas: projeto .mslice (cena + configuracoes da tela em JSON); a tela monta/le as configuracoes em ProjectSettingsJSON/ApplyProjectSettings.
- core/multislicer_support.pas: suportes (saliencia, coluna, hastes, bloqueadores, interface).
- core/multislicer_clip.pas: booleanas e offset de regioes com a Clipper2 (src/shared/clipper2).
- core/multislicer_quality.pas: perfis de qualidade (Fino/Normal/Rascunho + JSON do usuario).
- core/multislicer_userdata.pas: pasta de configuracao e leitura/gravacao JSON.
- import/multislicer_stl.pas: importacao STL.
- layout/: posicionamento, transformacao e arranjo 3D.
- export/multislicer_gcode.pas: G-code.
- ui/multislicer_view3d.pas: mesa em 3D (renderizador por software do MultiCAD, via multicad/src/core|kernel|ui no .lpi).
- ui/multislicer_view.pas: previa de camadas 2D.
- app/: aplicacao e posicionamento.
- tests/test_layout3d.lpr.

## Responsabilidade
Importar modelo, posicionar na mesa, aplicar transformacoes, definir perfil, fatiar e gerar G-code de impressao.

## Integracao
Pode receber geometria exportada pelo MultiCAD. Entrega G-code ao MultiCNC para execucao em impressora compativel.

## Nao pertence aqui
Controle serial, firmware/protocolo, usinagem CNC Router, desenho PCB ou montagem eletromecanica.

## Regra
Mantenha perfil de impressao separado da conexao com a impressora. O slicer prepara; MultiCNC executa.

## Tela
multislicer_main segue o padrao da suite (TSuiteHeader, etapas TSuiteButton, TPageControl sem abas,
rodape Validar/Fatiar/Gerar G-code/Abrir no MultiCNC), igual ao MakeRouter. Plano em docs/PLANO_TAREFAS.md.

## Previa e exportacao
multislicer_main usa TModernSlicer para ambos os fluxos. multislicer_view desenha TLayerData.Paths do mesmo resultado que gera o G-code. Qualquer alteracao de configuracao ou STL invalida o programa anterior; ExportProgram deve regenerar quando necessario. Importacao invalida preserva o modelo anterior. Nao use TSlicer antigo para contar camadas da previa enquanto exporta pelo pipeline moderno.
