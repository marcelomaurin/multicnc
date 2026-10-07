# LaserPCB

Prepara placas para laser com SVG, Gerber e Excellon. A conexão, o Frame e a execução pertencem ao MultiCNC.

## Fluxo da interface

1. **Importar:** abra vários Gerbers e os arquivos PTH/NPTH. Confira a função de cada camada; a detecção usa atributos X2 e nomes/extensões. Um SVG inicia um trabalho vetorial.
2. **Posicionar:** configure mesa, margem e espaçamento. Arraste a placa, ajuste X/Y, rotação e escala, duplique, trave ou distribua as cópias. O botão Placas ajusta o zoom ao conjunto; Mesa mostra a área útil.
3. **Processo:** selecione Top/Bottom e espelhamento, processo, diâmetro do feixe, potência S, S-max, velocidade, passadas, sobreposição e resolução. Atualizar trajetórias mostra a saída que será exportada.
4. **Validar:** corrija os erros, gere G-code e use Abrir no MultiCNC. Alterações nos parâmetros ou posições invalidam o arquivo disponível para envio.

## Processos

| Entrada/processo | Resultado |
|---|---|
| SVG / Vetores | Linhas, polígonos, retângulos, elipses, curvas e arcos, com unidades, viewBox e transformações |
| Gerber / Isolação | Anéis ao redor do cobre, compensados pelo raio do feixe |
| Gerber / Remoção | Varredura na área da placa sem cobre |
| Gerber / Preencher camada | Varredura da camada selecionada, incluindo máscara ou serigrafia |
| Excellon | Furos e rasgos na prévia e na máscara da placa; não gera perfuração física |

Na isolação, passadas são anéis de offset; o G-code percorre cada anel uma vez. Nos demais processos, passadas repetem as trajetórias. A compensação é recalculada depois da escala, mantendo o diâmetro físico do feixe. O espelhamento Bottom não modifica a geometria importada.

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
