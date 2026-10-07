# Central de Testes MultiSuite

## Objetivo
Executar e auditar funcionalidades reais da suite sem confundir ausencia de compilacao com sucesso.

## Componentes
- multisuite_test_catalog.pas: inventario dos testes por ferramenta.
- multisuite_test_runner.pas: executa processos, captura stdout, exit code e duracao.
- multisuite_test_console.lpr: runner para terminal/CI.
- multisuite_test_center.lpr: interface grafica.
- multisuite_test_report.txt: relatorio gerado.

## Estados
PASS: executou e retornou zero.
FAIL: executou e retornou codigo diferente de zero.
MISSING: binario do teste nao existe; deve ser compilado.
ERROR: erro ao iniciar/executar.
NOT RUN: reservado para teste ainda nao iniciado.

## Cobertura atual
MultiCNC: simulador.
MultiCAD: documento CAD.
MultiPCB: EDA, routing e heightmap.
MultiAssembly: modelo eletromecanico.
MultiCAM: CAM mecanico, setup, simulacao, eletronica virtual e pipeline demo.
MultiSlicer: layout 3D.
LaserPCB: job, layout e alinhamento.
MakePCB: nucleo (biblioteca, redes, Gerber/Excellon lidos pelo LaserPCB, roteamento, DRC, esquema, SMD, impressao) e interface.
LaserArt: saida G-code (SVG, texto, imagem) e matriz de teste de material.
MultiSuite: registro e workspace.

## Regra para IA
Nunca converta MISSING em PASS. Nunca afirme que uma funcionalidade foi validada apenas porque o fonte existe. Para declarar validacao, o teste correspondente deve ter executado e retornado PASS.

## Evolucao
Adicionar smoke tests de GUI, persistencia dos formatos nativos, round-trip salvar/abrir, integracao MultiSuite -> ferramenta, validacao de G-code e testes com transport simulator. Hardware real deve ficar separado e exigir confirmacao/configuracao explicita.
