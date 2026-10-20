# MultiProject — Requisitos funcionais (revisão 2026-10)

Referência funcional: **Microsoft Project** (versão desktop). Não é cópia: o MultiProject
segue o padrão visual da MultiSuite ([LAYOUT.md](LAYOUT.md)) e a divisão de papéis da suíte
([../../docs/AI_TOOLS_GUIDE.md](../../docs/AI_TOOLS_GUIDE.md)).

## Objetivo (como definido pelo autor)

Gerenciar projetos de peças mecânicas e eletrônicas a partir de um **objetivo** (exemplo:
construir um motor). Uma pessoa ou a IA divide o projeto em **tarefas** (peças ou
eletrônica). Cada tarefa pode se relacionar com outras por uma **lista de grafos**, em
**cadeia ou em paralelo**. Uma tarefa tem **Nome, ID, Descrição curta, Descrição longa,
Especificação técnica e Especificação funcional**.

- A tarefa de peça mecânica abre um projeto no **MultiCAD**, que fica vinculado à tarefa quando
  fica pronto.
- A tarefa de eletrônica abre um projeto no **MakePCB**.
- Quando as tarefas ficam prontas, o MultiProject gera as tarefas de **ligação entre as peças**
  (**MultiAssembly**) e as de **teste e validação** (**MultiPhysics**).
- Existem tarefas de **impressão 3D, usinagem CNC Router, corte laser, arte laser, usinagem de
  torno e impressão de placas**, cada uma ligada a uma ferramenta da suíte.

## Convenções

- **ID** `PJ-<área><nn>`. As áreas são:
  - `T`: tarefa;
  - `G`: grafo;
  - `S`: cronograma;
  - `C`: calendário;
  - `R`: recursos;
  - `$`: custos;
  - `B`: linha de base e acompanhamento;
  - `E`: valor agregado;
  - `V`: modos de exibição;
  - `P`: relatórios;
  - `M`: multiprojeto;
  - `X`: importação e exportação;
  - `U`: edição e colaboração;
  - `L`: vínculo com as ferramentas;
  - `A`: regras de geração;
  - `I`: IA;
  - `Q`: qualidade.

  O prefixo `PJ` evita colisão com os IDs `MP-` do MultiPhysics.
- **Prioridade:**
  - **P0** é obrigatório na primeira entrega (fases 1 a 6 de [TAREFA.md](TAREFA.md));
  - **P1** é evolução funcional;
  - **P2** é refinamento;
  - **N/A** é um recurso do Project fora do escopo, com o motivo.
- A coluna **Microsoft Project** cita o recurso de referência. A coluna **MultiProject** diz como
  ele entra na ferramenta e qual é o aceite. Nenhum requisito conta como implementado só porque
  este documento ou uma unidade existe; vale o teste ou a tela.

---

## 1. Projeto e objetivo

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-T01 | P0 | Informações do projeto (início, término, data de status, propriedades) | O projeto tem **objetivo** (nome, descrição curta e longa), escopo, critério de sucesso, data de início, data de status, calendário do projeto, autor, revisão e pasta raiz. O objetivo é a tarefa de resumo do projeto (nível 0). |
| PJ-T02 | P1 | Agendar a partir da data de término | Opção "agendar a partir do término" (prazo fixo de entrega). O padrão é a partir do início. |
| PJ-T03 | P0 | Modelos de projeto (`.mpt`) | Modelos `.mproj` com tarefas típicas: *Peça impressa*, *Placa eletrônica*, *Máquina CNC*, *Motor DC*. Criar o projeto a partir de um modelo copia as tarefas com IDs novos. |
| PJ-T04 | P1 | Campos do projeto (Organizer, campos globais) | Campos personalizados do projeto e das tarefas (texto, número, data, sinalizador, lista), definidos no projeto e salvos no `.mproj`. |

