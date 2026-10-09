# MultiCAD

> **Estado (09/10/2026):** em análise. Hoje há só um esqueleto (cerca de 120 linhas):
> documento, lista de *features*, *sketch* com linha, círculo e retângulo (sem restrições
> resolvidas), uma extrusão que guarda só a profundidade e uma vista 2D. O plano completo está
> em [docs/TAREFA.md](docs/TAREFA.md), com as decisões que precisam de aprovação.

O **MultiCAD** é o CAD **paramétrico de peças mecânicas** da suíte. O fluxo de referência é o do
**SolidWorks 2014**, sem copiá-lo:

1. escolher um plano (frontal, superior, lateral) ou uma face da peça;
2. desenhar o *sketch* com linhas, arcos e círculos, presos por **restrições** (coincidente,
   horizontal, paralelo, tangente...) e **cotas** que comandam a forma;
3. transformar o *sketch* em sólido com **operações** (*features*): ressalto extrudado, corte
   extrudado, revolução, furo, filete, chanfro, casca, padrões e espelhamento;
4. mudar qualquer cota e ver a peça **reconstruir** pela **árvore de operações**, como o
   FeatureManager.

O resultado é a geometria da peça, que as outras ferramentas usam para fabricar, montar e
simular. O MultiCAD **nunca** gera G-code nem fala com a máquina.

## Onde entra na suíte

```text
MultiCAD (peça) ──> MultiAssembly (montagem) ──> MultiPhysics (simulação)
     │
     ├── STL ────────> MultiSlicer ───────────────> MultiCNC (impressora 3D)
     ├── DXF (perfil) > MakeRouter / MultiCAM ─────> MultiCNC (CNC Router)
     └── STEP ───────> outros CADs (fase opcional, com OpenCascade)
```

| Ferramenta | Papel | Diferença para o MultiCAD |
|---|---|---|
| **MultiCAD** | peça mecânica sólida, paramétrica, com histórico | — |
| **MakeRouter** | madeira e letreiros: desenho 2D, relevo e percursos no mesmo programa | não tem sólido B-rep nem histórico de operações |
| **MultiCAM** | simulação da máquina e CAM de peças mecânicas | recebe a geometria do MultiCAD |
| **MultiAssembly** | junta peças, placas, motores e sensores | usa as peças do MultiCAD |
| **MakePCB / MultiPCB** | placas de circuito | outra linha de projeto |

## Telas previstas (padrão visual da suíte)

- **Esquerda:** árvore de operações (planos, origem, *sketches*, operações), com a barra de
  retrocesso para editar no meio do histórico, suprimir e reordenar.
- **Centro:** vista 3D (orbitar, deslocar, zoom, vistas padrão e isométrica, cubo de vistas)
  com seleção de faces, arestas e vértices. No modo *sketch*, a vista gira para o plano e
  mostra a grade, as relações e as cotas.
- **Direita:** propriedades da operação ou do *sketch* selecionado (como o PropertyManager).
- **Topo:** abas de comandos, como o CommandManager: *Sketch*, Operações, Avaliar (medir,
  propriedades de massa) e Exportar.
- **Rodapé:** estado do *sketch* (sub/totalmente definido), unidade (mm) e coordenadas.

## Documentação

- [docs/TAREFA.md](docs/TAREFA.md): decisões, fases, critérios de pronto e riscos.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): modelo de dados, núcleo geométrico, solver de
  restrições, reconstrução, vista 3D e exportação.
- [docs/AI_GUIDE.md](docs/AI_GUIDE.md): responsabilidades e limites, para quem for alterar o
  código.
