# TAREFA: MultiProject — gerenciador de projetos mecânicos e eletrônicos

- **Aberta em:** 20/10/2026.
- **Estado:** fase 0 (especificação) concluída. As decisões D1 a D12 aguardam o Marcelo; o
  código começa na fase 1 depois delas.
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

| Fase | Estado em 20/10/2026 | Entrega |
|---|---|---|
| 0 Especificação | concluída | README, REQUISITOS, ARCHITECTURE, LAYOUT, TAREFA, AI_GUIDE |
| 1 Documento e tarefas | pendente | tipos, tarefa com os 6 campos, EAP, `.mproj`, desfazer |
| 2 Grafo | pendente | lista de adjacência, 4 tipos de vínculo, latência, ciclo, cadeias |
| 3 Calendário e cronograma | pendente | calendários, CPM, restrições, margens, crítico, avisos |
| 4 Tela e registro na suíte | pendente | layout da suíte, Gantt, Rede, Quadro, painel da tarefa, bandeja |
| 5 Vínculo com as ferramentas | pendente | `--new`/`--task`, `.task.json`, detecção, verificadores, Abrir na ferramenta |
| 6 Regras de geração e modelos | pendente | PJ-A01..A08, exemplo Motor DC, modelos |
| 7 Recursos e custos | pendente | máquinas do MultiCNC, atribuições, superalocação, nivelamento, Equipe, custos |
| 8 Linha de base, acompanhamento e relatórios | pendente | linhas de base, progresso, valor agregado, HTML/PDF, Calendário, Linha do tempo |
| 9 IA | pendente | contrato do plano, decomposição do objetivo pela suíte CHATGPT |
| 10 Intercâmbio e multiprojeto | pendente | XML do Project (MSPDI), CSV, CLI, subprojetos, pool |

**Primeira entrega utilizável = fases 1 a 6 (todos os P0).** As fases 7 a 10 cobrem os P1 e
P2. Nenhuma fase conta como concluída sem o teste rodando no Linux e no Win64 (regra 9 do
guia da suíte).

## Decisões para o Marcelo

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

- [ ] 1.1 Árvore `multiproject/src/{core,io,integration,ai,view,app}` e `tests/`, além do
      `multiproject/tests/run.sh` chamado por `tests/run_all.sh multiproject`.
- [ ] 1.2 `multiproject_types`:
      - enums `TPJTaskKind`, `TPJProcess`, `TPJTaskState`, `TPJLinkType`, `TPJConstraint` e
        `TPJResourceType`, com nomes em texto para o arquivo;
      - registros de especificação técnica e de critério de aceite.
- [ ] 1.3 `multiproject_document`:
      - projeto e objetivo;
      - tarefas com os seis campos (PJ-T10..T12);
      - árvore `parent`/ordem, recuar/avançar/mover, código EAP (PJ-T13, T14);
      - marco e modo manual/auto (PJ-T15, T16);
      - geração de IDs que não reaproveita número.
- [ ] 1.4 Comandos com desfazer e refazer (PJ-U01): inserir, excluir, editar campo, mover,
      recuar e em lote.
- [ ] 1.5 Duração: interpretar e formatar `30min`, `4h`, `2d`, `1sem`, `14eh` e `?`
      (PJ-T17, T18).
- [ ] 1.6 `multiproject_json`: salvar e ler o `.mproj` com salvamento atômico, preservação
      de campos desconhecidos e recusa de versão futura (PJ-X01, Q02, Q04).
- [ ] 1.7 Teste `test_multiproject_core.lpr`:
      - EAP depois de recuar e mover;
      - ID não reaproveitado depois de excluir;
      - desfazer de cada comando;
      - ida e volta do JSON igual byte a byte na segunda gravação;
      - vírgula decimal regional sem efeito;
      - validação recusa tarefa sem nome ou sem descrição curta.

### Fase 2: grafo (≈ 3 h)

- [ ] 2.1 Vínculos TI/II/TT/IT, latência em duração ou %, antecipação, latência decorrida e
      "entrega artefato" (PJ-G01, G02, G06).
- [ ] 2.2 `multiproject_graph`:
      - lista de adjacência de sucessoras e predecessoras;
      - ordem topológica (Kahn);
      - `WouldCycle` com caminho (PJ-G04, G05).