## 2. Tarefas

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-T10 | P0 | Tarefa (Nome, ID, ID exclusivo) | Campos obrigatórios: **Nome**, **ID** e **Descrição curta**, além de **Descrição longa**, **Especificação técnica** e **Especificação funcional**. O ID é estável (`T-0001`, nunca reaproveitado, equivale ao *Unique ID*). O número da linha e o código EAP mudam com a ordem. Validar recusa tarefa sem nome ou sem descrição curta. |
| PJ-T11 | P0 | (próprio) | A **especificação técnica** tem duas partes: uma lista chave/valor com unidade (material, dimensões, tolerância ISO, massa, tensão, corrente, potência…) e um texto livre. Ela segue para a ferramenta vinculada como contexto e para o MultiPhysics como dado do estudo. |
| PJ-T12 | P0 | (próprio) | A **especificação funcional** é uma lista de **critérios de aceite** verificáveis (exemplo: "3000 rpm ± 10% a 12 V sem carga"). Cada critério tem estado (pendente, aprovado, reprovado) e evidência (texto ou arquivo). Uma tarefa só fica **Concluída** com todos os critérios aprovados ou dispensados com justificativa. |
| PJ-T13 | P0 | Tarefa de resumo, estrutura de tópicos (recuar/avançar) | Hierarquia em árvore: objetivo → subsistemas (resumo) → tarefas. Recuar e avançar (Alt+Shift+→/←), recolher e expandir. O resumo agrega datas, duração, trabalho, custo e % concluído das filhas. |
| PJ-T14 | P0 | Código EAP (WBS) | Código EAP automático (`1.2.3`), recalculado ao mover. Máscara opcional por nível (P2). |
| PJ-T15 | P0 | Marco (duração zero) | Marco: duração 0, losango no Gantt. Usado em "Liberado para fabricação" e "Objetivo concluído". |
| PJ-T16 | P0 | Tarefa agendada manualmente × automaticamente | Modo por tarefa. A automática é calculada pelo cronograma; a manual mantém as datas digitadas e aparece com aviso quando conflita com os vínculos. |
| PJ-T17 | P0 | Duração (min, h, d, sem, me), duração estimada (`?`) | Duração em minutos inteiros internamente. Entrada e exibição em `min`, `h`, `d`, `sem` (1 d = horas úteis do calendário). O sufixo `?` marca uma estimativa. |
| PJ-T18 | P0 | Duração decorrida (`ed`, `eh`) | Duração decorrida para trabalho de máquina que roda direto (uma impressão de 14 h atravessa a noite). É o padrão das tarefas de fabricação. |
| PJ-T19 | P1 | Tipo de tarefa (unidades fixas, duração fixa, trabalho fixo) e controlada pelo empenho | Os três tipos e a opção *controlada pelo empenho*, com a fórmula Trabalho = Duração × Unidades. Padrão: duração fixa para máquina e trabalho fixo para pessoa. |
| PJ-T20 | P1 | Tarefa inativa | Tarefa inativa continua no plano, mas sai do cálculo (alternativa descartada, peça opcional). |
| PJ-T21 | P0 | Anotações e hiperlinks | Anotações em texto e anexos (arquivo relativo à pasta do projeto, URL de datasheet). |
| PJ-T22 | P2 | Tarefa recorrente | Tarefa recorrente: manutenção da máquina, calibração do laser, troca de bico. |
| PJ-T23 | P2 | Dividir tarefa (interrupção) | Dividir tarefa em segmentos (impressão pausada para troca de filamento). |
| PJ-T24 | P1 | Prioridade (0–1000) | Prioridade numérica usada pelo nivelamento de recursos. |
| PJ-T25 | P0 | Indicadores (coluna de ícones) | Indicadores na tabela: restrição, prazo vencido, anotação, artefato vinculado, artefato desatualizado, gerada pela IA ou por regra, critério reprovado. |

