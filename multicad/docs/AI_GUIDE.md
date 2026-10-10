# MultiCAD - Guia para IA

## Missao
MultiCAD e o autor CAD da suite. Seu objetivo e criar e editar a geometria que representa pecas mecanicas. A direcao funcional e um CAD parametrico simplificado, semelhante conceitualmente a ferramentas como SolidWorks, sem tentar duplicar CAM ou controle de maquina.

## Estado (10/10/2026)
Em implementacao: decisoes D1 a D10 aprovadas, fases 0 (base, Ids, JSON, unidades,
materiais, malha rotulada, ICadKernel), 1 (esboco com solver, graus de liberdade e perfis),
2 (extrusao, corte, revolucao, planos, booleanas, reconstrucao) e 3 (vista 3D por software,
arvore, PropertyManager, modo esboco) e 4 (STL/DXF, medir, Abrir no MultiSlicer) concluidas;
425 checks no nucleo + teste de interface. Primeira entrega pronta. Proxima: fase 5 (furo,
padroes, espelho); pendencias da vista na 3E. Limites em TAREFA.md.
O plano completo esta em `TAREFA.md` (fases 0 a 8) e o projeto tecnico em `ARCHITECTURE.md` (modelo `.mcad`, solver
Newton/LM, nucleo em malha rotulada + CSG BSP atras de `ICadKernel`, OpenGL, exportacao).
Referencia de fluxo: SolidWorks 2014 (sketch com restricoes e cotas, arvore de operacoes,
reconstrucao), sem copiar.

## O que pertence aqui
Documento CAD, features, sketches, extrusoes, transformacoes geometricas, viewport e futuras operacoes de modelagem.

## Fontes atuais
- src/core/multicad_types.pas: vetores, matrizes, referenciais dos planos (Y para cima), UTF-8.
- src/core/multicad_units.pas: unidades e expressoes nas cotas (CadEval, CadFmt).
- src/core/multicad_materials.pas: biblioteca de materiais e massa.
- src/core/multicad_feature.pas: base das operacoes (Id persistente, estado, registro de tipos).
- src/core/multicad_document.pas: documento, arquivo .mcad, dependencias, retrocesso.
- src/features/multicad_refgeom.pas: origem, planos e eixos de referencia.
- src/features/multicad_extrude.pas: parametros de Ressalto/Base e Corte extrudado.
- src/sketch/multicad_sketch.pas: entidades com Id, restricoes e cotas, ranhura, poligono.
- src/sketch/multicad_solver.pas: solver (CadSolveSketch), graus de liberdade, estados.
- src/sketch/multicad_profile.pas: lacos fechados, regioes com ilhas (CadSketchProfiles).
- src/kernel/multicad_kernel.pas: interface ICadKernel e nucleo Pascal.
- src/kernel/multicad_mesh.pas: malha com faces rotuladas, solda, malha fechada, volume.
- src/kernel/multicad_triangulate.pas: poligono com furos -> triangulos.
- src/kernel/multicad_sweep.pas: extrusao (inclinacao) e revolucao com faces rotuladas.
- src/kernel/multicad_csg.pas: booleanas BSP + fusao de faces planas + reparo de juncoes T.
- src/features/multicad_revolve.pas: parametros da revolucao.
- src/features/multicad_bridge.pas: perfis do esboco -> regioes de varredura.
- src/features/multicad_rebuild.pas: TCadRebuilder (arvore -> corpos, referencias, cache).
- src/features/multicad_export.pas: STL (orientacao Y->Z / face na mesa) e DXF R12.
- src/features/multicad_measure.pas: Medir (area, diametro, distancias, angulos).
- src/sketch/multicad_sketchtools.pas: ferramentas do modo esboco sem LCL (cliques -> entidades,
  captura, H/V automaticas, cota inteligente, relacoes, apagar).
- src/ui/multicad_camera.pas: camera (vistas padrao, Normal a, orbitar, zoom no cursor, raio).
- src/ui/multicad_softrender.pas: z-buffer por software, 5 estilos, arestas, Id por pixel, secao.
- src/ui/multicad_view3d.pas: controle TCadView3D (mouse, teclado, cubo, triade, planos, esbocos).
- src/ui/multicad_sketchedit.pas: liga a sessao de esboco a vista (desenho, cotas na tela).
- src/ui/multicad_propman.pas: PropertyManager (extrusao, corte, revolucao, plano).
- src/app/multicad_main.pas: janela principal (abas, arvore, PropertyManager, arquivo).
- tests/test_multicad.lpr: testes do nucleo (sem LCL).
- tests/test_multicad_ui.lpr: teste da janela (Xvfb/Wine), grava capturas e o exemplo.
- examples/suporte.mcad: peca de exemplo.

## Entradas e saidas
Entrada: comandos de modelagem e, futuramente, formatos CAD/mesh suportados.
Saida: geometria/pecas reutilizaveis pelo MultiAssembly e MultiCAM; STL para MultiSlicer,
DXF (sketch ou face plana) para MakeRouter e LaserArt, propriedades de massa para
MultiPhysics (decisao D8).

## Nao pertence aqui
G-code, comunicacao serial, GRBL/Marlin, STEP/DIR, controle de spindle, PCB, slicing ou execucao fisica.

## Integracao
MultiAssembly referencia as pecas CAD na montagem. MultiCAM consome geometria para criar operacoes de usinagem.

## Regras para alteracao
Mantenha geometria independente da UI (camera, renderizador e ferramentas de esboco nao usam
LCL e tem testes no test_multicad). Nao acople o documento CAD a uma maquina fisica. Preserve compatibilidade de dados e crie testes para operacoes geometricas.
- Ids persistentes no arquivo (nunca endereco de objeto) e referencias a faces/arestas por
  nome estavel (`Extrude2/topo`).
- O nucleo geometrico so e acessado por `ICadKernel`.
- Toda booleana deixa a malha fechada; teste com volume analitico.
- Corte extrudado entra na peca por padrao (contra a normal do esboco), como no SolidWorks.
- Referencias por texto: plane:<id>, face:<nome>, axis:<id>, sketch:<id>/<entidade>[.<ponto>],
  body:<nome>, origin.
- Programas: `Application.CreateForm` no `.lpr` (regra 12 de `docs/AI_TOOLS_GUIDE.md`).
