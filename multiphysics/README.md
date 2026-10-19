# MultiPhysics 0.2
Ferramenta da suite MultiSuite para simular fisicamente uma montagem proveniente do MultiAssembly.
Manual do usuario: [docs/MANUAL.md](docs/MANUAL.md). Plano, tarefas e progresso: [docs/TAREFA.md](docs/TAREFA.md).
Exemplos: [models/multiphysics](../models/multiphysics/README.md).

## O que faz (e com que fidelidade)
| Area | Como | Fidelidade |
|---|---|---|
| Estrutural estatica linear | FEM proprio TET4/TET10, fixacao, deslocamento, forca, pressao, gravidade | ENGENHARIA com convergencia < 5% |
| Termica permanente | conducao, temperatura, fluxo, conveccao, potencia dissipada | ENGENHARIA com convergencia < 5% |
| Termomecanica | campo termico como carga de dilatacao | ENGENHARIA com convergencia < 5% |
| Modal | iteracao em subespaco, frequencias, formas, massa efetiva | ENGENHARIA com convergencia < 5% |
| Contato | colado (sem atrito/separacao) entre pecas e entre primitivas | idem a analise |
| CalculiX (opcional) | mesmo modelo em .inp, executa o ccx, le o .frd | ENGENHARIA (externo) |
| Sistema eletromecanico | fonte, PWM, motor DC com indutancia, carga, sensor, PI | ESTIMATIVA |
| CNC virtual | rampa, torque x velocidade, estol, homing, falhas | ESTIMATIVA |
| Circuitos | netlist SPICE sobre MNA Newton-Raphson, transitorio | ENGENHARIA nos casos conferidos (RC) |
| Fluido, atmosfera, flutuacao | arrasto/empuxo reduzidos, ISA, calado e GM pela malha | ESTIMATIVA (nao e CFD) |

## Arquitetura
`src/geometry` (primitivas, importacao do MultiAssembly) -> `src/mesh` (malha tetraedrica, contato) ->
`src/fem` (matrizes esparsas, Cholesky/PCG, elementos, analise) e `src/ccx` (CalculiX); `src/ui` (vista 3D,
grafico) e `src/app` (janela). O programa nao inventa resultado: sem malha, material ou fixacao o calculo e
recusado com a mensagem do que falta.

## Limites
Lados retos (cilindros poligonais), material linear, pequenos deslocamentos, contato so colado, geometria por
primitivas (STL ainda nao), sem CFD/FSI.

## Ambientes fisicos
O projeto possui presets Ar, Agua e Vacuo, alem da arquitetura para ambiente personalizado. Cada ambiente carrega temperatura, pressao, densidade, viscosidade dinamica, gravidade e vetor de escoamento.

## Barcos
A camada preliminar calcula velocidade relativa, pressao dinamica, arrasto aproximado e empuxo hidrostatico. Estes valores sao ESTIMATIVAS, nao substituem CFD. Evolucoes: centro de empuxo, estabilidade, superficie livre, ondas, casco, heave/pitch/roll e FSI.

## Aeroespacial
O preset Ar permite cargas preliminares de escoamento. Para foguetes, resultados de alta velocidade nao devem usar a aproximacao incompressivel como resultado final. Evolucoes: atmosfera por altitude, Mach, compressibilidade, choque, aquecimento aerodinamico, massa variavel, propulsao, 6-DOF e acoplamento estrutural/termico.

## Fidelidade
ESTIMATIVA = formulas reduzidas/pre-dimensionamento.
ENGENHARIA = solver numerico com malha, convergencia e condicoes documentadas.
VALIDADO = modelo comparado com referencia analitica, experimental ou benchmark aceito.
