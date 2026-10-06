# LaserArt - nova versao (estado em 06/10/2026)

O LaserArt e o editor de arte para laser da suite. O fluxo segue o
**LightBurn** (area de trabalho, ferramentas, paleta, Cuts/Layers, painel
Laser) e a tabela de camadas do **RDWorks** (cor, modo, velocidade,
potencia, saida, setas de ordem), com o visual da suite
(`multisuite/src/core/multisuite_controls.pas` e `multisuite_icons.pas`).

## Regras do projeto

- O LaserArt **prepara** o trabalho. Ele **nao** abre porta serial e nao
  controla a maquina. Execucao, Frame fisico, Home e Start ficam no MultiCNC.
- Camadas novas comecam com velocidade e potencia **zeradas**. O G-code so e
  gerado com camadas calibradas; a camada sem calibracao aparece em vermelho
  ("calibrar") e o erro cita a camada.
- O LaserArt nunca liga o laser automaticamente.
- A biblioteca de materiais comeca vazia.

## Arquivos

| Arquivo | Conteudo |
|---|---|
| `src/art/laserart_model.pas` | Camadas (30, paleta LightBurn), objetos, documento, arquivo `.lart` (JSON) |
| `src/art/laserart_geom.pas` | Contornos no mundo, caixas, preenchimento par-impar, Douglas-Peucker, ordenacao de caminhos, selecao |
| `src/art/laserart_imaging.pas` | Imagem em cinza, brilho/contraste/inverter, dithering (limiar, Floyd, Jarvis, tons de cinza), texto -> contornos, vetorizar imagem |
| `src/art/laserart_svgimport.pas` | Importador SVG: unidades/viewBox, transform, line/rect/circle/ellipse/polyline/polygon/path (inclui arco A), cor -> camada |
| `src/art/laserart_output.pas` | `BuildJob` + `JobToGCode`: Linha, Preencher, Imagem; passadas; ar M8/M9; M4 (ou M3); Iniciar de (absoluto, origem do usuario, zero da peca); tempo estimado; limite de 5 MB do MultiCNC |
| `src/art/laserart_materials.pas` | Biblioteca de materiais (JSON em `GetAppConfigDir`), aplicar/salvar camada |
| `src/ui/laserart_editor.pas` | Canvas: reguas, grade, zoom/pan, selecao com alcas, ferramentas, previa do trabalho |
| `src/ui/laserart_widgets.pas` | Lista de camadas (com rolagem), seletor de origem 3x3, paleta |
| `src/app/laserart_main.pas` | Tela principal (barra, propriedades, abas Cortes/Camadas, Objeto, Materiais, painel Saida, paleta, status, desfazer/refazer) |
| `src/app/laserart_calibrationform.pas` | Teste de material com previa da matriz (API `TLaserCalibration.BuildMatrix` mantida) |
| `tests/test_laserart_output.lpr/.lpi` | 27 verificacoes; registrado na Central de testes |

## Integracao com o MultiCNC

- **Enviar ao MultiCNC** grava o G-code ao lado do `.lart` (ou em
  `Documentos\MultiSuite Projects\LaserArt\`). Depois abre o MultiCNC com
  `--project/--file`.
- O MultiCNC (`src/app/multicnc.lpr` + `TMainForm.OpenProgramFile`) abre o
  arquivo recebido. Se o cabecalho tiver `; LaserArt`, ele seleciona
  **CNC Laser**, coloca Pass count = 1 e desliga o override de velocidade:
  potencia (S) e passadas ja vem no arquivo. Nada e enviado a maquina sem o
  usuario conectar e dar Start.

## Verificado

- Linux/GTK2 (Xvfb):
  - importacao SVG com camadas por cor, calibracao de camadas;
  - retangulo e texto, previa com tempo e area;
  - imagem com Floyd x tons de cinza, Teste de material.
- Windows x64 (Wine):
  - `laserart.exe` abre um SVG por parametro;
  - `multicnc.exe --file x.nc` com G-code do LaserArt abre em CNC Laser,
    Pass count 1 e override desligado.
- Testes: `test_laserart_output` OK (27), `test_calibration_matrix` OK,
  `test_job` OK.

## Falta / ideias

- Teste fim a fim na maquina real (ou no SimuCNC em modo laser via TCP):
  LaserArt -> Enviar ao MultiCNC -> conectar -> Start.
- Imagem ignora rotacao (o app avisa). Pode ser implementado reamostrando
  a imagem girada.
- Ferramentas futuras: offset de contorno, solda/booleanas, texto em curva,
  array/grade de copias, kerf.
- Units antigas sem uso (legado):
  - `art/`: `laserart_types.pas`, `laserart_document.pas`,
    `laserart_jobbuilder.pas`, `laserart_raster.pas`, `laserart_vector.pas`,
    `laserart_imagefx.pas`;
  - `ui/laserart_canvas.pas`.

  Elas podem ser apagadas quando quiser; nao estao no `laserart.lpi`.

## Como compilar

- Lazarus: abrir `laserpcb/src/app/laserart.lpi` e compilar. O projeto nao
  depende do pacote CHATGPT.
- Os caminhos incluem `../../../multisuite/src/core` e `../../../src/shared`.
