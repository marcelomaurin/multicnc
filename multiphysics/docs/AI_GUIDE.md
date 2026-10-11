# MultiPhysics - Guia para IA

## Finalidade
Simulacao fisica multidominio de uma montagem vinda do MultiAssembly: eletrica/eletronica,
microcontroladores, motores e atuadores, mecanica, termica, eletromagnetismo, energia,
materiais e falhas/degradacao. Mostra o comportamento antes de fabricar; nunca comanda a
maquina real.

## Estrutura
- src/core/: tipos, projeto, cenario, ambiente (Ar/Agua/Vacuo), materiais, energia/quimica.
- src/solver/: solver, MNA (circuitos), nao linear e acoplamento entre dominios.
- src/dynamics/: vetores, corpo rigido, mecanica e empuxo.
- src/runtime/: runtime em passos de tempo, grafo de componentes, biblioteca de
  componentes, modelos de circuito/movimento/stepper, MCU e programa, controle de eixo,
  dispositivos fisicos, falhas (eletricas e de maquina), degradacao, eletromagnetismo,
  importacao unificada e agendador.
- src/instruments/: instrumentos virtuais (medicao) da simulacao e da maquina.
- src/examples/: referencias de CNC (stepper, maquina de referencia).
- src/app/: executavel `multiphysics`.
- docs/: `RUNTIME.md` (ordem do passo de simulacao, limites) e
  `INTEGRATION_ROADMAP.md` (integracao com o restante da suite).
- tests/: mecanica, runtime, merge da importacao, corpo rigido, materiais e ambiente.
  Os demais testes de dominio ficam no catalogo da Central de Testes
  (`multisuite/src/testing/multisuite_test_catalog.pas`).

## Integracao
MultiAssembly define a montagem; componentes e redes usam o contrato unificado. A integracao direta com o MakePCB ainda e pendente. O MultiPhysics
acrescenta materiais, cargas, condicoes e modelos e devolve estados e resultados. O
MultiCNC continua sendo o unico dono da execucao fisica.

## Regras
1. Rotular a fidelidade de todo resultado: ESTIMATIVA, ENGENHARIA ou VALIDADO
   (ver `README.md`). Nunca apresentar estimativa como resultado de engenharia.
2. Sem malha/solver valido o solve fica bloqueado: nao inventar resultado.
3. Modelos simplificados (nao e SPICE, nao e FEM transitorio) devem dizer isso na saida.
4. Simulacao deterministica: mesma entrada, mesmo resultado (testes dependem disso).
5. Toda formula nova com teste contra caso analitico conhecido.

## Nao pertence aqui
Controle de porta serial/protocolo, geracao de G-code, CAD de pecas e projeto de PCB.
