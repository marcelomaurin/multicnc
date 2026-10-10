# TAREFA: MultiCAD (modelagem paramétrica de peças, referência SolidWorks 2014)

- **Aberta em:** 09/10/2026
- **Estado:** em implementação. Decisões D1 a D10 aprovadas pelo Marcelo em 09/10/2026, como
  propostas na tabela abaixo.
- **Visão:** [../README.md](../README.md)
- **Arquitetura:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Guia para IA:** [AI_GUIDE.md](AI_GUIDE.md)

## Ponto de partida

O código atual é um esqueleto de cerca de 120 linhas: `multicad_types`, `multicad_feature`
(Id pelo endereço do objeto, que não persiste), `multicad_document`, `multicad_sketch`
(linha, círculo, retângulo e restrições guardadas, sem solver), `multicad_extrude` (guarda só a
profundidade), `multicad_viewport` (2D) e `tests/test_document` (substituído por
`tests/test_multicad` na fase 0). O registro da suíte já tem
`stiMultiCAD`, no grupo **Projetar**. Quase tudo será reescrito; o que serve é a divisão em
documento, *feature* e *sketch*.

## Progresso

| Fase | Estado | O que foi feito |
|---|---|---|
| 0 Base | concluída (09/10) | `multicad_types` (vetores, matrizes, referenciais dos planos padrão como no SolidWorks, regra das faces), `multicad_units` (mm, cm, m, in, ", graus, rad, vírgula ou ponto, expressões, `D1@Esboço1`), `multicad_materials` (12 materiais, extensão por JSON), `multicad_feature` (Id persistente, estado ok/aviso/erro, registro de tipos), `multicad_refgeom` (origem, planos e eixos com os tipos da seção 3A), `multicad_sketch` (entidades com Id, restrições e cotas `D1`), `multicad_extrude` (PropertyManager completo da seção 3B e regras de validação), `multicad_document` (`.mcad` JSON, planos padrão Ids 1-3 e origem 4, nomes automáticos "Esboço1"/"Ressalto-Extrusão1", dependências, barra de retrocesso, gravação segura), `multicad_mesh` (malha rotulada, solda a 0,001 mm, malha fechada, volume, área, centro de massa, bloco e cilindro) e `multicad_kernel` (`ICadKernel` + núcleo Pascal). Central de Testes e CI `multicad-ci.yml`. |
| 1 Sketch e solver | concluída (09/10) | `multicad_sketch` (ponto, linha, arco por centro e por 3 pontos, círculo, retângulo, ranhura, polígono, construção, linha de centro; 11 restrições e 6 tipos de cota com `D1@Esboço1`, dirigente/dirigida, fixa guardando a posição, simétrica pela linha), `multicad_solver` (passo de norma mínima amortecido, GL pelo posto do jacobiano, redundância e conflito por restrição, azul/preto/vermelho por entidade, conflito não deforma o esboço), `multicad_profile` (laços fechados, ilhas, região com Id estável, entidade de cada segmento, erros de contorno aberto, ramificação e cruzamento), documento avalia expressões e resolve os esboços. |
| 2 Operações básicas | concluída (10/10) | `multicad_triangulate`, `multicad_sweep` (extrusão com inclinação, revolução), `multicad_csg` (booleanas BSP com nomes de face e malha fechada), `multicad_revolve`, `multicad_rebuild` (planos, eixos, esboço em face, todas as condições finais, recurso fino, contornos, inverter lado, multicorpo, avisos, cache, retrocesso, supressão). Limites anotados abaixo. |
| 3 Vista 3D e árvore | concluída (10/10), com pendências na 3E | `multicad_camera` (Y para cima, vistas padrão, Normal a, orbitar, deslocar, zoom no cursor, enquadrar, raio do pixel), `multicad_softrender` (z-buffer por software, 5 estilos, arestas de recurso e silhuetas, seleção exata por buffer de Id, seção), `multicad_view3d` (controle da vista, cubo de vistas, tríade, planos, esboços, origem, prévia), `multicad_sketchtools` (ferramentas do esboço sem LCL: linha em cadeia com H/V automáticas, retângulo, círculo, arco 3 pontos, linha de centro, ponto, captura com coincidente, cota inteligente, relações, apagar), `multicad_sketchedit` (modo esboço na vista), `multicad_propman` (PropertyManager de extrusão, corte, revolução e plano) e janela principal no padrão da suíte. `multicad.exe` Win64 em `bin/`. |
| 4 Exportação e suíte | pendente | |
| 5 Furo, padrões, espelho | pendente | |
| 6 Filete, chanfro, casca | pendente | |
| 7 Desenho 2D | pendente | |
| 8 OpenCascade (opcional) | pendente | |

## Decisões (aprovadas em 09/10/2026)

| # | Pergunta | Proposta |
|---|---|---|
| **D1** | Núcleo geométrico | **Híbrido:** núcleo próprio em Pascal (malha com faces rotuladas) atrás da interface `ICadKernel` agora; adaptador OpenCascade opcional na fase 8. Alternativas: só OCCT desde o início (robusto, mas ponte C++, dezenas de MB e build difícil no Win64/Linux) ou só Pascal para sempre (sem STEP exato nem filete geral). |
| **D2** | Booleanas em malha | CSG por árvore BSP com tolerância e solda de vértices, em Pascal puro. Bom para peças prismáticas e torneadas. |
| **D3** | Vista 3D | OpenGL 2.1 pelo **LazOpenGLContext** (`TOpenGLControl`), com renderização por *software* para miniaturas, testes e máquinas sem OpenGL. |
| **D4** | Solver de restrições | Solver próprio Newton/Levenberg-Marquardt, com graus de liberdade pelo posto do jacobiano e as cores do SolidWorks (azul, preto, vermelho). |
| **D5** | Formato de arquivo | `.mcad` em JSON com Ids persistentes (contador gravado), no lugar dos Ids por ponteiro. Referências a faces e arestas por nome estável (`Extrude2/topo`). |
| **D6** | Nomes na interface | Português, no estilo do SolidWorks em PT: "Ressalto/Base extrudado", "Corte extrudado", "Ressalto revolucionado", "Furo", "Filete", "Chanfro", "Casca", "Padrão linear", "Padrão circular", "Espelhar". |
| **D7** | Primeira entrega | Fases 0 a 4: *sketch* com restrições, extrusão (ressalto e corte), revolução, vista 3D com árvore, STL/DXF e propriedades de massa. |
| **D9** | Sistema de unidades e normas | Só métrico (mm, graus, kg), com conversão de polegadas na digitação. Roscas ISO 261/262, ajustes ISO 286, tolerância geral ISO 2768, desenho ABNT/ISO no 1º diedro. Tabelas em arquivos de dados. Detalhes em `ARCHITECTURE.md`, seção 6A. |
| **D10** | Vistas e navegação | Como no SolidWorks: Y para cima, atalhos Ctrl+1..8, F, barra de espaço, cubo de vistas, barra de vista, 5 estilos de exibição, seção dinâmica, vistas com nome, tela dividida. Exportação com orientação Y→Z para o MultiSlicer. Detalhes em `ARCHITECTURE.md`, seção 6. |
| **D8** | Integração | STL → MultiSlicer e MultiCAM; DXF (sketch ou face plana) → MakeRouter e LaserArt; `.mcad` → MultiAssembly; propriedades de massa → MultiPhysics e MultiAssembly. O MultiCAD nunca gera G-code. |

## Fases (depois das decisões)

Cada fase termina com testes no Linux e no Win64 (`-Cr -gt`), commit e push na `fila`, e o
andamento registrado neste arquivo. Mesmo procedimento do RouterPCB e do MakeRouter.

### Fase 0: base (≈ 2 h) — concluída em 09/10/2026
- [x] Árvore `multicad/src/{core,sketch,kernel,features,ui,app}` e `tests` (`export`, `standards`
      e `drawing` entram nas fases em que forem usadas).
- [x] Ids persistentes, parâmetros por operação, estado de erro, JSON `.mcad` ida e volta.
- [x] `multicad_types`: vetores, matrizes 4×4, planos, tolerância interna de 0,001 mm.
- [x] `multicad_units` (mm, graus, conversão de `in` na entrada, expressões nas cotas) e
      `multicad_materials` (biblioteca com densidade e módulo de elasticidade; arquivo JSON
      opcional, por exemplo `data/materials.json`, acrescenta ou substitui pelo nome).
- [x] Interface `ICadKernel` e malha rotulada (`multicad_mesh`) com verificação de malha fechada.
- [x] Testes: JSON, Ids estáveis entre execuções, malha de um cubo fechada e com volume certo.

Testes da fase 0: `tests/test_multicad.lpr`, **142 checks** passando no Linux e no Win64 (Wine),
com checagem de faixa, de estouro e variáveis locais embaralhadas (`-Cr -Co -gt`):
referenciais dos 3 planos padrão (a tabela da seção 3A), regra da face, matrizes; expressões
(`80/2`, `1in`, `2"`, `12,5`, `D1@Esboço1 + 5`, erros com mensagem); materiais (massa de
1000 cm³ de alumínio = 2,7 kg, arquivo inválido recusado sem alterar a biblioteca); documento
(Ids fixos dos planos, nomes automáticos, regras de ressalto e corte, dependências diretas e
indiretas, JSON idêntico na ida e volta, contador de Ids que não volta, arquivos inválidos
recusados sem alterar o documento aberto, referência perdida vira erro na árvore, gravação sem
deixar `.tmp`/`.bak`, barra de retrocesso); malha (bloco 80 × 50 × 10 com volume, área, centro
de massa e normais para fora, solda, malha aberta detectada, cilindro dentro de 0,5%,
transformação rígida, sólido invertido recusado pelo núcleo).

Observações:
- A tela atual (`multicad_main`) continua a provisória do esqueleto, só adaptada à nova API;
  a interface real é a fase 3.
- O programa e os testes definem a página de código como UTF-8 (`multicad_types`), como o LCL
  faz, para os nomes com acento ("Esboço1", "Aço 1020") baterem ao ler o JSON.

### Fase 1: sketch e solver (≈ 5 h) — concluída em 09/10/2026
- [x] Entidades: ponto, linha, arco, círculo, retângulo, ranhura, polígono, construção e
      linha de centro.
- [x] Restrições: coincidente, horizontal, vertical, paralela, perpendicular, tangente, igual,
      concêntrica, ponto médio, fixa, simétrica.
- [x] Cotas: distância, horizontal, vertical, raio, diâmetro, ângulo; nome `D1@Sketch1`.
- [x] Solver Newton/LM e graus de liberdade (sub, total, superdefinido).
- [x] Perfis: laços fechados com ilhas (a Clipper2 entra na fase 2, nos *offsets* da inclinação
      e do recurso fino; o perfil usa geometria própria, sem dependência).
- [x] Testes: retângulo 80×50 totalmente definido, mudança de cota move só o que deve, conflito
      detectado, tangência linha-arco, perfil com furo vira região com ilha.

Como ficou o solver (`multicad_solver`):
- Variáveis: pontos e raios; o arco guarda centro, início e fim com a equação interna
  |início − centro| = |fim − centro|.
- Passo de norma mínima amortecido `dx = −Jᵀ(JJᵀ + λI)⁻¹F`, partindo da posição atual: muda o
  mínimo possível, por isso mudar uma cota mexe só o que depende dela (testado: base de 80 para
  100 mm não move o lado esquerdo).
- Graus de liberdade pelo posto do jacobiano (Gram-Schmidt): restrição que não aumenta o posto
  é **redundante** (superdefinido, como o SolidWorks pede para tornar a cota dirigida);
  equação que não zera é **conflito**, e aí o esboço volta como estava.
- Cor por entidade: azul (livre), preto (definida), vermelho (em restrição redundante ou em
  conflito).
- Tangência com extremidade comum usa a forma de primeira ordem (direção perpendicular ao
  raio no ponto comum). A forma pela distância tem derivada nula quando o ponto já está na
  curva e derrubava o posto (a ranhura aparecia como superdefinida).
- Cotas com sinal "pegajoso" (distância à reta, horizontal, vertical, ângulo): o lado em que a
  geometria está ao resolver é mantido, para não espelhar o desenho.
- Desempenho: polígono de 40 lados em menos de 0,1 s.

Perfis (`multicad_profile`): laços pelos nós das extremidades (tolerância 0,0001 mm), arcos
discretizados pelo erro de corda, externos anti-horários e ilhas horárias, Id da região
`region:<menor Id de entidade do laço externo>`, entidade de origem por segmento (nome da face
lateral na fase 2). Recusa contorno aberto, ramificação (3 ou mais entidades num ponto) e
contornos que se cruzam ou se tocam.

Testes: **223 checks** (142 da fase 0 + 81 novos), Linux e Win64 (Wine), `-Cr -Co -gt`, sem
vazamento de memória (heaptrc).

Fica para depois:
- Ramificação com escolha de contorno (regiões pelo grafo planar), para "Contornos
  selecionados" em esboços com linhas que se cruzam.
- *Spline* e elipse (os tipos existem no arquivo, o solver ainda as ignora).
- Ferramentas de desenho na tela (arco tangente, aparar, estender, Converter entidades,
  Offset de entidades) entram com a interface, na fase 3.

### Fase 2: operações básicas (≈ 6 h) — concluída em 10/10/2026
- [x] Referencial local dos planos padrão e de faces planas (tabela em `ARCHITECTURE.md` 3A).
- [x] Plano de referência: deslocado (com número de planos), paralelo por ponto, em ângulo,
      plano médio, por três pontos, por linha e ponto, normal à curva, tangente à face
      cilíndrica. Eixo de referência e eixos temporários.
- [x] Ressalto/Base e Corte extrudado com o PropertyManager completo (`ARCHITECTURE.md` 3B):
      De (plano do esboço, face, vértice, deslocamento); condições Cego, Passante, Passante -
      ambos, Até o próximo, Até o vértice, Até a superfície, Deslocamento da superfície, Até o
      corpo, Plano médio; inverter direção; direção por aresta; inclinação; Direção 2;
      Mesclar resultado; Inverter lado a cortar; Recurso fino; Contornos selecionados;
      Escopo do recurso.
- [x] Mensagens de erro e aviso do SolidWorks (perfil aberto, corte sem interseção,
      multicorpo, inclinação grande, "até" sem face).
- [x] Ressalto e corte revolucionado no mesmo padrão.
- [x] Booleanas BSP (D2) e nomes estáveis das faces.
- [x] Reconstrução com cache a partir da primeira operação alterada; erros por operação.
- [x] Testes:
  - volume de cada condição final (cego, plano médio, até o próximo, até a superfície
    inclinada, deslocamento da superfície, passante - ambos);
  - inclinação de 5° em bloco: volume do tronco de pirâmide;
  - recurso fino de um retângulo aberto e de um fechado com tampas;
  - contornos selecionados (só uma das regiões extrudada);
  - inverter lado a cortar; corte sem interseção gera aviso; perfil aberto gera erro;
  - plano deslocado, em ângulo e plano médio na posição exata; referencial local da tabela;
  - nome de face `lat:E` mantido ao acrescentar entidade no sketch;
  - malha sempre fechada; cota alterada reconstrói.

Como ficou (fase 2):
- **Varredura** (`multicad_sweep`): extrusão com direção qualquer, deslocamento do início e
  inclinação para dentro/fora (laterais planas, cantos em esquadria); revolução parcial ou de
  360° (cilindro, cone, plano, esfera e toro rotulados). Tampas por triangulação com furos
  (`multicad_triangulate`: pontes + recorte de orelhas).
- **Booleanas** (`multicad_csg`): BSP iterativa (algoritmo do csg.js). Depois de cada
  booleana: solda a 0,2 µm, fusão de cada face plana pelo contorno (arestas quebradas em todos
  os vértices em uso, cancelamento a→b/b→a, retriangulação), reparo de junções em T só nas
  faces curvas, em uma passada, com triangulação validada contra inversão. Placa com 4 furos
  sucessivos: ~0,5 s por furo, volume exato.
- **Reconstrução** (`multicad_rebuild`): planos (deslocado, paralelo por ponto, em ângulo,
  plano médio paralelo e bissetor, 3 pontos, linha e ponto, normal à curva, tangente a
  cilindro, coincidente), eixos (face cilíndrica, linha, 2 planos, 2 pontos, ponto e face),
  esboço em face plana (`face:<nome>`), todas as condições finais (inclusive "Até a
  superfície" inclinada por recorte em semiespaço e "Até o próximo" por raios), Direção 2,
  inclinação, recurso fino aberto e fechado com "Tampar extremidades", contornos
  selecionados, inverter lado a cortar, mesclar/multicorpo, escopo, revolução com linha de
  centro ou eixo, avisos e erros do SolidWorks, cache por assinatura, retrocesso e supressão.
- Corte extrudado entra na peça por padrão (contra a normal do esboço), como no SolidWorks.
- Testes: **352 checks**, Linux e Win64, sem vazamento.

Limites desta versão (próximas fases):
- **Furos que se cruzam** (cilindro cortando cilindro) ainda são recusados com mensagem: as
  lascas da BSP nas faces curvas passam da tolerância. Solução prevista: fundir também as
  faces curvas no espaço paramétrico (cilindro desenrolado) ou usar o OpenCascade (fase 8).
- "Até o próximo"/"Até o corpo" em face curva terminam num plano (com aviso).
- Vértices e arestas do sólido ainda não são referências (pontos e linhas vêm dos esboços).
- Início em superfície não paralela ao esboço; recurso fino na revolução; "número de
  planos" > 1 cria só o primeiro plano.

### Fase 3: vista 3D e árvore (≈ 6 h)
- [x] Vista com Y para cima; orbitar (botão do meio ou Alt + esquerdo), deslocar (Ctrl + meio),
      zoom (Shift + meio, roda no cursor), setas giram 15°.
- [x] Orientação: Ctrl+1..7 (vistas padrão e isométrica), Ctrl+8 (Normal a; de novo vira o
      lado), F (enquadrar).
- [x] Cubo de vistas (clicar numa face muda a vista) e tríade de eixos.
- [x] Estilos: sombreado com arestas, sombreado, linhas ocultas removidas, linhas ocultas
      visíveis, arame; ortográfica/perspectiva.
- [x] Vista de seção pelo plano selecionado (ou Frontal pelo centro), faces internas na cor
      de seção.
- [x] Seleção de face, plano, esboço e origem com pré-seleção laranja e seleção azul
      (Ctrl soma).
- [x] Modo *sketch*: Normal a ao entrar, linha (cadeia, H/V automáticas), retângulo,
      círculo, arco 3 pontos, linha de centro, ponto, captura (coincidente na origem, em pontos
      e sobre curvas), cota inteligente (comprimento, diâmetro, raio, ângulo, distância; a que
      superdefine vira dirigida), clicar na cota edita o valor (aceita expressão), relações
      pela seleção, apagar, cores azul/preto/vermelho e estado na barra.
- [x] PropertyManager no painel esquerdo com OK/Cancelar, prévia ao vivo (a peça é
      reconstruída a cada mudança e as faces da operação ficam amarelas), campos de
      referência rosa que recebem o clique na vista, expressões nos campos numéricos;
      esboço absorvido sob a operação; Editar operação / Editar esboço.
- [x] *Sketch* sobre face plana (escolher a face na vista ao criar o esboço).
- [x] Árvore de operações: editar, suprimir, ocultar, excluir, renomear (atualiza nomes de
      faces e cotas), barra de retrocesso, cores de erro/aviso/suprimida, material.
- [x] Abas de comandos (Operações, Esboço, Avaliar, Exibir) no padrão visual da suíte;
      Novo/Abrir/Salvar/Salvar como; propriedades de massa; Ctrl+S/N/O/B.
- [x] Renderização por *software* (a mesma no Windows e no Linux, sem driver de vídeo).
- [x] Teste de interface `tests/test_multicad_ui` (Xvfb no Linux, Wine/Windows) com
      capturas de tela; `examples/suporte.mcad`.

Como ficou (fase 3):
- A vista usa só o renderizador por software (z-buffer em Pascal, `TLazIntfImage` para
  copiar). Funciona igual no Windows, no Linux e em máquina sem OpenGL; peças de alguns
  milhares de triângulos giram sem atraso. O caminho OpenGL (D3) ficou para a 3E.
- O Id de cada pixel diz qual face/plano/esboço está ali, então a seleção é exata e sem
  custo; `CadRayMesh` faz o mesmo por raio (usado nos testes).
- Silhuetas de faces curvas usam folga de profundidade proporcional ao pixel, para não
  sumirem quando a face vizinha está quase de perfil.
- Profundidade digitada como expressão (`D1@Esboço1*2`) é recalculada a cada reconstrução.
- Cancelar no PropertyManager restaura os parâmetros (ou apaga a operação nova).

### Fase 3E: pendências da vista (próximas)
- [ ] Caminho OpenGL (`TOpenGLControl`) com o software como reserva.
- [ ] Barra de espaço (vistas com nome no `.mcad`), vista anterior, transição animada,
      girar em torno de aresta/vértice, rolar, tela dividida 1/2/4.
- [ ] Seleção de arestas e vértices (hoje: faces, planos, esboços e origem).
- [ ] Seção com deslocamento/ângulo arrastáveis e face hachurada.
- [ ] Esboço: grade, Converter entidades, Offset de entidades, ranhura e polígono pela
      interface, aparar/estender, peça semitransparente, canto de confirmação na vista,
      desenhar relações (glifos) na tela.
- [ ] Seta de arraste e cota na tela na prévia; prévia separada em amarelo/vermelho.
- [ ] Desfazer/refazer.

### Fase 4: exportação e suíte (≈ 3 h)
- [ ] STL binário e ASCII com orientação (Y→Z ou face selecionada na mesa); DXF do *sketch*
      ou de face plana.
- [ ] Propriedades de massa (volume, área, centro de massa, massa pelo material) e medir.
- [ ] "Abrir no MultiSlicer" e "Abrir no MakeRouter" (mesmo padrão do `OpenInTool` do MakePCB).
- [ ] Suíte: `Application.CreateForm`, ícone, bandeja, MultiSuite, Central de Testes, CI,
      instalador e documentação.
- [ ] **Primeira entrega** (ver critério abaixo).

### Fase 5: furo, padrões e espelho (≈ 4 h)
- [ ] `multicad_threads` com tabelas em `data/*.json`: roscas ISO 261/262 M2 a M24 (passo
      normal e fino), broca para rosca, folgas ISO 273 (fina, normal, larga), rebaixo ISO 4762,
      escareado 90° ISO 10642.
- [ ] Assistente de furo: simples, passagem para parafuso, roscado, rebaixado, escareado, cego
      com ponta 118° (pontos de um *sketch* na face).
- [ ] Rosca cosmética: atributo da face, mostrado na vista e levado ao desenho.
- [ ] Teste: M8 gera furo Ø6,8; passagem M8 normal Ø9,0; rebaixo M8 Ø13 × 8,6 (pela tabela).
- [ ] Padrão linear e circular de operações; espelhar por plano.

### Fase 6: filete, chanfro e casca (≈ 6 h)
- [ ] Filete e chanfro em arestas retas e circulares entre faces planas e cilíndricas.
- [ ] Casca com espessura constante e faces removidas (faces planas).
- [ ] Teste: volume do filete de um cubo dentro de 0,5% do valor analítico.

### Fase 7: desenho 2D e tolerâncias (≈ 10 h)
- [ ] Folhas A4 a A0 (ISO 5457 / NBR 10068) com legenda: título, material, escala, autor,
      data, tolerância geral ISO 2768.
- [ ] 1º diedro (NBR 10067, padrão) e 3º diedro opcional.
- [ ] Vistas: 3 vistas padrão, vista do modelo, projetada, seção A-A (total, meia, alinhada),
      detalhe, auxiliar, interrompida e corte parcial.
- [ ] Linhas ISO 128 (contorno, oculta, centro, hachura), linhas e marcas de centro automáticas.
- [ ] Cotas ISO 129 / NBR 10126, importadas do modelo ou criadas no desenho.
- [ ] Tolerâncias por cota (±, bilateral, limites, ajuste ISO 286 H7/g6... com desvios pela
      tabela), tolerâncias geométricas ISO 1101 com referências e acabamento Ra (ISO 1302).
- [ ] Desenho associativo: mudar a peça atualiza as vistas.
- [ ] Saída DXF e PDF.
- [ ] Teste: Ø20 H7 dá +0,021/0; Ø20 g6 dá −0,007/−0,020.

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
5. Navegar como no SolidWorks: Ctrl+1..8, F, cubo de vistas, estilos e seção dinâmica.
6. O STL exportado chega em pé no MultiSlicer (orientação Y→Z).
7. Testes passando no Linux (GTK2) e no Win64 (Wine).

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
- **Tabelas de normas:** valores errados em roscas e ajustes geram peças que não montam.
  Mitigação: tabelas em arquivo de dados, conferidas contra as normas e com testes de valores
  conhecidos.
- **Linhas ocultas no desenho 2D:** custo alto em peças grandes. Mitigação: cálculo por
  arestas visíveis com z-buffer e cache por vista.
- **Escopo:** o SolidWorks tem décadas de trabalho. A entrega cobre peças prismáticas e
  torneadas; superfícies livres, chapas metálicas e soldas ficam fora.
