# MultiCAD

> **Estado (10/10/2026):** fases 0 a 4 prontas (primeira entrega). Já dá para abrir o `bin/multicad.exe`,
> criar esboços com cotas e relações (no plano ou numa face), fazer ressalto e corte
> extrudados ou revolucionados, planos de referência, editar pela árvore e pelo
> PropertyManager, ver em 5 estilos e em seção, salvar em `.mcad`, medir, exportar STL
> (em pé para o MultiSlicer) e DXF. Exemplo: `examples/suporte.mcad`. Próxima: furo,
> padrões e espelho (fase 5).
> Plano e pendências em [docs/TAREFA.md](docs/TAREFA.md).

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
| **MakePCB** | placas de circuito | outra linha de projeto |

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
- **Vistas como no SolidWorks:** Y para cima, Ctrl+1..8, F, barra de espaço, cubo de vistas,
  barra de vista, cinco estilos de exibição e seção dinâmica.

## Requisitos métricos

Só sistema métrico (mm, graus, kg), materiais com densidade, roscas ISO (M2 a M24),
furos de passagem e rebaixos por tabela, ajustes ISO 286 (H7/g6), tolerância geral ISO 2768,
tolerâncias geométricas, acabamento Ra e desenho técnico ABNT/ISO no 1º diedro. Detalhes em
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), seções 6A e 6B.

## Documentação

- [docs/TAREFA.md](docs/TAREFA.md): decisões, fases, critérios de pronto e riscos.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): modelo de dados, núcleo geométrico, solver de
  restrições, reconstrução, vista 3D e exportação.
- [docs/AI_GUIDE.md](docs/AI_GUIDE.md): responsabilidades e limites, para quem for alterar o
  código.
O núcleo CAD não envia comandos diretamente para máquinas.

## Paramétrico de verdade
- **Solver de restrições** (`multicad_constraint_solver`): horizontal, vertical, coincidente, paralelo, perpendicular, igual, distância, raio, ângulo e fixo, resolvidos por Levenberg-Marquardt a partir do desenho aproximado.
- **Graus de liberdade**: após resolver, o posto da Jacobiana classifica o sketch como subrestrito, totalmente restrito, redundante ou conflitante.
- **Sólidos** (`multicad_mesh`): perfis fechados (linhas encadeadas e círculos) com furos, triangulação por *ear clipping*, extrusão em malha fechada e exportação **STL** binário e **3MF**, que o MultiSlicer importa diretamente.

## Ajustar a profundidade com o mouse

Ao criar ou editar **Ressalto extrudado** ou **Corte extrudado**, arraste a alca da seta na vista 3D. A medida em mm, o campo Profundidade e a peca reconstruida acompanham o movimento. Soltar o mouse mantem a previa; confirme com **OK** ou descarte a edicao com **Cancelar**.

O arraste usa passos de 0,1 mm; segure **Shift** para passos de 0,01 mm. **Esc** durante o arraste restaura a medida anterior ao gesto; depois de soltar, Esc cancela a edicao completa. O campo numerico continua aceitando medidas e expressoes. Arrastar substitui a expressao da profundidade por uma medida direta.

As alcas acompanham a direcao invertida, a Direcao 2 e o Plano medio (medida total). Condicoes automaticas como **Passante** ou **Ate a superficie** continuam determinadas pela geometria e nao oferecem uma profundidade manual. Quando o eixo aponta para a camera, uma seta tracejada na tela permite o ajuste sem mudar a vista.

Regressao: `test_multicad` verifica projecao, eixo, volume e malha fechada; `test_extrude_ui` exercita os eventos de mouse, sincronia do campo, previa, OK/Cancelar/Esc e persistencia `.mcad`.


## Diagnostico e selecao de esbocos (11/10/2026)
- Ao sair de um esboco, a arvore e a vista 3D selecionam o esboco finalizado.
  Extrusao/corte respeita uma selecao explicita antes do ultimo esboco lembrado;
  abrir ou criar outra peca limpa esse historico de selecao.
- O executavel 0.3.1.0 cria/acrescenta `%LOCALAPPDATA%\Maurinsoft\MultiCAD\multicad.log`
  antes de criar a janela. Cada sessao tem data/hora e PID; cada registro e fechado
  imediatamente. O historico nao e apagado ao abrir novamente.
- Registra comandos, selecoes, parametros, alteracoes de esboco, arraste de profundidade,
  OK/Cancelar, reconstrucao/cache, estados de erro/aviso, arquivos, entradas invalidas,
  dialogos e excecoes (classe, mensagem, endereco e pilha quando disponivel).
  Falhas de gravacao do proprio log nao interrompem o CAD; ficam disponiveis em Sobre.
- O CommandManager segue a referencia SolidWorks 2014: icones acima dos textos,
  grupos separados e abas retangulares abaixo dos comandos, mantendo a paleta MultiSuite.
  Menus classicos Arquivo/Editar/Exibir/Inserir/Ferramentas/Sobre usam os mesmos comandos.
- A aba **Sobre** acompanha o CommandManager.
  **Sobre o MultiCAD** mostra a versao lida do recurso do executavel, compilacao e
  caminhos; **Abrir log** abre o arquivo no visualizador associado do Windows.
- A janela principal usa `Application.CreateForm`, para fechar o processo com a janela.
- `tests/test_log.lpi`: criacao, preservacao de sessoes, erros/excecoes, caminhos sem permissao.
- `tests/test_selection_ui.lpi`: regressao da selecao antiga, prioridade de selecao explicita,
  esboco ativo, comando bloqueado, aba Sobre, informacoes de versao e diagnostico.


