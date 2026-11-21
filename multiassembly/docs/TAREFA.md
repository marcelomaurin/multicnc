# TAREFA: MultiAssembly — montagem eletromecânica com referência no SolidWorks

- **Aberta em:** 14/10/2026.
- **Estado:** requisitos e plano de desenvolvimento documentados; as novas funções estão pendentes de implementação.
- **Solicitação:** usar o SolidWorks como referência funcional, preservar o layout dos outros projetos da MultiSuite e incluir elaboração de manual de montagem, listagem de peças e biblioteca de fixadores, rolamentos e motores DC/AC.
- **Base conferida:** branch `fila`, commit [752877afe6d190d28840b627d04c31575ff0d580](https://github.com/marcelomaurin/multicnc/tree/752877afe6d190d28840b627d04c31575ff0d580).
- **Visão:** [../README.md](../README.md).
- **Arquitetura atual:** [AI_GUIDE.md](AI_GUIDE.md).
- **Padrão de documentação:** [MakeRouter](../../makerouter/docs/TAREFA.md) e [RouterPCB](../../routerpcb/docs/TAREFA.md).
- **Referência de interface:** [controles da MultiSuite](../../multisuite/src/core/multisuite_controls.pas) e [tela do MakeRouter](../../makerouter/src/app/makerouter_main.pas).

## Objetivo

Transformar o MultiAssembly em uma ferramenta para **projetar uma montagem, verificar suas relações, elaborar a listagem de peças e preparar o manual que orienta sua montagem física**.

O usuário deve conseguir combinar peças do MultiCAD, placas do MakePCB e componentes de biblioteca em um conjunto: estrutura, parafusos, porcas, rebites, rolamentos, motores, fontes, drivers, sensores e cabos. Cada ocorrência mantém a mesma identidade na vista mecânica, no esquema elétrico, na BOM e nas etapas do manual.

Exemplo de entrega: montar uma pequena CNC ou um braço robótico, definir a posição das peças e seus vínculos, conferir conexões, gerar a lista de compra e produzir um manual ilustrado que mostre a sequência de instalação dos subconjuntos e fixadores.

A referência do SolidWorks orienta componentes, submontagens, relações geométricas, avaliação e documentação. A identidade visual e os controles seguem a **MultiSuite**.

## Progresso

| Fase | Estado em 14/10/2026 | Base disponível / entrega prevista |
|---|---|---|
| 0 Especificação | documentada | Este arquivo define requisitos, prioridades, layout, fases e aceite. |
| 1 Documento e persistência | pendente | O modelo atual mantém componentes, conexões e relações em memória; faltam documento persistente, ocorrências e hierarquia. |
| 2 Interface, biblioteca e montagem 3D | pendente | Há duas vistas demonstrativas; faltam editor, catálogo utilizável e cena 3D. |
| 3 Relações geométricas | pendente | Existem registros de relações; falta solver de montagem com diagnóstico. |
| 4 Conexões e verificação elétrica | parcial no núcleo | Reutilizar ERC existente e implementar edição gráfica e propriedades na interface. |
| 5 Listagem e manual de montagem | parcial no núcleo / manual pendente | Existe BOM CSV/JSON; falta acesso pela interface, catálogo completo e processo de elaboração do manual. |
| 6 Avaliação geométrica | pendente | Implementar interferências, folgas e propriedades da montagem. |
| 7 Integração e primeira entrega | parcial no núcleo | Existe exportador inicial para contrato unificado; faltam intercâmbio completo e fluxo de usuário. |
| 8 Recursos avançados | evolução posterior | Configurações, submontagens flexíveis, relações mecânicas avançadas e animação. |
| 9 Montagens grandes | evolução posterior | Carregamento seletivo, cache e medição de desempenho. |

**P0** = obrigatório na primeira entrega utilizável, fases 1 a 7. **P1** = evolução funcional. **P2** = refinamento e escala. Nenhum requisito novo abaixo deve ser marcado como implementado apenas por existir uma biblioteca ou este documento.

## O que os fontes atuais já entregam

| Área | Evidência no fonte | Situação |
|---|---|---|
| Modelo de componentes | `multiassembly_types.pas` | ID, nome, modelo, referência de origem, posição, rotação, tamanho e portas. |
| Projeto | `multiassembly_project.pas` | Coleções de componentes, fios e relações; rejeita ID de componente duplicado. |
| Interface | `multiassembly_main.pas` | Carrega CNC demonstrativa e sincroniza seleção em duas vistas. |
| Relações | `TMechanicalRelation` | Tipos fixed, axis, coupled, belt e lead screw, com eixo, relação e passo; não equivalem a um solver 3D. |
| ERC | `TAssemblyERC`, em `multiassembly_engineering.pas` | Verificação de acionamento, portas, tensão, alimentação, E-stop e referências. |
| Lista de materiais | `TAssemblyBOM` | Agrupamento e saídas CSV/JSON; a tela atual não oferece esse processo ao usuário. |
| Parâmetros de máquina | `TMachineConfigurator` | Cálculos e emissão de configurações GRBL/FluidNC no núcleo. |
| Intercâmbio físico | `ExportAssemblyToUnified` | Exporta componentes, posições e links; faltam transformações completas e propriedades detalhadas. |

O desenvolvimento deve ampliar essas bases. ERC, BOM e exportador existentes precisam ser adaptados ao modelo de ocorrências e conectados ao editor.

## Referência funcional: SolidWorks

Os conceitos abaixo foram conferidos na documentação oficial indicada em **Referências**. A tradução em requisitos, prioridades e arquitetura do MultiAssembly é uma proposta deste documento.

| Referência | Aplicação proposta no MultiAssembly |
|---|---|
| Árvore de montagem / FeatureManager [S1] | Hierarquia de peças, submontagens, relações e estados, sincronizada com as vistas. |
| Painel contextual / PropertyManager [S2] | Editar propriedades com prévia, Aplicar, Confirmar e Cancelar. |
| Relações de montagem / mates [S3, S4] | Posicionar componentes a partir de planos, eixos, pontos e superfícies compatíveis. |
| Avaliação de interferências [S5] | Localizar pares de peças em conflito e apresentar o nível de precisão da verificação. |
| BOM [S6] | Gerar listagem por quantidade, código, revisão e configuração, ligada às ocorrências. |
| Vista explodida e documentação [S7] | Apresentar como os componentes entram na montagem e ilustrar as etapas do manual. |
| Revisão de montagens grandes [S8] | Evoluir para abertura seletiva e visualização simplificada. |

O manual de montagem, o vínculo elétrico e o catálogo eletromecânico são requisitos próprios do MultiAssembly. A referência do SolidWorks fornece conceitos úteis para organizar esse processo.

## Layout: preservar o padrão da MultiSuite

Usar `multisuite_controls`, `multisuite_icons`, `SUITE_FONT` e a paleta `clSuite*`. As dimensões abaixo são referências a 100% de DPI, adaptadas do MakeRouter; devem escalar com o sistema e permitir redimensionamento.

| Área | Requisito |
|---|---|
| Cabeçalho | `TSuiteHeader`, referência de 72 px, nome MultiAssembly, projeto atual e indicação de alteração não salva. |
| Lateral esquerda | Navegação por seis etapas, referência de 214 px, Novo/Abrir/Salvar e árvore da montagem acessível em todas as etapas. |
| Árvore | Peças, submontagens, relações, conexões e etapas do manual; filtro por nome, código e ID; indicação de fixo, livre, oculto, suprimido ou com erro. |
| Área central | Vista 3D da montagem; alternância para esquema elétrico e prévia do manual. |
| Painel contextual | Referência de 336 px, propriedades, seleções, parâmetros e ações da etapa; rolagem própria. |
| Barra contextual | Comandos coerentes com a seleção: inserir, mover, girar, fixar, relacionar, ocultar, isolar, medir e enquadrar. |
| Rodapé | Referência de 66 px, estado, unidades, seleção, pendências e ações Validar, Gerar documentação e Abrir no MultiPhysics. |
| Componentes visuais | `TSuiteButton`, `TSuiteBadge` e títulos de seção compartilhados, com ícones e estados habilitado/desabilitado. |

### Seis etapas laterais

| Etapa | Conteúdo principal |
|---|---|
| **1 Projeto** | Identificação, unidades, referências, configurações iniciais, abrir/salvar e dependências. |
| **2 Componentes** | Importar peças/placas, biblioteca de fixadores, rolamentos, motores e demais componentes. |
| **3 Montagem** | Posicionar em 3D, fixar/liberar, criar submontagens e aplicar relações. |
| **4 Conexões** | Portas, alimentação, sinais, cabos e esquema elétrico sincronizado. |
| **5 Verificar** | Relações, graus de liberdade, interferências, folgas, ERC e dados ausentes. |
| **6 Documentar** | Listagem de peças, sequência de montagem, manual ilustrado, relatórios e intercâmbio. |

A navegação é livre: voltar a uma etapa deve conservar o trabalho. Alterações na montagem invalidam os resultados e documentos que dependem delas, com indicação visível de que precisam ser regenerados.

### Comportamento da interface

- Seleção na árvore, cena, esquema, BOM ou etapa do manual realça a mesma ocorrência.
- Ctrl/Shift permitem seleção múltipla; menus contextuais oferecem somente ações aplicáveis.
- Arrastar usa manipulador de translação/rotação; campos numéricos permitem posicionamento preciso.
- Componentes fixos ou restringidos respeitam suas condições durante o arraste.
- Ações com prévia só alteram o documento ao confirmar; Escape/Cancelar restaura o estado anterior.
- Ctrl+N/O/S, Ctrl+Z/Y, Delete e enquadramento da seleção seguem os padrões dos outros projetos.
- Testar 1024 × 768, janela redimensionada e DPI 100%, 125%, 150% e 200%, sem esconder ações essenciais.
- Mensagens mostram componente, problema e ação de correção; dados de implementação ficam nos logs.

## Requisitos funcionais

### Projeto, ocorrências e submontagens

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-P01 | P0 | Criar, abrir, salvar e Salvar como projeto `.massembly`, com esquema versionado. Reabrir deve conservar hierarquia, propriedades, transformações, relações, conexões e manual. |
| MA-P02 | P0 | Distinguir definição de peça e ocorrência. Dois parafusos do mesmo modelo compartilham definição, mas possuem IDs e posições distintos. |
| MA-P03 | P0 | Criar submontagens rígidas e editar sua hierarquia, impedindo ciclos. Mover um grupo mantém as posições relativas de seus filhos. |
| MA-P04 | P0 | Novo/Abrir/Fechar com alterações oferece salvar, descartar ou cancelar. Desfazer/refazer deve abranger inserção, exclusão, relações, conexões e etapas do manual. |
| MA-P05 | P0 | Tratar mm como unidade geométrica interna; a importação declara ou solicita a unidade. Exibir mm/polegada sem mudar o tamanho físico. |
| MA-P06 | P0 | Manter referências externas relativas ao projeto, revisão/hash da origem e estados disponível, alterado e ausente. Oferecer localizar/substituir com prévia. |
| MA-P07 | P0 | Salvar de forma atômica, manter backup e oferecer recuperação. Erro de gravação conserva documento aberto e conteúdo anterior íntegro. |
| MA-P08 | P1 | Configurações e estados de exibição separados: suprimir afeta a montagem ativa e a BOM; ocultar afeta somente a apresentação. |

### Inserção e montagem 3D

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-G01 | P0 | Inserir geometria do MultiCAD por adaptador, conservando identificação e revisão da peça; documentar o subconjunto suportado do `.mcad`. |
| MA-G02 | P0 | Importar STL/3MF como geometria de visualização, com unidade, orientação e material declarados. Usar referências explícitas quando a malha não fornecer superfícies analíticas. |
| MA-G03 | P0 | Criar primitivas e referências de montagem: bloco, cilindro, plano, eixo e ponto; permitem trabalhar antes de dispor de todos os modelos detalhados. |
| MA-G04 | P0 | Mover/girar em coordenadas locais ou globais, fixar/liberar, duplicar ocorrências e substituir uma definição sem trocar os IDs das ocorrências. |
| MA-G05 | P0 | Vista 3D com zoom, pan, órbita, vistas padrão, normal ao plano, enquadrar, ocultar/isolar e transparência. A seleção precisa identificar ocorrência e referência geométrica. |
| MA-G06 | P0 | Instâncias usam transformações rígidas. Alterar dimensões da peça é uma edição da definição; escala de importação deve ser explícita. |
| MA-G07 | P1 | Importar STEP/BREP pelo backend geométrico disponível, com unidades, orientação e diagnóstico de entidades não suportadas. |
| MA-G08 | P1 | Padrões lineares/circulares de componentes, edição de peça na ferramenta de origem e atualização assistida das referências. |

### Relações de montagem e solver

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-R01 | P0 | Relações coincidente, concêntrica, paralela, perpendicular, distância e ângulo sobre pares de entidades compatíveis; informar por que uma seleção é inválida. |
| MA-R02 | P0 | Fixar ocorrência elimina seus movimentos em relação à raiz; travar um par conserva a transformação relativa entre ambos. |
| MA-R03 | P0 | Solver para corpos rígidos em 3D, com translação e rotação, tolerâncias documentadas e solução determinística dentro delas. |
| MA-R04 | P0 | Apresentar montagem livre, parcialmente restringida, totalmente restringida ou conflitante; mostrar os movimentos ainda permitidos. |
| MA-R05 | P0 | Diagnosticar relações incompatíveis, redundantes, degeneradas e referências ausentes. Identificar os itens envolvidos e conservar a última solução válida. |
| MA-R06 | P0 | Edição, inversão de orientação, supressão e exclusão de relação são reversíveis. Exclusão de componente mostra as dependências afetadas. |
| MA-R07 | P0 | Referências persistem entre sessões. Atualização da peça que quebra uma face/eixo exige reparo explícito, com candidatos apresentados ao usuário. |
| MA-R08 | P1 | Tangência, simetria, largura/centralização e limites de distância/ângulo. |
| MA-R09 | P1 | Dobradiça, engrenagem, cremalheira/pinhão, correia/polia e fuso; preservar relação, sentido, passo e unidades. |
| MA-R10 | P1 | Submontagem flexível e movimento cinemático com posição inicial, limites e detecção de conflitos. Cálculo dinâmico detalhado fica no MultiPhysics. |

**Casos mínimos do solver:** um eixo concêntrico deve conservar deslocamento axial e rotação; acrescentar apoio axial elimina a translação correspondente; uma relação de travamento conserva a pose relativa; restrições incompatíveis devem gerar erro sem mover silenciosamente a montagem.

Separar o solver de montagem dos solucionadores de esboço do MultiCAD. Reutilizar álgebra e geometria verificadas onde houver compatibilidade, mantendo as responsabilidades e os testes específicos de corpos rígidos.

### Biblioteca de componentes e peças de fixação

A biblioteca é um processo obrigatório da primeira entrega. Ela deve servir à inserção, à BOM e ao manual, com cadastro editável, pesquisa, prévia e origem dos dados.

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-L01 | P0 | Catálogo local versionado em JSON, com categorias, código, descrição, fabricante/modelo quando conhecido, revisão, fonte e imagem/forma 3D. |
| MA-L02 | P0 | Pesquisar por categoria, nome, código e dimensão; inserir, cadastrar, editar, duplicar e importar/exportar componentes do usuário. |
| MA-L03 | P0 | Fixadores: parafusos de cabeça sextavada, Allen e panela; porcas comuns e travantes; arruelas lisas e de pressão; rebites cegos e sólidos; pinos, cupilhas, buchas e espaçadores. |
| MA-L04 | P0 | Rolamentos radiais e axiais, com geometria simplificada, eixo de montagem, diâmetro interno/externo, largura e código. |
| MA-L05 | P0 | Motores DC e AC, com forma simplificada, eixos, fixação e terminais; ficha técnica e parâmetros ausentes devem permanecer distinguíveis. |
| MA-L06 | P0 | Componentes da base existente: motores de passo, spindle, guias, fusos, polias/correias, fontes, drivers, controladores, VFD, relés, sensores, fins de curso, E-stop, conectores e PCB. |
| MA-L07 | P0 | Inserir várias ocorrências de um item sem duplicar sua definição. As quantidades aparecem corretamente na BOM e no manual. |
| MA-L08 | P0 | Referências de montagem padronizadas por componente: eixo, face de apoio, centros de furos e terminais. Seleção dessas referências permite relações básicas. |
| MA-L09 | P0 | Separar modelo ilustrativo, cadastro preenchido pelo usuário e dados de fabricante. Um parâmetro desconhecido não recebe valor nominal inventado. |
| MA-L10 | P1 | Inserção assistida de fixadores em furos, repetição em padrões e conjuntos parafuso/arruela/porca, sempre com prévia e confirmação. |

#### Dados específicos de cada família

| Família | Dados necessários |
|---|---|
| Parafuso | Tipo de cabeça, diâmetro nominal, comprimento, trecho roscado, passo, material, classe/identificação quando conhecida, norma/fonte e ferramenta de montagem. |
| Porca | Tipo, rosca/passo, dimensões, material e forma de travamento declarada. |
| Arruela | Tipo, diâmetros interno/externo, espessura e material. |
| Rebite | Tipo, diâmetro, comprimento, faixa de fixação quando fornecida e processo/ferramenta de aplicação. |
| Pino, bucha e espaçador | Diâmetros, comprimento, função, forma de retenção e material. |
| Rolamento | Código/modelo, dimensões, eixo, vedação/tipo, referências de assento; cargas e limites somente quando fornecidos pela fonte. |
| Motor DC | Modelo, tensão, corrente, rotação, torque, eixo, furos de fixação, polaridade/terminais, driver e redução quando existente. |
| Motor AC | Modelo, tensão, frequência, fases, corrente/potência, rotação, torque, eixo, fixação, terminais e forma de acionamento declarada. |
| Motor de passo / servo | Modelo, fixação, eixo, sinais/terminais e características fornecidas; passos por volta ou feedback ficam explícitos. |

Forma simplificada é suficiente para o catálogo inicial. Roscas e detalhes gráficos podem usar representação leve. Compatibilidade de rosca, encaixe e fixação depende dos parâmetros registrados; um modelo visual semelhante não prova intercambiabilidade.

### Conexões elétricas e identificação compartilhada

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-E01 | P0 | Cada ocorrência possui portas persistentes com ID, nome, tipo, direção e limites elétricos quando conhecidos. |
| MA-E02 | P0 | Criar, editar e excluir ligações pelo esquema; usar o mesmo ID da ocorrência mecânica e permitir seguir um terminal até a peça na vista 3D. |
| MA-E03 | P0 | Organizar redes, alimentação, terra e sinais; distinguir desenho do fio, conectividade elétrica e cabo físico. |
| MA-E04 | P0 | Expor `TAssemblyERC` na etapa Verificar, com erros/avisos ligados aos componentes e opção de corrigir/selecionar. |
| MA-E05 | P0 | Tipos explícitos de portas prevalecem. Inferência por nome, já existente, deve ser apresentada como inferência; tensão ausente permanece desconhecida. |
| MA-E06 | P0 | Conservar conexões ao mover uma ocorrência; substituir componente exige mapear portas alteradas com prévia. |
| MA-E07 | P1 | Chicotes, identificação de fios, conectores, comprimento de cabo e percurso espacial. |
| MA-E08 | P1 | Importar componentes/redes do MakePCB por contrato específico, preservando refdes e vinculando placa, conectores e componentes físicos. |

### Listagem de peças, materiais e compra

A **BOM/listagem de peças** deve ser editável como apresentação, mas suas quantidades derivam da montagem. Reutilizar `TAssemblyBOM` com agrupamento compatível com definições, revisões e configurações.

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-B01 | P0 | Listar número do item, código, descrição, quantidade, unidade, categoria, material, revisão, fornecedor/modelo quando registrado e observações. |
| MA-B02 | P0 | Oferecer listagem hierárquica e lista plana de peças, com agrupamento por definição + revisão/configuração e referência às ocorrências. |
| MA-B03 | P0 | Uma ocorrência representada nas vistas mecânica e elétrica conta uma vez; repetição física conta cada ocorrência. Evitar somar pai e filhos como a mesma peça. |
| MA-B04 | P0 | Ocultação visual conserva quantidade; supressão da configuração ativa exclui o item conforme regra explícita. |
| MA-B05 | P0 | Exportar CSV/JSON e versão de impressão/PDF ou HTML imprimível. Usar BOM no manual sem redigitar a lista. |
| MA-B06 | P0 | Lista de compra separa fabricar, comprar e fornecido pelo cliente; custo é opcional, com moeda e origem. Valor ausente permanece ausente. |
| MA-B07 | P0 | Mudança de componentes invalida a listagem gerada e permite regenerar mantendo notas e numeração compatíveis. |
| MA-B08 | P1 | Balões de identificação, desenho de conjunto, planilha de corte e relatório de massa/custo por submontagem. |

### Manual de montagem: processo da ferramenta

A ferramenta deve permitir **elaborar, revisar e gerar o manual de montagem**, além de produzir a geometria. A documentação tem seu próprio fluxo, ligado ao estado e à revisão do projeto.

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-M01 | P0 | Criar sequência de etapas e subetapas; adicionar, editar, duplicar e reordenar, com número, título, descrição e pré-requisitos. |
| MA-M02 | P0 | Vincular cada etapa às ocorrências instaladas, aos fixadores consumidos e às peças já montadas; destacar esses grupos na prévia. |
| MA-M03 | P0 | Registrar ferramentas necessárias, instruções, orientação, conferências e notas. Torque, adesivo, lubrificante e regulagem usam dados fornecidos; indicar quando faltarem. |
| MA-M04 | P0 | Gerar imagens a partir da própria montagem: câmera, peças visíveis, destaque e posição de apresentação por etapa, independentes da pose física e das relações. |
| MA-M05 | P0 | Mostrar listagem de peças geral e por etapa, vinculada à BOM e aos IDs. Cada fixador físico conserva sua identidade até a montagem final. |
| MA-M06 | P0 | Prévia da sequência acumulada: peças inseridas permanecem montadas nas etapas seguintes; edição de câmera/apresentação não muda a geometria de engenharia. |
| MA-M07 | P0 | Identificar peça de etapa inexistente, consumo duplicado da mesma ocorrência, item instalado antes do pré-requisito e peça final sem etapa ou sem justificativa de fornecimento pré-montado. |
| MA-M08 | P0 | Gerar HTML imprimível/PDF e Markdown com imagens locais, identificação, revisão, BOM, ferramentas, etapas e conferências. Todos os formatos devem conter a mesma sequência. |
| MA-M09 | P0 | Alterações na montagem marcam manual como desatualizado; revisão explícita e regeneração antes de marcar o documento como pronto. |
| MA-M10 | P0 | Importar imagens complementares e anexar ficha/instrução do fornecedor com origem; preservar esses recursos ao mover o projeto. |
| MA-M11 | P0 | Modo de leitura passo a passo com avançar/voltar e checklist; as marcações de execução ficam separadas do documento de projeto. |
| MA-M12 | P1 | Animação de montagem/desmontagem, balões automáticos, vista explodida global e assistência para sugerir etapas a partir da hierarquia. |

#### Fluxo de elaboração do manual

1. Definir nome, revisão e configuração da montagem que será documentada.
2. Conferir a BOM, separar compra/fabricação e identificar subconjuntos pré-montados.
3. Criar a ordem de preparação e instalação dos componentes.
4. Associar peças, parafusos, porcas, rebites, rolamentos e demais itens a cada etapa.
5. Ajustar câmera e apresentação; inserir instruções, ferramentas e conferências.
6. Revisar pré-requisitos e verificar se todas as ocorrências foram consideradas.
7. Conferir a prévia e gerar as saídas com imagens e referências.
8. Registrar revisão e acompanhar a montagem pelo modo passo a passo.

Reordenação não deve sugerir que uma sequência é fisicamente viável sem revisão. O autor confirma acesso às ferramentas, ordem de aperto, orientação e possibilidade de inserção de cada componente.

#### Estrutura mínima do manual gerado

| Seção | Conteúdo |
|---|---|
| Identificação | Produto, projeto, revisão, autor, data, configuração e imagem do conjunto. |
| Preparação | Peças e ferramentas necessárias, itens pré-montados e documentos do fornecedor. |
| Listagem | BOM geral, códigos, quantidades e legenda de identificação. |
| Etapas | Número, objetivo, pré-requisitos, peças utilizadas, imagem, instruções e conferência. |
| Conexões | Ligações elétricas envolvidas na etapa, nomes dos terminais e identificação dos cabos. |
| Conferência final | Itens de verificação definidos pelo autor e pendências documentadas. |
| Referências | Fichas, instruções e origem dos parâmetros de montagem. |

### Verificação e propriedades da montagem

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-V01 | P0 | Medir distância, ângulo, dimensão e folga, indicando seleção, unidade e origem dos dados. |
| MA-V02 | P0 | Verificar interferência estática; caixas envolventes só indicam candidatos. O resultado deve distinguir aproximação por malha de análise por sólidos. |
| MA-V03 | P0 | Exibir pares envolvidos, destacar região/conjunto e permitir documentar contato esperado, inclusão por projeto ou interferência pendente. |
| MA-V04 | P0 | Relatório reúne erros de referências, solver, ERC, biblioteca, BOM e manual, preservando severidade e ID do componente/etapa. |
| MA-V05 | P0 | Propriedades de massa e centro de massa usam somente geometria/densidade disponíveis; total parcial mostra itens excluídos. |
| MA-V06 | P1 | Colisão durante arraste/movimento, distância mínima, contatos e visualização em seção. |
| MA-V07 | P1 | Estados explodidos e configurações não alteram a verificação da configuração física selecionada. |

### Integração e saídas

| ID | Prioridade | Requisito e aceite |
|---|---|---|
| MA-I01 | P0 | Abrir por launcher/contexto da MultiSuite, manter registro/bandeja existentes e restaurar caminho do projeto. |
| MA-I02 | P0 | Adaptador MultiCAD conserva peça, revisão, material, geometria e referências de montagem suportadas. |
| MA-I03 | P0 | Placa do MakePCB pode entrar como componente físico com dimensões e terminais cadastrados/importados; identificar dados que precisem de preenchimento. |
| MA-I04 | P0 | Ampliar exportação para o contrato unificado/MultiPhysics: IDs, transformações, portas, ligações, massa/inércia quando conhecidas, relação/passo mecânico e unidade de cada grandeza. |
| MA-I05 | P0 | Expor exportação de parâmetros calculados de máquina como arquivo para revisão. Parâmetros desconhecidos impedem a geração correspondente. |
| MA-I06 | P0 | BOM, manual e relatórios compartilham revisão/configuração e avisam quando desatualizados; oferecer pasta de documentação do projeto. |
| MA-I07 | P1 | Exportar geometria posicionada para CAM, com referência e unidade; definição de trajetória pertence ao MultiCAM/MakeRouter. |
| MA-I08 | P2 | Assistência por IA para classificação de componentes e proposta de sequência/relações, sempre como alterações revisáveis no documento. |

MultiAssembly prepara projeto e documentação. MultiPhysics executa análises físicas; MultiCAD edita peças; MakePCB edita placas; MultiCAM/MakeRouter preparam fabricação; MultiCNC conduz a execução no equipamento.

## Modelo de dados e persistência propostos

Os nomes abaixo são requisitos de arquitetura, não APIs existentes.

| Entidade | Campos e regras essenciais |
|---|---|
| Projeto | `schema_version`, ID, nome, revisão, unidades, configurações e recursos. |
| Definição | ID próprio, código, revisão, categoria, origem, geometria, material e portas/referências locais. |
| Ocorrência | ID único, definição, pai, transformação local, estado e propriedades específicas. |
| Referência geométrica | Ocorrência + ID semântico da entidade + tipo + dados/fingerprint para validar atualização. |
| Relação | ID, tipo, referências, parâmetros/unidades, orientação, estado e diagnóstico. |
| Rede/conexão | ID, endpoints ocorrência/porta, tipo, identificação e cabo quando existente. |
| Etapa do manual | ID, ordem, pré-requisitos, ocorrências instaladas, peças de apoio, ferramentas, instruções, imagem/câmera, apresentação e conferências. |
| Documento gerado | Revisão do projeto, configuração, data, conteúdo e dependências/hashes. |
| Execução da montagem | ID próprio, revisão do manual e checklist realizado; separado do projeto autoral. |

Regras obrigatórias:

- Transformação mundial de ocorrência = transformação mundial do pai × transformação local. Declarar convenção de eixos, handedness, ordem de multiplicação e rotação.
- Usar `Double`; adotar quaternion normalizado ou matriz rígida validada para rotação. A migração dos ângulos atuais precisa declarar ordem e unidade.
- O ID da ocorrência é o identificador compartilhado pelas vistas, BOM, manual e contrato físico. A definição permite reutilização de uma peça sem juntar ocorrências distintas.
- Referências geométricas não podem depender apenas do índice de triângulo/face de uma reconstrução.
- Preservar unidade explícita no intercâmbio: mm na geometria; conversões para SI no adaptador físico devem ser rastreáveis.
- Biblioteca externa é versionada; a revisão utilizada fica registrada no projeto para reprodução.
- Armazenar caminho relativo e metadados de dependência; mover/copiar projeto deve levar recursos necessários por uma operação de empacotamento.
- Arquivo incompleto, versão não suportada ou dependência ausente gera diagnóstico sem substituir silenciosamente o documento.
- Imagens, posições de apresentação e execução de checklist não alteram relações ou conectividade da montagem física.

## Arquitetura: reutilização e módulos necessários

| Base existente | Desenvolvimento necessário |
|---|---|
| `multiassembly_types/project` | Definições/ocorrências, árvore, propriedades e interfaces de edição. |
| `multiassembly_engineering` | Integrar ERC/BOM/configurador, adaptando quantidades e referências ao novo documento. |
| `multiassembly_library` | Catálogo pesquisável, cadastro paramétrico e modelos leves das famílias solicitadas. |
| `multiassembly_physics_export` | Exportação completa com transformação, propriedades e parâmetros de relações. |
| `multiassembly_*_canvas` | Evoluir esquema e seleção sincronizada; adicionar cena 3D e prévia do manual. |
| Câmera/renderização/geometria do MultiCAD | Avaliar extração de interfaces compartilhadas; manter testes do CAD ao reutilizar. A tela atual do CAD tem dependências de seu documento. |
| `multisuite_controls/icons/context/launcher` | Reutilizar aparência e inicialização existentes. |
| `multisuite_numfmt` | Persistência/intercâmbio com ponto decimal, independente da configuração regional. |

Módulos propostos para organizar a implementação:

| Área | Responsabilidade |
|---|---|
| `core` | Documento, ocorrências, materiais, comandos, undo/redo e biblioteca. |
| `io` | `.massembly`, catálogo JSON, recursos, adaptadores MultiCAD/MakePCB e contratos de saída. |
| `mates` | Referências, relações, solver 3D, graus de liberdade e diagnóstico. |
| `view/ui` | Cena, picking, manipuladores, árvore, painel contextual e esquema elétrico. |
| `analysis` | Interferências, medidas, propriedades e composição dos relatórios. |
| `manual` | Sequência, consumo de ocorrências, câmeras/apresentação, checklist e revisão. |
| `export` | BOM, HTML/PDF/Markdown, imagens e pacote de documentação. |
| `app` | Coordenação da interface e comandos; cálculos e persistência ficam nos módulos correspondentes. |

Para PDF, selecionar um caminho de geração/impressão reproduzível em Windows e Linux na fase 5. HTML imprimível e Markdown com imagens devem funcionar como saídas portáveis. O backend escolhido precisa ser documentado e incluído no empacotamento quando necessário.

## Requisitos de qualidade

| ID | Prioridade | Requisito |
|---|---|---|
| MA-N01 | P0 | Compilar e validar núcleo/interface no Windows x64 e Linux amd64 com Lazarus/FPC; registrar dependências geométricas e de documentação por plataforma. |
| MA-N02 | P0 | Operações demoradas apresentam progresso/cancelamento; callbacks usam estado consistente e controles permanecem utilizáveis. |
| MA-N03 | P0 | Falha do solver/importação/exportação conserva a última versão válida; operações editoriais são transações reversíveis. |
| MA-N04 | P0 | Log persistente com data/hora, revisão, operação, IDs e erro; falha no log não corrompe a montagem. |
| MA-N05 | P0 | Mensagens e valores com unidades claras; texto em português e estrutura para localização dos idiomas da suíte. |
| MA-N06 | P0 | Importações validam formato, tamanho, valores finitos, IDs e ciclos; arquivos de projeto não executam comandos externos automaticamente. |
| MA-N07 | P0 | Testes invariantes ao separador decimal, caminho com espaços/acentos, recursos ausentes e estado cancelado. |
| MA-N08 | P1 | Benchmark com arquivo, contagem de ocorrências/relações/triângulos, hardware, tempo e memória registrados. Definir metas a partir da primeira implementação. |
| MA-N09 | P2 | Instâncias compartilham geometria; carregamento seletivo, cache e simplificação para montagens maiores. |
| MA-N10 | P1 | Qualificar arm64/armhf após conferir backends e dependências; registrar separadamente compilação e execução efetiva. |

## Fases de implementação

Cada fase deve terminar com resultado utilizável, validação proporcional, atualização desta tabela e commit na `fila`. Tempos e percentuais serão estimados após implementar e medir a base.

### Fase 1: documento, ocorrências e arquivos

- [ ] Implementar MA-P01 a MA-P07 e migração explícita do modelo atual.
- [ ] Definir identidade de definição/ocorrência, unidades e transformações hierárquicas.
- [ ] Salvar/carregar documento versionado e recursos, com backup.
- [ ] Implementar comandos transacionais e undo/redo.
- [ ] Testar repetição de peça, submontagem, ciclos, recuperação e arquivos ausentes.

### Fase 2: layout, catálogo e montagem 3D

- [ ] Implementar as seis etapas e reutilizar controles visuais da MultiSuite.
- [ ] Árvore, propriedades e seleção sincronizada.
- [ ] Inserção MultiCAD/malha/primitivas e posicionamento por manipulador/campos.
- [ ] Catálogo de parafusos, porcas, arruelas, rebites, pinos, buchas/espaçadores, rolamentos e motores DC/AC.
- [ ] Cadastrar terminais, eixos e faces de apoio; registrar origem e dados ausentes.
- [ ] Testar DPI, redimensionamento e navegação sem perder alterações.

### Fase 3: relações básicas

- [ ] Implementar MA-R01 a MA-R07.
- [ ] Solver 3D, estados de restrição, prévia e cancelamento.
- [ ] Referências persistentes e reparo assistido após alteração da peça.
- [ ] Demonstrar eixo/rolamento, motor/suporte e conjunto de fixação.
- [ ] Testar liberdade residual, conflito, redundância e limites numéricos.

### Fase 4: esquema elétrico e ERC

- [ ] Implementar MA-E01 a MA-E06 e apresentar ERC na interface.
- [ ] Conectar motor DC/AC, driver/acionamento, fonte/controlador e sensores usando terminais cadastrados.
- [ ] Sincronizar seleção e preservar ligações ao mover componentes.
- [ ] Testar porta ausente, sinal incompatível, tensão desconhecida e curto/alimentação segundo as regras suportadas.

### Fase 5: listagem e manual de montagem

- [ ] Implementar MA-B01 a MA-B07 e MA-M01 a MA-M11.
- [ ] Oferecer BOM/lista de compra geral, hierárquica e por etapa.
- [ ] Editor de sequência, referências a ocorrências, instruções, ferramentas e conferências.
- [ ] Imagens geradas da cena com câmera/apresentação independente.
- [ ] Detectar peças não consideradas, consumo duplicado e pré-requisitos inválidos.
- [ ] Gerar HTML/PDF/Markdown, exportar CSV/JSON e empacotar imagens/anexos.
- [ ] Modo passo a passo e checklist independente.
- [ ] Confirmar que mudança da montagem invalida manual/listagem anteriores.

### Fase 6: verificação da montagem

- [ ] Implementar MA-V01 a MA-V05.
- [ ] Medidas, folgas e interferências, identificando aproximação geométrica.
- [ ] Massa/centro de massa com indicação de dados parciais.
- [ ] Relatório unificado de relações, ERC, biblioteca, BOM e manual.
- [ ] Testar contato esperado, interferência real e seleção dos itens do relatório.

### Fase 7: integração e entrega do MVP

- [ ] Implementar MA-I01 a MA-I06 e validar launcher/bandeja.
- [ ] Exportar montagem própria para o contrato MultiPhysics, registrando parâmetros sem suporte.
- [ ] Consolidar adaptadores, recursos e revisão do projeto.
- [ ] Expor configurador de máquina como saída revisável de arquivo.
- [ ] Executar o cenário de aceite completo abaixo e registrar limitações.
- [ ] Atualizar README/manual do usuário, capturas, versão, executável e instalador conforme o fluxo de release da suíte.

### Fase 8: montagem e documentação avançadas

- [ ] Relações avançadas e mecânicas, submontagens flexíveis e configurações.
- [ ] Padrões e inserção assistida de fixadores.
- [ ] Vista explodida global, balões e animação de montagem/desmontagem.
- [ ] Importação STEP/BREP, chicotes e integração detalhada MakePCB.
- [ ] Colisão em movimento e integração geométrica com CAM.

### Fase 9: escala e assistência

- [ ] Medir montagens grandes, implementar cache e carregamento seletivo.
- [ ] Ampliar formatos/plataformas com backends qualificados.
- [ ] Assistência por IA para sugestões editoriais revisáveis.

## Critério de pronto: primeira entrega

A primeira entrega somente passa quando **todas as funções P0** forem utilizáveis pela interface e o seguinte cenário puder ser realizado fora da demonstração fixa:

1. Criar projeto e inserir estrutura, suporte, motor DC, motor AC, rolamento, placa/conector e fixadores de biblioteca.
2. Usar pelo menos dois parafusos da mesma definição, porcas, arruelas e rebites, com ocorrências distintas.
3. Criar uma submontagem rígida, fixar a base e posicionar o conjunto por relações básicas.
4. Mover o que ainda estiver livre; provocar uma relação incompatível e obter diagnóstico reversível.
5. Criar ligações elétricas a partir das portas cadastradas e verificar um erro pelo ERC.
6. Gerar BOM/lista de compra; conferir que vistas distintas não duplicam a peça e que repetições físicas somam quantidades.
7. Elaborar manual com preparação, instalação de subconjuntos, fixação, ligação elétrica e conferência final.
8. Cada etapa deve apresentar imagem, peças/fixadores, ferramentas, instrução e pré-requisitos; justificar itens fornecidos pré-montados.
9. Detectar uma ocorrência atribuída duas vezes como instalada e uma peça final sem etapa.
10. Gerar manual HTML/PDF/Markdown com BOM e imagens, abrir os arquivos e conferir legibilidade e referências.
11. Salvar, fechar e reabrir mantendo montagem, relações, ligações, biblioteca utilizada e manual.
12. Alterar uma peça/quantidade e observar invalidação dos documentos; revisar e regenerar.
13. Verificar interferência/medida e exportar montagem para análise física pelo contrato suportado.
14. Abrir o projeto pelo launcher e repetir o fluxo no Windows e Linux, com limitações registradas.

## Validação planejada

| Grupo | Casos necessários |
|---|---|
| Documento | Ida e volta, versão, backup, recursos relativos, ocorrências repetidas, hierarquia, ciclo e campos desconhecidos. |
| Relações | Pares válidos/inválidos, graus de liberdade, conflitos, degeneração, cancelamento e referências quebradas. |
| Biblioteca | Cadastro, famílias solicitadas, dados ausentes, geometria leve, eixos/portas e revisão. |
| BOM | Agrupamento, quantidade, supressão versus ocultação, lista plana/hierárquica, compra/fabricação e CSV/JSON. |
| Manual | Ordem/pré-requisitos, consumo de ocorrências, pré-montados, apresentação independente, invalidação e checklist separado. |
| Documentos | Mesma sequência em HTML/PDF/Markdown, imagens locais, paginação, caracteres portugueses e arquivos movidos. |
| Elétrica | Portas explícitas/inferidas, sinais, tensão desconhecida, ligações e seleção pelo ERC. |
| Geometria | Transformações aninhadas, seleção, medição, contato, interferência e limite de precisão. |
| Integração | Contexto de abertura, peça/placa com revisão, contrato físico e parâmetros não suportados. |
| Interface | Fluxo completo, teclado, cancelamento, DPI, tamanho mínimo e preservação de trabalho. |

Testes de biblioteca não substituem o cenário de usuário. Registros de compilação, testes e documentos revisados devem identificar commit, plataforma e limitações efetivamente observadas.

## Pontos de atenção e limites de escopo

| Ponto | Encaminhamento |
|---|---|
| Referências de face mudam na reconstrução | Identificação persistente, validação e reparo assistido; conservar última montagem válida. |
| Malha não tem cilindro/plano analítico confiável | Criar referências explícitas de montagem e indicar o método de seleção. |
| Submontagem e peça repetida | Separar definição e ocorrência para não duplicar geometria nem perder identidade. |
| Configuração de fixador/motor incompleta | Registrar campos ausentes e limitar avaliação/documentação que dependa deles. |
| Sequência do manual impossível de executar | Pré-requisitos e revisão do autor; sugestões automáticas permanecem propostas. |
| Manual ficou antigo após alteração | Revisão/configuração/hashes de dependências e invalidação visível. |
| Exportador físico atual perde propriedades | Ampliar contrato/adaptador antes de declarar integração completa. |
| Dependência do kernel geométrico | Detectar disponibilidade e oferecer capacidades suportadas por plataforma. |

FEM/CFD, geração de trajetórias e controle de máquina permanecem nas ferramentas responsáveis. Arquivos nativos proprietários de montagem não fazem parte do MVP. O formato `.massembly` é uma proposta a implementar; o documento atual ainda não oferece sua persistência.

## Referências

Documentação oficial consultada em **14/10/2026**. Os títulos e URLs identificam os conceitos de referência; o escopo e as prioridades do MultiAssembly foram definidos neste documento.

| ID | Referência |
|---|---|
| S1 | [SOLIDWORKS 2026 — FeatureManager Design Tree Overview](https://help.solidworks.com/2026/English/SolidWorks/sldworks/c_featuremanager_design_tree_overview.htm) |
| S2 | [SOLIDWORKS 2026 — PropertyManager Overview](https://help.solidworks.com/2026/english/solidworks/sldworks/r_pm_overview.htm) |
| S3 | [SOLIDWORKS 2026 — Standard Mates by Entity](https://help.solidworks.com/2026/english/SolidWorks/sldworks/r_Standard_Mates_by_Entity.htm?id=7.7.5) |
| S4 | [SOLIDWORKS 2026 — Machine Design Tools Overview](https://help.solidworks.com/2026/english/SolidWorks/sldworks/c_machine_desing_tools_overview.htm?id=3.2) |
| S5 | [SOLIDWORKS 2026 — Interference Detection PropertyManager](https://help.solidworks.com/2026/English/SolidWorks/sldworks/HIDD_DVE_INTERFERENCE.htm) |
| S6 | [SOLIDWORKS 2026 — Bill of Materials Overview](https://help.solidworks.com/2026/english/SolidWorks/sldworks/c_Bill_of_Materials1.htm?id=13.9.0) |
| S7 | [SOLIDWORKS 2026 — Exploded Views in Drawings](https://help.solidworks.com/2026/english/solidworks/sldworks/t_Exploded_Views_in_Drawings.htm) |
| S8 | [SOLIDWORKS 2026 — Assemblies / Large Scale Design](https://help.solidworks.com/2026/english/solidworks/sldworks/c_assemblies_Large_Scale_Design.htm) |

### Fontes do MultiCNC usadas na análise

- [Modelo de componentes](../src/core/multiassembly_types.pas).
- [Projeto em memória](../src/core/multiassembly_project.pas).
- [Interface atual](../src/app/multiassembly_main.pas).
- [Biblioteca atual](../src/core/multiassembly_library.pas).
- [ERC, BOM e configurador](../src/core/multiassembly_engineering.pas).
- [Exportador para contrato unificado](../src/core/multiassembly_physics_export.pas).
- [Contrato compartilhado](../../src/shared/multisuite_component_contract.pas).
- [Integração MultiPhysics](../../multiphysics/docs/INTEGRATION_ROADMAP.md).

## Registro desta revisão

**14/10/2026:** documentados requisitos do MultiAssembly com referência funcional no SolidWorks e identidade visual MultiSuite. Incorporados como processos obrigatórios **elaboração do manual de montagem**, **listagem de peças** e **biblioteca de fixadores, rolamentos e motores DC/AC**. Esta revisão acrescenta planejamento e critérios de aceite; não entrega implementação desses recursos.