- [ ] 2.3 Cadeias (componentes conexos por união-busca) e a consulta "em cadeia" ×
      "em paralelo" entre duas tarefas.
- [ ] 2.4 Interpretar e formatar a coluna Predecessoras (`T-0003TI+2h;T-0004II-10%`)
      (PJ-G03).
- [ ] 2.5 Vínculo em resumo expandido para as folhas (PJ-G07, P1: só o núcleo nesta fase).
- [ ] 2.6 Teste `test_multiproject_graph.lpr`:
      - ciclo A→B→C→A recusado com o caminho e o documento intacto;
      - ordem topológica válida em 1.000 tarefas aleatórias;
      - 3 cadeias corretas;
      - A e B paralelas, A e C encadeadas;
      - ida e volta da sintaxe de predecessoras.

### Fase 3: calendário e cronograma (≈ 4 h)

- [ ] 3.1 `multiproject_calendar`:
      - calendários Padrão e 24 Horas e as exceções;
      - feriados brasileiros fixos e móveis (Páscoa pelo algoritmo de Meeus);
      - minuto útil ↔ data e soma de duração (PJ-C01..C03, C05).
- [ ] 3.2 `multiproject_schedule`:
      - passagem de ida e de volta com os quatro tipos de vínculo e latência;
      - restrições ASAP/ALAP/SNET/SNLT/FNET/FNLT/MSO/MFO;
      - data limite (PJ-S01..S06).
- [ ] 3.3 Margem total e livre, crítico pelo limiar e agregação dos resumos (PJ-S07, S08).
- [ ] 3.4 Avisos com tarefa, problema e correção (PJ-S10).
- [ ] 3.5 Teste `test_multiproject_schedule.lpr`:
      - um caso mínimo por tipo de vínculo e restrição;
      - o exemplo do motor com datas, margens e críticas esperadas, calculadas à mão;
      - feriado no meio de uma tarefa;
      - impressão decorrida atravessando o fim de semana;
      - 2.000 tarefas em menos de 200 ms (PJ-Q03).

### Fase 4: tela e registro na suíte (≈ 6 h)

- [ ] 4.1 `stiMultiProject`, `sikProject` (glifo), registro, grupo PLANEJAR na bandeja e no
      MultiSuite e `akProject` (LAYOUT, "Registro na suíte").
- [ ] 4.2 `multiproject.lpr` com `Application.CreateForm` e o esqueleto de LAYOUT
      (cabeçalho, 7 etapas, barra da vista, painel de 336 px, rodapé) (PJ-Q07).
- [ ] 4.3 `multiproject_gantt`:
      - tabela editável e escala de tempo com zoom;
      - barras de tarefa, resumo, marco, crítica e progresso;
      - setas dos vínculos, data de status e indicadores (PJ-V01, T25).
- [ ] 4.4 `multiproject_network`: caixas em camadas, cadeias, criar vínculo arrastando e
      realce do crítico (PJ-V02).
- [ ] 4.5 `multiproject_board`: colunas por estado com as regras de transição (PJ-V03,
      L06).
- [ ] 4.6 Página da tarefa com as 9 seções de LAYOUT e as páginas das etapas 1, 2, 3 e 5.
- [ ] 4.7 Filtros, agrupamentos, ordenação e realce (PJ-V08), atalhos (PJ-U03) e realce de
      alterações (PJ-U02).
- [ ] 4.8 Teste `test_multiproject_ui.lpr` (Xvfb):
      - abre o exemplo;
      - insere, recua e vincula;
      - a vista Rede mostra as cadeias;
      - fechar a janela encerra o processo;
      - 1024 × 768 sem cortar o rodapé.

### Fase 5: vínculo com as ferramentas (≈ 5 h)

- [ ] 5.1 `multiproject_kinds`: a tabela de tipos de ARCHITECTURE (PJ-L01).
- [ ] 5.2 `--new`/`--task` em `ReadSuiteContext` (as duas cópias, ou unificar) e
      `TSuiteLauncher.LaunchNew`, com `multisuite/tests/test_context.lpr` ampliado (D4).
- [ ] 5.3 `multiproject_taskctx`: gravar o `<artefato>.task.json` com as especificações e os
      `inputs` (PJ-L03).
