# MultiSlicer - Guia para IA

## Missao
MultiSlicer prepara modelos 3D para impressao 3D.

## Estrutura atual
- core/multislicer_types.pas: tipos.
- core/multislicer_mesh.pas: malha.
- core/multislicer_engine.pas: motor de slicing.
- core/multislicer_profile.pas: perfil.
- import/multislicer_stl.pas: importacao STL.
- layout/: posicionamento, transformacao e arranjo 3D.
- export/multislicer_gcode.pas: G-code.
- ui/multislicer_bedcanvas.pas: mesa.
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
