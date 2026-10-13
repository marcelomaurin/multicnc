# MultiSlicer - Guia para IA

## Missao
MultiSlicer prepara modelos 3D para impressao 3D.

## Estrutura atual
Ver docs/ARCHITECTURE.md (tabela por unidade). Pontos de entrada:
- core/multislicer_pipeline.pas: TModernSlicer.Slice (unico motor; o antigo multislicer_engine foi removido).
- core/multislicer_scene.pas: cena e transformacoes.
- core/multislicer_project.pas: projeto .mslice; a tela monta/le as configuracoes em ProjectSettingsJSON/ApplyProjectSettings.
- core/multislicer_meshcheck.pas: conferencia da malha ao abrir (OpenFile).
- core/multislicer_machines.pas: catalogo por marca/modelo; o combo 'SavedEquipment' no topo le as impressoras 3D do cadastro do MultiCNC (multicnc_equipment).
- ui/multislicer_view3d.pas + ui/multislicer_toolpath3d.pas: mesa 3D e previa das trajetorias (PreviewMode).
- app/multislicer_main.pas: tela; GenerateProgram fatia numa TSliceThread (Esc/Cancelar).
- tests/: test_modern_slicer, test_scene, test_support, test_machines, test_meshcheck, test_slicer_app.

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
