# MultiProject — Layout no padrão da MultiSuite

Mesmo esqueleto do MakeRouter, do MultiSlicer e do MultiAssembly: `multisuite_controls`,
`multisuite_icons`, `SUITE_FONT` (Segoe UI 10) e a paleta `clSuite*`. As medidas são
referências a 100% de DPI e escalam com o sistema. Referência de código:
[`makerouter_main.pas`](../../makerouter/src/app/makerouter_main.pas).

## Esqueleto da janela

```text
+--------------------------------------------------------------------------------------------+
| [sikProject] MultiProject                     Gestão de projetos mecânicos e eletrônicos   |  TSuiteHeader 72 px
|              Motor DC didático  •  rev. A  •  alterado                      /  MultiSuite  |
+--------------+-----------------------------------------------------------+-----------------+
| 1 Objetivo   | [Gantt][Rede][Quadro][Equipe][Calendário][Linha do tempo] | PROPRIEDADES    |
| 2 Tarefas    | [Ajustar][+][-]  Filtro:[Todas v]  Agrupar:[EAP v] [Crít.]| (página da etapa|
| 3 Relações   +-----------------------------------------------------------+  ou da tarefa   |
| 4 Recursos   | EAP  ID     Nome              Ferram.  Dur.  Início ...   |  selecionada)   |
| 5 Cronograma | 1    T-0001 Motor DC didático           18d   26/10   ███ |                 |
| 6 Acompanhar | 1.1  T-0002  Carcaça do estator MultiCAD 1d  26/10   ██  |  Nome           |
| 7 Relatórios | 1.2  T-0003  Eixo do rotor      MultiCAD 4h  26/10   █   |  ID  T-0002     |
|              | ...                                                ◆      |  Descr. curta   |
| [Novo][Abrir]|                                                           |  Descr. longa   |
| [Salvar][Demo]                                                           |  Espec. técnica |
|              |                                                           |  Espec. funcion.|
| CADEIAS      |                                                           |  Vínculo        |
|  ▸ Cadeia 1  |                                                           |  [Abrir no      |
|  ▸ Cadeia 2  |                                                           |   MultiCAD]     |
| SUGESTÕES (3)|                                                           |                 |
+--------------+-----------------------------------------------------------+-----------------+
| ● 2 avisos  •  Término previsto 13/11/2026  •  Crítico: 9 tarefas     [Validar] [Gerar     |  rodapé 66 px
|   Selecionada: T-0002 (em paralelo com T-0003..T-0005)                 tarefas] [Abrir na  |
|                                                                        ferramenta]         |
+--------------------------------------------------------------------------------------------+
  lateral 214 px                    área central (alClient)                  painel 336 px
```

| Área | Requisito |
|---|---|
| Cabeçalho | `TSuiteHeader`, 72 px: `Header.Setup('MultiProject', 'Gestão de projetos mecânicos e eletrônicos  /  MultiSuite', sikProject)`. A segunda linha mostra o projeto, a revisão e o indicador de alteração não salva. |
| Lateral esquerda | `TPanel` de 214 px, `clSuiteCard`, com as 7 etapas em `TSuiteButton` (190 × 34, passo de 44 px), Novo/Abrir/Salvar/Demo (92 × 34), a lista **CADEIAS** (os grafos do projeto, PJ-G04: clicar filtra) e a lista **SUGESTÕES** (tarefas propostas por regra ou IA, com aceitar/recusar). |
| Barra da vista | `TPanel` de 52 px, `clSuiteSurface`, com os botões de vista (o ativo em `sbsSolid`), ajustar/zoom, filtro, agrupamento e a caixa "Críticas". |
| Área central | A vista ativa (Gantt, Rede, Quadro, Equipe, Calendário ou Linha do tempo), em `TCustomControl` próprio desenhado no Canvas, como as vistas do MakeRouter. A troca de vista mantém a seleção. |
| Painel direito | `TPageControl` de 336 px sem abas (`ShowTabs := False`), uma página por etapa, cada uma com `TScrollBox` em `clSuiteCard`, título em negrito e campos de 290 px (`LabelAt`/`Field`/`Combo`, como no MakeRouter). Com uma tarefa selecionada, a página **Tarefa** substitui a da etapa (equivale ao Formulário de tarefas do Project). Esc volta para a página da etapa. |
| Rodapé | `TPanel` de 66 px, `clSuiteCard`: estado com o indicador `clSuiteSuccess`/`Warning`/`Danger`, término previsto e número de críticas, seleção e a relação dela (em cadeia ou em paralelo). Botões à direita: **Validar** (`sikTests`), **Gerar tarefas** (`sikWand`) e **Abrir na ferramenta** (`sbsSolid`, `sikSend`), que muda de rótulo conforme o tipo ("Abrir no MultiCAD", "Abrir no MakePCB", "Abrir no MultiCNC"…). |

## Sete etapas laterais

| Etapa | Ícone | Página do painel |
|---|---|---|
| **1 Objetivo** | `sikTarget` | Nome, descrição curta e longa, escopo, critérios de sucesso, início, agendar a partir de, calendário, modelo de origem, pasta raiz, revisão. Botão **Decompor com IA** (fase 9). |
| **2 Tarefas** | `sikLayers` | Inserir tarefa por tipo (menu com os ícones das ferramentas), resumo, marco, recuar/avançar, mover, excluir e duplicar. Abre na vista Gantt. |
| **3 Relações** | `sikArrowRight` | Tipo de vínculo padrão, lista de predecessoras e sucessoras da seleção (tipo, latência, entrega artefato), "vincular em cadeia" e "desvincular". Abre na vista Rede. |
| **4 Recursos** | `sikGear` | Planilha de recursos, **Importar máquinas do MultiCNC**, calendários e exceções. Abre na vista Equipe. |
| **5 Cronograma** | `sikPulse` | Recalcular, avisos, caminho crítico, nivelar e limpar nivelamento, linhas de base (definir e comparar). |
| **6 Acompanhar** | `sikGauge` | Data de status, atualizar projeto, % concluído em lote, artefatos (estado, verificar todos), critérios de aceite pendentes e valor agregado. Abre no Quadro. |
| **7 Relatórios** | `sikExport` | Relatório HTML, dossiê de artefatos, imprimir ou PDF do Gantt e da rede, exportar XML do Project e CSV. |