## 3. Grafo de dependências

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-G01 | P0 | Vincular tarefas: TI, II, TT, IT | Quatro tipos de vínculo: **TI** término-início (padrão, encadeada), **II** início-início (paralela com partida conjunta), **TT** término-término e **IT** início-término. Tarefas sem vínculo entre si correm **em paralelo**. |
| PJ-G02 | P0 | Latência e antecipação (lag negativo) | Latência em duração ou em % da predecessora. Valor negativo é antecipação. Exemplo: cura da resina, 24 h decorridas depois da impressão. |
| PJ-G03 | P0 | Colunas Predecessoras/Sucessoras | Edição pela tabela (`T-0003TI+2h;T-0004II`), pelo painel de propriedades e arrastando na vista de rede ou no Gantt. |
| PJ-G04 | P0 | (próprio) "lista de grafos" | O grafo é guardado como **lista de adjacência** (sucessoras e predecessoras por tarefa). O projeto pode ter **vários componentes conexos**: o painel lista cada grafo (cadeia) separadamente e permite filtrar por ele. |
| PJ-G05 | P0 | Aviso de vínculo circular | Recusar o vínculo que cria ciclo, mostrando o caminho que fecha o laço. Teste: A→B→C→A é recusado e o documento fica inalterado. |
| PJ-G06 | P0 | (próprio) | Um vínculo pode marcar **"entrega artefato"**: a sucessora consome o arquivo da predecessora (a carcaça `.mcad` alimenta a impressão; as peças alimentam a montagem). É assim que a montagem descobre quais peças importar. |
| PJ-G07 | P1 | Vincular tarefas de resumo | Vínculo em tarefa de resumo vale para todas as filhas. O aviso aparece quando contradiz um vínculo das filhas. |
| PJ-G08 | P1 | Caminho da tarefa (Task Path) e Inspetor de tarefas | Selecionar uma tarefa realça as predecessoras que a dirigem, todas as predecessoras, as sucessoras e as dirigidas, em cores diferentes. O inspetor explica o que define a data de início. |
| PJ-G09 | P2 | Vincular automaticamente ao inserir (autolink) | Opção desligada por padrão: inserir uma tarefa entre duas vinculadas refaz a cadeia. |
| PJ-G10 | P0 | (próprio) Revisão sem ciclo | Uma validação reprovada não cria vínculo de volta. Cria uma **tarefa de revisão** nova (`T-0002 rev.B`) ligada à reprovação, e o grafo continua acíclico. |

## 4. Restrições, prazos e cálculo do cronograma

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-S01 | P0 | Restrições: O Mais Breve Possível, O Mais Tarde Possível | ASAP (padrão) e ALAP. |
| PJ-S02 | P0 | Não iniciar antes de / Não terminar antes de | SNET e FNET (exemplo: chegada do material comprado). |
| PJ-S03 | P0 | Não iniciar depois de / Não terminar depois de | SNLT e FNLT. |
| PJ-S04 | P0 | Deve iniciar em / Deve terminar em | MSO e MFO. O conflito com os vínculos gera aviso, e a restrição prevalece, como no Project. |
| PJ-S05 | P0 | Data limite (deadline) | Data limite por tarefa, que não move a tarefa. Indicador e filtro "atrasadas" quando o término passa da data limite. |
| PJ-S06 | P0 | Agendamento por caminho crítico | Cálculo **CPM**: passagem para frente (início e término mais cedo), passagem para trás (mais tarde), considerando calendários, latência e restrições. Teste contra o exemplo do motor calculado à mão. |
| PJ-S07 | P0 | Margem de atraso total e livre | Margem total e livre por tarefa, em duração útil. |
| PJ-S08 | P0 | Caminho crítico | Crítica = margem total ≤ limiar (padrão 0). Barras em `clSuiteDanger` e filtro "Críticas". |
| PJ-S09 | P1 | Vários caminhos críticos | Opção de calcular um caminho crítico por cadeia (componente conexo, PJ-G04). |
| PJ-S10 | P0 | Avisos de agendamento (sublinhado ondulado) | Lista de avisos com tarefa, problema e correção: restrição × vínculo, tarefa manual fora do lugar, recurso superalocado, prazo vencido, artefato desatualizado. |
| PJ-S11 | P1 | Recalcular manualmente / automaticamente | Recalcular automaticamente por padrão, com opção manual (F9) para projetos grandes. |

## 5. Calendários

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-C01 | P0 | Calendários base Padrão, 24 Horas, Turno da noite | Calendários base **Padrão** (seg–sex, 08:00–12:00 e 13:00–17:00) e **24 Horas** (máquinas). |
| PJ-C02 | P0 | Exceções (feriados, folgas) e semanas de trabalho | Exceções por data ou intervalo, com feriados nacionais brasileiros fixos e móveis pré-carregados (Carnaval, Sexta-feira Santa, Corpus Christi) e editáveis. |
| PJ-C03 | P0 | Calendário do recurso | Cada recurso tem calendário próprio, derivado de um base: a pessoa usa o Padrão, a impressora usa 24 Horas com manutenção como exceção. |
| PJ-C04 | P1 | Calendário da tarefa | Calendário na tarefa, com a opção de ignorar o do recurso. |
| PJ-C05 | P0 | Opções de calendário (horas por dia, por semana, dias por mês) | Horas por dia e por semana usadas para converter `d` e `sem` em minutos. |

