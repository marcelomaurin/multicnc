# MultiCAD

Núcleo CAD paramétrico da suíte MultiCNC.

Objetivo: oferecer uma aplicação desktop Lazarus com fluxo de trabalho inspirado em CADs mecânicos paramétricos: documento, árvore de features, Sketch 2D, cotas/restrições e geração de sólidos, mantendo fabricação separada em MultiCAM, MultiSlicer, LaserPCB, MultiPCB e MultiCNC.

## Primeira etapa
- documento CAD
- árvore paramétrica
- Sketch 2D
- linha, círculo e retângulo
- cotas lineares/radiais
- restrições básicas
- Extrude e Cut como features paramétricas
- serialização preparada
- interface principal com árvore, viewport e propriedades

## Arquitetura
MultiCAD -> modelo geométrico -> adaptadores de fabricação
- MultiCAM: usinagem CNC
- MultiSlicer: impressão 3D
- LaserPCB: laser
- MultiPCB: eletrônica/PCB
- MultiCNC: execução física

O núcleo CAD não envia comandos diretamente para máquinas.

## Paramétrico de verdade
- **Solver de restrições** (`multicad_constraint_solver`): horizontal, vertical, coincidente, paralelo, perpendicular, igual, distância, raio, ângulo e fixo, resolvidos por Levenberg-Marquardt a partir do desenho aproximado.
- **Graus de liberdade**: após resolver, o posto da Jacobiana classifica o sketch como subrestrito, totalmente restrito, redundante ou conflitante.
- **Sólidos** (`multicad_mesh`): perfis fechados (linhas encadeadas e círculos) com furos, triangulação por *ear clipping*, extrusão em malha fechada e exportação **STL** binário e **3MF**, que o MultiSlicer importa diretamente.