## Visibilidade do perfil e clique nos comandos (0.3.2.0)
- O esboco da extrusao/corte/revolucao em edicao permanece visivel, mesmo consumido,
  ocultado manualmente ou atras/dentro do solido. A visibilidade temporaria termina
  no OK/Cancelar; a preferencia de ocultacao do usuario e preservada.
- Um esboco selecionado e desenhado sobre o solido, permitindo reconhecer o contorno
  antes de iniciar a operacao. A geometria e a direcao da extrusao nao sao alteradas.
- ShowTab oculta os controles antigos e usa Application.ReleaseComponent: nao libera
  o botao ainda em uso por WMLButtonUp. Regressao reproduzida com mensagens nativas
  de pressionar/soltar, incluindo troca de ferramenta e corte direto do modo esboco.
- O log continua escrito e fechado a cada registro; nao forca FlushFileBuffers em
  cada linha no Windows, evitando pausas perceptiveis durante cliques/reconstrucoes.
- Teste: tests/test_sketch_visibility_ui.lpi (perfil sobre solido, visibilidade
  temporaria, esboco selecionado e ciclo real de clique).

## Aviso de operacao com erro (0.3.3.0)
- PMOK atualiza os caches da vista imediatamente depois de RB.Rebuild e antes
  de abrir o dialogo de confirmacao. A reconstrucao substitui as malhas; o
  dialogo processa eventos de pintura e nao pode usar os enderecos anteriores.
- Responder Nao mantem a edicao aberta; Sim aceita a feature marcada com erro.
  Cancelar restaura os parametros. Nenhum desses caminhos usa malhas liberadas.
- Teste: tests/test_cut_failure_ui.lpi, com pintura durante o dialogo,
  respostas Nao/Sim, restauracao e correcao posterior. Excecoes da aplicacao
  fazem o teste falhar, inclusive antes do retorno do dialogo.
- Esta correcao nao altera o algoritmo BSP: o caso de furos cilindricos cruzados
  registrado em 11/10/2026 ainda pode falhar na booleana. A ultima geometria
  valida continua disponivel para corrigir os parametros ou cancelar a edicao.

## Cancelar edicao de planos e eixos (0.3.4.0)
- LoadParams invalida o referencial calculado do plano e a geometria do eixo,
  mesmo quando Cancelar restaura parametros identicos. O cache da reconstrucao
  guarda corpos, nao esses dados derivados: so e reutilizado se FrameValid/Valid
  tambem estiver valido. Caso contrario, recalcula a referencia e seus dependentes.
- Isso evita plano marcado como correto, mas recusado ao iniciar um esboco ou
  criar um plano deslocado. Referencias realmente perdidas continuam gerando erro.
- Testes: TestReferenceCacheRestoration no nucleo e test_plane_cancel_ui.lpi,
  cobrindo Cancelar sem/com alteracoes, plano dependente, novo esboco e reabrir.

## Cota inteligente e referencias entre esbocos (0.3.5.0)
- Durante a colocacao de uma cota de reta ou entre pontos, a posicao do cursor
  escolhe a direcao: acima/abaixo entre as coordenadas X = horizontal; ao lado
  entre as coordenadas Y = vertical; fora dos dois intervalos = comprimento real.
  Retas horizontais/verticais conservam seu eixo valido. A previa muda antes do
  clique final; o texto da previa nao intercepta esse clique. Cotas ja colocadas
  continuam conservando seu tipo quando o texto e arrastado.
- Na ferramenta de cota, extremidades, pontos medios de retas e centros de
  esbocos anteriores visiveis podem servir para posicionar o esboco ativo.
  As referencias sao projetadas no plano ativo e aparecem com a geometria
  anterior tracejada, usando as mesmas cores da interface.
- reference_point guarda sketch:<id>/<entidade>.<ponto> em um ponto de construcao
  local constante no solver. A reconstrucao atualiza sua projecao antes de resolver
  o esboco. O vinculo entra em Dependencies, persiste no .mcad e nao altera a
  geometria fonte. Fonte posterior, suprimida, com erro ou ponto perdido gera
  erro explicito; nao ha reconexao por indice de entidade. Escape remove proxies
  sem restricoes. A selecao de novas referencias ignora esbocos ocultos/futuros.
- Testes: test_smart_dimension (X/Y/alinhada, valor dirigente, projecao em outro
  plano, atualizacao associativa, persistencia, referencia perdida e Escape) e
  test_smart_dimension_ui (cliques reais, previa, selecao de outro esboco,
  valor numerico, ocultacao e reabertura). Incluidos na CI Linux/Windows.

## Painel contextual do esboco (0.3.6.0)
- O painel mostra a ferramenta ativa, selecao e orientacao correspondente.
  Cota, Filete e Chanfro ocultam o seletor de tipo de linha. Selecionar mostra
  esse controle somente com geometria editavel selecionada; ferramentas de
  desenho mantem a escolha normal/apoio, com termos de geometria para curvas.
- UpdateSketchPanel sincroniza os botoes existentes com Session.Tool, inclusive
  ao voltar a Selecionar por Esc, sem reconstruir os comandos durante o evento.
- Textos usam a largura disponivel; a orientacao ocupa a area liberada pelo
  seletor oculto. Mantidos paleta, dimensoes do painel e posicao da arvore.
- test_smart_dimension_ui cobre troca pelos botoes, Esc, selecao de linha,
  Filete/Chanfro/Circulo e retorno a Linha, alem dos testes existentes de cotas.