## 6. Recursos e atribuições

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-R01 | P0 | Planilha de recursos; tipos Trabalho, Material, Custo | Recursos dos tipos **Pessoa**, **IA** (agente), **Máquina** (trabalho), **Material** (consumível com unidade: kg de filamento, chapa MDF, placa cobreada) e **Custo**. |
| PJ-R02 | P0 | (próprio) | **Máquinas vêm do MultiCNC**: importar ou sincronizar os equipamentos de `multicnc.json` (`TEquipmentStore`): nome, tipo router/laser/impressora e volume de trabalho. O MultiProject só lê, nunca altera esse arquivo. |
| PJ-R03 | P0 | Atribuir recursos, unidades de atribuição | Atribuição tarefa × recurso com unidades (100% = dedicação total) e quantidade para material. A tarefa de fabricação exige uma máquina do tipo compatível (impressão → impressora; corte laser → laser), e o Validar acusa a incompatibilidade. |
| PJ-R04 | P0 | Unidades máximas, superalocação | Unidades máximas por recurso. Uma máquina tem máximo 1 (não imprime duas peças ao mesmo tempo). A superalocação aparece na tabela e no Planejador de equipe. |
| PJ-R05 | P1 | Nivelamento de recursos (ordem por prioridade, nivelar dentro da margem) | Nivelamento que atrasa tarefas pela prioridade, depois pela margem e depois pelo ID, com opção de nivelar só dentro da margem. Limpar nivelamento restaura as datas. Teste: duas impressões na mesma Ender-3 viram sequenciais. |
| PJ-R06 | P1 | Recurso genérico / substituição | Recurso genérico ("impressora FDM qualquer"), trocado depois pelo recurso real. |
| PJ-R07 | P2 | Perfis de trabalho (contornos) | Perfis de trabalho: plano, inicial, final. |
| PJ-R08 | P2 | Pool de recursos compartilhado | Pool de recursos compartilhado entre projetos: as mesmas máquinas da oficina em vários `.mproj` (ver PJ-M02). |

## 7. Custos

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-$01 | P1 | Taxa padrão, taxa de horas extras, custo por uso | Taxa por hora (pessoa, máquina), custo por uso (preparação da máquina) e custo unitário de material. |
| PJ-$02 | P1 | Custo fixo e acumulação (início, rateado, fim) | Custo fixo por tarefa (frete, serviço terceirizado), com acumulação no início, rateada ou no fim. |
| PJ-$03 | P1 | (próprio) | Custo de material automático: a massa de filamento estimada pelo MultiSlicer e a BOM do MultiAssembly (componentes comprados) alimentam as atribuições de material, mantendo a origem rastreável. |
| PJ-$04 | P2 | Tabelas de taxas de custo (A–E), recursos de orçamento | Cinco tabelas de taxa por recurso e recurso de orçamento no resumo do projeto. |

## 8. Linha de base e acompanhamento

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-B01 | P0 | Definir linha de base (Linha de base, 1–10) | Linha de base 0 a 10 com data, nome, autor e escopo (projeto inteiro ou seleção). Guarda início, término, duração, trabalho e custo por tarefa. |
| PJ-B02 | P1 | Plano provisório | Planos provisórios com início e término apenas. |
| PJ-B03 | P0 | % concluído, % trabalho concluído, início/término real, duração restante | Campos de progresso. A data de status marca o "hoje" do relatório. Marcar 100% preenche o término real. |
| PJ-B04 | P0 | Atualizar projeto, "marcar como no prazo" | "Atualizar até a data de status" marca como concluído o trabalho agendado antes dela. "Reagendar trabalho incompleto" move o restante para depois dela. |
| PJ-B05 | P0 | Gantt de controle (Tracking Gantt), variações | Barra da linha de base sob a barra atual. Colunas de variação de início, término, duração e custo. |
| PJ-B06 | P1 | Linhas de progresso | Linha de progresso na data de status. |
| PJ-B07 | P0 | (próprio) Progresso por artefato | Sugerir o % concluído a partir do estado do artefato (sem arquivo 0%, criado 25%, salvo e válido 75%, marcado pronto 90%, critérios aprovados 100%). O usuário confirma; nada muda sozinho. |
| PJ-B08 | P1 | (próprio) Real das máquinas | Importar do log do MultiCNC o início e o fim reais de cada G-code vinculado (quando o MultiCNC registrar isso, BUG-016). |

