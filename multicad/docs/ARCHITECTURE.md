# MultiCAD - Arquitetura (proposta para análise)

Estado: em análise (09/10/2026). As decisões marcadas com **[D#]** estão em `TAREFA.md`.

## 1. Camadas

```text
app/ui   árvore de operações, vista 3D, propriedades, abas de comandos
  │
doc      TCadDocument: planos, sketches, operações (parâmetros), arquivo .mcad
  │        reconstrução: percorre a árvore e chama o núcleo
  │
sketch   entidades 2D + restrições + cotas  ──> solver (Newton/LM)  ──> perfis (laços)
  │
kernel   ICadKernel (interface) ──> núcleo Pascal (malha + faces rotuladas)   [D1]
  │                              └> adaptador OpenCascade (opcional, fase 8)
  │
export   STL, DXF, .mcad, (STEP com OCCT)
```

Regras:

- A geometria nunca depende da interface. Testes rodam sem LCL.
- O núcleo fica atrás de uma interface, para trocar o núcleo Pascal pelo OpenCascade sem mexer
  na árvore nem na tela.
- A reconstrução é determinística: o mesmo arquivo gera o mesmo sólido.

## 2. Modelo de dados (`.mcad`, JSON)

```text
TCadDocument
  Units: mm ; Material (densidade, para massa)
  Origin + planos padrao: Frontal (XY), Superior (XZ), Lateral (YZ)
  Features[] (ordem = historico)
    TCadPlane      : offset/angulo de plano ou face, Id persistente
    TCadSketch     : Plane ref (plano ou face por referencia estavel), Entities[], Constraints[],
                     Dimensions[] (valor, nome "D1@Sketch1", dirigida/dirigente)
    TCadExtrude    : Sketch ref, Kind (ressalto|corte), Fim (cego, passante, ate face,
                     plano medio), Profundidade, Inclinacao, Direcao 2, Contorno selecionado
    TCadRevolve    : Sketch ref, Eixo (linha do sketch), Angulo
    TCadHole       : face + pontos do sketch, tipo (simples, rebaixo, escareado), diametros
    TCadPattern    : features fonte, linear (direcao, passo, qtd) ou circular (eixo, qtd)
    TCadMirror     : features fonte, plano
    TCadFillet/Chamfer/Shell : arestas/faces por referencia estavel, raio/distancia/espessura
  Suppressed, RollbackIndex
  Equations[] (fase posterior): "D2@Sketch1 = D1@Sketch1 / 2"
```

- **Ids persistentes.** Hoje o Id vem do endereço do objeto (`IntToHex(PtrUInt(Self))`) e muda a
  cada execução. Ele passa a ser um contador gravado no arquivo, como no MakeRouter.
- **Referências estáveis a faces e arestas** (*naming*): a face é identificada pela operação que
  a criou e por um rótulo local, por exemplo `Extrude2/topo`, `Extrude2/lateral[3]` ou
  `Revolve1/cilindro`. Um corte posterior não renomeia a face. Esse é o ponto mais delicado de
  qualquer CAD paramétrico: quando a referência some, a operação fica com erro na árvore (como no
  SolidWorks) e não quebra o arquivo.

## 3. Sketch e solver de restrições **[D4]**

- Entidades: ponto, linha, arco (centro/3 pontos/tangente), círculo, retângulo (4 linhas +
  restrições), ranhura, polígono, *spline* (fase posterior), linha de construção, linha de
  centro (eixo de revolução).
- Restrições: coincidente, horizontal, vertical, paralela, perpendicular, tangente, igual,
  concêntrica, ponto médio, fixa, simétrica.
- Cotas: distância, horizontal, vertical, raio, diâmetro, ângulo.
- Solver: as variáveis são as coordenadas dos pontos, raios e ângulos; cada restrição vira uma
  ou mais equações `f(x) = 0`. Resolve por Newton com mínimos quadrados (Levenberg-Marquardt),
  partindo da posição atual, o que mantém o desenho "parecido" ao arrastar.
- Graus de liberdade pelo posto do jacobiano: **azul** = subdefinido, **preto** = totalmente
  definido, **vermelho** = conflito/superdefinido (as mesmas cores do SolidWorks).
- Perfis: os laços fechados do sketch (com ilhas) são achados no grafo de entidades e passam
  à Clipper2 (`src/shared/clipper2`) para regiões e booleanas 2D. A extrusão usa a região
  escolhida.

## 4. Núcleo geométrico **[D1] [D2]**

### Núcleo Pascal (primeira entrega)

- O sólido é uma **malha fechada de triângulos** com cada triângulo rotulado pela face de origem
  (Id da operação + rótulo + tipo de superfície: plano, cilindro, cone, toro e parâmetros).
  O rótulo permite selecionar "a face" (todos os triângulos com o mesmo rótulo), fazer sketch
  sobre face plana, medir e exportar.
- Extrusão e revolução geram a malha diretamente do perfil (laterais com rótulo por segmento
  do perfil; arcos viram faces cilíndricas).
- Booleanas (ressalto = união, corte = diferença) sobre malha: CSG por árvore BSP com
  tolerância e solda de vértices **[D2]**. É simples, em Pascal puro, e serve bem para peças
  prismáticas e torneadas.
- Limites: filete e chanfro só em arestas retas e circulares de faces planas e cilíndricas
  (fase 6); casca por offset de faces planas. Superfícies livres e STEP exato ficam com o
  OpenCascade.

### Adaptador OpenCascade (opcional, fase 8)

- OCCT (LGPL) num DLL/SO pequeno com API C (`mcad_occt.dll`: criar prisma, revolver,
  booleana, filete, casca, tesselar, STEP ler/gravar), chamado pelo Lazarus por
  `external`. A mesma interface `ICadKernel`.
- Custo: compilar o OCCT para Win64 e Linux, distribuir dezenas de MB e manter a ponte. Vale
  quando filete, casca robusta ou STEP forem prioridade.

## 5. Reconstrução

- A árvore é avaliada em ordem até a barra de retrocesso: cada operação recebe o sólido
  anterior e devolve o novo. Erros (perfil aberto, referência perdida, booleana vazia) marcam a
  operação em vermelho com a mensagem e seguem para a próxima, quando possível.
- Cache por operação: só reconstrói a partir da primeira operação alterada.
- Mudar uma cota resolve o sketch, invalida as operações seguintes e reconstrói.

## 6. Vista 3D **[D3]**

- OpenGL pelo pacote **LazOpenGLContext** (`TOpenGLControl`), com pipeline fixo do OpenGL 2.1
  (funciona em placas antigas e no Mesa). Sombreado com arestas, cores por face selecionada e
  transparência no modo sketch.
- Navegação como no SolidWorks: botão do meio orbita, Ctrl + meio desloca, roda dá zoom no
  cursor, barra de espaço abre as vistas padrão, e há cubo de vistas no canto.
- Seleção: *picking* por ID de cor num buffer escondido (face, aresta, vértice).
- Alternativa por *software* (z-buffer em Pascal) para miniaturas, testes sem GPU e máquinas
  sem OpenGL.

## 7. Exportação e integração

| Saída | Para quem | Fase |
|---|---|---|
| STL (binário e ASCII, mm) | MultiSlicer (impressão 3D), MultiCAM | 4 |
| DXF do sketch ou de uma face plana | MakeRouter (madeira, chapas), LaserArt | 4 |
| `.mcad` (peça paramétrica) | MultiAssembly (referência da peça) | 4 |
| Propriedades de massa (volume, área, centro de massa) | MultiPhysics, MultiAssembly | 4 |
| STEP | outros CADs | 8 (OCCT) |
| Desenho 2D (vistas, cotas) em DXF/PDF | oficina | 7 |

## 8. Unidades previstas

| Pasta | Unidades |
|---|---|
| `src/core` | `multicad_types` (vetores, matrizes, tolerâncias), `multicad_document` (árvore, Ids, JSON), `multicad_feature` (base com parâmetros e estado de erro), `multicad_rebuild` |
| `src/sketch` | `multicad_sketch` (entidades, restrições, cotas), `multicad_solver` (Newton/LM, graus de liberdade), `multicad_profile` (laços e regiões) |
| `src/kernel` | `multicad_kernel` (interface), `multicad_mesh` (malha rotulada, solda), `multicad_csg` (BSP), `multicad_sweep` (extrusão e revolução), `multicad_occt` (adaptador, fase 8) |
| `src/features` | `multicad_extrude`, `multicad_revolve`, `multicad_hole`, `multicad_pattern`, `multicad_mirror`, `multicad_fillet` |
| `src/export` | `multicad_stl`, `multicad_dxf`, `multicad_massprops` |
| `src/ui` | `multicad_view3d` (OpenGL), `multicad_softrender`, `multicad_sketchview`, `multicad_tree`, `multicad_props` |
| `src/app` | `multicad_main` (padrão da suíte) |
| `tests` | solver, perfis, malha fechada (*manifold*), volumes analíticos, JSON, reconstrução, STL |
