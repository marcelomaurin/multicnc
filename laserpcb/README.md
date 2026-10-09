# LaserPCB

Prepara placas para laser com SVG, Gerber e Excellon e gera a furação para CNC Router. A conexão, o Frame e a execução pertencem ao MultiCNC.

## Fluxo da interface

1. **Importar:** abra vários Gerbers e os arquivos PTH/NPTH. Confira a função de cada camada; a detecção usa atributos X2 e nomes/extensões. Um SVG inicia um trabalho vetorial. Placas feitas no **MakePCB** chegam como uma pasta: `laserpcb --file <pasta>` (botão "Abrir no LaserPCB") importa todos os Gerber/Excellon dela e, em face simples, já seleciona o lado Bottom.
2. **Posicionar:** configure mesa, margem e espaçamento. Arraste a placa, ajuste X/Y, rotação e escala, duplique, trave ou distribua as cópias. O botão Placas ajusta o zoom ao conjunto; Mesa mostra a área útil.
3. **Camadas:** a tabela "Cortes / Camadas" (estilo LightBurn) lista os processos do trabalho com cor, nome, modo, velocidade/potência e as chaves Saída e Ver. Ao importar, o LaserPCB cria as camadas típicas: isolação do cobre, marcar furos, máscara, serigrafia e contorno da placa (o contorno fica por último). Só a isolação começa com Saída ligada, e toda camada nova começa com potência e velocidade zeradas ("calibrar"). Selecione uma camada para editar processo, camada de origem, potência S, velocidade, passadas, sobreposição e marcação; a paleta 00–29 abaixo da prévia muda a cor da camada. Nova camada, Excluir, Subir e Descer organizam a ordem de corte. Feixe, S-max, resolução e espelhamento Bottom ficam em Máquina. Atualizar trajetórias gera todas as camadas com Saída ou Ver ligada; a prévia mostra cada camada na sua cor, o cobre Top em vermelho e o Bottom em verde, com réguas em mm.
4. **Saída:** confira o resumo das camadas com Saída e o tempo estimado, corrija os erros (cada erro cita a camada, ex.: "C03 Mascara Top: potencia nao calibrada"), gere o G-code e use Abrir no MultiCNC. As camadas saem num único arquivo, na ordem da tabela, cada uma com sua potência e velocidade. Alterações nos parâmetros ou posições invalidam o arquivo disponível para envio.
5. **Furar:** filtre os furos (diâmetro, PTH/NPTH) e configure a broca: profundidade, bicada, Z, avanços, rotação e espera. Para dupla face, ative os pinos de registro. Use Conferir furação e Gerar furação. O padrão é um arquivo por broca. Abrir no MultiCNC carrega o arquivo em CNC Router. Detalhes em [docs/FURACAO.md](docs/FURACAO.md).

## Processos

| Entrada/processo | Resultado |
|---|---|
| SVG / Vetores | Linhas, polígonos, retângulos, elipses, curvas e arcos, com unidades, viewBox e transformações |
| Gerber / Isolação | Anéis ao redor do cobre, compensados pelo raio do feixe |
| Gerber / Remoção | Varredura na área da placa sem cobre |
| Gerber / Preencher camada | Varredura da camada de origem, incluindo máscara ou serigrafia |
| Gerber / Contorno da placa | Linha sobre o contorno (marcação ou corte de material fino) |
| Excellon / Marcar furos (laser) | Centro, contorno ou corte de cada furo/rasgo pelo laser |
| Excellon / Furar (CNC Router) | Programa GRBL por broca, com bicadas, rasgos e pinos de registro |

Na isolação, passadas são anéis de offset; o G-code percorre cada anel uma vez. Nos demais processos, passadas repetem as trajetórias daquela camada. A compensação é recalculada depois da escala, mantendo o diâmetro físico do feixe. O espelhamento Bottom não modifica a geometria importada.

Gerber requer contorno fechado. Contornos internos e furos são excluídos da placa. O CAM recorta cada segmento na máscara, sem ligar trechos através de furos. A borda recebe recuo de meio feixe. Precisão depende da resolução raster; o limite é 16 milhões de pixels por máscara.

## Limites e parâmetros

Potência, velocidade e diâmetro do feixe precisam de calibração da máquina/material. Confira S-max com `$30` e modo laser com `$32=1` no MultiCNC. Não há presets universais de potência/velocidade.

A validação bloqueia trajetórias vazias, parâmetros inválidos, S arredondado para zero, potência acima de S-max, placas fora da mesa, colisões e zonas proibidas. Recursos de importação ignorados geram avisos e bloqueiam exportação. SVG com texto, imagens, referências `use`, máscaras ou recortes precisa ser convertido para vetores suportados.

Colisão e nesting usam caixas envolventes conservadoras, inclusive após rotação livre. Zonas proibidas reservam espaço para as placas; os deslocamentos rápidos entre trajetórias não são roteados ao redor dessas zonas. Confira os movimentos no MultiCNC.

Alinhamento manual usa dois fiduciais, com coordenadas do arquivo original e coordenadas medidas em mm. O solver aplica escala, rotação e translação; considera origem e espelhamento Bottom. A câmera continua indisponível.

Perfis JSON preservam feixe, potência, velocidade, S-max, passadas e tipo de processo laser. A sessão completa de camadas e posicionamento não é salva pelo perfil.

## Compilação e testes

Requer Lazarus/LCL e FPC. O SVG reutiliza `laserart/src/core/laserart_svgimport.pas`; o visual reutiliza `multisuite_controls` e `multisuite_icons`.

```bash
lazbuild laserpcb/src/app/laserpcb.lpi
lazbuild --ws=nogui laserpcb/tests/test_pipeline.lpi
./laserpcb/tests/test_pipeline
lazbuild --ws=gtk2 laserpcb/tests/test_ui.lpi
xvfb-run -a ./laserpcb/tests/test_ui /tmp/laserpcb-ui
```

A automação `LaserPCB CI` testa o núcleo e a interface nativa em Linux/Windows e disponibiliza o executável Windows como artefato. Os testes cobrem SVG, exportações repetidas, parâmetros, transformações, nesting, polaridade Gerber, Excellon, recorte e compensação após escala.
## Segurança
Parâmetros de potência/velocidade não são universais. Devem ser calibrados para a máquina, material e processo. O LaserPCB não habilita laser automaticamente.

## Raster moderno (laserart_rasterizer)
Independente da LCL (`TGrayImage`): ajustes de brilho/contraste/gama, sete algoritmos de dithering (Floyd-Steinberg, Jarvis, Stucki, Atkinson, Sierra, Burkes, Bayer) com varredura serpentina, ou escala de cinza com potência variável entre `PowerMin` e `PowerMax`. O G-code usa `M4` (potência acompanha a velocidade real), runs de mesma potência em uma linha, overscan com `S0`, varredura bidirecional e salto de áreas brancas. O exportador de jobs (`laserpcb_gcode`) também passou a gerar saída modal.
