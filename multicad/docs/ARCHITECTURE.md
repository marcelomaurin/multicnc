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
    TCadPlane      : plano de referencia (ate 3 referencias + restricoes), Id persistente; ver 3A
    TCadAxis       : eixo de referencia (face cilindrica, 2 pontos, 2 planos, linha); ver 3A
    TCadSketch     : Plane ref (plano ou face por referencia estavel), Entities[], Constraints[],
                     Dimensions[] (valor, nome "D1@Sketch1", dirigida/dirigente)
    TCadExtrude    : Sketch ref, Kind (ressalto|corte), De, Direcao1/Direcao2 (condicao final,
                     profundidade, inclinacao), Fino, Contornos selecionados, Mesclar,
                     Inverter lado; ver 3B
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

## 3A. Planos de referência e vista do plano do sketch

### Planos padrão e referencial local

Cada plano tem origem, normal e eixos locais `x`/`y` do *sketch*. Os eixos locais definem como o
desenho aparece na tela ao entrar no *sketch*, então seguem o SolidWorks:

| Plano | Normal | x do sketch (direita na tela) | y do sketch (para cima na tela) | Visto de |
|---|---|---|---|---|
| Frontal | +Z | +X | +Y | frente (+Z) |
| Superior | +Y | +X | −Z | cima (+Y) |
| Lateral (direita) | +X | −Z | +Y | direita (+X) |

Em **face plana**: normal = normal externa da face; `x` = projeção do X global na face (se
quase paralelo à normal, usa o Z global); `y = normal × x`; origem = projeção da origem global
na face. A regra é determinística, para o *sketch* não "girar" quando a peça reconstrói.

### Plano de referência (comando "Plano")

Como o PropertyManager de Plano do SolidWorks: até **três referências** (plano, face, aresta,
eixo, ponto, vértice), cada uma com uma restrição. As combinações válidas:

| Tipo | Referências | Parâmetros |
|---|---|---|
| Deslocado (*offset*) | plano ou face plana | distância, inverter, **número de planos** (cria vários igualmente espaçados) |
| Paralelo por ponto | plano/face + ponto/vértice | — |
| Em ângulo | plano/face + aresta/eixo/linha | ângulo, inverter, número de planos |
| Plano médio | duas faces/planos paralelos (ou não paralelos: bissetor) | — |
| Por três pontos | 3 vértices/pontos | — |
| Por linha e ponto | aresta/linha + ponto | — |
| Normal à curva | aresta/linha do sketch + ponto nela (ou extremidade) | — |
| Tangente à face cilíndrica | face cilíndrica + plano (paralelo/perpendicular) ou linha | — |
| Coincidente | plano/face | só para criar plano nomeado sobre face |

- A interface mostra o plano em amarelo enquanto edita e só habilita o OK quando as
  referências definem o plano por completo ("Totalmente definido", como no SolidWorks).
- Planos aparecem como retângulos translúcidos com o nome, dimensionados à caixa da peça
  (redimensionáveis por alças), e podem ser ocultos.
- Referências a faces usam o nome estável (seção 2). Se a face some, o plano fica com erro.

### Eixo de referência

Por face cilíndrica/cônica, por aresta reta, por dois planos (interseção), por dois pontos e
por ponto + face (normal). Eixos temporários das faces cilíndricas (mostrar/ocultar), como no
SolidWorks, para revolução e padrão circular sem criar eixo.

### Vista ao entrar e sair do sketch