A navegação é livre. Mudar de etapa só troca o painel e a vista sugerida, sem perder nada.

## Página da tarefa (painel direito)

Seções em ordem, cada uma com título `fsBold` e `clSuiteMuted` para o rótulo dos campos:

1. **Identificação:** Nome, ID (somente leitura), Tipo (combo com ícone), Processo (para
   peça), Estado e Modo (auto/manual).
2. **Descrições:** Descrição curta (`TEdit`), Descrição longa (`TMemo`, 120 px).
3. **Especificação técnica:** grade chave/valor/unidade (`TStringGrid`, 3 colunas, + / −) e
   texto livre.
4. **Especificação funcional:** lista de critérios com estado (`TSuiteBadge` pendente,
   aprovado, reprovado) e evidência.
5. **Datas:** duração (`8h`, `2d`, `14eh`), início e término calculados (somente leitura no
   modo auto), restrição, data, data limite e prioridade.
6. **Vínculo com a ferramenta:** caminho do artefato, estado (badge), última verificação,
   mensagem do verificador e os botões **Abrir na ferramenta**, **Vincular arquivo...**,
   **Verificar** e **Marcar pronta**.
7. **Predecessoras e sucessoras:** grade com ID, nome, tipo, latência e artefato.
8. **Recursos:** grade com recurso, unidades e quantidade. Para fabricação, combo só com as
   máquinas compatíveis.
9. **Origem e anotações:** quem criou (usuário, regra Axx ou IA), tarefas de origem,
   anotações e anexos.

## Vistas centrais

| Vista | Desenho |
|---|---|
| **Gantt** | Tabela à esquerda com colunas configuráveis e divisor arrastável. Escala de tempo com duas faixas (mês/semana ou semana/dia) e barras de 14 px: tarefa em `clSuitePrimary`, crítica em `clSuiteDanger`, resumo em `clSuiteNavy` com pontas, marco como losango, linha de base em `clSuiteFaint` sob a barra, progresso como faixa interna mais escura. Setas de vínculo em cotovelo. Fim de semana e feriado sombreados. Linha da data de status em `clSuiteWarning`. Um ícone da ferramenta antes do nome. |
| **Rede** | Caixas de 180 × 72 (ID, nome, ícone, início/término, duração, margem) em camadas da ordem topológica, cadeias empilhadas e separadas por título. Borda vermelha nas críticas, tracejada nas sugeridas. Arrastar de uma caixa a outra cria o vínculo TI, e Alt troca o tipo. Clique realça o caminho da tarefa (PJ-G08). |
| **Quadro** | Colunas por estado com cartões (ícone da ferramenta, ID, nome, recurso, término e badge do artefato). Arrastar muda o estado, e um movimento recusado volta e explica o motivo no rodapé. |
| **Equipe** | Uma linha por recurso, pessoas primeiro e máquinas depois (com o ícone do tipo), com as barras no tempo e a superalocação em `clSuiteDanger` hachurado. Arrastar entre linhas reatribui. |
| **Calendário** | Mês ou semana com as barras e marcos. |
| **Linha do tempo** | Faixa única com os marcos e as tarefas marcadas "mostrar na linha do tempo". Exporta PNG. |

## Registro na suíte

- `stiMultiProject` **no fim** de `TSuiteToolID`, ícone `sikProject` **no fim** de
  `TSuiteIconKind` (os ordinais aparecem em caches) e entrada em `TSuiteRegistry`:
  `Add(stiMultiProject,'MultiProject','Gestao de projetos mecanicos e eletronicos','multiproject','multiproject/src/app/multiproject.lpi')`.
- Glifo de `sikProject`: três barras horizontais deslocadas, como um Gantt, com um losango
  na ponta. Cor na bandeja: índigo `C(79, 70, 229)`, diferente das demais.
- Bandeja e MultiSuite: novo grupo **PLANEJAR** antes de PROJETAR, contendo só o MultiProject
  (D1).
- `TArtifactKind`: acrescentar `akProject` no fim, para o `.mproj` aparecer no workspace.

## Comportamento

- Ctrl+N/O/S, Ctrl+Z/Y, Delete, Insert (nova tarefa abaixo), Alt+Shift+→/← (recuar e
  avançar), Ctrl+F2 (vincular a seleção em cadeia TI), Ctrl+Shift+F2 (desvincular), Shift+F2
  (página da tarefa), F9 (recalcular) e F5 (verificar artefatos).
- Edição na tabela com Enter/Tab, como numa planilha. Duração e predecessoras aceitam a
  sintaxe do Project (`2d`, `4h?`, `T-0003TI+2h`).
- Mensagens dizem a tarefa, o problema e a correção ("T-0020 começa antes de T-0002
  terminar: o vínculo TI foi recusado porque fecharia o ciclo T-0020 → T-0011 → T-0002").
- Testar em 1024 × 768, com a janela redimensionada e DPI de 100%, 125%, 150% e 200%.
