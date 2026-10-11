# LaserArt

Editor de arte para laser da suite MultiCNC: logos, textos, vetores e imagens
para gravacao e corte. O fluxo segue o LightBurn (area de trabalho,
ferramentas, paleta de camadas, Cuts/Layers) e a tabela de camadas do RDWorks.

## Responsabilidades
- importar SVG (camada por cor) e imagens (BMP/PNG/JPG)
- criar texto (qualquer fonte), retangulo, elipse, poligono e linha
- 30 camadas com modo Linha, Preencher ou Imagem
- dithering (Floyd, Jarvis, limiar, tons de cinza) e vetorizacao de imagem
- teste de material (matriz potencia x velocidade) e biblioteca de materiais
- previa do trabalho com tempo estimado
- gerar G-code GRBL (M4/M3) e enviar ao MultiCNC

O LaserArt prepara o trabalho. O MultiCNC controla a maquina.

## Mesa e equipamentos do MultiCNC

No botão **Mesa**, o combobox **Laser salvo no MultiCNC** lista os equipamentos
do tipo laser cadastrados em AppData/Maurinsoft/MultiCNC/multicnc.json,
incluindo CUSTOM. Selecione o nome e clique em **Aplicar**: a mesa do desenho
recebe a área X/Y salva e a visualização se ajusta ao novo tamanho.
As dimensões passam a fazer parte do projeto LaserArt e podem ser desfeitas.

A opção **Ajuste manual** continua disponível. O S máximo ($30) é mantido e
editável: ele não é inferido da potência em watts nem do nome do equipamento.
Cadastros sem área válida não aparecem; cadastro ausente ou inválido permite
continuar com o ajuste manual.

## Seguranca
Potencia e velocidade nao sao universais. Camadas novas comecam zeradas e o
G-code so e gerado com camadas calibradas para a maquina e o material. O
LaserArt nao abre porta serial e nao liga o laser.

## Estrutura
- `src/core/`: modelo (.lart), geometria, imagem, importador SVG, gerador de G-code, materiais e teste de material.
- `src/ui/`: editor (canvas) e widgets (lista de camadas, origem, paleta).
- `src/app/`: tela principal, Teste de material e `laserart.lpi`.
- `tests/`: `test_laserart_output` e `test_calibration_matrix`.
- `docs/`: `LASERART_PLANO.md` (estado e proximos passos) e `AI_GUIDE.md`.

## Compilar
Abrir `src/app/laserart.lpi` no Lazarus. Depende dos módulos da suíte: cadastro em src/core,
`multisuite/src/core` e `src/shared` (nao usa o pacote CHATGPT).