- [ ] 5.4 MultiCAD e MakePCB tratam `--new` (salvar como no caminho dado) e mostram a
      especificação da tarefa num painel informativo.
- [ ] 5.5 `multiproject_artifacts`:
      - vincular arquivo;
      - conferir tamanho e data a cada 2 s e ao ativar a janela, recalculando o SHA-1 se mudaram;
      - estados none/created/valid/ready e desatualização das sucessoras (PJ-L04).
- [ ] 5.6 `multiproject_checks`: verificadores de `.mcad`, `.mpcb` (DRC e Gerber), G-code
      (`SuiteCheckGCode` + `MS-MACHINE`) e "não verificado" para os demais (PJ-L05).
- [ ] 5.7 Estados e transições (PJ-L06), o botão "Abrir na ferramenta" com rótulo por tipo
      e "Abrir no MultiCNC" só com `--file` (PJ-L07).
- [ ] 5.8 Teste `test_multiproject_links.lpr`:
      - abrir com `--new` gera o comando certo (lançador falso);
      - o `.task.json` tem os `inputs`;
      - alterar o arquivo deixa as sucessoras desatualizadas;
      - G-code de laser vinculado a uma tarefa de impressão 3D é recusado.

### Fase 6: regras de geração e modelos (≈ 4 h)

- [ ] 6.1 `multiproject_rules`: A01 (processo da peça → fabricação) e A02 (placa →
      fabricar e comprar).
- [ ] 6.2 A03 (prontas → montagem por subsistema e do objetivo) e A04 (montagem → validação,
      com o tipo de estudo pela especificação técnica).
- [ ] 6.3 A05 (marco de liberação e `fabrication_gate`), A06 (montagem física → teste
      funcional → objetivo concluído) e A07 (reprovação → tarefa de revisão sem ciclo).
- [ ] 6.4 A08: origem registrada, sem duplicar (chave regra + origens). Aceitar e recusar
      sugestão sozinha ou em lote, como um passo de desfazer, e a lista SUGESTÕES na lateral.
- [ ] 6.5 Exemplo `multiproject/examples/motor_dc.mproj` (o grafo do README) e modelos em
      `models/multiproject/` (Peça impressa, Placa eletrônica, Motor DC) (PJ-T03).
- [ ] 6.6 Folha de processo de torno em Markdown a partir da especificação técnica (D7).
- [ ] 6.7 Teste `test_multiproject_rules.lpr`:
      - o exemplo do motor, a partir só das 4 tarefas de projeto, gera exatamente as tarefas e
        os vínculos do README;
      - rodar de novo não duplica;
      - a reprovação gera revisão e o grafo continua acíclico;
      - sem `fabrication_gate`, as fabricações dependem só das peças.
- [ ] 6.8 **Primeira entrega:**
      - setup com o MultiProject;
      - manual curto em `docs/Manuals`;
      - capturas em `imgs/`;
      - linha no README da suíte e na tabela de `docs/AI_TOOLS_GUIDE.md`;
      - `NEWS.md`.

### Fase 7: recursos e custos (≈ 5 h)

- [ ] 7.1 Recursos (pessoa, IA, máquina, material, custo), unidades máximas e calendário do
      recurso (PJ-R01, C03).
- [ ] 7.2 Importar e sincronizar máquinas do `multicnc.json` em somente leitura (PJ-R02).
- [ ] 7.3 Atribuições com compatibilidade máquina × tipo de tarefa e superalocação (PJ-R03,
      R04).
- [ ] 7.4 Nivelamento e limpeza do nivelamento (PJ-R05), vista Equipe (PJ-V06), recurso
      genérico (PJ-R06) e prioridade (PJ-T24).
- [ ] 7.5 Custos: taxas, custo por uso, custo fixo com acumulação e material automático do
      MultiSlicer e da BOM (PJ-$01..$03).
- [ ] 7.6 Estimativa de duração pelo G-code e pelo MultiSlicer (PJ-L08).
- [ ] 7.7 Tipos de tarefa e controlada pelo empenho (PJ-T19).
- [ ] 7.8 Testes: duas impressões na mesma Ender-3 viram sequenciais; limpar o nivelamento
      restaura as datas; fórmula do trabalho nos três tipos.

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
