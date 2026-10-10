# Bugs de integração e operação do MultiCNC

Avaliação de 10/10/2026, baseada nos fontes da branch `fila`, commit
`d1f1083c4d76116818d9e90e97e8e8ead7aa43cc`.

O foco desta avaliação é a passagem de arquivos, projetos, configurações e
comandos entre os programas. A integração está parcialmente implementada:
existem contratos compartilhados e testes de conversão, mas há bloqueios no
lançador e funções do núcleo que ainda não são chamadas pelas aplicações.

A avaliação inclui os três sintomas relatados pelo usuário: laser que não
desliga ao terminar o objeto, router/CNC que não é reconhecida e impressão 3D
rápida demais para o filamento. Os BUG-009 a BUG-015 registram falhas e lacunas
localizadas nesses fluxos. A correspondência com a ocorrência específica do
usuário ainda precisa do G-code, do log TX/RX e da identificação do equipamento
ou simulador utilizado.

O BUG-016 registra também o pedido de log automático em arquivo do funcionamento
do MultiCNC no último dia, entendido aqui como as últimas 24 horas.

Todos os itens abaixo estão **abertos**. Este documento registra a avaliação;
não representa uma correção dos fontes.

## Como interpretar as evidências

- **Confirmado nos fontes:** o caminho descrito foi localizado no código do
  commit acima. Os passos de reprodução indicam como verificar o comportamento
  na aplicação compilada; não foram executados nesta avaliação.
- **Confirmado no CI:** o resultado foi verificado na execução do GitHub Actions
  correspondente ao mesmo commit.
- **Impacto inferido:** a consequência decorre do caminho identificado, mas não
  foi observada em equipamento físico.
- **Relato do usuário:** sintoma comunicado nesta conversa, sem reprodução
  independente. Encontrar uma falha relacionada não comprova, por si só, a
  causa daquela ocorrência.

Nos BUG-011, BUG-012, BUG-014 e BUG-015, a implementação do simulador/parser pertence à
dependência `marcelomaurin/CHATGPT`. Foi consultado o commit
`f2954d9c2c4785ed731fd8cfa07b6d985cf2c7af`, disponível em 10/10/2026. O fonte
`aimarlinsimulator.pas` tem blob `14b090426d533bcfaccadaef648a422924162821`.
Essa referência permite repetir a análise, mas não identifica a versão da
dependência embutida no executável instalado pelo usuário.

Não houve compilação ou execução local dos programas Pascal nesta avaliação:
este ambiente não dispõe de `fpc` ou `lazbuild`. Não houve teste com máquinas
físicas. Os resultados de execução citados abaixo pertencem ao CI.

## Relação com os sintomas relatados

| Relato | Itens relacionados | Limite da conclusão |
| --- | --- | --- |
| Laser não desliga ao terminar o objeto | BUG-009, BUG-010, BUG-011 e BUG-015 | Existem falhas concretas de envio/encerramento; o caso do SimuCNC depende da versão consultada. O feixe físico não foi testado. |
| Router/CNC não é reconhecida | BUG-012 e BUG-013 | Confirmados bloqueio após reset no SimuCNC e prontidão sem validação. A causa da conexão inicial relatada precisa de log. |
| Impressão 3D rápida demais para o filamento | BUG-014 | Confirmadas lacunas de vazão/perfil; os cálculos básicos de extrusão e conversão de velocidade existem. A causa física precisa do G-code e dos limites da impressora. |

## Prioridades

| ID | Prioridade | Integração afetada | Problema |
| --- | --- | --- | --- |
| BUG-001 | Alta | MakePCB → LaserPCB / RouterPCB | O lançador rejeita a pasta de fabricação. |
| BUG-002 | Alta | MultiSuite → CAD / CAM / PCB / Assembly / Physics | O arquivo recebido não é carregado pelas cinco aplicações. |
| BUG-003 | Alta | MakePCB → fabricação | Editar a placa não invalida a exportação anterior. |
| BUG-004 | Alta | MultiSlicer / MultiCAM → MultiCNC | A identificação automática de máquina não cobre esses produtores. |
| BUG-005 | Média | CAD → MultiSlicer por 3MF | O importador existe, mas a aplicação usa somente o importador STL. |
| BUG-006 | Alta | CAD → Slicer; PCB / Assembly → Physics | Rotinas de conversão testadas não estão ligadas ao fluxo das aplicações. |
| BUG-007 | Alta | MultiCNC → transporte TCP no Linux | A sessão usa uma implementação dependente de Winsock2. |
| BUG-008 | Média | MultiSlicer Klipper → MultiCNC | O produtor oferece um dialeto que o executor não seleciona como protocolo. |
| BUG-009 | Alta | Preparação laser / framing → sessão | O envio usa o tamanho do programa original para percorrer outra lista. |
| BUG-010 | Crítica | Sessão laser → desligamento | A conclusão não espera a confirmação de M5; caminhos de erro não solicitam desligamento. |
| BUG-011 | Alta | Programa laser → SimuCNC | Comentários gerados são enviados como linhas pendentes, mas o simulador não os confirma. |
| BUG-012 | Alta | MultiCNC GRBL → reset do SimuCNC | A resposta `start` não libera a espera pelo reinício GRBL. |
| BUG-013 | Alta | Conexão → reconhecimento da CNC | Porta aberta é tratada como controladora pronta, sem validar uma resposta do firmware. |
| BUG-014 | Alta | Perfil / filamento → MultiSlicer → impressão 3D | Faltam limites de vazão e configuração do diâmetro do filamento na aplicação. |
| BUG-015 | Média | Configuração de velocidade laser → G-code | O override acrescenta outro F em vez de substituir o existente. |
| BUG-016 | Alta | Operação / comunicação → diagnóstico em arquivo | Não há histórico automático persistente das últimas 24 horas; salvar o console manualmente não preserva esse período. |

## BUG-001 — Pasta de fabricação bloqueada pelo lançador

