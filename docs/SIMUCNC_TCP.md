# SimuCNC: servidor TCP Marlin

O SimuCNC pode receber G-code por uma conexão TCP persistente e enviar as respostas
Marlin na mesma conexão. A simulação atualiza a mesa 3D, o bico e os segmentos de
material extrudado. Este modo dispensa com0com, portas COM e adaptadores físicos.
O servidor é executado enquanto a aplicação está aberta; não é um serviço Windows.

## Uso

1. Abra `bin/SimuCNC.exe` e selecione **TCP** no combobox **Comunicação**. Apenas os campos TCP serão exibidos.
2. Selecione o equipamento e o protocolo: **Impressora 3D** oferece **Marlin** e **GRBL**;
   **CNC Router** e **CNC Laser** usam **GRBL**.
3. Informe **IP local TCP** e **Porta TCP**. O padrão é `0.0.0.0:9000`, escutando em todas as interfaces.
   No MultiCNC, selecione TCP no combobox Comunicação, use `127.0.0.1` e porta
   `9000` para o mesmo computador, escolha protocolo Marlin e clique em Conectar.
4. Clique em **Iniciar TCP**.
5. Conecte um cliente TCP ao endereço e envie G-code terminado em LF (`\n`)
   ou CRLF. Por exemplo, `M115\n` consulta o firmware e `M105\n` a temperatura.
6. Aguarde as respostas `ok` antes de enviar o próximo comando. As respostas,
   inclusive erros e mensagens de espera, voltam no mesmo socket.
7. Arraste a visualização para rotacionar e use a roda do mouse para zoom.
   Clique em **Parar TCP** para fechar cliente e servidor.

Para atender outra máquina, informe o IPv4 local da interface de rede ou `0.0.0.0`
(todas as interfaces). O cliente deve usar o IP real do computador do SimuCNC,
jamais `0.0.0.0`. Se necessário, permita a conexão de entrada no firewall.
O protocolo é TCP bruto, sem HTTP, Telnet, autenticação ou TLS; use em rede de testes confiável.

Apenas uma controladora é aceita por vez; conexões adicionais são fechadas.
A serial e o TCP são alternativas exclusivas. Pare um transporte antes de iniciar
outro. O combobox de comunicação fica bloqueada enquanto a serial ou o servidor TCP estiver ativo. Ao desconectar, a simulação pausa; cada nova conexão reinicia o estado
Marlin e limpa a peça para não herdar comandos parciais da sessão anterior.

`SimuCNC.exe -tcp` inicia a escuta automaticamente no endereço padrão.

## Componentes e validação

O motor Marlin existente e a visualização são reutilizados. O componente genérico
`aitcpserver.pas` foi acrescentado ao projeto CHATGPT, em `pacote/AI Input/AISockets`,
sem alterar o `aisockets.pas`. Ele atende um cliente, usa sockets não bloqueantes,
trata envios parciais e limita a fila de saída a 1 MB. Esta implementação usa
Winsock2 e tem como alvo Windows.

Execute `powershell -File tests/run_tcp_tests.ps1` (Lazarus em `C:\lazarus`,
FPC 3.2.2 e Python no PATH). Deixe a porta 9000 livre antes do teste.
O teste abre o SimuCNC, verifica comandos fragmentados, CRLF, comandos agrupados,
firmware, movimento, temperatura e reconexão. Também instancia a sessão e o
transporte reais do MultiCNC para verificar envio de G-code com quebra de linha,
respostas em repouso e reconexão. Encerra somente o processo de teste ao terminar.
A automação verifica a comunicação; a aparência da mesa não é validada por ela.

## Visualização da impressão

A mesa quadriculada, o cabeçote e a ponta do bico usam as mesmas coordenadas XYZ.
O bico acompanha inclusive movimentos sem extrusão; somente o material depositado
pelo motor Marlin é acrescentado à peça, em azul. Extrusão a frio continua sujeita
às regras do simulador. A atualização visual ocorre a cada 33 ms aproximadamente.
Arraste para girar, use a roda para zoom e dê duplo clique para restaurar a vista.
Os botões Perspectiva, Superior e Frontal mudam o ângulo; Estrutura exibe as guias.
A geometria exibida representa os trajetos de filamento, não um STL importado.

### CNC Laser

Selecione **CNC Laser** e **GRBL** no SimuCNC. O servidor aceita `M3 S0..1000`
ou `M4 S0..1000` para ligar o laser, `M5` para desligá-lo e movimentos `G0/G1`
com `X`, `Y`, `F` e `S`. A mesa passa para fundo branco e cada trecho percorrido
com potência acima de zero é desenhado em preto, representando a área queimada.
Movimentos sem laser ligado deslocam o cabeçote sem marcar a mesa.
O CNC Laser não possui eixo Z: comandos que tentem movimentar Z são recusados e
o cabeçote permanece na altura fixa de foco.
