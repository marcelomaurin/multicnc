# MultiSuite Bandeja

O executável distribuído no Windows é **multisuite_tray.exe**: atalhos para abrir as aplicações instaladas ao lado do relógio, com o padrão visual restaurado da bandeja.

## Usar a bandeja

Clique no ícone para abrir o painel de aplicativos. A busca filtra as ferramentas; selecione um aplicativo para iniciá-lo. Setas navegam, Enter abre o resultado e Esc fecha o painel. O painel também fecha quando perde o foco.

O menu de contexto oferece **Abrir painel** e **Sair**. Não contém abertura de um aplicativo MultiSuite separado, Central de Testes ou configurações de inicialização. A opção de iniciar com o Windows fica no instalador.

`--tray` inicia apenas na área de notificação; `--show` solicita a abertura do painel. O processo permanece em segundo plano enquanto a bandeja estiver ativa. Use **Sair** para encerrá-lo.

## Aplicativos

A lista utiliza o registro e os executáveis disponíveis. O setup 007 inclui:

| Aplicativo | Finalidade |
|---|---|
| MultiCNC | Conexão, prévia e execução de trabalhos na máquina |
| SimuCNC | Simulação de router, laser e impressora |
| MultiCAD | Projeto mecânico paramétrico |
| MultiAssembly | Montagem eletromecânica |
| MultiPhysics | Simulação física |
| MultiCAM | Preparação e simulação de usinagem |
| MultiSlicer | Preparação para impressão 3D |
| MakePCB | Esquema, componentes e projeto de placa |
| MakeRouter | Desenho e usinagem de madeira |
| RouterPCB | Isolação, furação e recorte por fresagem |
| LaserPCB | Montagem das formas dos componentes e preparação de PCB para laser |
| LaserArt | Desenhos, textos, imagens e vetores para laser |

O décimo terceiro executável é a própria bandeja. MultiPCB foi removido; o projeto de placas está no MakePCB. O pacote não inclui `multisuite.exe` nem `multisuite_test_center.exe`.

## Instalação Windows

[Setup 007](../setup/setup_multcnc_007.exe) · [Notas da versão](../docs/SETUP_007.md) · [Como gerar o instalador](../installer/windows/README.md)

A tarefa **Iniciar a MultiSuite Bandeja com o Windows** vem marcada por padrão e registra `multisuite_tray.exe --tray` na inicialização do usuário. Pode ser desmarcada no setup ou desativada nas configurações de inicialização do Windows. A desinstalação remove esse registro.

## Desenvolvimento

`src/tray/multisuite_tray.lpi` gera a bandeja. Os ícones e controles são reutilizados de `src/core/multisuite_icons.pas` e `multisuite_controls.pas`.

O launcher procura o executável instalado, os caminhos dos projetos de desenvolvimento, `bin` e a raiz do repositório. A lógica de CAD, EDA, CAM, laser e controle permanece nas ferramentas especializadas.

Os fontes de workspace `.msuite`, do gestor de desenvolvimento e dos testes permanecem no repositório, mas esses executáveis não fazem parte da distribuição Windows atual. Para testes de console, execute `python tools/verify_suite.py console`.
