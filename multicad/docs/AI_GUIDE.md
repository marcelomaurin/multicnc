# MultiCAD - Guia para IA

## Missao
MultiCAD e o autor CAD da suite. Seu objetivo e criar e editar a geometria que representa pecas mecanicas. A direcao funcional e um CAD parametrico simplificado, semelhante conceitualmente a ferramentas como SolidWorks, sem tentar duplicar CAM ou controle de maquina.

## Estado (09/10/2026)
Em implementacao: decisoes D1 a D10 aprovadas, fases 0 (base, Ids, JSON, unidades,
materiais, malha rotulada, ICadKernel) e 1 (esboco com solver, graus de liberdade e perfis)
concluidas; 223 checks. Proxima: fase 2 (extrusao, corte e revolucao em solido). O plano completo esta em `TAREFA.md` (decisoes D1 a D8 aguardando
aprovacao, fases 0 a 8) e o projeto tecnico em `ARCHITECTURE.md` (modelo `.mcad`, solver
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
- src/ui/multicad_viewport.pas e src/app/: tela provisoria (interface real na fase 3).
- tests/test_multicad.lpr: testes do nucleo (sem LCL).

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
Mantenha geometria independente da UI. Nao acople o documento CAD a uma maquina fisica. Preserve compatibilidade de dados e crie testes para operacoes geometricas.
- Ids persistentes no arquivo (nunca endereco de objeto) e referencias a faces/arestas por
  nome estavel (`Extrude2/topo`).
- O nucleo geometrico so e acessado por `ICadKernel`.
- Toda booleana deixa a malha fechada; teste com volume analitico.
- Programas: `Application.CreateForm` no `.lpr` (regra 12 de `docs/AI_TOOLS_GUIDE.md`).
