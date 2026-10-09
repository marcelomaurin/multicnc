# TAREFA: MultiCAD (modelagem paramétrica de peças, referência SolidWorks 2014)

- **Aberta em:** 09/10/2026
- **Estado:** em análise. Aguardando aprovação das decisões D1 a D8.
- **Visão:** [../README.md](../README.md)
- **Arquitetura:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Guia para IA:** [AI_GUIDE.md](AI_GUIDE.md)

## Ponto de partida

O código atual é um esqueleto de cerca de 120 linhas: `multicad_types`, `multicad_feature`
(Id pelo endereço do objeto, que não persiste), `multicad_document`, `multicad_sketch`
(linha, círculo, retângulo e restrições guardadas, sem solver), `multicad_extrude` (guarda só a
profundidade), `multicad_viewport` (2D) e `tests/test_document`. O registro da suíte já tem
`stiMultiCAD`, no grupo **Projetar**. Quase tudo será reescrito; o que serve é a divisão em
documento, *feature* e *sketch*.

## Progresso

| Fase | Estado | O que foi feito |
|---|---|---|
| 0 Base | pendente | |
| 1 Sketch e solver | pendente | |
| 2 Operações básicas | pendente | |
| 3 Vista 3D e árvore | pendente | |
| 4 Exportação e suíte | pendente | |
| 5 Furo, padrões, espelho | pendente | |
| 6 Filete, chanfro, casca | pendente | |
| 7 Desenho 2D | pendente | |
| 8 OpenCascade (opcional) | pendente | |

## Decisões para o Marcelo

| # | Pergunta | Proposta |
|---|---|---|
| **D1** | Núcleo geométrico | **Híbrido:** núcleo próprio em Pascal (malha com faces rotuladas) atrás da interface `ICadKernel` agora; adaptador OpenCascade opcional na fase 8. Alternativas: só OCCT desde o início (robusto, mas ponte C++, dezenas de MB e build difícil no Win64/Linux) ou só Pascal para sempre (sem STEP exato nem filete geral). |
| **D2** | Booleanas em malha | CSG por árvore BSP com tolerância e solda de vértices, em Pascal puro. Bom para peças prismáticas e torneadas. |
| **D3** | Vista 3D | OpenGL 2.1 pelo **LazOpenGLContext** (`TOpenGLControl`), com renderização por *software* para miniaturas, testes e máquinas sem OpenGL. |
| **D4** | Solver de restrições | Solver próprio Newton/Levenberg-Marquardt, com graus de liberdade pelo posto do jacobiano e as cores do SolidWorks (azul, preto, vermelho). |
| **D5** | Formato de arquivo | `.mcad` em JSON com Ids persistentes (contador gravado), no lugar dos Ids por ponteiro. Referências a faces e arestas por nome estável (`Extrude2/topo`). |
| **D6** | Nomes na interface | Português, no estilo do SolidWorks em PT: "Ressalto/Base extrudado", "Corte extrudado", "Ressalto revolucionado", "Furo", "Filete", "Chanfro", "Casca", "Padrão linear", "Padrão circular", "Espelhar". |
| **D7** | Primeira entrega | Fases 0 a 4: *sketch* com restrições, extrusão (ressalto e corte), revolução, vista 3D com árvore, STL/DXF e propriedades de massa. |
| **D8** | Integração | STL → MultiSlicer e MultiCAM; DXF (sketch ou face plana) → MakeRouter e LaserArt; `.mcad` → MultiAssembly; propriedades de massa → MultiPhysics e MultiAssembly. O MultiCAD nunca gera G-code. |

## Fases (depois das decisões)

Cada fase termina com testes no Linux e no Win64 (`-Cr -gt`), commit e push na `fila`, e o
andamento registrado neste arquivo. Mesmo procedimento do RouterPCB e do MakeRouter.

### Fase 0: base (≈ 2 h)
- [ ] Árvore `multicad/src/{core,sketch,kernel,features,export,ui,app}` e `tests`.
- [ ] Ids persistentes, parâmetros por operação, estado de erro, JSON `.mcad` ida e volta.
- [ ] `multicad_types`: vetores, matrizes 4×4, planos, tolerâncias.
- [ ] Interface `ICadKernel` e malha rotulada (`multicad_mesh`) com verificação de malha fechada.
- [ ] Testes: JSON, Ids estáveis entre execuções, malha de um cubo fechada e com volume certo.

### Fase 1: sketch e solver (≈ 5 h)
- [ ] Entidades: ponto, linha, arco, círculo, retângulo, ranhura, polígono, construção e
      linha de centro.
- [ ] Restrições: coincidente, horizontal, vertical, paralela, perpendicular, tangente, igual,
      concêntrica, ponto médio, fixa, simétrica.