- **Ao criar ou editar um sketch**, a vista gira para "Normal a" o plano (opção "Girar
  automaticamente a vista para normal ao plano do esboço", ligada por padrão), com o `x` do
  sketch à direita e o `y` para cima.
- **Ctrl+8** volta a ficar normal ao plano a qualquer momento; um segundo Ctrl+8 gira 180° (vê
  pelo outro lado), como no SolidWorks.
- **Vista de seção do esboço:** opção de cortar a peça no plano do sketch para desenhar dentro
  dela (útil em faces internas).
- Os sólidos ficam semitransparentes e as arestas da peça podem ser usadas por **Converter
  entidades** (projeta arestas no sketch, com referência) e **Offset de entidades**.
- **Ao sair do sketch** a vista fica onde está (mesmo comportamento do SolidWorks); o atalho
  de vista anterior volta à orientação de antes.
- O canto superior direito mostra o ícone "Sair do esboço" e "Cancelar alterações" (confirm
  corner do SolidWorks).

## 3B. Extrusão e corte (Ressalto/Base extrudado e Corte extrudado)

### Fluxo (como no SolidWorks)

1. Selecionar um sketch na árvore (ou estar editando um) e clicar em **Ressalto/Base
   extrudado** ou **Corte extrudado**. Sem sketch selecionado, o comando pede para escolher um
   plano/face e abre um sketch novo; ao sair do sketch, volta ao comando.
2. O painel esquerdo troca a árvore pelo **PropertyManager** da operação, com OK (✓, Enter) e
   Cancelar (✗, Esc). A árvore continua acessível pela vista suspensa sobre a área 3D, para
   escolher referências.
3. **Pré-visualização** amarela translúcida em tempo real (corte em vermelho translúcido), com
   **seta de arraste** para a profundidade e a cota mostrada na tela, editável por duplo clique.
4. Ao confirmar, o sketch passa a ficar **absorvido** sob a operação na árvore
   (`Extrude1 > Sketch1`), como no SolidWorks.
5. **Editar operação** reabre o PropertyManager; **Editar esboço** abre o sketch e reconstrói ao
   sair. Duplo clique na operação mostra as cotas na tela para alteração rápida.

### PropertyManager

| Grupo | Opção (PT) | Valores |
|---|---|---|
| **De** | Início | Plano do esboço; Superfície/Face/Plano; Vértice; Deslocamento (distância, inverter) |
| **Direção 1** | Condição final | Cego; Passante; Até o próximo; Até o vértice; Até a superfície; Deslocamento da superfície (distância, inverter, "transladar superfície"); Até o corpo; Plano médio |
| | Inverter direção | botão ao lado da condição |
| | Direção de extrusão | normal ao sketch (padrão) ou aresta/linha/eixo escolhido |
| | Profundidade | mm, com expressões |
| | Inclinação | ângulo de saída, "Inclinação para fora" |
| | Mesclar resultado | (só ressalto) une ao corpo existente; desligado cria um corpo novo |
| | Inverter lado a cortar | (só corte) remove o lado de fora do perfil |
| **Direção 2** | caixa de seleção | condição final, profundidade e inclinação próprias (não existe com Plano médio) |
| **Recurso fino** | caixa de seleção | Tipo: Uma direção, Plano médio, Duas direções; espessura (e espessura 2); "Tampar extremidades" com espessura da tampa (perfil fechado) |
| **Contornos selecionados** | lista | regiões do sketch escolhidas na vista; vazio = todas |
| **Escopo do recurso** | | Todos os corpos / Corpos selecionados (+ "Seleção automática") |

Condições finais disponíveis por operação:

| Condição | Ressalto | Corte | Observação |
|---|---|---|---|
| Cego | ✓ | ✓ | profundidade |
| Passante | — | ✓ | atravessa todos os corpos |
| Passante - ambos | — | ✓ | nas duas direções (direção 2 automática) |
| Até o próximo | ✓ | ✓ | até a próxima face que cobre todo o perfil |
| Até o vértice | ✓ | ✓ | plano paralelo ao sketch pelo vértice |
| Até a superfície | ✓ | ✓ | face ou plano escolhido (pode ser inclinado) |
| Deslocamento da superfície | ✓ | ✓ | distância a partir da face |
| Até o corpo | ✓ | ✓ | até o corpo escolhido |
| Plano médio | ✓ | ✓ | profundidade total dividida igualmente |

### Regras e mensagens

- **Perfil aberto** só vale com Recurso fino; sem ele, erro "O esboço tem contornos abertos"
  com os pontos abertos destacados.
- **Primeira operação** só pode ser ressalto (corte sem corpo dá erro); o primeiro ressalto
  cria o corpo base ("Ressalto/Base").
- Perfis com **auto-interseção** ou entidades sobrepostas: erro com a entidade marcada.
- **Contornos aninhados** viram regiões com ilhas (a ilha vira furo), pela Clipper2.
- **Ressalto** que não toca o corpo com "Mesclar" ligado gera um segundo corpo e um aviso
  (multicorpo), como no SolidWorks.
- **Corte** que não remove nada: aviso "O corte não intercepta o modelo".
- **Até o próximo / Até a superfície** sem face válida na direção: erro com sugestão de
  inverter a direção.
- Inclinação que fecha o perfil antes da profundidade: erro "Ângulo de inclinação muito
  grande".

Sentido padrão: o ressalto sai pela normal do esboço; o **corte entra na peça** (contra a
normal), como no SolidWorks. "Inverter direção" troca os dois.

### Geometria (núcleo Pascal)

- O perfil (regiões com ilhas) é varrido na direção escolhida: tampas inicial e final
  (triangulação do polígono com furos) e laterais por segmento do perfil. Arcos viram faces
  cilíndricas (ou cônicas, com inclinação) com o centro e o raio guardados no rótulo.
- **Inclinação:** cada nível é o *offset* do perfil por `d·tan(a)` (Clipper2, cantos retos
  para arestas retas e arredondados para arcos).
- **Condições "até":** calcula a distância ao longo da direção até a face (para plano
  inclinado, a tampa final é a interseção do prisma com o plano: varre além e faz booleana
  com o semiespaço).
- **Recurso fino:** a região é o *offset* do contorno (dentro, fora ou centrado) com a
  espessura; com "Tampar extremidades", casca do perfil fechado + tampas.
- Ressalto = união; corte = diferença (BSP, seção 4).

### Nomes estáveis das faces

| Face | Nome |
|---|---|
| Tampa no plano do sketch | `Extrude2/inicio` |
| Tampa final | `Extrude2/fim` |
| Lateral gerada pela entidade `E` do sketch | `Extrude2/lat:E` |
| Lateral de recurso fino (dentro/fora) | `Extrude2/lat:E/in`, `Extrude2/lat:E/out` |

O nome usa o **Id persistente da entidade** do sketch, não a posição na lista, para que
acrescentar uma linha no sketch não renomeie as outras faces.

### Revolução (mesmo padrão)

Ressalto/Corte revolucionado: eixo (linha de centro do sketch, aresta ou eixo de referência),
condição (Cego com ângulo, Plano médio, Até o vértice/superfície, Direção 2), Recurso fino e
Contornos selecionados. Faces `Revolve1/rev:E` (cilindro, cone, toro ou plano conforme a
entidade) e, abaixo de 360°, `Revolve1/inicio` e `Revolve1/fim`.

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
  (funciona em placas antigas e no Mesa). Cores por face selecionada e transparência no modo
  sketch.
- Seleção: *picking* por ID de cor num buffer escondido (face, aresta, vértice).
- Alternativa por *software* (z-buffer em Pascal) para miniaturas, testes sem GPU e máquinas
  sem OpenGL.

### 6.1 Sistema de coordenadas

- Igual ao SolidWorks: **Y para cima**. Plano Frontal = XY (olhando de +Z), Superior = XZ,
  Lateral (direita) = YZ. Origem visível no centro.
- Na exportação (STL, DXF) há uma opção de orientação, porque o MultiSlicer e as máquinas usam
  **Z para cima**: "Y do modelo → Z" (padrão) ou "apoiar a face selecionada na mesa". Sem
  isso a peça chega deitada no fatiador.

### 6.2 Navegação (mouse)

| Ação | Comando |
|---|---|
| Orbitar | botão do meio |
| Deslocar | Ctrl + botão do meio |
| Zoom no cursor | roda (para frente aproxima, como no SolidWorks) |
| Girar em torno de aresta/vértice | botão do meio sobre a entidade (fixa o centro de giro) |
| Rolar no plano da tela | Alt + botão do meio |

### 6.3 Orientação e atalhos

| Vista | Atalho |
|---|---|
| Frontal / Posterior | Ctrl+1 / Ctrl+2 |
| Esquerda / Direita | Ctrl+3 / Ctrl+4 |
| Superior / Inferior | Ctrl+5 / Ctrl+6 |
| Isométrica | Ctrl+7 |
| Normal a (de frente para a face ou plano selecionado) | Ctrl+8 |
| Zoom para ajustar (peça inteira) | F |
| Diálogo de orientação (vistas padrão + vistas salvas) | barra de espaço |
| Vista anterior | Ctrl+Shift+Z |

- **Cubo de vistas** no canto superior direito (clicar em face, aresta ou vértice orienta) e
  **tríade de eixos** no canto inferior esquerdo.
- Transição animada curta entre orientações (desligável).
- **Vistas com nome** salvas no `.mcad` ("Vista do furo", etc.).
- Tela dividida em 1, 2 (horizontal/vertical) ou 4 janelas, cada uma com orientação própria.

### 6.4 Barra de vista (sobre a área 3D, como a *heads-up view toolbar*)

Zoom ajustar, zoom por área, vista anterior, vista de seção, orientação, estilo de exibição,
ocultar/mostrar itens (planos, eixos, origem, sketches) e perspectiva.

### 6.5 Estilos de exibição

| Estilo | Uso |
|---|---|
| Sombreado com arestas (padrão) | modelagem |
| Sombreado | apresentação |
| Linhas ocultas removidas | conferência de contorno |
| Linhas ocultas visíveis (tracejadas) | ver furos internos |
| Arame | todas as arestas |

- Projeção **ortográfica** por padrão, perspectiva opcional.
- **Vista de seção dinâmica:** corta a peça por um plano (Frontal/Superior/Lateral, face ou
  plano de referência) com deslocamento e ângulo, mostrando a face de corte hachurada. É só
  visual: não altera o sólido.

## 6A. Requisitos métricos e normas

O MultiCAD trabalha **só no sistema métrico** (mm, graus, kg). Medidas em polegadas podem ser
digitadas convertendo na entrada (`1in` = 25,4 mm), mas o modelo e os arquivos ficam em mm.

### Precisão
- Tolerância interna do modelo: 0,001 mm (solda de vértices, coincidência, booleanas).
- Casas decimais das cotas configuráveis (padrão 2 para mm, 1 para graus).
- Expressões nas cotas: `80/2`, `D1@Sketch1 + 5`.

### Materiais
Biblioteca com densidade (e módulo de elasticidade, para o MultiPhysics):
aço 1020, aço 1045, inox 304, alumínio 6061, latão, ferro fundido, nylon, POM, ABS, PLA, PETG,
MDF. Material editável e gravado no `.mcad`.

### Roscas e furos (assistente de furo, fase 5)
- Roscas métricas **ISO 261/262**: M2 a M24, passo normal e fino (M8 × 1,25 / M8 × 1,0...).
- Broca para rosca escolhida pela tabela (M6 → Ø5,0; M8 → Ø6,8; M10 → Ø8,5).
- Rosca representada como **cosmética** (o sólido fica com o furo da broca; a rosca é um
  atributo da face, mostrado na vista e no desenho), como no SolidWorks.
- Furo de passagem para parafuso: folga fina, normal e larga (ISO 273).
- Rebaixo para parafuso Allen (ISO 4762 / DIN 912) e escareado 90° (ISO 10642), com
  diâmetros e profundidades da tabela.
- Furo cego com ponta de broca a 118°.
- Tabelas em arquivo de dados, não no código, para ampliar sem recompilar.

### Tolerâncias (cota e desenho, fase 7)
- Por cota: nenhuma, simétrica (±), bilateral (+a/−b), limites, básica e **ajuste ISO 286**
  (furo H7, H8, eixo g6, h6, k6...), com cálculo dos desvios pela tabela.
- Tolerância geral **ISO 2768** (f, m, c, v) indicada na legenda do desenho.
- Tolerâncias geométricas **ISO 1101** (planeza, perpendicularidade, paralelismo,
  concentricidade, posição) com referências (A, B, C).
- Acabamento superficial **Ra** (ISO 1302 / NBR 8404).
- Tolerâncias são **informação** (desenho, propriedades); o sólido é sempre o nominal.

## 6B. Desenho 2D (fase 7)

- Normas **ABNT/ISO**: projeção no **1º diedro** (padrão no Brasil, NBR 10067), 3º diedro
  como opção; linhas ISO 128; cotagem ISO 129 / NBR 10126; folhas A4 a A0 (ISO 5457 /
  NBR 10068) com legenda (carimbo: título, material, escala, autor, data, tolerância geral).
- Vistas, como nos desenhos do SolidWorks:

| Vista | Descrição |
|---|---|
| 3 vistas padrão | frontal, superior e lateral alinhadas pelo diedro |
| Vista do modelo | qualquer orientação, incluindo isométrica e vistas com nome |
| Projetada | arrastada a partir de uma vista existente, alinhada |
| Seção (A-A) | linha de corte com setas e hachura; seção total, meia seção, alinhada |
| Detalhe | círculo na vista-mãe, ampliado em outra escala |
| Auxiliar | perpendicular a uma aresta inclinada |
| Interrompida | encurta peças longas |
| Corte parcial | remove parte da vista para mostrar o interior |

- Linhas ocultas, linhas de centro e marcas de centro automáticas.
- Cotas importadas do modelo (as do sketch) ou criadas no desenho, com tolerâncias.
- Associativo: mudar a peça atualiza o desenho.
- Saída DXF (oficina, MakeRouter) e PDF.

## 7. Exportação e integração

| Saída | Para quem | Fase |
|---|---|---|
| STL (binário e ASCII, mm, orientação Y→Z ou face na mesa) | MultiSlicer (impressão 3D), MultiCAM | 4 |
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
| `src/standards` | `multicad_units` (mm, expressões), `multicad_materials`, `multicad_threads` (ISO 261/262, brocas, folgas, rebaixos), `multicad_fits` (ISO 286, ISO 2768); tabelas em `data/*.json` |
| `src/drawing` | `multicad_drawing` (folha, legenda), `multicad_views2d` (projeção, linhas ocultas, seção, detalhe), `multicad_dims2d` |
| `src/export` | `multicad_stl`, `multicad_dxf`, `multicad_pdf`, `multicad_massprops` |
| `src/ui` | `multicad_view3d` (OpenGL), `multicad_softrender`, `multicad_sketchview`, `multicad_tree`, `multicad_props` |
| `src/app` | `multicad_main` (padrão da suíte) |
| `tests` | solver, perfis, malha fechada (*manifold*), volumes analíticos, JSON, reconstrução, STL |