**Evidência:** confirmada nos fontes.

O MakePCB guarda a pasta Gerber/Excellon em `FExportDir` e a entrega a
`TSuiteLauncher.LaunchArtifact`. O lançador verifica apenas `FileExists(AF)`;
não aceita `DirectoryExists(AF)`. LaserPCB e RouterPCB implementam a abertura
de diretórios, mas o lançamento é interrompido antes de chegar a essas funções.

**Fontes:**

- `makepcb/src/app/makepcb_main.pas`: `ExportTo`, `OpenInTool`.
- `multisuite/src/core/multisuite_launcher.pas`: `RunTool`, especialmente a
  verificação do artefato nas linhas 17–21 do commit avaliado.
- `laserpcb/src/app/laserpcb_main.pas`: `OpenFile`.
- `routerpcb/src/app/routerpcb_main.pas`: `OpenFile`.

**Reprodução:** exportar uma placa no MakePCB; clicar em abrir no LaserPCB e
depois no RouterPCB. A pasta existe, mas o lançador retorna "Arquivo nao
encontrado". Abrir manualmente a mesma pasta nas ferramentas de destino permite
separar o bloqueio do lançador de um eventual problema de importação.

**Correção proposta:** aceitar arquivos e pastas de acordo com a capacidade da
ferramenta de destino; manter a rejeição de caminhos inexistentes. Testar também
pastas com espaços e caminhos relativos ao projeto.

## BUG-002 — Arquivo recebido da suíte fica apenas no título

**Evidência:** confirmada nos fontes.

O lançador envia `--project` e `--file`. Nas entradas de MultiCAD, MultiCAM,
MultiPCB, MultiAssembly e MultiPhysics, `ReadSuiteContext` lê esses argumentos,
mas não há chamada de carregamento do arquivo. O nome é apresentado por
`ContextCaption` e, em quatro dessas aplicações, também pelo `Hint`.

O MultiSuite considera o lançamento bem-sucedido quando o processo inicia;
isso não confirma que a ferramenta carregou o artefato.

**Fontes:**

- `multisuite/src/app/multisuite_main.pas`: `OpenArtifact`.
- `src/shared/multisuite_context.pas`: `ReadSuiteContext`, `ContextCaption`.
- `multicad/src/app/multicad.lpr`.
- `multicam/src/app/multicam.lpr`.
- `multipcb/src/app/multipcb.lpr`.
- `multiassembly/src/app/multiassembly.lpr`.
- `multiphysics/src/app/multiphysics.lpr`.

**Reprodução:** registrar na suíte um arquivo válido para uma dessas ferramentas
e abri-lo pela árvore de artefatos. Comparar o conteúdo da janela com o arquivo;
o título pode mostrar o nome sem restaurar o projeto. Repetir para as cinco
ferramentas, não apenas para o lançador.

**Correção proposta:** ligar cada entrada ao carregador do formato suportado.
Quando não houver carregador, apresentar claramente essa limitação, em vez de
tratar a mudança de título como abertura do projeto.

## BUG-003 — Exportação antiga do MakePCB permanece disponível após edição

**Evidência:** confirmada nos fontes; o conteúdo obsoleto no destino ainda
precisa de reprodução funcional.

`ExportTo` atribui `FExportDir`. `DocChanged` atualiza o estado de validação e a
interface, mas não limpa essa variável nem desabilita os botões de abertura.
`OpenInTool` solicita nova exportação somente se a pasta não existir ou o
caminho estiver vazio. Portanto, a edição da placa pode continuar apontando
para Gerber/Excellon de uma versão anterior.

Este problema continua relevante depois de corrigir o BUG-001, que hoje bloqueia
a passagem automática da pasta.

**Fontes:** `makepcb/src/app/makepcb_main.pas`: `DocChanged`, `ExportTo`,
`ExportClick`, `OpenInTool`.

**Reprodução:** exportar a placa; mover um componente ou alterar uma trilha;
tentar abrir no LaserPCB/RouterPCB sem exportar novamente. Conferir se a
geometria importada corresponde à edição mais recente.

**Correção proposta:** invalidar a fabricação quando houver alteração relevante;
exigir regeneração antes da passagem à ferramenta seguinte. Uma revisão ou hash
do documento pode vincular a exportação à versão que a originou.

## BUG-004 — Tipo de máquina não acompanha todos os produtores de G-code

**Evidência:** confirmada nos fontes; incompatibilidade durante execução física
é um impacto inferido.

`OpenProgramFile` distingue somente `soNone`, `soLaser` e `soRouter`, procurando
comentários específicos de LaserArt/LaserPCB e o texto
`-> MultiCNC (CNC Router)`. O arquivo moderno do MultiSlicer identifica
`generated by MultiSlicer` e `;FLAVOR:Marlin` ou `;FLAVOR:Klipper`, mas não é
reconhecido como impressão 3D por esse caminho. O exportador simples do MultiCAM
escreve `; MultiCAM -> MultiCNC`, que também não corresponde ao identificador
de router esperado pela função.

Uma nova instância do MultiCNC começa com CNC Router e GRBL. Abrir um arquivo do
fatiador não muda automaticamente essas escolhas. A seleção de impressora com
GRBL gera um aviso no log de conexão, mas não é bloqueada nesse ponto. Para as
origens reconhecidas, a troca automática de máquina só ocorre desconectado.

**Fontes:**

- `src/app/mainform.pas`: criação dos seletores, `OpenProgramFile`, conexão.
- `multislicer/src/core/multislicer_pipeline.pas`: cabeçalho de `Slice`.
- `multicam/src/export/multicam_gcode.pas`: `ExportJob`.
- `src/shared/multisuite_gcode_writer.pas`: `TSuiteGCodeHeader`.

**Reprodução:** abrir no MultiCNC recém-iniciado um G-code Marlin exportado pelo
MultiSlicer e verificar os seletores de máquina/protocolo. Depois selecionar
laser e abrir um G-code do MultiCAM; verificar se permanece selecionado laser.
Executar esses testes desconectado de equipamento físico.

