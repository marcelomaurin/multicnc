# Pendencias da suite (atualizado 06/10/2026, noite)

Lista do que ficou aberto. Detalhes do LaserArt em
`laserpcb/docs/LASERART_PLANO.md`.

## LaserArt
- **Nova versao pronta** (estilo LightBurn/RDWorks):
  - SVG, texto, imagem e formas, com 30 camadas;
  - Teste de material e biblioteca de materiais;
  - previa com tempo estimado;
  - Salvar G-code e Enviar ao MultiCNC.
- `bin\laserart.exe` e `laserpcb\src\app\laserart.exe` (x64) gerados.
- Teste `laserpcb/tests/test_laserart_output` (27 verificacoes) esta na
  Central de testes.
- Falta: teste fim a fim na maquina/SimuCNC laser. Apagar as units
  antigas sem uso (lista no plano).

## SimuCNC
- Layout novo e 3D por equipamento (impressora/router/laser) em
  `src/simucnc/`.
- Dependencias resolvidas. `SimuCNC.exe` gerado em `bin\` e em
  `src\simucnc\`; tambem compila pelo Lazarus.
- `tests/test_simucnc_jog.lpr` ainda nao foi executado.

## MultiCNC
- Layout novo gravado; `bin\multicnc.exe` (x64) atualizado.
- `src/app/multicnc.exe` continua o antigo ate recompilar no Lazarus (o
  painel da bandeja abre esse primeiro).
- `tests/test_app.lpr` atualizado para `TSuiteButton`, mas ja travava antes
  (tenta conectar em porta serial real) - revisar o teste.
- Feito: abre o arquivo recebido em `--file` (ou 1o parametro). G-code do
  LaserArt (`; LaserArt` no cabecalho) seleciona CNC Laser, Pass count = 1 e
  override desligado. `bin\multicnc.exe` (x64) recompilado com isso.

## MultiSuite
- `multisuite.exe` precisa ser recompilado (correcao do launcher que acha as
  ferramentas na arvore de desenvolvimento).
- Abertos da analise inicial:
  1. Raiz da suite errada quando instalado (`..\..\..` a partir do exe):
     botao "Central de testes" e projeto demonstracao.
  2. Interface nao abre/salva `.msuite` e o `.lpr` nao le o arquivo passado
     pela associacao do instalador.
  3. Projeto demonstracao so existe em memoria (artefatos nao criados).
  4. Testes `multisuite/tests/*.lpr` sem `.lpi` (aparecem como MISSING);
     `test_context` e `test_launcher_paths` fora do catalogo.
  5. `Load` do workspace sem validacao de faixa; `|` no nome quebra o arquivo;
     `multisuite_project.pas` sem uso; etapas do workspace diferentes do menu;
     `AI_GUIDE.md` lista 8 ferramentas (falta MultiPhysics).

## MultiSuite Bandeja
- `bin\multisuite_tray.exe` pronto. Falta incluir no `build_release.bat` e no
  `installer\windows\multisuite.iss` (atalho + opcao "Iniciar com o Windows").

## Geral
- Builds atuais da suite sao i386; os executaveis gerados nesta sessao
  (tray, MultiCNC) sao x64, como o instalador.
- Controles visuais comuns em `multisuite/src/core/multisuite_controls.pas`
  e icones em `multisuite_icons.pas` - usar nas demais ferramentas
  (MultiCAD, MultiPCB, MultiCAM, MultiSlicer, MultiPhysics, MultiAssembly,
  LaserPCB) para padronizar o visual.
