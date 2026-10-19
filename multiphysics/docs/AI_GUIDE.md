# MultiPhysics - Guia para IA

Plano de trabalho em andamento: [TAREFA.md](TAREFA.md) (fases, tarefas MP-x.y, benchmarks e progresso).

## Finalidade
Simulacao fisica multidominio de uma montagem vinda do MultiAssembly: eletrica/eletronica,
microcontroladores, motores e atuadores, mecanica, termica, eletromagnetismo, energia,
materiais e falhas/degradacao. Mostra o comportamento antes de fabricar; nunca comanda a
maquina real.

## Estrutura
- src/core/: tipos, projeto `.mphys` (JSON, SI) com validacao, unidades, cenario, ambiente
  (Ar/Agua/Vacuo), materiais (biblioteca indexavel), energia/quimica.
- src/geometry/: primitivas box/cyl/prism com faces nomeadas; importacao do `.massembly`
  (usa `multiassembly/src/core`).
- src/mesh/: malha tetraedrica (secao 2D extrudada; prismas por Delaunay), TET10, qualidade,
  massa/inercia, VTK; `multiphysics_contact` (amarracoes do contato colado).
- src/fem/: CSR, PCG, Cholesky (perfil/RCM ou esparso/disseccao aninhada, escolhido pelo custo),
  elementos com integracao exata, estatico/termico/modal (`multiphysics_fem`) e a analise do
  projeto com fidelidade e convergencia (`multiphysics_analysis`).
- src/ccx/: deck CalculiX, execucao e leitor `.frd`.
- src/ui/: vista 3D com mapa de cores e grafico de series temporais.
- src/testing/: `multiphysics_check` (Check/CheckNear/Finish dos testes).
- src/solver/: MNA, Newton-MNA, netlist SPICE, ODE, nao linear e acoplamento runtime -> FEM.
- src/dynamics/: vetores, corpo rigido, mecanica, empuxo e `multiphysics_hydro` (ISA, flutuacao).
- src/runtime/: runtime em passos de tempo, grafo de componentes, biblioteca de
  componentes, modelos de circuito/movimento/stepper, MCU e programa, controle de eixo,
  dispositivos fisicos, falhas (eletricas e de maquina), degradacao, eletromagnetismo,
  importacao unificada e agendador.
- src/instruments/: instrumentos virtuais (medicao) da simulacao e da maquina.
- src/examples/: referencias de CNC (stepper, maquina de referencia).
- src/app/: executavel `multiphysics`.
- docs/: `MANUAL.md` (usuario), `TAREFA.md` (plano e progresso), `RUNTIME.md` e
  `INTEGRATION_ROADMAP.md`.
- tests/: um `.lpr` por assunto, todos registrados no catalogo da Central de Testes
  (`multisuite/src/testing/multisuite_test_catalog.pas`); `tests/run_all.ps1` roda todos.
- `multiphysics.exe --capture=static|thermal|modal|system|circuit|loads|thread arquivo.png`
  resolve a demonstracao e salva a imagem da janela (conferencia sem clicar).

## Integracao
MultiAssembly define a montagem e abre o MultiPhysics com ela (`--file arquivo.massembly`); componentes e redes usam o contrato unificado. A integracao direta com o MakePCB ainda e pendente. O MultiPhysics
acrescenta materiais, cargas, condicoes e modelos e devolve estados e resultados. O
MultiCNC continua sendo o unico dono da execucao fisica.

## Regras
1. Rotular a fidelidade de todo resultado: ESTIMATIVA, ENGENHARIA ou VALIDADO
   (ver `README.md`). Nunca apresentar estimativa como resultado de engenharia.
2. Sem malha/solver valido o solve fica bloqueado: nao inventar resultado.
3. Modelos simplificados (nao e SPICE, nao e FEM transitorio) devem dizer isso na saida.
4. Simulacao deterministica: mesma entrada, mesmo resultado (testes dependem disso).
5. Toda formula nova com teste contra caso analitico conhecido.
6. Com numeros reais, escreva `Max(0.0, x)` e `Min(1.0, x)`: com literal inteiro o Free Pascal
   escolhe a versao `Single` e o resultado perde precisao.

## Nao pertence aqui
Controle de porta serial/protocolo, geracao de G-code, CAD de pecas e projeto de PCB.