**Correção proposta:** transportar origem, máquina e dialeto em contrato
compartilhado, consumido pelo executor. Detectar incompatibilidade com uma
conexão já ativa e exigir configuração compatível antes do envio. Não presumir
que todo arquivo `.gcode` pertence ao modo de máquina atualmente selecionado.

## BUG-005 — 3MF suportado no núcleo, mas não na aplicação MultiSlicer

**Evidência:** confirmada nos fontes; conversão de núcleo aprovada no CI.

Existe `T3MFImporter` e o teste paramétrico do CAD exporta 3MF e o importa para o
slicer. Entretanto, `TMultiSlicerForm.OpenFile` chama exclusivamente
`TSTLImporter.Load`, e o diálogo de abertura oferece apenas `*.stl`. Um 3MF
enviado pela suíte também passa por esse mesmo carregador STL.

**Fontes:**

- `multislicer/src/app/multislicer_main.pas`: `OpenFile`, `OpenClick`.
- `multislicer/src/app/multislicer.lpr`: consumo de `--file`.
- `multislicer/src/import/multislicer_3mf.pas`.
- `multicad/tests/test_parametric.lpr`: fluxo STL/3MF → slicer.

**Reprodução:** usar um 3MF gerado pelo fluxo do teste paramétrico; abrir pelo
diálogo e por `--file`. O diálogo não oferece o formato e a abertura por contexto
tenta tratá-lo como STL.

**Correção proposta:** selecionar o importador pelo formato, incluir 3MF na
abertura da aplicação e preservar o modelo atual quando houver falha na leitura.

## BUG-006 — Conversões do núcleo não estão disponíveis no fluxo normal

**Evidência:** confirmada nos fontes; testes dessas conversões aprovados no CI.

Este item trata da passagem do conteúdo produzido por uma ferramenta à próxima;
o BUG-002 trata especificamente da abertura inicial de um arquivo pela suíte.

- **CAD → Slicer:** há exportação STL/3MF e fatiamento no teste paramétrico, mas
  `multicad_main.pas` oferece somente novo esboço, retângulo, círculo e extrusão.
  Não liga essas operações a uma ação de exportação/abertura no slicer.
- **PCB/Assembly → Physics:** existem `ExportPCBToUnified`,
  `ExportAssemblyToUnified` e `UnifiedToSimulation`, usados pelo teste de fusão.
  As aplicações de PCB e Assembly não chamam esses exportadores. No Physics,
  o botão "CARREGAR MAQUINA EXECUTAVEL" chama `BuildDemoMachine`, sem importar
  a montagem ou placa editada pelo usuário.

**Fontes:**

- `multicad/src/app/multicad_main.pas`.
- `multicad/tests/test_parametric.lpr`.
- `multipcb/src/app/multipcb_main.pas`.
- `multipcb/src/core/multipcb_physics_export.pas`.
- `multiassembly/src/app/multiassembly_main.pas`.
- `multiassembly/src/core/multiassembly_physics_export.pas`.
- `multiphysics/src/app/multiphysics_main.pas`: `LoadMachine`.
- `multiphysics/src/runtime/multiphysics_unified_import.pas`.
- `multiphysics/tests/test_unified_merge.lpr`.

**Reprodução:** criar uma peça no CAD e tentar continuar no slicer pela aplicação;
editar uma montagem/placa e tentar simular esses mesmos componentes no Physics.
Conferir IDs e parâmetros: carregar uma demonstração não valida o projeto real.

**Correção proposta:** ligar os exportadores/importadores às aplicações e definir
a persistência do modelo compartilhado entre processos. Preservar IDs, unidades,
parâmetros e conexões; não substituir silenciosamente o projeto por uma demo.

## BUG-007 — Sessão TCP usa código específico de Windows no Linux

**Evidência:** confirmada nos fontes e no CI do commit avaliado.

Existem duas implementações de transporte TCP. `multicnc_tcp.pas` usa
`ssockets`; `multicnc_tcp_transport.pas` importa `Winsock2` sem condição de
plataforma. A sessão usada pela aplicação importa a segunda unidade e instancia
`TTCPTransport.Create(Device)`.

No CI Linux, `test_printer_temperatures`, `test_session` e `test_streaming`
falharam na compilação com `Can't find unit Winsock2 used by
multicnc_tcp_transport`. Isso impede validar a integração da sessão/streaming
nessa plataforma, mesmo que outros testes do controlador passem.

**Fontes:**

- `src/transports/multicnc_tcp.pas`.
- `src/transports/multicnc_tcp_transport.pas`.
- `src/app/multicnc_session.pas`: `uses`, `Connect`.
- `tests/test_printer_temperatures.lpr`, `tests/test_session.lpr`,
  `tests/test_streaming.lpr`.

**Reprodução:** em Linux com FPC e dependências instaladas, executar
`bash tests/run_all.sh .` e conferir as três compilações.

**Correção proposta:** consolidar o transporte em uma implementação portátil ou
selecionar explicitamente a implementação por plataforma. Conferir também a
compatibilidade das interfaces, construtores e eventos da sessão antes de trocar
a unidade. Validar o controlador real da aplicação, além do transporte isolado.

## BUG-008 — G-code Klipper não tem protocolo correspondente no executor

**Evidência:** confirmada nos fontes; resposta de um equipamento a esse envio
não foi testada.

O MultiSlicer oferece Marlin e Klipper e gera, no segundo caso, comandos como
`EXCLUDE_OBJECT_DEFINE` e `SET_PRINT_STATS_INFO`. O MultiCNC oferece GRBL e
Marlin; `TProtocolKind` contém somente `pkGRBL` e `pkMarlin`. Não há seleção de
Klipper nem tratamento do cabeçalho `;FLAVOR:Klipper` no caminho de abertura.

