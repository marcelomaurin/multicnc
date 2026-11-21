# TAREFA: MultiProject — gerenciador de projetos mecânicos e eletrônicos

- **Aberta em:** 20/10/2026.
- **Estado:** decisões D1 a D12 **aprovadas como propostas** pelo Marcelo (20/10/2026).
  Fases 1 a 6 implementadas e conferidas no Win64 (22/10), com setup 016 gerado.
  Console do MultiProject aprovado no Linux; interfaces Linux em validação no GitHub Actions.
- **Solicitação:** um gerenciador de projeto em que se define um **objetivo** (exemplo:
  construir um motor). Uma pessoa ou a IA divide o objetivo em tarefas de peça e de eletrônica.
  As tarefas se relacionam por uma **lista de grafos**, em cadeia ou em paralelo, e têm Nome,
  ID, Descrição curta, Descrição longa, Especificação técnica e Especificação funcional.
  - Peça → MultiCAD e eletrônica → MakePCB, com o arquivo vinculado quando fica pronto.
  - Prontas as tarefas, são geradas as de ligação entre as peças (MultiAssembly) e as de teste
    e validação (MultiPhysics).
  - Tarefas de impressão 3D, router, corte laser, arte laser, torno e placa, cada uma ligada a
    uma ferramenta.
  - Layout igual ao das outras aplicações e Microsoft Project como referência, com cada
    requisito funcional do Project integrado.
- **Base conferida:** branch `fila`, commit `d9945b9` (19/10/2026).
- **Visão:** [../README.md](../README.md)
- **Requisitos:** [REQUISITOS.md](REQUISITOS.md) (IDs `PJ-*`, prioridades P0/P1/P2)
- **Arquitetura:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Layout:** [LAYOUT.md](LAYOUT.md)
- **Padrão seguido:** [MakeRouter](../../makerouter/docs/TAREFA.md), [MultiAssembly](../../multiassembly/docs/TAREFA.md)

## Progresso

| Fase | Estado em 22/10/2026 | Entrega |
|---|---|---|
| 0 Especificação | concluída | README, REQUISITOS, ARCHITECTURE, LAYOUT, TAREFA, AI_GUIDE |
| 1 Documento e tarefas | concluída no Linux (20/10) e conferida no Win64 (22/10) | `multiproject_types`, `multiproject_document`, `multiproject_json`; `test_multiproject_core.lpr` com 102 checks; usa `aiprojectduration`, `aiundohistory` e `aijsonutils` do CHATGPT |
| 2 Grafo | concluída no Linux (20/10) e conferida no Win64 (22/10) | `aitaskgraph` no CHATGPT (`ec5cccf`, 61 checks) + `multiproject_graph` (adaptador com expansão dos resumos) e vínculos no documento e no `.mproj`; `test_multiproject_graph.lpr` com 88 checks |
| 3 Calendário e cronograma | concluída no Linux (20/10) e conferida no Win64 (22/10) | `aiworkcalendar` (`c9ad854`, 57 checks) e `aicpmscheduler` (`3557a7b`, 47 checks) no CHATGPT + `multiproject_schedule`, calendários e restrições no documento e no `.mproj`; `test_multiproject_schedule.lpr` com 82 checks |
| 4 Tela e registro na suíte | concluída (20/10); `bin/multiproject.exe` win64 e setup 015 (21/10) | vistas genéricas no CHATGPT (`TAIGanttView`, `TAINetworkView`, `TAIBoardView`, até `1448eb8`, 42 checks) + `multiproject_main`/`multiproject_views`, registro na suíte (grupo PLANEJAR), `test_multiproject_ui` com 51 checks sob Xvfb e `test_multiproject_states` com 20 |
| 5 Vínculo com as ferramentas | implementada; Win64 validado (22/10), regressão Linux pendente | `--new`/`--task`, `.task.json`, detecção, verificadores, Abrir na ferramenta |
| 6 Regras de geração e modelos | implementada; testes Win64 aprovados (22/10); setup 016 gerado; console Linux aprovado, interface Linux em validação | PJ-A01..A08, exemplo Motor DC, modelos |
| 7 Recursos e custos | 7.1 a 7.4 e 7.8 concluídas (21/10); 7.5 a 7.7 implementadas (26/10) e conferidas no Linux, Win64 pendente; falta o recurso genérico (PJ-R06) | `airesourceload` (`TAIResourceLoad`, `TAIResourceLeveler`, 83 checks) e `TAIResourceView` (68 checks nas vistas) no CHATGPT, até `78f3f2b` + `multiproject_resources`, recursos e atribuições no documento e no `.mproj`, etapa 4 Recursos, vista Equipe, coluna Recursos e nivelamento na etapa 5; `test_multiproject_resources.lpr` com 116 checks; 7.5 a 7.7: `aitasktype` e `aicostmodel` no CHATGPT (`b31c7df`) + `multiproject_estimates` e `multiproject_bom`, colunas Trabalho e Custo, tipo/trabalho/custos/estimativa na página da tarefa e taxas na etapa 4; `test_multiproject_costs.lpr` com 154 checks e `test_multiproject_ui` com 105 |
| 8 Linha de base, acompanhamento e relatórios | pendente | linhas de base, progresso, valor agregado, HTML/PDF, Calendário, Linha do tempo |
| 9 IA | pendente | contrato do plano, decomposição do objetivo pela suíte CHATGPT |
| 10 Intercâmbio e multiprojeto | pendente | XML do Project (MSPDI), CSV, CLI, subprojetos, pool |

