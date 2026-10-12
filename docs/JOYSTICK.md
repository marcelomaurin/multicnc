# Controle de joystick — MultiCNC 0.1.0.3

A aba **Acessórios**, imediatamente depois de **Trajetoria e analise**,
configura o joystick para o equipamento conectado no MultiCNC: router,
laser ou impressora 3D. A conexao do equipamento continua sendo feita
pelos controles existentes. O joystick nao seleciona nem conecta uma CNC.

No Windows, o componente `TAIJoystick` da biblioteca CHATGPT reconhece
automaticamente controles XInput, como Xbox 360, e joysticks genericos
expostos pelo driver WinMM. Xbox 360/XInput tem prioridade na descoberta.
O controle ativo permanece selecionado ate desconectar; e possivel escolher
um dispositivo especifico. Um mesmo Xbox pode aparecer tambem como WinMM:
prefira a entrada XInput, que disponibiliza gatilhos independentes.

Padrao:

| Controle Xbox 360 | Movimento |
|---|---|
| Analogico esquerdo horizontal | X |
| Analogico esquerdo vertical (para cima) | Y+ |
| RB, botao superior direito | Z+ |
| RT, gatilho inferior direito | Z- |

Os eixos, a inversao de X/Y e os dois controles de Z podem ser alterados.
Por exemplo, LB/LT permitem usar o lado esquerdo. O monitor mostra os
numeros dos botoes pressionados para configurar outros modelos. WinMM
fornece botoes 1..32; LT=33/RT=34 sao controles virtuais exclusivos do XInput.
O Z so funciona quando o perfil do equipamento suporta esse eixo; o perfil
laser padrao trabalha apenas em X/Y.

## Ligar e desligar spindle da router

Em **Acessórios > Router - spindle** ha dois comandos separados:
**Ligar spindle** e **Desligar spindle**. Escolha o **Botao para ligar spindle**
e o **Botao para desligar spindle**, configure **Rotacao / valor S (RPM)** e
clique **Salvar configuracao**. Os atalhos inicialmente ficam em **Sem atalho**;
por exemplo, X pode ligar e B pode desligar, conservando RB/RT para o Z.
Nao e permitido usar o mesmo botao para duas funcoes, nem compartilhar com Z.

Uma pressao envia um unico comando; manter pressionado nao repete. O spindle
permanece ligado depois de soltar o botao. Para desligar, use o comando de
desligamento ou a parada existente. A janela precisa estar ativa e o joystick
liberado em repouso antes de aceitar um novo atalho. Para ligar, centralize o
analogico e aguarde a controladora ociosa. Desligar durante um jog cancela esse
movimento antes de enviar o desligamento e exige voltar ao repouso para mover.
Se os dois botoes forem pressionados juntos, desligar tem prioridade.

Esses comandos sao exclusivos da router com GRBL conectado em operacao
manual; ficam bloqueados durante programas em execucao/pausa e nos modos
laser/impressora. Os botoes na tela funcionam mesmo com o joystick desativado.
Ligar envia `M3 S<valor>` e desligar envia `M5`, com controle de fluxo normal.
O console informa solicitacao, recusas e respostas do firmware; envio nao e
confirmacao de rotacao fisica.

O valor inicial de S e 1000, configuravel de 1 a 100000 e limitado tambem
pelo maximo do perfil de router, quando informado. Ajuste S conforme o spindle
e a escala `$30` da controladora; a velocidade fisica depende dessa configuracao.
Mapeamento e valor S ficam no mesmo `joystick.ini` em AppData.

Zona morta padrao: 20%. Velocidade maxima inicial: 500 mm/min, ajustavel
de 1 a 3000. A velocidade acompanha a inclinacao do analogico; diagonais
tem velocidade vetorial limitada. Cada pulso tem no maximo 2 mm e usa a
distancia correspondente a 100 ms na velocidade escolhida (ou o passo
maximo configurado, o que for menor). Aceleracao da maquina e comunicacao
podem aumentar a duracao real de um pulso.

Ao conectar, trocar de controle, mudar o mapeamento, sair de um dialogo ou
retornar a janela, solte os botoes e centralize o analogico. Apenas depois
disso os movimentos sao liberados. O joystick fica suspenso enquanto um
programa esta em execucao ou pausado, durante edicao de campos, dialogos,
alarmes, inicializacao ou perda de foco. Desativar o joystick tambem cancela
seu movimento. Os botoes de parada existentes continuam disponiveis.

Nao ha fila de varios pulsos. Em GRBL 1.1, cada movimento usa `$J=G91 G21`,
e o proximo aguarda um novo estado Idle. Soltar/desconectar/suspender envia
o cancelamento de jog `0x85`, seguido de `G4 P0` para sincronizar. GRBL
antigo nao tem suporte ao joystick continuo; os controles manuais existentes
continuam disponiveis. Em Marlin, `G21/G91/G1/G90/M400/M114` executa um unico
passo e aguarda a conclusao fisica antes do proximo. Ao soltar, esse passo
curto termina; nao e enviado M410, que pode perder a referencia da posicao.
Um erro ou reinicio durante jog suspende o joystick ate reconectar a CNC.

Clique **Salvar configuracao** para persistir as escolhas. O caminho
`joystick.ini` fica na pasta de configuracao do MultiCNC em AppData e aparece
na propria aba. As alteracoes sao aplicadas imediatamente na sessao; salvar
as conserva para a proxima abertura. O console registra deteccao, estados,
recusas e comandos enviados.

## Compilacao e validacao

A copia local da biblioteca CHATGPT deve incluir
`pacote/AI Input/AIJoystick/aijoystick.pas` e o diretorio deve estar nos
caminhos do compilador. `MULTICNC_CHATGPT_DIR` seleciona a raiz da biblioteca;
`tools/verify_suite.py` e `installer/windows/build_release.ps1` ja incluem
o novo caminho. `third_party/chatgpt/AIJoystick` conserva uma copia identica
do novo componente para builds com revisoes antigas da biblioteca, inclusive
o commit atualmente fixado no CI. Ao atualizar o componente na biblioteca,
sincronize essa copia e seus testes. A copia externa e usada quando disponivel.

`tests/test_joystick.lpr` usa dispositivos e transportes falsos: normalizacao,
hotplug, prioridade, mapeamento, persistencia, zona morta, diagonais, bloqueios,
cancelamento e protocolos. `tests/test_accessories_ui.lpi` verifica a nova
aba e a gravacao/restauracao da configuracao. Nenhum teste movimenta CNC real.
Validacao fisica com joystick e maquinas ainda pendente; sem joystick
conectado a aba mostra **Aguardando joystick**.

`tests/test_router_spindle.lpr` acrescenta 57 verificacoes de persistencia,
conflitos de botoes, acionamento por pressao, prioridade de desligamento,
rotacao, restricoes de equipamento/programa e cancelamento de jog.
O teste de interface verifica tambem os comandos manuais e a gravacao/restauracao
dos atalhos do spindle (27 verificacoes no total).

Referencias de protocolo:
- https://github.com/gnea/grbl/wiki/Grbl-v1.1-Jogging
- https://marlinfw.org/docs/gcode/M400.html
- https://marlinfw.org/docs/gcode/M410.html
- https://github.com/gnea/grbl/wiki/Grbl-v1.1-Commands
