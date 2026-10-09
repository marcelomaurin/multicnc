# 13 — Controlador Lazarus: uso e desenvolvimento

## Abrir e compilar

Abra `apps/control/multicnc.lpi` no Lazarus e compile. A interface LCL é criada em Object Pascal, sem formulário `.lfm`. O projeto inicial é Windows/Win64 e utiliza APIs seriais do Windows; Linux ainda não está implementado.

Também é possível executar, no PowerShell:

```powershell
cd C:\projetos\maurinsoft\multicnc\apps\control
.\build.ps1 -LazarusDir C:\lazarus -Test
```

O script usa o FPC 3.2.2 Win64 incluído na instalação indicada. Ajuste o caminho do compilador no script para outra versão de FPC. Saída: `apps/control/bin/multicnc.exe`. Binários e dados de execução não são versionados.

## Experimentar sem equipamento

1. Abra o executável e selecione a aba Demonstração.
2. Clique em Conectar. A worker do simulador gera posições e desenha um rastro.
3. Alterne XY, XZ e YZ; veja as coordenadas e a identificação explícita de simulação.
4. Abra `examples/quadrado-simulacao.gcode` e clique em Executar.
5. Cadastre outro equipamento com protocolo `simulator`, conecte-o e alterne entre abas para observar threads independentes.

O simulador percorre pontos, sem modelar aceleração, velocidade de processo, remoção de material ou aquecimento. Ao ficar ocioso, volta ao movimento demonstrativo. Não usar seu tempo de execução como estimativa de fabricação.

## Cadastrar uma máquina serial

Selecione uma referência do catálogo e revise todos os campos. Informe nome, categoria, marca/modelo, porta COM, baud e protocolo. Os nomes podem ser personalizados. Portas são enumeradas no Windows e também podem ser digitadas.

O cadastro fica em `%LOCALAPPDATA%\MultiCNC\devices.ini`. Salvar mantém backup anterior `.bak`. Editar/excluir exige encerrar a sessão da máquina. Uma porta já usada por outra aba é recusada; o Windows também exige abertura exclusiva.

Conectar abre serial e tenta identificar o firmware. Não há movimento, homing ou energização enviados automaticamente. A própria abertura da porta pode afetar DTR/RTS/reset conforme a placa; configure o perfil real antes da bancada.

## Controle disponível

| Protocolo | Ações nesta versão |
| --- | --- |
| Simulador | Conectar, gráfico, executar pontos lineares, pausar, retomar e cancelar |
| GRBL 1.1 | Identificar, monitorar, enviar G-code linear limitado, hold/resume e reset |
| Marlin/Prusa | Identificar, monitorar posição e desconectar |

Não há jog, homing, controle manual de temperatura, fila persistente ou impressão serial nesta revisão. Comandos não implementados não são simulados como sucesso. M3/M4/M5 em um trabalho GRBL podem controlar emissão/spindle; a execução física exige confirmação dentro da aplicação.

## Ler o gráfico

Cada aba possui seu próprio histórico. Linhas verdes conectam amostras e não reconstroem todo o percurso físico. A prévia cinza é de programa, em coordenadas de trabalho. Ela fica oculta quando a máquina reporta outro referencial. As coordenadas Z continuam visíveis e podem ser projetadas em XZ/YZ.

Uma posição sem atualização é identificada como antiga. Logs e contagem de linhas aceitas são independentes do rastro. Posição projetada Marlin é identificada como tal. Sem sensores adicionais, não é possível detectar perda de passos apenas desenhando a telemetria do controlador.

## Verificações sem hardware

`build.ps1 -Test` compila o aplicativo e os testes de console. Os testes cobrem parsing, fragmentação de respostas, persistência, dois simuladores, snapshots copiados e duas conexões seriais falsas com erro isolado.

`multicnc.exe --smoke` abre uma sessão de teste com simulador, gera `bin/smoke.bmp` e `bin/smoke.txt` ao lado do executável e encerra. Não lê/salva cadastros do usuário nem abre COM. O modo testa criação da janela, timer, worker e desenho; não substitui ensaio manual completo da interface.

## Homologação física pendente

1. Registrar configuração real e documentação do equipamento.
2. Validar identificação e relatórios com a máquina em condição apropriada de bancada.
3. Comparar unidade, referencial e coordenadas com o painel do equipamento.
4. Verificar perda de conexão, reset e alarmes sem depender de parada por software.
5. Só então validar movimentos e processo por perfil, com origem/limites confirmados.

Registrar evidências e limitações em `OBJETIVO_CONTROLADOR.md`. Não promover um modelo pesquisado a “suportado em produção” apenas porque o executável compilou.