**Primeira entrega utilizável = fases 1 a 6 (todos os P0).** As fases 7 a 10 cobrem os P1 e
P2. Nenhuma fase conta como concluída sem o teste rodando no Linux e no Win64 (regra 9 do
guia da suíte).

## Reuso da suíte CHATGPT

Regra do Marcelo (20/10/2026): usar o que já existe na suíte CHATGPT. O que der para tornar
genérico vira **componente do CHATGPT primeiro** e depois é usado no MultiProject.

Conferido em `marcelomaurin/CHATGPT` (`main`, 20/10/2026):
- **AI Project** e **AI Project Core** modelam projetos de software (tarefas com commits e
  arquivos, ações de agente). O `TAIProjectGantt` só desenha barras. Não há cronograma, vínculos
  TI/II/TT/IT nem estrutura de tópicos.
- **AI Graph** (`TAIDependencyGraph`) inventaria dependências de repositório. Não há ordem
  topológica, ciclo com caminho nem componentes conexos.
- **AI Schedule** (`TIASchedule`) é uma lista de tarefas com "depende de" e "pronta".

Por isso os componentes genéricos entram no pacote `openai_project_core` (pasta
`pacote/AI Project Core`, somente FCL), e o MultiProject usa esses componentes:

| Fase | Componente no CHATGPT | Estado |
|---|---|---|
| 1 | `aiprojectduration` (`TAIDuration`), `aiundohistory` (`TAIUndoHistory`), `aijsonutils` (leitura tipada, mescla que preserva campos, ISO 8601, gravação atômica) | publicados em `35203a3`; `tests/test_aiprojectcore_utils.lpr` com 59 checks |
| 2 | `aitaskgraph`: grafo de tarefas com os 4 tipos de vínculo e latência, ciclo com caminho, ordem topológica, cadeias, em cadeia × em paralelo, coluna Predecessoras | publicado em `ec5cccf`; `tests/test_aitaskgraph.lpr` com 61 checks |
| 3 | `aiworkcalendar` (expediente, exceções, feriados BR, minuto útil) e `aicpmscheduler` (CPM, restrições, margens, crítico) | publicados em `c9ad854` e `3557a7b`; 57 + 47 checks |
| 7 | `aitasktype` (tipo de tarefa e empenho, Trabalho = Duração × Unidades) e `aicostmodel` (taxa, uso, material, custo fixo com acumulação, texto de dinheiro sem depender da região) | publicados em `b31c7df` (26/10); `tests/test_aitasktype.lpr` com 21 checks e `tests/test_aicostmodel.lpr` com 22 |
| 9 | `aiplancontract`: contrato e parser determinístico de plano de tarefas gerado por IA | a fazer |

Ficam no MultiProject só o modelo da tarefa, os tipos ligados às ferramentas da suíte, as regras
de geração e a tela.

A suíte compila com a pasta externa `../CHATGPT/pacote/AI Project Core` quando ela tem as units.
Senão, usa a cópia `third_party/chatgpt/AIProjectCore`, porque o CI fixa uma revisão antiga do
CHATGPT. É o mesmo padrão do AIJoystick: altere primeiro no CHATGPT e depois sincronize a cópia.

## Decisões para o Marcelo

Aprovadas como propostas em 20/10/2026.