A exportação para um executor externo pode ser válida. A incompatibilidade aqui
é a passagem desse arquivo ao executor MultiCNC da própria suíte sem um caminho
de execução correspondente e sem detecção específica desse dialeto na abertura.

**Fontes:** `multislicer/src/app/multislicer_main.pas`,
`multislicer/src/core/multislicer_pipeline.pas`, `src/app/multicnc_session.pas`,
`src/app/mainform.pas`.

**Reprodução:** exportar em Klipper e abrir no MultiCNC; verificar os protocolos
disponíveis e a ausência de seleção/validação específica. Não enviar ao hardware
para reproduzir a incompatibilidade de configuração.

**Correção proposta:** sinalizar os destinos compatíveis e impedir o envio por
um protocolo incompatível. Implementar uma integração Klipper apenas se esse
destino fizer parte do escopo de execução do MultiCNC.

## BUG-009 — Laser e framing percorrem a lista ativa com a contagem original

**Evidência:** confirmada nos fontes; efeito no equipamento ainda não testado.
Relacionado ao relato de término incorreto do trabalho laser.

`GetCount` retorna `FLoadedLines.Count` sempre que existe um arquivo carregado.
Entretanto, `Start` substitui `FLines` pela saída de `TransformGCodeForLaser`,
que acrescenta comentários, assistência de ar, encerramento e novas passadas.
`FeedJob` usa `FIndex < Count` para acessar `FLines[FIndex]`, e também usa
`Count` para decidir se terminou. O limite pertence a uma lista diferente da
que está sendo enviada.

Consequências previstas pelo código:

- No laser, somente um prefixo do programa preparado é enviado. Passadas
  adicionais e comandos de encerramento podem ficar fora desse prefixo.
- Em `RunFraming`, `FLines` passa a conter o contorno, mas a contagem continua
  sendo a do arquivo aberto. Um arquivo menor pode truncar o contorno; um
  arquivo maior pode provocar acesso além do fim da lista do contorno.
- O progresso pode indicar conclusão do número original de linhas sem que
  todo o programa preparado tenha sido enviado.

Existe um `M5` adicional no encerramento de `FeedJob`. Portanto, a contagem
incorreta não prova isoladamente que o laser ficará ligado; os BUG-010 e
BUG-011 descrevem problemas nesse encerramento.

**Fontes:**

- `src/app/multicnc_session.pas`: `GetCount` (354–360), `RunFraming`, `Start`,
  `FeedJob` (503–540), `GetCompleted`.
- `src/core/multicnc_laser_config.pas`: `TransformGCodeForLaser` (118–190).

**Reprodução:** em transporte de teste que registre as linhas enviadas,
executar um arquivo laser com duas passadas e comparar a sequência transmitida
com a sequência preparada. Confirmar que ambas as passadas e todo o
encerramento chegam ao destino. Repetir o framing com arquivos cuja quantidade
de comandos seja menor e maior que a quantidade de linhas do contorno.

**Correção proposta:** usar a contagem da lista ativa para envio e conclusão;
manter a contagem original apenas para apresentação, quando necessária.
Relacionar progresso aos comandos efetivamente confirmados. Validar laser,
passadas e framing com registro do conteúdo enviado, não apenas do estado final.

## BUG-010 — Desligamento laser não faz parte da conclusão confirmada

**Evidência:** confirmada nos fontes; permanência física do feixe é impacto
inferido. **Prioridade crítica** por envolver o desligamento relatado.

Há comandos `M5` no código: no programa transformado e no fim de `FeedJob`.
A falha não é ausência geral do comando, mas a forma como a sessão acompanha
seu envio e sua confirmação:

1. Quando as linhas do trabalho deixam de estar pendentes, `FeedJob` solicita
   `M5` e o desligamento do ar, ignora o resultado de `SendGCode` e muda
   imediatamente para `ssDone`. Não espera a confirmação dessas novas linhas.
2. `CheckFirmwareFaults` e a rejeição de uma linha em `FeedJob` limpam a fila e
   entram em `ssError`, sem executar uma rotina de desligamento. Se o laser já
   estiver acionado, o `M5` que estava no restante do programa pode ser descartado.
3. `Pause` chama primeiro a pausa GRBL, que bloqueia `Pump` por
   `FFeedPaused`, e só depois enfileira `M5`. Esse pedido fica retido enquanto a
   fila estiver pausada. O efeito de desligamento do próprio feed hold depende
   do firmware/modo e não foi verificado nesta avaliação.

Além disso, `CheckFirmwareFaults` só acompanha `ssRunning` e `ssPaused`.
Uma resposta de erro ao `M5` depois de marcar `ssDone` não transforma esse
encerramento em erro de sessão. A interface pode anunciar "all lines
confirmed" antes da confirmação do desligamento.

**Fontes:**

- `src/app/multicnc_session.pas`: `CheckFirmwareFaults`, `FeedJob`, `Pause`.
- `src/core/multicnc_machine.pas`: `Pump`, `Pause`, `EnqueueLines`.
- `src/app/mainform.pas`: `Tick`, mensagem emitida para `ssDone`.

**Reprodução:** usar um transporte controlado, sem equipamento físico, que
confirme o trabalho e retenha a resposta de `M5`; verificar que a sessão hoje
já entra em `ssDone`. Repetir recusando o envio ou retornando erro para esse
comando. Injetar erro após o acionamento laser e conferir se há pedido de
desligamento ao abortar. Na pausa, conferir a ordem real dos bytes transmitidos.

**Correção proposta:** criar uma etapa explícita de encerramento, verificar
falhas de envio e aguardar a confirmação apropriada ao protocolo. Centralizar
o desligamento em conclusão, abortamento e pausa, usando o mecanismo adequado
para atuar mesmo quando o envio normal está bloqueado. Exibir falha quando não
for possível confirmar o desligamento. A confirmação serial deve ser
distinguida da execução física concluída.

## BUG-011 — Comentário da preparação laser fica sem confirmação no SimuCNC