## 9. Valor agregado

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-E01 | P1 | COTA/COTR/CRTR (VP, VA, CR) | Valor planejado, valor agregado e custo real na data de status, a partir da linha de base escolhida. |
| PJ-E02 | P1 | VPR, VC, IDP, IDC, EAC, VNT, IDPT | VPR, VC, IDP, IDC, estimativa no término, variação no término e índice de desempenho para término, conferidos contra um exemplo numérico de livro. |
| PJ-E03 | P2 | Método de VA por % concluído físico | VA pelo % físico (critérios aprovados / total) como alternativa ao % de duração. |

## 10. Modos de exibição

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-V01 | P0 | Gráfico de Gantt (tabela + barras, escala de tempo) | Tabela com EAP, ID, nome, tipo, ferramenta, duração, início, término, predecessoras, recursos e % concluído, mais barras na escala de tempo (dias/semanas/meses, zoom com a roda e Ctrl), setas dos vínculos, marcos, resumos, críticas, data de status e linha "hoje". |
| PJ-V02 | P0 | Diagrama de rede (PERT) | Vista do **grafo**: caixas com ID, nome, ferramenta, datas, duração e margem, organizadas por camadas topológicas. Criar vínculo arrastando de uma caixa a outra, filtrar por cadeia (PJ-G04) e realçar o caminho crítico. |
| PJ-V03 | P0 | Quadro de tarefas (Kanban, Project Online) | Quadro com colunas por estado (Sugerida, Planejada, Em andamento, Pronta para revisão, Concluída, Bloqueada). Arrastar entre colunas muda o estado, respeitando as regras de PJ-L06. |
| PJ-V04 | P1 | Calendário | Mês e semana com as barras das tarefas. |
| PJ-V05 | P1 | Linha do tempo | Faixa com marcos e tarefas escolhidas, exportável como PNG. |
| PJ-V06 | P1 | Planejador de equipe (Team Planner) | Uma linha por recurso (pessoas e máquinas) com as tarefas no tempo, superalocação em vermelho e arraste para reatribuir. Mostra a fila de cada máquina da oficina. |
| PJ-V07 | P1 | Planilha de recursos, Uso dos recursos, Uso da tarefa, Gráfico de recursos | Planilha de recursos e uso por período (trabalho e custo por dia/semana). |
| PJ-V08 | P0 | Tabelas, filtros, grupos, realce, classificação | Filtros prontos (Críticas, Atrasadas, Por ferramenta, Por tipo, Sem artefato, Desatualizadas, Geradas pela IA, Por cadeia) e personalizados. Agrupar por subsistema, ferramenta, recurso ou estado. Ordenar por qualquer coluna. Realçar sem esconder. |
| PJ-V09 | P0 | Modo dividido (Formulário de tarefas) | O painel de propriedades à direita faz o papel do Formulário de tarefas: editar a seleção sem sair da vista (ver [LAYOUT.md](LAYOUT.md)). |
| PJ-V10 | P1 | Personalizar estilos de barra | Estilos de barra por tipo de tarefa e ferramenta, usando as cores das ferramentas na bandeja. |

## 11. Relatórios

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-P01 | P1 | Painéis: Visão geral do projeto, Tarefas a começar, Tarefas atrasadas, Tarefas críticas | Relatório HTML imprimível (padrão do MultiAssembly e do MultiPhysics): visão geral (% concluído, marcos, término previsto), próximas tarefas, atrasadas e críticas. |
| PJ-P02 | P1 | Visão geral de custo, de trabalho, Burndown | Custo planejado × real, trabalho por recurso e burndown de trabalho e de tarefas. |
| PJ-P03 | P1 | (próprio) Relatório de artefatos | Lista de tarefas × arquivo vinculado × estado × data, com os critérios de aceite e as evidências. É o "dossiê" do objetivo. |
| PJ-P04 | P1 | Imprimir modo de exibição (escala, legenda, páginas) | Impressão do Gantt e da rede com escala de tempo, legenda e cabeçalho do projeto. Saída em PDF (mesmo caminho da fase 5 do MultiAssembly). |
| PJ-P05 | P2 | Relatórios visuais (Excel/Visio) | Exportar o uso por período em CSV para planilha. |

