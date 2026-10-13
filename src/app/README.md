# MultiCNC - guia do painel 0.1.0.3

O MultiCNC abre, analisa e envia programas G-code para CNC Router, CNC Laser e
impressora 3D compatíveis. A interface oferece **Serial**, **TCP** e **Simulador
local**, com estado, posição, confirmações e mensagens da controladora.

[Manual ilustrado em português (PDF)](../../docs/Manuals/Manual_do_Usuario_MultiCNC_0.1.0.3_PT-BR.pdf) · [Manual em texto](../../docs/Manuals/Manual_do_Usuario_MultiCNC_0.1.0.3_PT-BR.md) · [17 capturas atuais](../../imgs/manual_multicnc_0_1_0_3/README.md)

Referência: executável `bin/multicnc.exe` **0.1.0.3**, Windows x64; documentação
conferida nas fontes do commit **687756e**, em **12/10/2026**. Alguns controles
usam rótulos em inglês, preservados nas instruções abaixo.

## Capturas da interface

As imagens mostram o **MultiCNC 0.1.0.3**, referência do manual ilustrado,
com exemplos demonstrativos de **12/10/2026**.

![MultiCNC: programa G-code, jog manual, posição e controles de execução](../../imgs/manual_multicnc_0_1_0_3/01_programa.png)

| Router: equipamento e conexão | Trajetória e análise |
|---|---|
| ![MultiCNC: perfil de router, porta serial e equipamentos salvos](../../imgs/manual_multicnc_0_1_0_3/02_router_config.png) | ![MultiCNC: prévia XY, limites, estimativa de tempo e análise do G-code](../../imgs/manual_multicnc_0_1_0_3/04_analise.png) |

| Laser: prévia do trabalho | Impressão 3D: programa e temperaturas |
|---|---|
| ![MultiCNC: trajetória do laser e limites de análise](../../imgs/manual_multicnc_0_1_0_3/09_laser_previa.png) | ![MultiCNC: G-code de impressão e painel de temperaturas do bico e da mesa](../../imgs/manual_multicnc_0_1_0_3/11_impressora_painel.png) |

| Console no simulador local | Acessórios e joystick |
|---|---|
| ![MultiCNC: comandos enviados e respostas no Console do simulador](../../imgs/manual_multicnc_0_1_0_3/05_console.png) | ![MultiCNC: detecção, mapeamento e ajustes do joystick](../../imgs/manual_multicnc_0_1_0_3/12_joystick.png) |

[Ver as 17 capturas e suas descrições](../../imgs/manual_multicnc_0_1_0_3/README.md) · [Manual ilustrado em português (PDF)](../../docs/Manuals/Manual_do_Usuario_MultiCNC_0.1.0.3_PT-BR.pdf)

## Operação básica

1. Abra **Config** e escolha **Machine**, marca, modelo e protocolo. Router e
   laser normalmente usam GRBL; a impressora correspondente usa Marlin.
2. Confira curso/área útil, porta COM e baud ou IP/porta TCP. Para aprender sem
   equipamento, escolha **Simulador local**.
3. Abra o programa por **Open Program...**, `Ctrl+O`, arrastando o arquivo ou
   recebendo-o pelo launcher. O limite é 5 MB; o arquivo precisa ter comandos.
4. Confira **Trajetoria e analise**, projeções XY/XZ/YZ, limites e avisos.
5. Clique **Connect Device** e aguarde a controladora pronta. Consulte **Console**
   e **Status / Pos** se houver dúvida sobre a conexão.
6. Estabeleça referência e zero conforme o equipamento e o programa. Use **Start**
   para iniciar, **Pause** para suspender, **Resume** para continuar e
   **Emergency Stop** para interromper.
7. Acompanhe os comandos confirmados e salve o registro do Console quando necessário.

A confirmação `ok` não comprova, por si só, conclusão física do movimento. O botão
Emergency Stop depende da comunicação e do firmware; mantenha disponível a parada
física apropriada. Após interrupção, uma nova partida reinicia o programa; não há
retomada automática por linha.

## Interface e arquivos

| Área | Funções |
|---|---|
| Cabeçalho | Estado, equipamento salvo e conexão/desconexão |
| Painel esquerdo | Step, Feed rate, jog XY/Z, HOME, homing, zero e consulta de posição |
| Program | Texto original somente para leitura; busca com Ctrl+F, F3 e Enter |
| Config | Máquina, comunicação, cadastro, perfis e parâmetros de processo |
| Console | Envio manual quando permitido, respostas, salvar e limpar registro |
| Trajetoria e analise | XY/XZ/YZ, limites, avisos e exportação de relatório |
| Acessórios | Joystick e comandos/atalhos do spindle da router |
| Rodapé | Progresso dos comandos confirmados |

