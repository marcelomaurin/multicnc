# MultiCNC - Guia para IA

## Missao
MultiCNC e a camada de execucao fisica da suite. Conecta, configura, monitora e controla CNC Router, Laser e Impressoras 3D usando interface comum e drivers independentes.

## Arquitetura
- multicnc_types.pas: tipos comuns.
- multicnc_interfaces.pas: contratos.
- multicnc_machine.pas: maquina.
- multicnc_profile.pas: perfil/configuracao.
- multicnc_job.pas: trabalho a executar.
- multicnc_safety.pas: seguranca.
- multicnc_devices.pas: dispositivos.
- multicnc_visualizer.pas: visualizacao.
- protocols/multicnc_grbl.pas: GRBL.
- protocols/multicnc_marlin.pas: Marlin.
- transports/multicnc_chatgpt_serial.pas: transporte serial usando a suite CHATGPT.
- transports/multicnc_simulator.pas: transporte simulado.
- app/: GUI e CLI.

## Separacao obrigatoria
Tipo de maquina, protocolo e transporte sao independentes. Nao codifique GRBL diretamente na UI e nao amarre Serial ao protocolo.

## Transportes
Serial/USB-Serial, TCP/IP/Wi-Fi e simulador devem obedecer a mesma abstracao quando implementados.

## Protocolos
GRBL e Marlin sao os iniciais. FluidNC/grblHAL podem ser adicionados sem alterar a camada de aplicacao.

## Fluxo
Abrir trabalho -> visualizar -> carregar perfil -> validar seguranca -> simular quando aplicavel -> conectar -> executar -> acompanhar respostas/estado -> finalizar.

## Integracao
MultiCAM, MultiSlicer, LaserPCB e LaserArt preparam jobs. MultiAssembly descreve a composicao eletromecanica e futuramente pode gerar/auxiliar o perfil. MultiCNC executa.

## Dependencia CHATGPT
Reutilize a biblioteca Lazarus CHATGPT do autor, especialmente AISerial/TAISerialModem e componentes de comunicacao existentes. Nao crie uma segunda implementacao serial sem necessidade.

## Seguranca
E-Stop, limites, estado da maquina e validacao devem ser deterministas. IA pode auxiliar configuracao/diagnostico, mas nunca deve contornar safety nem enviar comandos fisicos sem passar pelas validacoes.

## Regra para IA
Nao coloque CAD, CAM, EDA ou slicing dentro do MultiCNC. Aqui ficam hardware, protocolos, transporte, safety, job execution e monitoramento.

## Correcoes GRBL (2026-10-05)

- A pausa GRBL bloqueia a fila do host antes de enviar `!`. Respostas `ok`
  liberam a contagem de bytes, mas nao enviam novas linhas ate `Resume`.
- O limite de RX e conferido inclusive para a primeira linha. Linhas GRBL
  brutas com mais de 79 bytes sao recusadas conservadoramente (buffer de
  linha padrao de 80 bytes); comentarios e espacos contam neste limite.
- `!`, `~`, `?` e bytes acima de ASCII 126 nao podem aparecer nas linhas
  enfileiradas, pois o firmware interpreta comandos de tempo real fora do
  parser G-code, inclusive em comentarios. Use Pause/Resume/Status.
- A parada por Ctrl-X recusa novos comandos ate receber o banner `Grbl`.
  Um `ok` atrasado nao libera o bloqueio. O banner invalida o WCO anterior.
- `tests/test_grbl_regressions.lpr` cobre pausa/retomada, limite de linha,
  capacidade RX, comandos de tempo real, erro fragmentado e reset/WCO.
  Este teste nao depende de AISerial/LCL e roda no workflow do nucleo.
- Validacao local: regressao GRBL, simulador e numeros independentes da
  configuracao regional passaram com FPC 3.2.2. Sem teste em hardware real.