**Evidência:** confirmada na combinação dos fontes do MultiCNC e da dependência
consultada; reprodução executável ainda pendente. Explica um caminho concreto
em que o trabalho pode terminar seu movimento sem chegar ao desligamento final.

`LoadFile` elimina comentários de linha inteira do arquivo original.
`TransformGCodeForLaser`, porém, acrescenta novos comentários, começando por
`; === MultiCNC Laser Preparation ===`. A sessão envia essas linhas por
`SendGCode`, e `TMultiCNCMachine.Pump` registra cada uma em `FInFlight`.

O SimuCNC entrega o texto a `TAIMarlinSimulator.Receive`. Seu parser considera
uma linha só de comentário como `C.Empty`; `SubmitLine` retorna sucesso nesse
caso **sem emitir `ok`**. A linha continua pendente no executor. Como a
finalização exige `PendingLines = 0`, o `M5` adicional de `FeedJob` pode nunca
ser solicitado.

Um caso particularmente claro, com uma passada e sem assistência de ar, usa:

```gcode
G21
G90
M3 S500
G1 X10 F600
M5
```

Com o BUG-009, as cinco linhas enviadas são o comentário de preparação seguido
dos quatro primeiros comandos originais. O `M5` original fica fora do prefixo
enviado. O simulador confirma os quatro comandos, mas não o comentário;
portanto, resta uma linha pendente e o desligamento de fallback não é alcançado.
Este é o resultado previsto pelo código, não um teste executado nesta avaliação.

**Fontes:**