| # | Pergunta | Proposta |
|---|---|---|
| **D1** | Nome e lugar na suíte | `multiproject/` na raiz, `stiMultiProject` e `sikProject` no fim dos enums, novo grupo **PLANEJAR** na bandeja e no MultiSuite, antes de PROJETAR. |
| **D2** | Relação com o projeto do MultiSuite (`TWorkspace`) | O `.mproj` é o plano. O MultiProject também registra os artefatos no `TWorkspace` e atualiza as etapas dele, para a bandeja e o MultiSuite mostrarem os mesmos arquivos. Nada é duplicado no `.mproj`. |
| **D3** | Formato do arquivo | JSON `.mproj` (`fpjson`, como `.mslice`, `.mrouter` e `.massembly`), com `schema_version`, datas ISO, ponto decimal e caminhos relativos. Datas calculadas não são gravadas. |
| **D4** | Como abrir uma ferramenta para um arquivo que ainda não existe | Acrescentar `--new <arquivo>` e `--task <arquivo.task.json>` ao `ReadSuiteContext` (as duas cópias) e `TSuiteLauncher.LaunchNew`. É compatível para trás. MultiCAD e MakePCB tratam os parâmetros na fase 5; as outras ferramentas, depois. Até lá, a ferramenta abre com `--project` e o MultiProject mostra o caminho em que o arquivo deve ser salvo. |
| **D5** | Quando a tarefa fica "pronta" | Arquivo existe + verificador do tipo aprovado + **o usuário clica Marcar pronta**. "Concluída" exige ainda os critérios funcionais aprovados. Se o arquivo mudar depois (hash), a tarefa volta para revisão e as sucessoras ficam desatualizadas. |
| **D6** | Ordem padrão: validar antes de fabricar? | Sim. O marco "Liberado para fabricação" depois do MultiPhysics bloqueia as fabricações (`fabrication_gate = true`). Pode ser desligado por projeto (protótipo rápido: imprimir já). |
| **D7** | Usinagem de torno: não há ferramenta nem tipo de máquina torno na suíte | Na primeira entrega é uma tarefa **manual**: desenho do MultiCAD + **folha de processo** (operações, ferramentas, rotação, avanço, cotas de controle) gerada pelo MultiProject em Markdown/PDF, com o recurso "Torno" do tipo `lathe`. Uma ferramenta de torno (MultiLathe ou CAM de torneamento no MultiCAM) e o tipo torno no MultiCNC ficam como trabalho futuro separado. |
| **D8** | Corte laser e arte laser | As duas usam o **LaserArt** (corte = camada de linha com kerf e pontes; arte = gravação). O MultiCAD já exporta **DXF R12** do esboço ou da face (`CadExportSketchDXF`/`CadExportFaceDXF`), mas o LaserArt só importa SVG e imagem. Proposta: **importação DXF no LaserArt**, como dependência da tarefa de corte laser (ver ARCHITECTURE, "Dependências"). Até lá, a tarefa vincula o `.lart` feito à mão. |
| **D9** | Router: MakeRouter ou MultiCAM? | Segue a D1 do MakeRouter: madeira, chapa, letreiro e móvel vão para o **MakeRouter**; peça mecânica do MultiCAD (alumínio, faces, furos) vai para o **MultiCAM**. O usuário pode trocar por tarefa. |
| **D10** | Desenho das vistas (Gantt, Rede, Quadro) | `TCustomControl` próprio desenhado no Canvas, como as vistas do MakeRouter e do MultiAssembly. Sem componente de terceiros, funciona no Wine e no Linux. Rolagem virtual: só as linhas visíveis são desenhadas. |
| **D11** | Unidade de tempo | Minuto útil em `Int64`. Exibição em min/h/d/sem pelo calendário. Fabricação usa duração decorrida e o calendário 24 Horas por padrão. |
| **D12** | IA | Pela suíte **CHATGPT** do autor (vários provedores, inclusive local), na fase 9. Saída somente JSON no contrato de ARCHITECTURE, com parser determinístico, entrando como tarefas Sugeridas. A IA nunca aplica nada sozinha. |

## Fases (depois das decisões)

Cada fase termina com:
- testes rodando no Linux e no Win64;
- commit e push na `fila`;
- o progresso registrado neste arquivo;
- entrada em `NEWS.md` quando houver setup.

As tarefas abaixo são atômicas, para que uma pessoa ou um agente execute uma por vez e
confira o aceite.

### Fase 1: documento e tarefas (≈ 3 h)

- [x] 1.1 `multiproject/src/{core,io}` e `tests/`. O módulo entrou em `MODULES` de
      `tools/verify_suite.py`, então `tests/run_all.sh multiproject` descobre os testes. As
      pastas `integration`, `ai`, `view` e `app` nascem nas fases delas.
- [x] 1.2 `multiproject_types`:
      - enums `TPJTaskKind`, `TPJProcess`, `TPJTaskState`, `TPJLinkType`, `TPJConstraint` e
        `TPJResourceType`, com nomes em texto para o arquivo;
      - registros de especificação técnica e de critério de aceite.
- [x] 1.3 `multiproject_document`:
      - projeto e objetivo;
      - tarefas com os seis campos (PJ-T10..T12);
      - árvore `parent`/ordem, recuar/avançar/mover, código EAP (PJ-T13, T14);
      - marco e modo manual/auto (PJ-T15, T16);
      - geração de IDs que não reaproveita número.
- [x] 1.4 Comandos com desfazer e refazer (PJ-U01): inserir, excluir, editar campo, mover,
      recuar e em lote.
- [x] 1.5 Duração: interpretar e formatar `30min`, `4h`, `2d`, `1sem`, `14eh` e `?`
      (PJ-T17, T18).
- [x] 1.6 `multiproject_json`: salvar e ler o `.mproj` com salvamento atômico, preservação
      de campos desconhecidos e recusa de versão futura (PJ-X01, Q02, Q04).
- [x] 1.7 Teste `test_multiproject_core.lpr` (102 checks no Linux, inclusive com `-Cr -gt -Ci -Co`
      e com a cópia de reserva das units do CHATGPT; Win64 conferido em 22/10):
      - EAP depois de recuar e mover;
      - ID não reaproveitado depois de excluir;
      - desfazer de cada comando;
      - ida e volta do JSON igual byte a byte na segunda gravação;
      - vírgula decimal regional sem efeito;
      - validação recusa tarefa sem nome ou sem descrição curta.

