# MultiProject — Arquitetura

Proposta para as fases 1 a 10 de [TAREFA.md](TAREFA.md). Os nomes de unidades e tipos abaixo
são **requisitos de arquitetura**, não APIs existentes.

## Princípios

1. **Núcleo sem LCL.** Documento, grafo, calendário, cronograma, regras, I/O e contrato da IA
   compilam no console (`fpc`) e têm teste próprio. A interface só chama o núcleo.
2. **Uma fonte da verdade.** O `.mproj` guarda o plano. Os arquivos das outras ferramentas
   ficam **referenciados** por caminho relativo e hash, nunca copiados para dentro dele.
3. **Propor, não impor.** Regras e IA produzem *propostas* (tarefas Sugeridas). Só o usuário
   promove uma proposta a plano.
4. **Nada de máquina aqui.** O MultiProject abre o MultiCNC com o arquivo; não fala com
   transporte nem protocolo (regra 3 do [guia da suíte](../../docs/AI_TOOLS_GUIDE.md)).
5. **Reutilizar o CHATGPT primeiro.** O que é genérico vira componente em
   `CHATGPT/pacote/AI Project Core` e o MultiProject só adapta:
   - `aiprojectduration`, `aiundohistory` e `aijsonutils` (fase 1);
   - `aitaskgraph` (fase 2);
   - `aiworkcalendar` e `aicpmscheduler` (fase 3);
   - `aiplancontract` (fase 9).

   Veja [TAREFA.md](TAREFA.md#reuso-da-suíte-chatgpt).
6. **Reutilizar a MultiSuite:** `multisuite_controls`/`icons` (tela), `multisuite_context`/
   `launcher`/`registry` (abrir ferramentas), `multisuite_workspace` (artefatos), `multisuite_numfmt`
   (números), `multicnc_equipment` (máquinas), `multisuite_gcode_writer.SuiteCheckGCode` e
   `multicnc_gcode_preflight` (validar e estimar G-code).

## Árvore de fontes

```text
multiproject/
  README.md
  docs/               REQUISITOS, ARCHITECTURE, LAYOUT, TAREFA, AI_GUIDE
  src/core/           multiproject_types        enums, registros, IDs
                      multiproject_document     projeto, objetivo, árvore EAP, comandos + desfazer (TAIUndoHistory)
                      multiproject_graph        adaptador documento -> aitaskgraph (CHATGPT)
                      multiproject_calendar     adaptador -> aiworkcalendar (CHATGPT)
                      multiproject_schedule     adaptador -> aicpmscheduler (CHATGPT), avisos com a tarefa
                      multiproject_resources    recursos, atribuições, superalocação, nivelamento
                      multiproject_cost         taxas, custo fixo, acumulação
                      multiproject_tracking     linhas de base, progresso, atualizar projeto
                      multiproject_evm          valor agregado
  src/io/             multiproject_json         .mproj (fpjson), migração de schema_version
                      multiproject_mspdi        XML do Microsoft Project (ida e volta)
                      multiproject_csv          exportar/importar tabela
                      multiproject_report       relatório HTML
  src/integration/    multiproject_kinds        tipo de tarefa -> ferramenta, extensão, pasta, verificador
                      multiproject_artifacts    vínculo, hash, estado, detecção de mudança, desatualização
                      multiproject_checks       verificadores por tipo (.mcad, .mpcb, .massembly, .mphys, G-code)
                      multiproject_rules        regras PJ-A01..A09
                      multiproject_estimates    duração por G-code/MultiSlicer
                      multiproject_equipment    máquinas de multicnc.json como recursos (somente leitura)
                      multiproject_taskctx      arquivo <artefato>.task.json para a ferramenta
  src/ai/             multiproject_ai_contract  esquema e parser determinístico do plano
                      multiproject_ai_planner   montagem do prompt e chamada pela suíte CHATGPT
  src/view/           multiproject_gantt        tabela + barras (TCustomControl)
                      multiproject_network      diagrama de rede (grafo em camadas)
                      multiproject_board        quadro por estado
                      multiproject_planner      planejador de equipe / máquinas
                      multiproject_calview      calendário e linha do tempo
  src/app/            multiproject.lpi/.lpr     Application.CreateForm(TMultiProjectForm)
                      multiproject_main         tela da suíte (ver LAYOUT.md)
                      multiproject_cli.lpr      --check / --export-xml / --export-csv
  tests/              test_multiproject_core, _graph, _calendar, _schedule, _rules, _io, _ui
  examples/           motor_dc.mproj (exemplo do README)
models/multiproject/  modelos .mproj (Peça impressa, Placa, Motor DC, Máquina CNC)
```

## Modelo de dados

### Projeto

| Campo | Tipo | Observação |
|---|---|---|
| `schema_version` | inteiro | começa em 1; leitura migra versões antigas |
| `id`, `name`, `revision`, `author` | texto | |
| `objective` | Objetivo | `short`, `long`, `scope`, `success` (critérios do objetivo) |
| `start`, `status_date` | data ISO | `schedule_from`: `start` ou `finish` |
| `calendar` | ID de calendário | calendário do projeto |
| `options` | registro | `minutes_per_day`, `minutes_per_week` (inteiros), limiar crítico, recalcular automático, regras ativas, `fabrication_gate` (D6) |
| `next_task_number` | inteiro | gera `T-0001…`, nunca reaproveitado |
| `tasks`, `links`, `resources`, `assignments`, `calendars`, `baselines`, `custom_fields` | listas | |

### Tarefa

| Campo | Obrig. | Observação |
|---|---|---|
| `id` | sim | `T-0001` (tarefa) ou `M-0001` (marco); estável |
| `name` | sim | |
| `short` | sim | descrição curta (uma linha) |
| `long` | não | descrição longa (texto, pode ter Markdown) |
| `tech_spec` | não | `{ "items": [ {key, value, unit} ], "text": "" }` |
| `func_spec` | não | `[ {id, text, state: pending/passed/failed/waived, evidence} ]` (critérios de aceite) |
| `parent` | — | ID da tarefa de resumo (vazio = filha do objetivo); a ordem dos irmãos é a ordem da lista |
| `kind` | sim | ver [tipos](#tipos-de-tarefa) |
| `process` | não | para peça: `print3d`, `router`, `laser_cut`, `lathe`, `none` |
| `state` | sim | `suggested`, `planned`, `in_progress`, `review`, `done`, `blocked`, `outdated`, `cancelled` |
| `mode` | sim | `auto` ou `manual` |
| `duration` | sim | minutos inteiros; `elapsed` (bool); `estimated` (bool) |
| `task_type` | não | `fixed_duration` (padrão), `fixed_units`, `fixed_work`; `effort_driven` |
| `constraint` | não | `{type: ASAP/ALAP/SNET/SNLT/FNET/FNLT/MSO/MFO, date}` |
| `deadline` | não | data |
| `priority` | não | 0–1000, padrão 500 |
| `calendar` | não | calendário da tarefa |
| `manual_start`, `manual_finish` | não | só no modo manual |
| `progress` | não | `percent`, `actual_start`, `actual_finish`, `remaining` |
| `artifact` | não | `{path, tool, hash, size, mtime, status: none/created/valid/ready, checked_at, check_msg}` |
| `origin` | não | `{by: user/rule/ai, rule, sources:[IDs], ai_plan}` |
| `inactive`, `notes`, `attachments`, `fixed_cost`, `custom` | não | |

O código EAP, as datas calculadas, as margens e o crítico **não são gravados**: são
recalculados ao abrir. Isso evita arquivos inconsistentes. A linha de base é gravada, porque
é uma foto.

### Vínculo (aresta do grafo)

| Campo | Observação |
|---|---|
| `from`, `to` | IDs das tarefas (predecessora → sucessora) |
| `type` | `FS` (TI), `SS` (II), `FF` (TT), `SF` (IT) |
| `lag` | minutos (negativo = antecipação) ou `lag_pct` (% da duração da predecessora) |
| `elapsed` | latência decorrida (cura, secagem) |
| `artifact` | bool: a sucessora consome o artefato da predecessora (PJ-G06) |

### Recurso e atribuição

| Recurso | Campos |
|---|---|
| comum | `id` (`R-001`), `name`, `type` (`person`, `ai`, `machine`, `material`, `cost`), `max_units` (em %: 100 = uma pessoa ou máquina), `calendar`, `group`, `rate` e `per_use` (fase 7.5) |
| pessoa | `role` (função), `email` |
| máquina | `equipment` (nome do equipamento no `multicnc.json`), `machine_type` (`router`, `laser`, `printer3d`, `lathe`, `other`), `work_volume` |
| material | `unit` (kg, m², un), `unit_cost` |

Atribuição: `{task, resource, units, quantity, source}`, com `units` em % (50 = meio período)
e `quantity` na unidade do material. A tarefa guarda `priority` (0–1000) e `level_start`
(atraso do nivelamento, "não iniciar antes de"; vazio sem nivelamento). `source` diz se o valor veio do
usuário, do MultiSlicer (massa) ou da BOM.

## Tipos de tarefa

`multiproject_kinds` é a única tabela que liga tipo → ferramenta. As regras, a tela e os
verificadores leem dela.

| `kind` | Grupo | Ferramenta (`TSuiteToolID`) | Extensão | Pasta padrão | Máquina exigida | Verificador "válido" |
|---|---|---|---|---|---|---|
| `summary` | — | — | — | — | — | — |
| `milestone` | — | — | — | — | — | — |
| `general` | gestão | — | — | — | — | — |
| `purchase` | gestão | — | — | — | — | — |
| `part` | projeto | `stiMultiCAD` | `.mcad` | `pecas/` | — | JSON válido e ≥ 1 corpo |
| `electronics` | projeto | `stiMakePCB` | `.mpcb` | `eletronica/` | — | DRC sem erro e pasta Gerber+Excellon |
| `assembly` | integração | `stiMultiAssembly` | `.massembly` | `montagem/` | — | contém as peças das predecessoras com `artifact=true` |
| `validation` | integração | `stiMultiPhysics` | `.mphys` | `simulacao/` | — | estudo com resultado |
| `print3d` | fabricação | `stiMultiSlicer` → `stiMultiCNC` | `.mslice` + `.gcode` | `fabricacao/impressao/` | `printer3d` | G-code aceito + cabeçalho `MS-MACHINE: printer3d` |
| `router` | fabricação | `stiMakeRouter` ou `stiMultiCAM` → `stiMultiCNC` | `.mrouter` / `.gcode` | `fabricacao/router/` | `router` | G-code aceito + `MS-MACHINE: router` |
| `laser_cut` | fabricação | `stiLaserArt` → `stiMultiCNC` | `.lart` + `.gcode` | `fabricacao/laser/` | `laser` | G-code aceito + `MS-MACHINE: laser` |
| `laser_art` | fabricação | `stiLaserArt` → `stiMultiCNC` | `.lart` + `.gcode` | `fabricacao/laser/` | `laser` | idem |
| `lathe` | fabricação | — (D7) | `.pdf`/`.md` (folha de processo) | `fabricacao/torno/` | `lathe` | folha de processo anexada |
| `pcb_fab` | fabricação | `stiLaserPCB` ou `stiRouterPCB` → `stiMultiCNC` | `.gcode` | `fabricacao/placas/` | `laser` ou `router` | G-code aceito |
| `physical_assembly` | fechamento | — | — | — | — | checklist concluído |
| `functional_test` | fechamento | — | — | — | — | critérios funcionais aprovados |

Novos tipos entram **no fim** do enum, porque os ordinais podem ir para cache, como em
`TSuiteToolID` e `TSuiteIconKind`. No arquivo o tipo é gravado como texto.

## Grafo: lista de adjacência

```pascal
type
  TPJEdge = record
    Link: Integer;          // índice no vetor de vínculos do documento
    Other: Integer;         // índice da tarefa na outra ponta
  end;
  TPJAdjacency = array of array of TPJEdge;

  TPJGraph = class
    Succ, Pred: TPJAdjacency;      // por índice de tarefa
    Component: array of Integer;   // cadeia (componente conexo, sem considerar direção)
    TopoOrder: array of Integer;   // ordem topológica (Kahn)
    function Build(Doc: TPJDocument): Boolean;           // falso = ciclo
    function WouldCycle(AFrom, ATo: Integer; out Path: TIntArray): Boolean;
    function Chains: TPJChainList;                        // a "lista de grafos" (PJ-G04)
    function DrivingPredecessors(T: Integer): TIntArray;  // caminho da tarefa (PJ-G08)
  end;
```

- **Encadeada** = existe caminho de A até B. **Paralela** = nenhum caminho entre A e B em
  nenhum sentido. A tela usa essa definição para os rótulos "em cadeia" e "em paralelo".
- `WouldCycle` faz uma busca a partir de `ATo`. Se alcança `AFrom`, devolve o caminho para a
  mensagem de erro (PJ-G05). O custo é O(V+E) por vínculo novo.
- Vínculos em tarefa de resumo são expandidos no cálculo: valem para as folhas.
- `Component` usa união-busca. Cada componente é uma "cadeia" na lista lateral e no filtro.

## Cronograma (CPM)

O algoritmo genérico fica no `aicpmscheduler` do CHATGPT (fase 3). O MultiProject entrega as
tarefas, os vínculos e os calendários e recebe as datas.

Unidade interna: **minuto útil** (`Int64`), contado a partir da data de início do projeto em
cada calendário. `multiproject_calendar` converte entre data/hora e minuto útil e soma
durações respeitando o expediente e as exceções. Duração decorrida usa o calendário 24 Horas.

1. Montar o grafo e a ordem topológica. Se houver ciclo, para com aviso (não deveria ocorrer:
   a edição já recusa).
2. **Ida** (na ordem topológica): o início mais cedo é o máximo, entre as predecessoras, de
   - TI: `EF(p) + lag`;
   - II: `ES(p) + lag`;
   - TT: `EF(p) + lag - dur`;
   - IT: `ES(p) + lag - dur`.

   Depois aplicar SNET/FNET (empurram), MSO/MFO (fixam e geram aviso se conflitam) e o modo
   manual (fica onde está e gera aviso).
3. **Volta** (na ordem inversa): o término mais tarde é o mínimo análogo sobre as sucessoras,
   partindo do término do projeto (ou da data de término, se agendar pelo término). Aplicar
   SNLT/FNLT/MSO/MFO e a data limite (só aviso).
4. Margem total = `LS - ES`; margem livre = `min(ES(s)) - EF` sobre as sucessoras TI. Crítica
   = margem total ≤ limiar.
5. ALAP: a tarefa é colocada no fim da sua margem livre.
6. Resumos agregam as filhas: início mínimo, término máximo, trabalho e custo somados, %
   ponderado pela duração.
7. Nivelamento (fase 7) roda depois e só atrasa: ordena as tarefas superalocadas por
   prioridade, margem e ID e as empurra até o recurso ficar livre.

Teste de referência: o exemplo do motor com durações conhecidas, calculado à mão em planilha
e gravado como valores esperados em `test_multiproject_schedule.lpr`, mais os casos mínimos
de cada tipo de vínculo e restrição.

## Formato `.mproj` (JSON)

```json
{
  "schema_version": 1,
  "format": "MultiProject",
  "id": "P-2026-0001",
  "name": "Motor DC didático",
  "revision": "A",
  "objective": {
    "short": "Construir um motor DC escovado de 12 V para aula",
    "long": "Motor com carcaça impressa, eixo torneado, base em MDF e driver próprio.",
    "scope": "Uma unidade funcional e o dossiê de fabricação.",
    "success": [ { "id": "OK-1", "text": "3000 rpm ± 10% a 12 V sem carga", "state": "pending" } ]
  },
  "start": "2026-10-26T08:00:00",
  "status_date": "2026-10-26",
  "calendar": "padrao",
  "calendar": "padrao",
  "options": { "minutes_per_day": 480, "minutes_per_week": 2400, "critical_slack": 0,
               "fabrication_gate": true, "rules": ["A01","A02","A03","A04","A05","A06","A07"] },
  "next_task_number": 33,
  "tasks": [
    { "id": "T-0002", "name": "Carcaça do estator", "short": "Carcaça que fixa os ímãs",
      "long": "", "kind": "part", "process": "print3d", "state": "planned", "mode": "auto",
      "duration": 480, "duration_unit": "d", "elapsed": false, "estimated": false, "parent": "T-0001",
      "constraint": { "type": "SNET", "date": "2026-10-27T08:00:00" }, "deadline": "",
      "manual_start": "", "manual_finish": "", "calendar": "",
      "tech_spec": { "items": [ { "key": "material", "value": "PETG", "unit": "" },
                                { "key": "diametro_externo", "value": "60", "unit": "mm" } ],
                     "text": "Encaixe H7 para o rolamento 608." },
      "func_spec": [ { "id": "F-1", "text": "Suporta 60 °C sem deformar", "state": "pending" } ],
      "artifact": { "path": "pecas/T-0002_carcaca_do_estator.mcad", "tool": "MultiCAD",
                    "status": "none" },
      "origin": { "by": "user" } }
  ],
  "links": [ { "from": "T-0002", "to": "T-0020", "type": "FS", "lag": 0, "lag_unit": "d",
               "lag_elapsed": false, "lag_is_percent": false, "lag_percent": 0, "artifact": true } ],
  "resources": [ { "id": "R-001", "name": "Ender-3", "type": "machine", "machine_type": "printer3d",
                   "equipment": "Ender-3", "max_units": 100, "calendar": "24h" } ],
  "assignments": [ { "task": "T-0020", "resource": "R-001", "units": 100, "quantity": 0 } ],
  "calendars": [ { "name": "padrao", "week": [[], [[480,720],[780,1020]], "...", []],
                   "exceptions": [ { "date": "2026-11-02", "name": "Finados", "intervals": [] } ] },
                 { "name": "24h", "week": [[[0,1440]], "..."], "exceptions": [] } ],
  "baselines": [], "custom_fields": []
}
```

Regras do arquivo:
- Datas em ISO 8601 local, sem fuso (as datas são de oficina).
- Números com ponto decimal, sempre.
- Caminhos relativos à pasta do `.mproj`.
- Campos desconhecidos são preservados ao salvar (outra versão pode tê-los criado).
- O salvamento é atômico: grava em `.tmp`, confere e renomeia.

## Integração com as ferramentas

### Abrir uma tarefa na ferramenta (PJ-L02)

```text
<ferramenta> --project <raiz> --file <artefato>                       (artefato existe)
<ferramenta> --project <raiz> --new <artefato> --task <arquivo.task.json>   (artefato novo)
```

- `--new` e `--task` são **novos parâmetros** de `multisuite_context.ReadSuiteContext` (D4).
  Ele hoje lê só `--project` e `--file`. Os campos `NewFileName` e `TaskFile` entram no
  registro `TSuiteContext`, compatíveis para trás: uma ferramenta que ainda não os trata abre
  vazia com `--project`, e o MultiProject mostra "salve como `<artefato>`" com o caminho
  copiável.
- A adoção por ferramenta é gradual: MultiCAD e MakePCB na fase 5 (P0); MultiAssembly,
  MultiPhysics, MultiSlicer, MakeRouter e LaserArt em seguida.
- `TSuiteLauncher.LaunchArtifact` hoje recusa arquivo inexistente. O caminho `--new` vai num
  método novo (`LaunchNew`), sem mudar o atual.
- Existem duas unidades `multisuite_context.pas` iguais (`src/shared` e `multisuite/src/core`).
  A fase 5 unifica as duas ou altera as duas juntas, com o teste `multisuite/tests/test_context.lpr`.

### Arquivo de contexto da tarefa (PJ-L03)

`<artefato>.task.json`, escrito pelo MultiProject antes de abrir a ferramenta:

```json
{ "format": "MultiProject.Task", "schema_version": 1,
  "project": "../motor_dc.mproj", "task": "T-0002", "name": "Carcaça do estator",
  "short": "...", "long": "...", "tech_spec": { ... }, "func_spec": [ ... ],
  "inputs": [ "pecas/T-0003_eixo.mcad" ] }
```

`inputs` traz os artefatos das predecessoras com `artifact=true`. É assim que o
MultiAssembly sabe quais peças importar e o MultiSlicer sabe qual STL abrir.

### Detecção e validade (PJ-L04, PJ-L05)

- O estado do artefato é guardado no `.mproj` (`hash` SHA-1, `size`, `mtime`). Ao ativar a
  janela e a cada 2 s com ela ativa, compara só `size`/`mtime`. Se mudaram, recalcula o hash.
- Hash mudou numa tarefa `ready` ou `done`: a tarefa volta para `review`, e as sucessoras com
  `artifact=true` ficam `outdated`. Desatualização não se propaga sozinha além de um nível
  sem o usuário ver: a lista de avisos mostra a cadeia inteira.
- Os verificadores (`multiproject_checks`) leem os arquivos **sem** depender das units de tela
  das outras ferramentas. O `.mcad` e os demais formatos JSON são lidos com `fpjson` só nos
  campos necessários. O G-code passa por `SuiteCheckGCode` e `SuiteParseHeader`.

### Máquinas (PJ-R02)

`multiproject_equipment` usa `multicnc_equipment.TEquipmentStore` em **somente leitura**,
com o mesmo `EquipmentFileName` (inclusive a variável `MULTICNC_EQUIPMENT_FILE` para os
testes). O recurso guarda o nome do equipamento. Se o equipamento sumir do cadastro, o
recurso fica com aviso e não é apagado.

### MultiSuite (PJ-L09)

`TWorkspace` (`multisuite_workspace`) já tem artefatos e etapas (`wsDesign` … `wsExecution`).
O MultiProject registra ali os artefatos que vincula (D2). Ele não usa as etapas do workspace
como cronograma, mas atualiza o estado delas pelo estado agregado das tarefas de cada grupo.

## Contrato do plano da IA

A IA devolve **somente** JSON neste esquema. O parser (`TPJAIPlanContract.ParsePlan`) é
determinístico e recusa qualquer desvio, sem aplicar nada parcialmente:

```json
{ "format": "MultiProject.AIPlan", "schema_version": 1,
  "objective_ref": "P-2026-0001",
  "tasks": [
    { "ref": "a1", "parent_ref": "", "name": "...", "short": "...", "long": "...",
      "kind": "part", "process": "print3d", "duration": "8h",
      "tech_spec": { "items": [ { "key": "material", "value": "PETG", "unit": "" } ], "text": "" },
      "func_spec": [ "..." ] }
  ],
  "links": [ { "from_ref": "a1", "to_ref": "a2", "type": "FS", "lag": "0h", "artifact": true } ],
  "notes": "premissas e dúvidas da IA" }
```

Validação, em ordem:
1. Formato e versão.
2. `ref` único.
3. `kind` e `process` conhecidos.
4. Seis campos obrigatórios presentes (`name`, `short`; `long`, `tech_spec` e `func_spec`
   podem vir vazios, mas presentes).
5. Duração interpretável.
6. Vínculos com refs existentes e tipo válido.
7. Sem ciclo (com o grafo existente somado).
8. Limites: até 500 tarefas por plano.

O plano aprovado vira tarefas `suggested` com IDs novos e `origin.by = ai`. A tabela `ref →
ID` fica registrada em `origin.ai_plan`.

## Dependências entre fases e outras ferramentas

| Necessidade | Onde | Situação em 20/10/2026 |
|---|---|---|
| `--new` / `--task` no contexto | `multisuite_context` (2 cópias) | a fazer (fase 5) |
| Contorno da peça para corte laser | MultiCAD → LaserArt | o MultiCAD exporta DXF R12 do esboço e da face; o LaserArt importa SVG e imagem, mas não DXF. Falta a importação DXF no LaserArt (D8) |
| Peça mecânica para a router | MultiCAD → MultiCAM / MakeRouter | o MakeRouter ainda não importa DXF/SVG (fase 2 dele); o MultiCAM é o CAM de peça mecânica (D1 do MakeRouter, D9 aqui) |
| Torno | — | não há tipo de máquina torno no MultiCNC nem CAM de torneamento (D7) |
| Real das máquinas | log do MultiCNC | depende do BUG-016 (log persistente) |