Os filtros incluem `.nc`, `.gcode`, `.tap`, `.cnc`, `.ngc` e, para impressora,
`.gco`. Comentários e linhas vazias permanecem no texto exibido; a sessão remove
comentários completos e delimitadores da lista de envio. A busca ignora
maiúsculas/minúsculas e retorna ao início depois da última ocorrência.
O Console mantém as últimas 1000 linhas. Use **Save Log...** para preservar o
registro e **Clear Console** para limpar a exibição.

Abrir outro arquivo, desconectar e operar movimentos manuais ficam bloqueados
durante execução/pausa. Edite o G-code na ferramenta de origem e abra-o novamente.

## Equipamentos salvos

Em Config, ajuste máquina, perfil, protocolo, comunicação e curso. Preencha um
nome em **Equipamentos salvos** e clique **Salvar**. O mesmo nome atualiza o
cadastro; **Novo nome** conserva os parâmetros para cadastrar outro equipamento.
**Excluir** exige confirmação e sessão desconectada. A lista do cabeçalho
restaura as configurações; a conexão só começa em Connect Device.

O cadastro fica em `%LOCALAPPDATA%\Maurinsoft\MultiCNC\multicnc.json`, com versão
anterior em `multicnc.json.bak`. Guarda também especificações CUSTOM do laser.
Potência, velocidades, passadas e temperaturas desejadas continuam sendo ajustes
de trabalho; o cadastro não persiste uma receita completa. Uma porta salva
ausente continua selecionada, sem troca automática para outra COM.

## Serial, TCP e simulação

- **Serial:** abra a lista COM Port para atualizar os dispositivos e confira baud.
  A sessão usa 8N1. Porta aberta ainda pode estar aguardando a inicialização da placa.
- **TCP:** informe IPv4 e porta de 1 a 65535. Para SimuCNC no mesmo computador,
  use `127.0.0.1:9000` quando o servidor estiver configurado assim. Não use
  `0.0.0.0` como destino. Consulte [SimuCNC TCP](../../docs/SIMUCNC_TCP.md).
- **Simulador local:** executa a sessão demonstrativa dentro do MultiCNC, sem
  conectar uma máquina física. É diferente do servidor do SimuCNC.

GRBL é identificado por banner, formato de estado e consulta `$I` em repouso.
O Console informa o firmware reconhecido; reconectar descarta a identificação
anterior. Marlin aguarda o boot antes das consultas de identificação e temperatura.

## Trajetória, limites e análise

A análise e a prévia compartilham `TGCodeAnalyzer`: movimentos G0/G1, arcos G2/G3,
unidades, coordenadas absolutas/relativas e planos. Azul indica corte, cinza
pontilhado indica rápido e vermelho indica fora dos limites de análise.

**Limites de analise...** configura mínimos/máximos XYZ, avanço máximo/rápido e
acelerações XY/Z no sistema de coordenadas do programa. **Exportar relatorio...**
salva o resultado em texto. Esse envelope é diferente do curso cadastrado na máquina.

Homing, G53, G92 e probe podem tornar a análise parcial. Offsets de múltiplos
sistemas e compensações de ferramenta não formam uma transformação completa da
máquina. A estimativa não inclui toda espera de aquecimento nem garante tempo físico.
A prévia conserva até 200 mil segmentos; a análise limita-se a 1 milhão, indicando
erro e análise parcial ao atingir o teto. Divida arquivos extensos quando necessário.

No simulador local, erros da análise bloqueiam Start. Na conexão real, revise
também posicionamento, curso, compatibilidade e avisos. A prévia não verifica
colisões, grampos, remoção de material ou qualidade do processo.

## Jog, referências e origem

**Step (mm)** determina a distância por clique (0,01 a 100 mm) e **Feed rate** o
avanço manual (1 a 10000 mm/min). O perfil e o estado da sessão restringem os
movimentos. Na impressora, **Go To Position** solicita uma posição absoluta XYZ.

| Comando | Finalidade |
|---|---|
| Physical Homing | Referência física pelos sensores: `$H` GRBL / `G28` Marlin |
| Set Home Ref | Grava referência HOME sem movimento, usando `G28.1` no fluxo CNC |
| Go Home | Retorna à referência conforme o protocolo |
| Zero Workpiece | Define a origem de trabalho atual no fluxo CNC (`G92`) |
| Status / Pos | Consulta estado e posição |
| Unlock | Solicita desbloqueio/reinicialização compatível; examine a causa do alarme antes |