Resultado da fase 1:
- **ID nunca volta, nem com o desfazer.** O desfazer restaura o documento, mas o contador fica
  no maior valor já usado, porque o ID pode ter dado nome a um arquivo (`T-0008_peca.mcad`).
- **Avançar uma tarefa** faz as irmãs seguintes virarem filhas dela, como no Project.
- O arquivo grava `options.minutes_per_day` e `minutes_per_week` (inteiros) em vez de horas,
  para não gravar números com casas decimais.

### Fase 2: grafo (≈ 3 h)

- [x] 2.0 Criar `aitaskgraph` no CHATGPT (`pacote/AI Project Core`), com teste próprio, publicar
      e sincronizar a cópia em `third_party/chatgpt/AIProjectCore`. O `multiproject_graph`
      passa a ser só o adaptador do documento para o grafo.

- [x] 2.1 Vínculos TI/II/TT/IT, latência em duração ou %, antecipação, latência decorrida e
      "entrega artefato" (PJ-G01, G02, G06).
- [x] 2.2 `multiproject_graph`:
      - lista de adjacência de sucessoras e predecessoras;
      - ordem topológica (Kahn);
      - `WouldCycle` com caminho (PJ-G04, G05).
- [x] 2.3 Cadeias (componentes conexos por união-busca) e a consulta "em cadeia" ×
      "em paralelo" entre duas tarefas.
- [x] 2.4 Interpretar e formatar a coluna Predecessoras (`T-0003TI+2h;T-0004II-10%`)
      (PJ-G03).
- [x] 2.5 Vínculo em resumo expandido para as folhas (PJ-G07, P1: só o núcleo nesta fase).
- [x] 2.6 Teste `test_multiproject_graph.lpr`:
      - ciclo A→B→C→A recusado com o caminho e o documento intacto;
      - ordem topológica válida em 1.000 tarefas aleatórias;
      - 3 cadeias corretas;
      - A e B paralelas, A e C encadeadas;
      - ida e volta da sintaxe de predecessoras.

Resultado da fase 2:
- Os vínculos ficam no documento (`TPJLink`): tipo, latência, "entrega artefato" e campos
  desconhecidos preservados. No arquivo, o tipo vai com o código do Project (`FS`/`SS`/`FF`/`SF`)
  e a tela mostra TI/II/TT/IT.
- Vínculo de resumo vale para as folhas. Ligar um resumo à própria subtarefa é recusado. Recuar
  ou avançar uma tarefa que deixaria um vínculo inválido também é recusado, com o motivo em
  `LastError` e sem entrar no desfazer.
- Quando o ciclo passa por um vínculo de resumo, a mensagem diz qual vínculo é.
- Ctrl+F2 (`LinkChain`) vincula a seleção em cadeia TI como um único passo de desfazer. Se um
  elo fecharia ciclo, nada é gravado.
- Na leitura, arquivo com ciclo, vínculo repetido, tarefa inexistente ou resumo ligado à
  subtarefa é recusado sem alterar o documento.
- 2000 tarefas e 4000 vínculos montam o grafo e a ordem topológica bem abaixo de 1 s.

### Fase 3: calendário e cronograma (≈ 4 h)

- [x] 3.0 Criar `aiworkcalendar` e `aicpmscheduler` no CHATGPT, com testes, e sincronizar a
      cópia. O MultiProject só adapta as tarefas e os vínculos.

- [x] 3.1 `multiproject_calendar`:
      - calendários Padrão e 24 Horas e as exceções;
      - feriados brasileiros fixos e móveis (Páscoa pelo algoritmo de Meeus);
      - minuto útil ↔ data e soma de duração (PJ-C01..C03, C05).
- [x] 3.2 `multiproject_schedule`:
      - passagem de ida e de volta com os quatro tipos de vínculo e latência;
      - restrições ASAP/ALAP/SNET/SNLT/FNET/FNLT/MSO/MFO;
      - data limite (PJ-S01..S06).
- [x] 3.3 Margem total e livre, crítico pelo limiar e agregação dos resumos (PJ-S07, S08).
- [x] 3.4 Avisos com tarefa, problema e correção (PJ-S10).
- [x] 3.5 Teste `test_multiproject_schedule.lpr`:
      - um caso mínimo por tipo de vínculo e restrição;
      - o exemplo do motor com datas, margens e críticas esperadas, calculadas à mão;
      - feriado no meio de uma tarefa;
      - impressão decorrida atravessando o fim de semana;
      - 2.000 tarefas em menos de 200 ms (PJ-Q03).

Resultado da fase 3:
- **Calendários no documento.** O projeto nasce com **padrao** (seg–sex 08–12/13–17, feriados
  nacionais do ano anterior até 5 anos à frente, Carnaval e Corpus Christi incluídos) e **24h**
  (máquinas). Os calendários vão inteiros para o `.mproj`, com as exceções. Um arquivo antigo sem
  calendários recebe os dois.
- **Campos novos na tarefa:** restrição e data, data limite, início e término manuais, e
  calendário próprio. No arquivo ficam `constraint {type, date}`, `deadline`, `manual_start`,
  `manual_finish` e `calendar`. As opções ganham `critical_slack` (minutos).