## 12. Multiprojeto

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-M01 | P2 | Projeto mestre e subprojetos inseridos | Inserir outro `.mproj` como tarefa de resumo vinculada (subsistema desenvolvido à parte). |
| PJ-M02 | P2 | Pool de recursos | Arquivo de pool da oficina com máquinas e pessoas, e superalocação entre projetos. |
| PJ-M03 | P2 | Vínculos entre projetos | Predecessora externa, somente leitura. |

## 13. Importação e exportação

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-X01 | P0 | Formato nativo `.mpp` | Formato nativo **`.mproj`** em JSON (ver [ARCHITECTURE.md](ARCHITECTURE.md)), com ponto decimal invariante e caminhos relativos. O `.mpp` é binário e proprietário: não lemos. |
| PJ-X02 | P1 | XML do Project (MSPDI) | Exportar e importar o XML do Microsoft Project (tarefas, EAP, vínculos, latência, restrições, calendários, recursos, atribuições e linha de base), para abrir o plano no Project, no ProjectLibre ou no GanttProject. Teste de ida e volta sem perda dos campos mapeados. Os campos próprios (ferramenta, artefato, especificações) vão em campos estendidos. |
| PJ-X03 | P1 | Exportar para Excel/CSV | Exportar a tabela visível em CSV com ponto decimal. Importar a lista de tarefas de um CSV (nome, descrição, duração, predecessoras). |
| PJ-X04 | P1 | Salvar como PDF | Ver PJ-P04. |

## 14. Edição e colaboração

| ID | P | Microsoft Project | MultiProject: requisito e aceite |
|---|---|---|---|
| PJ-U01 | P0 | Desfazer em vários níveis | Desfazer e refazer em vários níveis (Ctrl+Z/Y), inclusive para as tarefas geradas por regra ou pela IA, que entram como um único passo. |
| PJ-U02 | P0 | Realce de alterações | Depois de editar, realçar as datas que mudaram com o recálculo. |
| PJ-U03 | P0 | Atalhos (Ctrl+N/O/S, Insert, Delete, recuar, vincular Ctrl+F2) | Atalhos da suíte e do Project: Insert insere tarefa, Ctrl+F2 vincula a seleção em cadeia TI, Ctrl+Shift+F2 desvincula, Shift+F2 abre as informações da tarefa. |
| PJ-U04 | P2 | Atualização de status pela equipe (Project Online/SharePoint) | Arquivo de atualização: cada pessoa exporta e importa o progresso das próprias tarefas. Sem servidor. |
| PJ-U05 | N/A | Macros VBA | Fora do escopo. A automação vem pela CLI (PJ-Q05) e pela IA (PJ-I*). |
| PJ-U06 | N/A | Project Online/Server, timesheets | Fora do escopo: a suíte é desktop e local. |

---

## 15. Vínculo com as ferramentas da suíte (próprio do MultiProject)