- [ ] Cotas: distância, horizontal, vertical, raio, diâmetro, ângulo; nome `D1@Sketch1`.
- [ ] Solver Newton/LM e graus de liberdade (sub, total, superdefinido).
- [ ] Perfis: laços fechados com ilhas, via Clipper2.
- [ ] Testes: retângulo 80×50 totalmente definido, mudança de cota move só o que deve, conflito
      detectado, tangência linha-arco, perfil com furo vira região com ilha.

### Fase 2: operações básicas (≈ 6 h)
- [ ] Planos de referência (deslocado, em ângulo, pela face).
- [ ] Ressalto e corte extrudado: cego, passante, até a face, plano médio, inclinação,
      direção 2.
- [ ] Ressalto e corte revolucionado.
- [ ] Booleanas BSP (D2) e nomes estáveis das faces.
- [ ] Reconstrução com cache a partir da primeira operação alterada; erros por operação.
- [ ] Testes: volumes analíticos (bloco, furo passante, cilindro revolucionado), malha sempre
      fechada, nome de face mantido depois de um corte, cota alterada reconstrói.

### Fase 3: vista 3D e árvore (≈ 6 h)
- [ ] `TOpenGLControl`: sombreado com arestas, orbitar, deslocar, zoom no cursor, vistas
      padrão, isométrica e cubo de vistas.
- [ ] Seleção por cor (face, aresta, vértice) e realce.
- [ ] Modo *sketch*: gira para o plano, grade, relações, cotas editáveis com duplo clique.
- [ ] *Sketch* sobre face plana.
- [ ] Árvore de operações: editar, suprimir, excluir, renomear, barra de retrocesso.
- [ ] Painel de propriedades e abas de comandos (padrão visual da suíte).
- [ ] Renderização por *software* para miniatura e teste sem GPU.

### Fase 4: exportação e suíte (≈ 3 h)
- [ ] STL binário e ASCII; DXF do *sketch* ou de face plana.
- [ ] Propriedades de massa (volume, área, centro de massa, massa pelo material) e medir.
- [ ] "Abrir no MultiSlicer" e "Abrir no MakeRouter" (mesmo padrão do `OpenInTool` do MakePCB).
- [ ] Suíte: `Application.CreateForm`, ícone, bandeja, MultiSuite, Central de Testes, CI,
      instalador e documentação.
- [ ] **Primeira entrega** (ver critério abaixo).

### Fase 5: furo, padrões e espelho (≈ 4 h)
- [ ] Assistente de furo: simples, rebaixado, escareado (pontos de um *sketch* na face).
- [ ] Padrão linear e circular de operações; espelhar por plano.

### Fase 6: filete, chanfro e casca (≈ 6 h)
- [ ] Filete e chanfro em arestas retas e circulares entre faces planas e cilíndricas.
- [ ] Casca com espessura constante e faces removidas (faces planas).
- [ ] Teste: volume do filete de um cubo dentro de 0,5% do valor analítico.

### Fase 7: desenho 2D (≈ 5 h)
- [ ] Vistas ortográficas e isométrica, linhas ocultas, cotas e legenda.
- [ ] Saída DXF e PDF.

### Fase 8: OpenCascade (opcional, ≈ 10 h ou mais)
- [ ] `mcad_occt` (DLL/SO com API C) atrás de `ICadKernel`; STEP ler/gravar, filete e casca
      gerais.
- [ ] Build para Win64 e Linux e empacotamento no instalador.

## Critério de pronto (primeira entrega, fases 0 a 4)
1. Modelar um suporte: base 80 × 50 × 10 mm, dois furos Ø8 (padrão), um corte retangular e um
   ressalto revolucionado.
2. Mudar a cota da base de 80 para 100 mm e ver a peça reconstruir sem erro, com os furos no
   lugar.
3. Exportar STL que o MultiSlicer abre; volume dentro de 0,5% do valor analítico.
4. Salvar, fechar e abrir o `.mcad`: mesma árvore, mesmos Ids, mesmo sólido.
5. Testes passando no Linux (GTK2) e no Win64 (Wine).

## Riscos
- **Nomes estáveis de faces:** é o ponto mais delicado de qualquer CAD paramétrico. Mitigação:
  rótulo pela operação de origem, e operação marcada com erro (sem quebrar o arquivo) quando a
  referência some.
- **Robustez da CSG em malha:** faces coplanares e arestas coincidentes geram lixo numérico.
  Mitigação: tolerância, solda de vértices, testes de malha fechada em toda booleana e o
  adaptador OCCT como saída.
- **OpenGL no Wine e em placas antigas:** pipeline fixo 2.1 e alternativa por *software*.
- **Convergência do solver:** partir da posição atual, amortecimento LM e detecção de conflito
  pelo posto do jacobiano.
- **Escopo:** o SolidWorks tem décadas de trabalho. A entrega cobre peças prismáticas e
  torneadas; superfícies livres, chapas metálicas e soldas ficam fora.