- **Convenção do Project para os horários:** uma tarefa termina às 17:00 e a sucessora começa às
  08:00 do próximo dia útil. O marco fica no término da predecessora. A tarefa decorrida (14eh)
  não é encaixada no expediente.
- **Data limite** não move a tarefa: reduz a margem, que pode ficar negativa, e gera aviso. ALAP
  vai para o fim da margem livre, sem atrasar as sucessoras.
- **Exemplo do motor conferido à mão.** O projeto termina na terça 03/11 10:00, porque Finados
  cai na segunda. Caminho crítico: driver → montagem → validação → liberação → torno/placa →
  montagem física → teste.
- **Desempenho:** 2000 tarefas e 4000 vínculos em cerca de 55 ms (meta PJ-Q03: 200 ms).
- **Fica para depois:** agendar a partir do término (PJ-T02, P1), restrição em tarefa de resumo
  e recálculo manual (F9) na tela.

### Fase 4: tela e registro na suíte (≈ 6 h)

- [x] 4.1 `stiMultiProject`, `sikProject` (glifo), registro, grupo PLANEJAR na bandeja e no
      MultiSuite e `akProject` (LAYOUT, "Registro na suíte").
- [x] 4.2 `multiproject.lpr` com `Application.CreateForm` e o esqueleto de LAYOUT
      (cabeçalho, 7 etapas, barra da vista, painel de 336 px, rodapé) (PJ-Q07).
- [x] 4.3 `multiproject_gantt`:
      - tabela editável e escala de tempo com zoom;
      - barras de tarefa, resumo, marco, crítica e progresso;
      - setas dos vínculos, data de status e indicadores (PJ-V01, T25).
- [x] 4.4 `multiproject_network`: caixas em camadas, cadeias, criar vínculo arrastando e
      realce do crítico (PJ-V02).
- [x] 4.5 `multiproject_board`: colunas por estado com as regras de transição (PJ-V03,
      L06).
- [x] 4.6 Página da tarefa com as 9 seções de LAYOUT e as páginas das etapas 1, 2, 3 e 5.
- [x] 4.7 Filtros, agrupamentos, ordenação e realce (PJ-V08), atalhos (PJ-U03) e realce de
      alterações (PJ-U02).
- [x] 4.8 Teste `test_multiproject_ui.lpr` (Xvfb):
      - abre o exemplo;
      - insere, recua e vincula;
      - a vista Rede mostra as cadeias;
      - fechar a janela encerra o processo;
      - 1024 × 768 sem cortar o rodapé.

Resultado da fase 4:
- **Vistas genéricas no CHATGPT** (aba AI Project): `TAIGanttView`, `TAINetworkView` e
  `TAIBoardView`, com cores por propriedade. A tela aplica a paleta `clSuite*`. Cópia em
  `third_party/chatgpt/AIProject`.