- `src/app/multicnc_session.pas`: `LoadFile`, `Start`, `FeedJob`.
- `src/core/multicnc_laser_config.pas`: `TransformGCodeForLaser`.
- `src/core/multicnc_machine.pas`: `Pump`, `PendingLines`, `TransportData`.
- `src/simucnc/simuform.pas`: `TCPData`, `SerialReceive`.
- Dependência: [aimarlinsimulator.pas no commit consultado](https://github.com/marcelomaurin/CHATGPT/blob/f2954d9c2c4785ed731fd8cfa07b6d985cf2c7af/pacote/AI%20Simulation/Marlin/aimarlinsimulator.pas),
  `SubmitLine`, especialmente `if C.Empty then Exit(True)` na linha 225.
- Dependência: [aigcodeparser.pas no mesmo commit](https://github.com/marcelomaurin/CHATGPT/blob/f2954d9c2c4785ed731fd8cfa07b6d985cf2c7af/pacote/AI%20Simulation/Marlin/aigcodeparser.pas),
  `Parse`, remoção de comentários e identificação de comando vazio.

**Reprodução:** executar o exemplo pelo MultiCNC conectado ao SimuCNC em modo
laser/GRBL, registrar cada linha TX e resposta RX e verificar potência e linhas
pendentes depois do movimento. Conferir também comentário puro enviado
diretamente ao simulador. Repetir após corrigir o BUG-009, com programa maior
que o buffer, para não depender de o encerramento caber no primeiro envio.

**Correção proposta:** remover comentários sem comando da lista final enviada
e ajustar a contagem/progresso depois dessa filtragem. Tornar a confirmação do
simulador coerente com o contrato de streaming do protocolo selecionado.
Cobrir o percurso real de preparação laser até o simulador.

## BUG-012 — Reset GRBL do SimuCNC responde com identificação Marlin

**Evidência:** confirmada na combinação dos fontes e da dependência consultada.
Relacionada ao controle/reconhecimento da CNC; não comprova a causa de uma
falha inicial de conexão a uma máquina física.

`TMultiCNCMachine.Stop` coloca `FWaitingReset := True` em GRBL e transmite
Ctrl-X (`#24`). A espera só é liberada quando o protocolo identifica uma
resposta de reinício por `TakeResetDetected`.

No SimuCNC, `FilterRealtime` recebe Ctrl-X e chama `Sim.Reset`, inclusive quando
a interface está selecionada como GRBL/router. A dependência emite `start`,
uma identificação Marlin. `TGRBLProtocol.HandleLine` reconhece reinício por
prefixos `grbl ` e `grblhal`, mas não por `start`. A conexão continua aberta,
enquanto o executor fica esperando um reinício que não reconhece. Relatórios
`<Idle|...>` não liberam `FWaitingReset`.

O transporte de demonstração `TSimulatorTransport` emite um banner `Grbl 1.1h`
ao receber Ctrl-X. Assim, um teste com esse transporte pode passar mesmo que
o SimuCNC conectado por TCP/serial fique bloqueado.

**Fontes:**

- `src/core/multicnc_machine.pas`: `Stop`, `TransportData`, `GetState`,
  `EnqueueLines`.
- `src/protocols/multicnc_grbl.pas`: `HandleLine` (187–218).
- `src/simucnc/simuform.pas`: `FilterRealtime`, `TCPConnected`, `MachineChanged`.
- `src/transports/multicnc_simulator.pas`: `Send`.
- Dependência `aimarlinsimulator.pas`, commit indicado no BUG-011:
  `Reset` (106–116), emissão de `start`.

**Reprodução:** selecionar router/GRBL no SimuCNC e no MultiCNC, conectar,
executar uma movimentação, pressionar Parar e tentar enviar outro comando.
Registrar Ctrl-X em TX, `start` em RX e a rejeição pela espera de reinício.
Comparar com o transporte local de demonstração e com reconexão completa.

**Correção proposta:** fazer o SimuCNC respeitar a identificação e as respostas
do protocolo selecionado, incluindo conexão inicial e reset. Validar parada
seguida de novo comando por TCP e serial em router e laser. Não aceitar
indiscriminadamente uma identificação de outro firmware para contornar a falha.

## BUG-013 — Conexão aberta é apresentada como controladora reconhecida

**Evidência:** confirmada nos fontes como falha de validação de prontidão.
O relato de CNC não reconhecida permanece sem causa específica comprovada.

`TMultiCNCMachine.Connect` passa de `msConnecting` para `msIdle` quando o
transporte abre. `TSimulationSession.GetControllerReady` retorna `Connected`
em GRBL; em Marlin, exige somente que a janela de 2,5 segundos tenha passado.
Nenhuma das condições exige uma resposta válida do firmware.

`CheckControllerSilence` registra um aviso após cinco segundos sem resposta,
mas não altera a prontidão nem bloqueia início/comandos. Qualquer dado
recebido, mesmo sem reconhecimento pelo parser, preenche `FLastRxAt` e impede
esse aviso. A interface habilita ações com base em `ControllerReady`.
O protocolo é selecionado manualmente; os avisos de combinação incompatível
em `ConnectClick` também não interrompem a conexão.

Isso permite apresentar como pronta uma porta incorreta, uma conexão sem
controladora respondendo ou uma comunicação com protocolo/baud inadequado.
O código não permite identificar qual dessas condições ocorreu na máquina
relatada. Falhas TCP no Linux são tratadas separadamente no BUG-007; a
identificação do tipo de máquina pelo arquivo é tratada no BUG-004.

**Fontes:**

- `src/core/multicnc_machine.pas`: `Connect`.
- `src/app/multicnc_session.pas`: `ConnectTransport`, `GetControllerReady`,
  `CheckControllerSilence`, `Receive`, `Poll`.
- `src/app/mainform.pas`: `ConnectClick`, `UpdateControls`.
- `tests/test_streaming.lpr`: `TestConsoleLog` verifica o aviso de silêncio,
  mas não exige que a controladora permaneça indisponível sem identificação.

**Reprodução:** conectar a um transporte de teste que abra e não responda.
Consultar `ControllerReady` antes de qualquer resposta GRBL e depois do
prazo de silêncio. Repetir enviando texto sem identificação válida. Conferir
se Iniciar e comandos ficam habilitados apesar da ausência de validação.

**Correção proposta:** separar transporte conectado, firmware identificado e
controladora pronta. Exigir resposta compatível ao handshake/consulta de
estado, com timeout e diagnóstico explícito. Manter indisponível a execução
quando não houver comunicação válida. Para o caso relatado, obter porta ou
endpoint, baud, firmware, versão do executável e log de conexão TX/RX.

## BUG-014 — Velocidade 3D não considera limites de vazão e perfil do filamento

**Evidência:** lacunas confirmadas nos fontes; causa da velocidade excessiva
relatada ainda não reproduzida. O cálculo básico de extrusão existe.

O fatiador calcula o comprimento extrudado a partir da seção do cordão e da
área do filamento em `ExtrusionPerMM`. `TGCodeWriter.SetF` converte a velocidade
de mm/s para mm/min multiplicando por 60. Nesses pontos, não foi localizada
uma ausência do cálculo nem uma conversão de unidade que explique, sozinha,
o relato.

As lacunas encontradas são:

- `TSliceSettings` e o perfil não oferecem limite de vazão volumétrica por
  material/hotend. `Slice` escolhe velocidades de parede/preenchimento e as
  entrega diretamente ao writer, sem limitar pela seção extrudada.
- A interface permite velocidade de impressão de 1 a 500 mm/s, sem verificar
  a capacidade do conjunto material, bico e extrusor.
- `Settings` recria `DefaultPrinterProfile`, cujo diâmetro de filamento é
  1,75 mm. Não existe campo de diâmetro do filamento nessa tela. Um filamento
  de outro diâmetro não pode ser configurado pelo fluxo normal da aplicação.
- O diâmetro dos perfis do MultiCNC é apenas apresentado em
  `PrinterSpecsLabel`; esses perfis não são transferidos ao MultiSlicer.

Para um limite de vazão configurado `Qmax`, a restrição deve considerar
`Q = seção do cordão × velocidade` e a velocidade de alimentação do filamento
`vE = Q / área do filamento`. O teto deve vir do perfil validado do equipamento
e do material; não é possível deduzir um valor adequado ao usuário apenas
pelos fontes.

A sessão copia o G-code 3D carregado sem aplicar a transformação laser.
O transporte Marlin limita o envio a uma linha sem confirmação por vez.
A rapidez de transmissão serial não determina, por si só, a velocidade física:
é necessário conferir `F`, `E`, modo absoluto/relativo, overrides e os limites
do firmware. O SimuCNC consultado calcula duração por distância e feed, mas
seu `StartMove` não limita a vazão/capacidade de alimentação do extrusor.
Assim, essa simulação também não valida os limites reais do filamento.

**Fontes:**

- `multislicer/src/core/multislicer_pipeline.pas`: `TSliceSettings`,
  `ExtrusionPerMM` (161–167), `TGCodeWriter.SetF` (568–574), `Slice`.
- `multislicer/src/core/multislicer_profile.pas`: `DefaultPrinterProfile`.
- `multislicer/src/core/multislicer_types.pas`: `TPrinterProfile`.
- `multislicer/src/app/multislicer_main.pas`: campo `PrintSpeed` (87),
  `Settings` (128–145).
- `src/core/multicnc_printer_profiles.pas`: `TPrinterProfile`.
- `src/app/mainform.pas`: `PrinterModelChanged`, `FeedRateChanged`.
- `src/app/multicnc_session.pas`: `Start`.
- `src/core/multicnc_machine.pas`: `Pump`.
- `src/protocols/multicnc_marlin.pas`: `ReceiveBufferSize`.
- Dependência `aimarlinsimulator.pas`, commit indicado no BUG-011:
  `StartMove` (297–332), `Advance` (496–550).

**Reprodução:** gerar o mesmo trecho com diâmetros de filamento distintos
usando o núcleo e comparar `E`; verificar que a aplicação não oferece essa
seleção. Variar velocidade, largura e altura do cordão e calcular a vazão
solicitada pelo G-code, verificando que não existe teto configurável. Comparar
o G-code efetivamente utilizado pelo usuário e os overrides `M220`/`M221` com
o perfil e os limites do firmware, antes de atribuir a velocidade ao executor.

**Correção proposta:** compartilhar/configurar o perfil correto no momento do
fatiamento, permitir informar o diâmetro do filamento e limitar a geração pela
vazão máxima e capacidade do extrusor. Validar esses parâmetros e registrar
os pressupostos no G-code. Não recalcular automaticamente `E` de um arquivo
já fatiado ao trocar de perfil no executor. Cobrir matematicamente a vazão e
validar o tempo de movimentos/extrusão no simulador e no equipamento adequado.

## BUG-015 — Override laser produz F duplicado e ignora linhas sem F

**Evidência:** confirmada nos fontes; rejeição prevista no parser do SimuCNC
consultado. Relacionada à integração das configurações laser com o executor.

Com `OverrideSpeeds` habilitado, `TransformGCodeForLaser` verifica se uma
linha `G1`, `G2` ou `G3` contém ` F`. Se contém, acrescenta outro campo `F`
ao fim, sem remover o existente. Se não contém, não acrescenta o feed
configurado. Por exemplo, configurar 600 para `G1 X10 F1000` produz
`G1 X10 F1000 F600`, em vez de substituir o valor.

`TAIGCodeParser.Parse` da dependência recusa parâmetros repetidos com
`Duplicate parameter`. No SimuCNC, isso impede a execução do comando.
Também há impacto inferido para controladoras que rejeitem essa duplicação.
Se a rejeição ocorrer após acionar o laser, o caminho de erro sem desligamento
descrito no BUG-010 passa a ser relevante.

**Fontes:**

- `src/core/multicnc_laser_config.pas`: `TransformGCodeForLaser` (166–170).
- `src/app/multicnc_session.pas`: `Start`, `CheckFirmwareFaults`.
- Dependência `aigcodeparser.pas`, commit indicado no BUG-011: `Parse`,
  verificação `Command.Present[Key]`.

**Reprodução:** transformar e enviar uma linha com `F` existente, uma sem
`F` e uma com escrita compacta/minúscula, com override habilitado. Conferir
que há exatamente um feed correto por movimento ao qual o override se aplica.
Separar essa verificação da contagem/confirmação dos BUG-009 e BUG-011.

**Correção proposta:** alterar parâmetros com um parser de G-code, preservando
comentários e formatos aceitos; substituir `F` existente e inserir o valor
quando necessário. Não concatenar palavras duplicadas.

## BUG-016 — Falta log automático em arquivo das últimas 24 horas

**Evidência:** confirmada nos fontes do fluxo de console do MultiCNC.
**Solicitação do usuário:** gravar em arquivo o funcionamento do último dia,
para permitir investigar laser, router e impressão 3D. **Estado:** aberto;
requisito registrado para implementação.

Atualmente, `Session.OnLog` alimenta `TMainForm.Log`, que mantém mensagens em
`MemoLog`. Cada linha recebe somente a hora (`hh:nn:ss`), sem data, e as linhas
mais antigas são eliminadas quando a lista passa de 1.000. `ClearLogClick`
apaga esse conteúdo. O console também se perde ao fechar a aplicação.

Existe a ação manual **Save Log...**, mas `SaveLogClick` salva apenas o
conteúdo ainda presente no console, quando o usuário escolhe um arquivo.
Esse fluxo não grava continuamente nem garante o histórico das últimas
24 horas. Não é possível recuperar retroativamente mensagens já descartadas.

Há também lacunas no conteúdo necessário ao diagnóstico: `SerialTX` filtra
consultas periódicas e é ligado somente ao transporte serial em `Connect`;
`Receive` retira relatórios GRBL de estado e determinadas respostas de
temperatura. Copiar apenas o console para um arquivo não produz um registro
completo e uniforme de operação por serial, TCP e simulador.

**Fontes:**

- `src/app/mainform.pas`: ligação de `Session.OnLog` ao criar o formulário,
  `Log` (1508–1526), `SaveLogClick` (2236–2256), `ClearLogClick`.
- `src/app/multicnc_session.pas`: `Diag`, `SerialTX`, `Receive`, `Connect`.
- `src/core/multicnc_machine.pas`: `Pump`, `TransportData`, controle da fila
  e respostas que precisam integrar o diagnóstico.

**Reprodução da limitação atual:** operar a aplicação até ultrapassar 1.000
linhas, salvar o console e verificar que o início da atividade foi descartado.
Fechar/reabrir sem salvar e verificar que o histórico anterior não é
restaurado. Conferir que não existe ação para obter o período das últimas
24 horas, atravessando sessões e a mudança de data.

**Comportamento solicitado / critérios de aceitação:**

1. Gravar automaticamente em arquivo desde a inicialização, preservando ao
   menos as últimas 24 horas entre encerramentos e reinícios. Um arquivo por
   data, como `multicnc-AAAA-MM-DD.log`, pode organizar esse histórico; obter
   as últimas 24 horas precisa abranger ambas as datas quando houver meia-noite.
2. Registrar data, hora com milissegundos e fuso, identificador da sessão,
   versão/build e tipo de evento, permitindo reconstruir a ordem das operações.
3. Incluir máquina, protocolo, porta/endpoint e baud, conexão/reconexão,
   arquivo executado, parâmetros aplicados, início, pausa, retomada, parada,
   término, progresso, erros, alarmes e falhas de comunicação.
4. Registrar TX/RX nos três transportes e a relação entre comando enviado e
   resposta recebida. Preservar no arquivo as informações de estado e
   temperatura necessárias ao diagnóstico, mesmo que a tela use filtros.
   Em especial, permitir conferir solicitação, transmissão e resposta de `M5`.
5. Oferecer **Exportar log das últimas 24 horas** e acesso à pasta dos logs,
   sem depender do conteúdo limitado do console. Limpar o console não deve
   apagar o histórico persistente.
6. Usar pasta gravável do usuário em Windows/Linux, com rotação e política de
   retenção que preserve o período solicitado. Não sobrescrever o histórico
   ao reabrir a aplicação; sinalizar falha de gravação e não bloquear o
   controle/streaming da máquina com escrita de log.

**Correção proposta:** introduzir um registrador persistente compartilhado
pela sessão e pelos transportes, capturando eventos antes dos filtros da
interface. A tela pode continuar resumindo a atividade; o arquivo deve
conservar os dados necessários para diagnóstico do período solicitado.

**Validação após implementação:** operar com serial, TCP e simulador; fechar
e reabrir; passar da meia-noite; ultrapassar 1.000 linhas; limpar o console;
exportar as últimas 24 horas e conferir continuidade, timestamps e TX/RX.
Validar também falha de escrita e fluxo de desligamento do laser.

## O que os testes atuais confirmam — e seus limites

O CI de suíte do commit avaliado registrou **79 testes aprovados, três falhas de
compilação e um teste TCP ignorado**. O número 83 apresentado pelo runner é o
número de registros, incluindo o teste ignorado; não significa 83 execuções
aprovadas.

As conversões CAD → STL/3MF → slicer e PCB + Assembly → modelo unificado →
Physics passaram no nível de núcleo. Também passaram os testes de contexto,
lançamento de arquivo, workspace e vários testes de geometria e fabricação.

`test_launcher_delivery.lpr` usa uma cópia do próprio executável de teste para
conferir os argumentos recebidos. Não abre LaserPCB/RouterPCB com a pasta
Gerber. `test_suite_app.lpr` registra e reabre o workspace, mas não confirma
carregamento nas cinco ferramentas do BUG-002. `test_slicer_app.lpr` cobre STL,
prévia/exportação e invalidação de configurações; não cobre a abertura de 3MF.
Esses testes úteis ainda não validam o percurso completo entre aplicações.

`tests/test_session.lpr` inicia duas linhas em modo laser com
`TSimulatorTransport`, mas confere estado e contagem, sem verificar o conteúdo
integral enviado depois da transformação. O transporte confirma comentários
e emite o banner GRBL esperado ao parar, diferentemente do SimuCNC consultado.
`TestSessionJob` em `tests/test_streaming.lpr` confere a sequência enviada no
modo router; não cobre a mudança de contagem por preparação laser/framing.
`tests/test_simucnc_tcp.py` verifica conexão, movimentos e reconexão, mas não
cobre comentário da preparação laser, desligamento final ou Ctrl-X seguido de
retomada. Esses cenários precisam de cobertura específica. Os testes de sessão
citados estão entre as falhas de compilação Linux registradas no BUG-007.

Referência da execução: [Suite CI do commit avaliado](https://github.com/marcelomaurin/multicnc/actions/runs/37938099064),
job `console-tests` (`113845171462`).

## Menor sequência de validação para avançar

1. **Pasta de fabricação:** MakePCB → LaserPCB e RouterPCB, com caminho contendo
   espaços. Confirmar camadas, dimensões e furos importados.
2. **Versão da placa:** exportar, editar e abrir novamente no destino. Exigir
   regeneração e confirmar que a alteração aparece na geometria importada.
3. **Artefato real pela suíte:** abrir um projeto de cada ferramenta do BUG-002.
   Verificar conteúdo restaurado, não somente título e processo iniciado.
4. **Peça até programa:** exportar STL e 3MF do mesmo modelo, abri-los pela
   aplicação MultiSlicer e comparar dimensões/camadas; abrir o G-code Marlin no
   MultiCNC e verificar máquina/protocolo. Para Klipper, validar destino externo
   compatível ou rejeição explícita no MultiCNC.
5. **Montagem até simulação:** transferir placa/montagem reais ao Physics e
   conferir IDs, parâmetros e conexões. A demonstração não substitui esse teste.
6. **Executor até simulador:** corrigir a seleção do transporte, compilar a
   sessão no Linux e validar TCP com SimuCNC: carregar, iniciar, pausar, retomar,
   parar e desconectar. Verificar que a reconexão não executa comandos antigos.
7. **Laser completo:** registrar as linhas preparadas, enviadas e confirmadas
   em uma e várias passadas, com e sem assistência de ar. Testar framing com
   quantidades distintas de linhas. Confirmar que desligamento faz parte do
   encerramento e que atraso/erro no M5 não aparece como sucesso.
8. **Laser no SimuCNC:** executar o exemplo do BUG-011 e um programa maior que
   o buffer. Verificar resposta aos comentários e potência ao terminar;
   injetar erro e conferir o caminho de desligamento. Validar override de feed.
9. **Router e reconhecimento:** testar conexão sem resposta, texto inválido
   e resposta compatível. No SimuCNC GRBL, parar com Ctrl-X e enviar outro
   comando, verificando que o reset foi reconhecido e a espera liberada.
10. **Impressão e filamento:** conferir diâmetro configurado, seção do cordão,
    `E`, `F`, modos de extrusão, overrides e limites de vazão do perfil. Medir
    tempo e alimentação em um trecho conhecido. Diferenciar envio serial,
    duração simulada e movimento físico.
11. **Histórico de diagnóstico:** implementar o BUG-016 e validar o arquivo
    automático e a exportação das últimas 24 horas após reinício, meia-noite,
    console limpo e mais de 1.000 mensagens, nos três transportes.

Priorizar o desligamento laser (BUG-010), com os BUG-009 e BUG-011 que afetam
seu fluxo. Em seguida, validar reset/reconhecimento da CNC (BUG-012 e BUG-013)
e a impressão relatada (BUG-014 junto dos BUG-004 e BUG-008). O BUG-016 deve
acompanhar esse trabalho para preservar evidências dos testes de operação.
No fluxo de PCB,
priorizar BUG-001 e BUG-003; no Linux, BUG-007. Ligar os carregadores e
conversores às aplicações para que os testes de núcleo correspondam ao
percurso disponível ao usuário.