Perfis sem homing desabilitam o comando físico. Na impressora, Set Home Ref e
Zero Workpiece não aparecem. Não confunda origem da peça com referência física.

## Router, laser e impressora

**Router:** confira perfil, curso, ferramenta, zero e profundidades. Em
Acessórios > Router - spindle, configure S e use **Ligar spindle** / **Desligar
spindle**. Exigem router/GRBL em operação manual pronta. A escala de S depende
da placa e do spindle; soltar o atalho não desliga a ferramenta.

**Laser:** configure marca/modelo ou CUSTOM, área XY e especificações ópticas.
Confira M3/M4, escala Max S, comandos de ar e framing. **Outline** percorre a caixa
XY com laser desligado e avanço automático visando 8 segundos; **Frame (Test)**
usa avanço de framing e pode habilitar laser de teste, desligado por padrão.
Aguarde a conclusão e confira a posição antes de Start. Consulte
[Outline](../../docs/OUTLINE.md) e [perfis](../../docs/LASER_PROFILES.md).

Os campos de laser têm processamento parcial em 0.1.0.3: a transformação troca
M3/M4, repete passadas, acrescenta pausa/descida entre passadas de corte e pode
acrescentar F às linhas reconhecidas com avanço. Os S originais não são
reescalados universalmente. Picote não segmenta automaticamente o contorno;
kerf, min/max power, rapid feed e pre/post fire não possuem aplicação completa.
Prepare esses parâmetros no LaserArt/LaserPCB ou CAM de origem; o manual detalha
o comportamento de cada grupo para evitar interpretar um campo como processamento pronto.

**Impressora:** selecione o perfil Marlin compatível, confira volume e limites
térmicos e abra o G-code fatiado. **Set Targets (M104/M140)** envia os alvos do
bico/mesa sem aguardar o aquecimento; **Cooldown Heaters** envia alvo zero.
O arquivo pode alterar os alvos novamente. Acompanhe leituras reais separadamente.

## Joystick e compatibilidade

Em **Acessórios**, selecione o controle, eixos/inversões, botões de Z, zona morta,
velocidade e passo máximo; **Salvar configuracao** persiste em `joystick.ini`,
cujo caminho aparece na aba. Windows oferece XInput/WinMM. Padrão Xbox: analógico
esquerdo XY, RB Z+, RT Z-. Z depende do perfil.

Centralize o analógico e solte os botões após conectar ou voltar à janela.
Movimentos ficam suspensos em execução/pausa, edição, diálogos e perda de foco.
GRBL 1.1 usa jog nativo e cancelamento; Marlin conclui o passo curto atual.
GRBL antigo não oferece joystick contínuo. Atalhos de ligar/desligar spindle
devem usar botões diferentes entre si e dos controles de Z.
Consulte [o guia de joystick](../../docs/JOYSTICK.md).

Para GRBL antigo, o jog manual consulta `$$`/`$G`, exige unidades/modos
compatíveis e restaura os modos após o passo. A adaptação não grava firmware.
O início verifica comandos conhecidos incompatíveis com GRBL, incluindo
extrusão E, comandos de impressora e checksum Marlin; a mensagem aponta a linha.
Gere o arquivo para o equipamento/protocolo correto.

## Integração e organização técnica

LaserArt/LaserPCB, MakeRouter/MultiCAM/RouterPCB e MultiSlicer preparam o trabalho.
Cabeçalhos podem sugerir o tipo de máquina quando desconectado. MS-DATUM,
MS-STOCK e MS-BOUNDS são registrados no log, mas não estabelecem o zero físico
nem implementam toda a conferência de offsets. Consulte
[o contrato de G-code](../../docs/CONTRATO_GCODE.md).

- `mainform.pas`: telas, carregamento, análise e ações.
- `multicnc_preview.pas`: projeções dos segmentos do analisador.
- `multicnc_session.pas`: transportes serial/TCP/simulador, estados e envio.
- `multicnc_accessories.pas`: joystick e comandos/atalhos de spindle.
- `multicnc_gcode_analyzer.pas` / `multicnc_gcode_preflight.pas`: limites, trajetória e estimativa.

Os projetos `tests/test_app.lpi`, `tests/test_equipment_app.lpi` e
`tests/test_accessories_ui.lpi`, junto dos testes de sessão/protocolo, verificam
fluxos sem movimentar uma CNC física. A compilação do painel usa
`lazbuild src/app/multicnc.lpi`, com Lazarus/LCL e dependências CHATGPT configuradas.