- **Tela no padrão da suíte:**
  - cabeçalho com o projeto, a revisão e a marca "alterado";
  - lateral com as 7 etapas, Novo/Abrir/Salvar/Demo, Cadeias e Sugestões;
  - painel de 336 px com as páginas das etapas e a da tarefa (9 seções);
  - rodapé com o término previsto, as críticas e a relação da tarefa selecionada ("em cadeia
    com N, em paralelo com M").
- **Barra da vista em duas linhas** (52 + 36 px), para caber em 1024 × 768. Os botões Equipe,
  Calendário e Linha do tempo ficam ocultos até as fases 7 e 8. A tabela do Gantt cede espaço
  ao gráfico em janelas estreitas.
- **Edição pela tabela** (nome, duração, predecessoras) e pela página da tarefa, cada uma como
  um passo de desfazer. Os vínculos podem ser criados arrastando na rede. O Quadro muda o
  estado com as regras de `multiproject_states`: não conclui com predecessora TI aberta nem
  com critério pendente.
- **Filtros** (críticas, atrasadas, sugeridas, cadeia) e **agrupamento** por EAP, tipo ou estado.
- **Registro na suíte:**
  - `stiMultiProject`, `sikProject` (ícone de Gantt com marco), `akProject`;
  - grupo PLANEJAR na bandeja e seção Planejar no MultiSuite;
  - cor azul-céu `C(2, 132, 199)`, porque o índigo já é do MultiAssembly.
- **Bugs que o teste visual achou e foram corrigidos no CHATGPT:**
  - a linha de grupo sem datas derrubava a pintura do Gantt (coordenada de −1,8 milhão de px
    no GDK);
  - o quadro não tinha rolagem horizontal, e a etiqueta sobrepunha o rodapé do cartão;
  - o "Ajustar" da rede reduzia até ficar ilegível.
- **Falta:** compilar o Win64 e gerar `bin/multiproject.exe`, que precisam do Lazarus no
  Windows.

### Fase 5: vínculo com as ferramentas (≈ 5 h)

- [x] 5.1 `multiproject_kinds`: a tabela de tipos de ARCHITECTURE (PJ-L01).
- [x] 5.2 `--new`/`--task` em `ReadSuiteContext` (as duas cópias, ou unificar) e
      `TSuiteLauncher.LaunchNew`, com `multisuite/tests/test_context.lpr` ampliado (D4).
- [x] 5.3 `multiproject_taskctx`: gravar o `<artefato>.task.json` com as especificações e os
      `inputs` (PJ-L03).
- [x] 5.4 MultiCAD e MakePCB tratam `--new` (salvar como no caminho dado) e mostram a
      especificação da tarefa num painel informativo.
- [x] 5.5 `multiproject_artifacts`:
      - vincular arquivo;
      - conferir tamanho e data a cada 2 s e ao ativar a janela, recalculando o SHA-1 se mudaram;
      - estados none/created/valid/ready e desatualização das sucessoras (PJ-L04).
- [x] 5.6 `multiproject_checks`: verificadores de `.mcad`, `.mpcb` (DRC e Gerber), G-code
      (`SuiteCheckGCode` + `MS-MACHINE`) e "não verificado" para os demais (PJ-L05).
- [x] 5.7 Estados e transições (PJ-L06), o botão "Abrir na ferramenta" com rótulo por tipo
      e "Abrir no MultiCNC" só com `--file` (PJ-L07).
- [x] 5.8 Teste `test_multiproject_links.lpr`:
      - abrir com `--new` gera o comando certo (lançador falso);
      - o `.task.json` tem os `inputs`;
      - alterar o arquivo deixa as sucessoras desatualizadas;
      - G-code de laser vinculado a uma tarefa de impressão 3D é recusado.

Validação de 22/10/2026 (Win64, FPC 3.2.2):
- Documento: 103 checks; grafo: 88; cronograma: 82; recursos: 116; estados: 21.
- `test_multiproject_links`: 36 checks (inclui peça real reconstruída, DRC/Gerber,
  G-code de impressora/laser, hash, persistência, desfazer e polling sem alterações).
- `test_multiproject_ui`: 84 checks, incluindo layout em 1024 × 768.
- `test_multiproject_toolctx`: 6 checks nas interfaces reais do MultiCAD/MakePCB:
  painel de especificação, Ctrl+S no destino novo e recusa de destino já existente.
- `test_context` compilado contra cada cópia da unit; `test_launcher_delivery` com
  processo falso recebendo `--new`/`--task` e preservando espaços nos caminhos.
- MultiProject, MultiCAD e MakePCB compilados em Win64 para verificação, sem atualizar
  os executáveis de distribuição nem gerar setup.
- A conferência automática no Win64 substitui os antigos marcadores de pendência das
  fases 1 a 3; inspeção visual manual e hardware não fazem parte destes testes.
- A fase 5 ainda precisa da regressão Linux antes de seu aceite multiplataforma.

### Fase 6: regras de geração e modelos (≈ 4 h)

- [x] 6.1 `multiproject_rules`: A01 (processo da peça → fabricação) e A02 (placa →
      fabricar e comprar).
- [x] 6.2 A03 (prontas → montagem por subsistema e do objetivo) e A04 (montagem → validação,
      com o tipo de estudo pela especificação técnica).
- [x] 6.3 A05 (marco de liberação e `fabrication_gate`), A06 (montagem física → teste
      funcional → objetivo concluído) e A07 (reprovação → tarefa de revisão sem ciclo).
- [x] 6.4 A08: origem registrada, sem duplicar (chave regra + origens). Aceitar e recusar
      sugestão sozinha ou em lote, como um passo de desfazer, e a lista SUGESTÕES na lateral.
- [x] 6.5 Exemplo `multiproject/examples/motor_dc.mproj` (o grafo do README) e modelos em
      `models/multiproject/` (Peça impressa, Placa eletrônica, Motor DC) (PJ-T03).
- [x] 6.6 Folha de processo de torno em Markdown a partir da especificação técnica (D7).
- [x] 6.7 Teste `test_multiproject_rules.lpr`:
      - o exemplo do motor, a partir só das 4 tarefas de projeto, gera exatamente as tarefas e
        os vínculos do README;
      - rodar de novo não duplica;
      - a reprovação gera revisão e o grafo continua acíclico;
      - sem `fabrication_gate`, as fabricações dependem só das peças.
- [x] 6.8 **Primeira entrega Windows (setup 016):**
      - setup com o MultiProject;
      - manual curto em `docs/Manuals`;
      - capturas em `imgs/`;
      - linha no README da suíte e na tabela de `docs/AI_TOOLS_GUIDE.md`;
      - `NEWS.md`.

Resultado em 22/10/2026:
- A01/A02 propõem fabricação pelo processo, gravação encadeada quando especificada,
  compra quando há componentes e máquina compatível sugerida (RouterPCB quando há router).
- A03/A04 respeitam a prontidão das entregas e os subsistemas; A05 só propõe liberação
  depois da validação aprovada. Aceitar o marco acrescenta os vínculos às fabricações futuras.
- A06 deriva verificações de `manual_steps` do MultiAssembly, quando vinculado, e copia
  os critérios do objetivo para o teste final. A07 exige o ID `revisar_tarefa` e leva a evidência.
- A08 usa regra + tipo de saída + origens ordenadas: os dois resultados de A02 e a cadeia
  de A06 têm identidades distintas. Recusas ficam como canceladas e não reaparecem.
- Gerar, decidir em lote e alterar a liberação são transações com um único desfazer.
  Os modelos recriam IDs e limpam resultados e artefatos anteriores.
- `test_multiproject_rules`: 145 checks; `test_multiproject_rules_ui`: 34 checks no Win64,
  incluindo decisões individuais/em lote, desfazer, origem, filtro, modelos e 1024 × 768.
- O exemplo completo tem 15 tarefas e 21 vínculos. Os quatro vínculos de projeto para
  fabricação, necessários para entregar os arquivos, agora estão explícitos no README.
- Console do MultiProject aprovado também no Linux pelo Suite CI (`5fe749d`, 22/10).
  Interface Linux em validação pelo workflow próprio MultiProject CI; setup 016 em preparação.
  O Suite CI geral registrou falhas de TCP/Winsock2, catálogo FDM e fonte do MultiCAD, fora deste módulo.

### Fase 7: recursos e custos (≈ 5 h)

- [x] 7.1 Recursos (pessoa, IA, máquina, material, custo), unidades máximas e calendário do
      recurso (PJ-R01, C03). A pessoa guarda função e e-mail (usuário da equipe); a máquina
      guarda o tipo (router, laser, impressora 3D, torno) e o equipamento do MultiCNC. Tarefa
      sem calendário próprio usa o calendário da máquina atribuída (impressora 24 h).
- [x] 7.2 Importar as máquinas do `multicnc.json` em somente leitura (PJ-R02): cria ou
      atualiza um recurso por equipamento e nunca apaga.
- [x] 7.3 Atribuições com unidades e quantidade, compatibilidade máquina × tipo de tarefa no
      Validar e superalocação no tempo útil do recurso (PJ-R03, R04): aviso com o recurso, o
      período e as tarefas; marca `(!)` na coluna Recursos, no Quadro, na planilha e na vista
      Equipe.
- [x] 7.4 Nivelamento e limpeza do nivelamento (PJ-R05), com prioridade 0–1000 (PJ-T24),
      "só dentro da margem" e tarefa em andamento fixa; vista Equipe (PJ-V06) com arraste
      para reatribuir. Falta o recurso genérico (PJ-R06).
- [x] 7.5 Custos (26/10): taxa por hora, custo por uso, custo unitário do material, recurso
      de custo com valor na atribuição ("Frete[R$ 150,00]"), custo fixo com acumulação no
      início, rateada ou no fim, resumo = filhas + o próprio, custo do projeto no rodapé e na
      etapa 5 (PJ-$01, $02). Material automático (PJ-$03): o filamento da estimativa do
      MultiSlicer entra no material em kg ou g com origem `multislicer`; a lista de materiais
      do MultiAssembly (`TAssemblyBOM`) entra na tarefa de compra com origem `bom`, sem peças e
      placas da suíte. Editar a coluna sem mudar a quantidade mantém a origem.
      Taxa de horas extras e tabelas de taxa (PJ-$04, P2) ficam para depois.
- [x] 7.6 Estimativa (26/10, PJ-L08): cabeçalho `MS-PRINT` do MultiSlicer (tempo, filamento,
      material) ou planejador do Grbl de `multicnc_gcode_preflight` com o volume da máquina
      atribuída (somente leitura do `multicnc.json`). Fica como sugestão com origem e data;
      "Aplicar" troca a duração e lança o filamento num único passo de desfazer.
- [x] 7.7 Tipos de tarefa (26/10, PJ-T19): duração fixa, unidades fixas e trabalho fixo,
      controlada pelo empenho; padrão automático pelo tipo (máquina = duração fixa, pessoa =
      trabalho fixo). Trabalho não é gravado: sempre Duração × Unidades. Atribuição inicial em
      lote não mexe na duração; incluir ou retirar recurso depois segue o empenho.
- [x] 7.8 Testes: impressões na mesma máquina viram sequenciais; limpar o nivelamento
      restaura as datas; a fórmula do trabalho nos três tipos está em `test_multiproject_costs`.

Pendências da fase 7 (levantadas em 26/10):

- [ ] Compilar os 14 aplicativos e rodar `test_multiproject_costs` e `test_multiproject_ui`
      no Win64 (regra 13 do AI_GUIDE); no Linux já passaram.
- [ ] Recurso genérico ("impressora FDM qualquer"), trocado depois pelo real (PJ-R06).
- [ ] Taxa de horas extras (PJ-$01): depende de modelar hora extra no plano.
- [ ] Tabelas de taxa A–E e recurso de orçamento (PJ-$04, P2).
- [ ] Estimativa desatualizada: marcar quando o G-code mudar depois da estimativa (hoje só a data mostra).
- [ ] Documentação do usuário: custos, tipo de tarefa e estimativa em
      `docs/Manuals/MultiProject_Guia_Rapido.md` e `multiproject/README.md`; seção nova no `NEWS.md`.
- [ ] Setup 017 com as novidades.

### Fase 8: linha de base, acompanhamento e relatórios (≈ 5 h)

- [ ] 8.1 Linhas de base 0–10 e planos provisórios (PJ-B01, B02).
- [ ] 8.2 Progresso, data de status, atualizar projeto e reagendar o incompleto (PJ-B03,
      B04).
- [ ] 8.3 Gantt de controle, variações, linha de progresso e progresso sugerido pelo
      artefato (PJ-B05..B07).
- [ ] 8.4 Valor agregado (PJ-E01, E02), conferido com um exemplo numérico de livro.
- [ ] 8.5 Relatório HTML: visão geral, atrasadas, críticas, custos, burndown e dossiê de
      artefatos; impressão e PDF (PJ-P01..P04).
- [ ] 8.6 Vistas Calendário e Linha do tempo (PJ-V04, V05).

### Fase 9: IA (≈ 4 h)

- [ ] 9.0 Criar `aiplancontract` no CHATGPT. A chamada ao modelo usa os componentes de
      provedor já existentes na suíte, sem implementação própria de HTTP.

- [ ] 9.1 `multiproject_ai_contract`: esquema e `ParsePlan` com as 8 validações de
      ARCHITECTURE (PJ-I02).
- [ ] 9.2 `multiproject_ai_planner`: prompt com o objetivo, a tabela de tipos e o contrato,
      chamada pela suíte CHATGPT e configuração fora do `.mproj` (PJ-I01, I04).
- [ ] 9.3 Proposta na lista SUGESTÕES com o indicador IA, aceitação como um desfazer
      (PJ-I03), botão "Decompor com IA" na etapa 1 e assistência pontual (PJ-I05).
- [ ] 9.4 Testes do contrato com 20 planos inválidos (um por regra) e 3 válidos, sem rede
      (resposta gravada).

### Fase 10: intercâmbio e multiprojeto (≈ 5 h)

- [ ] 10.1 `multiproject_mspdi`: exportar e importar o XML do Project (PJ-X02), com teste de
      ida e volta e um arquivo aberto no ProjectLibre.
- [ ] 10.2 CSV de entrada e saída (PJ-X03).
- [ ] 10.3 `multiproject_cli` (`--check`, `--export-xml`, `--export-csv`) (PJ-Q05) e o
      workflow da CI.
- [ ] 10.4 P2: subprojetos, pool de recursos, vínculo externo, tarefa recorrente, divisão de
      tarefa e atualização pela equipe (PJ-M01..M03, T22, T23, U04).

## Critério de pronto (primeira entrega, fases 1 a 6)

1. Criar o objetivo "Motor DC didático" e as quatro tarefas de projeto (carcaça, eixo, base,
   driver) com os seis campos, em paralelo.
2. Abrir a carcaça no MultiCAD pelo botão. O arquivo nasce em
   `pecas/T-0002_carcaca_do_estator.mcad`, volta vinculado, é verificado e marcado pronto.
3. Com as quatro prontas, o MultiProject sugere a montagem virtual, a validação, o marco, as
   cinco fabricações (impressão, torno, corte laser → arte laser, placa), a montagem física e
   o teste funcional, com os vínculos do README.
4. O Gantt mostra o caminho crítico. A vista Rede mostra o grafo do README. Mudar a duração da
   impressão recalcula as datas em tempo real.
5. Alterar o `.mcad` depois de pronto deixa a impressão e a montagem desatualizadas.
6. Os testes das fases 1 a 6 passam no Linux e no Win64, e os testes das outras ferramentas
   continuam passando com o `--new` no contexto.

## Riscos

- **Escopo do Project é enorme.** Por isso a primeira entrega fica nos P0, e recursos, custos,
  valor agregado e intercâmbio vão para as fases 7 a 10.
- **Datas e calendários** são a fonte clássica de erros (feriado móvel, fuso, horário de verão
  antigo). Mitigação: minuto útil inteiro, datas sem fuso e testes de borda.
- **Integração depende das outras ferramentas** aceitarem `--new`/`--task`. A alternativa
  (salvar no caminho mostrado) mantém o fluxo funcionando enquanto a adoção é gradual.
- **Verificadores leem formatos de outras ferramentas** que podem mudar. Eles leem só campos
  mínimos, e um campo ausente vira "não verificado", não erro. Cada verificador tem teste com
  um arquivo real do repositório (`models/`).
- **Torno sem ferramenta:** a tarefa manual atende agora, mas não gera G-code. Fica explícito na
  tela.
- **IA produzindo planos ruins:** o contrato barra a forma, não o mérito. Por isso tudo entra
  como Sugerida para revisão humana.

## Setup 016 (22/10/2026)

- 14 aplicativos Win64 compilados; 119 testes de console aprovados e 1 integração separada.
- `setup/setup_multcnc_016.exe` e `bin/setup_multcnc_016.exe`, com o mesmo SHA-256.
- Manifesto de fontes limpas e QA em `setup/build-manifest-016.json` e `setup/qa-tests-016.json`.
- Modelos instalados com o componente MultiProject; guia e capturas na documentação offline.
- [Notas da edição](../../docs/SETUP_016.md) e [verificação da fase 6](../../docs/qa/multiproject-fase6-2026-10-22.md).