| ID | P | Requisito e aceite |
|---|---|---|
| PJ-L01 | P0 | Cada tarefa tem **tipo**, e o tipo define a ferramenta, a extensão e a pasta padrão (tabela em [ARCHITECTURE.md](ARCHITECTURE.md#tipos-de-tarefa)). |
| PJ-L02 | P0 | **Abrir na ferramenta:** sem arquivo vinculado, o MultiProject propõe o nome `<pasta>/<ID>_<nome>.<ext>` dentro da raiz do projeto e abre a ferramenta com `--project`, `--new` e `--task` (D4). Com arquivo, usa `--file`. Usa `TSuiteLauncher` e `TSuiteRegistry`. |
| PJ-L03 | P0 | A especificação técnica e a funcional vão para a ferramenta num arquivo de contexto `<arquivo>.task.json`, para que a ferramenta mostre "o que esta peça precisa atender". As ferramentas que ainda não leem o arquivo o ignoram, e nada quebra. |
| PJ-L04 | P0 | **Detecção do artefato:** ao voltar o foco e a cada 2 s com a janela ativa, conferir existência, tamanho, data e hash dos arquivos vinculados. Arquivo novo vira "criado" e pode ser vinculado; arquivo alterado depois de "Pronta" marca a tarefa e as sucessoras com vínculo de artefato como **desatualizadas**. |
| PJ-L05 | P0 | **Validação mínima por tipo** antes de aceitar "pronto": o arquivo abre (JSON válido nos formatos JSON da suíte). Depois, um verificador por tipo: `.mcad` com pelo menos um corpo; `.mpcb` com DRC sem erro e pasta Gerber + Excellon gerada; `.massembly` com todas as peças das predecessoras; `.mphys` com resultado; G-code aceito por `SuiteCheckGCode` e com o cabeçalho `MS-...` do [contrato](../../docs/CONTRATO_GCODE.md). Verificação ausente aparece como "não verificado", nunca como aprovado. |
| PJ-L06 | P0 | **Estados da tarefa:** Sugerida → Planejada → Em andamento → Pronta para revisão → Concluída, mais Bloqueada (predecessora TI não concluída), Desatualizada e Cancelada. Não é possível concluir uma tarefa com predecessora TI aberta, sem artefato válido (quando o tipo exige) ou com critério de aceite pendente. |
| PJ-L07 | P0 | **Fabricação nunca executa na máquina.** A tarefa de fabricação vincula o arquivo preparado e o botão "Abrir no MultiCNC" abre o MultiCNC com `--file`. Executar, posicionar o zero e fazer o Frame continuam no MultiCNC. |
| PJ-L08 | P1 | **Estimativas automáticas:** a duração da fabricação vem do G-code (estimativa do `multicnc_gcode_preflight` / `multicnc_cli --check`) e do MultiSlicer (tempo e massa). A estimativa é sugerida com origem e data. |
| PJ-L09 | P1 | Registrar os artefatos também no `TWorkspace` da MultiSuite (D2), para que a bandeja e o MultiSuite mostrem os mesmos arquivos. |
| PJ-L10 | P1 | Tarefas de compra: a BOM do MultiAssembly gera itens de compra com quantidade, e a restrição SNET usa a data prevista de entrega. |

## 16. Regras de geração de tarefas (próprio do MultiProject)

As regras **propõem** tarefas no estado *Sugerida*. O usuário aceita, edita ou recusa cada
uma, sozinha ou em lote, e a aceitação é um único passo de desfazer. Nenhuma regra apaga
tarefa nem altera tarefa concluída.

| ID | P | Regra |
|---|---|---|
| PJ-A01 | P0 | **Processo da peça:** a peça mecânica com processo definido na especificação técnica (impressão 3D, router, corte laser, torno) gera a tarefa de fabricação correspondente, com vínculo TI e "entrega artefato" e máquina compatível sugerida. |
| PJ-A02 | P0 | **Placa:** a tarefa de eletrônica gera "Fabricar placa" (LaserPCB ou RouterPCB, conforme a máquina disponível) e, se houver componentes, "Comprar componentes". |
| PJ-A03 | P0 | **Montagem:** quando as tarefas de projeto (peça e eletrônica) de um subsistema (resumo) ou do objetivo ficam **prontas**, gera "Montagem virtual de <subsistema>" (MultiAssembly), com as tarefas como predecessoras TI com entrega de artefato. Montagem de subsistemas gera a montagem do objetivo. |
| PJ-A04 | P0 | **Validação:** a montagem pronta gera "Validar <subsistema>" (MultiPhysics). O tipo de estudo é sugerido pela especificação técnica: carga → estático, temperatura → térmico, rotação → modal, tensão/corrente → circuito. Os critérios funcionais mensuráveis viram critérios de aceite do estudo. |
| PJ-A05 | P0 | **Liberação:** a validação aprovada gera o marco "Liberado para fabricação", e as fabricações passam a depender dele (D6, configurável). |
| PJ-A06 | P0 | **Fechamento:** as fabricações geram "Montagem física" (checklist a partir do manual do MultiAssembly) → "Teste funcional" (todos os critérios funcionais do objetivo) → marco "Objetivo concluído". |
| PJ-A07 | P0 | **Reprovação:** a validação ou o teste reprovado gera a tarefa de revisão da peça ou placa apontada (PJ-G10), com a evidência anexada. |
| PJ-A08 | P0 | Cada tarefa gerada registra a regra de origem e as tarefas que a dispararam (indicador e filtro). Rodar a regra de novo não duplica a tarefa: a chave é regra + tarefas de origem. |
| PJ-A09 | P1 | Regras ligáveis e desligáveis por projeto. Modelos (PJ-T03) trazem o conjunto de regras. |

## 17. Inteligência artificial (próprio do MultiProject)

| ID | P | Requisito e aceite |
|---|---|---|
| PJ-I01 | P1 | **Decompor o objetivo:** a partir do objetivo, das descrições e dos critérios, a IA propõe subsistemas, tarefas (com os seis campos obrigatórios), tipo, processo, durações estimadas e vínculos, num **plano JSON** ([contrato](ARCHITECTURE.md#contrato-do-plano-da-ia)). |
| PJ-I02 | P1 | O plano passa por um **parser de contrato** determinístico: esquema, IDs, tipos conhecidos, vínculos válidos e ausência de ciclo. Um plano inválido é recusado com a lista de erros e não toca o documento. |
| PJ-I03 | P1 | O plano válido aparece como **proposta**: as tarefas ficam Sugeridas com o indicador "IA". O usuário aceita, edita ou recusa, e a aceitação é um passo de desfazer. |
| PJ-I04 | P1 | Provedores pela suíte **CHATGPT** do autor (vários provedores, inclusive local). A chave e o endpoint ficam na configuração do usuário, nunca no `.mproj`. Funciona desligada: sem IA, nada quebra. |
| PJ-I05 | P2 | Assistência pontual: detalhar a especificação técnica de uma tarefa, sugerir critérios de aceite mensuráveis, estimar a duração, explicar o caminho crítico. Sempre como sugestão revisável. |
| PJ-I06 | P0 | A IA **não executa** nada: não abre máquina, não altera arquivo de outra ferramenta e não marca tarefa como concluída. A IA também pode ser um recurso do tipo IA (PJ-R01), que registra quem fez a proposta. |

## 18. Qualidade

| ID | P | Requisito e aceite |
|---|---|---|
| PJ-Q01 | P0 | Núcleo (documento, grafo, calendário, cronograma, regras e I/O) sem dependência de LCL, testável no console, com testes no Linux e no Win64 (`tests/run_all.sh multiproject`). |
| PJ-Q02 | P0 | Números e datas invariantes no arquivo (ponto decimal, ISO 8601), independentemente da configuração regional (`multisuite_numfmt`). |
| PJ-Q03 | P0 | Projeto de 2.000 tarefas e 4.000 vínculos recalculado em menos de 200 ms, e Gantt rolando sem travar. |
| PJ-Q04 | P0 | Arquivo de versão futura ou corrompido gera diagnóstico e não sobrescreve. Salvar grava em arquivo temporário e renomeia (salvamento atômico). |
| PJ-Q05 | P1 | CLI `multiproject_cli`: `--check arquivo.mproj` (validar e recalcular), `--export-xml`, `--export-csv`. Usada nos testes e na CI. |
| PJ-Q06 | P0 | Tela testada em 1024 × 768 e DPI 100–200% sem esconder ações essenciais (mesmo critério do MultiAssembly). |
| PJ-Q07 | P0 | A janela principal é criada com `Application.CreateForm` (regra 12 do guia da suíte). |

## Referências

- [M1] Microsoft. *Link tasks in a project*. <https://support.microsoft.com/en-us/project/link-tasks-in-a-project> (tipos TI/II/TT/IT, latência e antecipação, vínculo automático, caminho da tarefa).
- [M2] Microsoft. *Set a task start or finish date (constraint) for a task*. <https://support.microsoft.com/en-us/project/set-a-task-start-or-finish-date-constraint-for-a-task> (oito tipos de restrição).
- [M3] Microsoft. *Choose the right view of your project schedule*. <https://support.microsoft.com/en-au/project/choose-the-right-view-of-your-project-schedule> (Gantt, Calendário, Linha do tempo, Planejador de equipe).
- [M4] Microsoft. *Project management goal: Track progress*. <https://support.microsoft.com/en-us/project/project-management-goal-track-progress> (linha de base, acompanhamento, relatórios, valor agregado).
- [M5] Microsoft. *Predecessors (task field)* e *Successors (task field)*. <https://support.microsoft.com/en-US/project/predecessors-task-field>.

A transcrição em requisitos, as prioridades e as adaptações à MultiSuite são propostas deste
documento. Os demais recursos citados (EAP, tipos de tarefa, nivelamento, valor agregado,
MSPDI) seguem o comportamento conhecido do Project desktop e devem ser conferidos na ajuda
oficial ao implementar cada fase.
