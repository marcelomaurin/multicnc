# LaserPCB

Prepara placas para laser com SVG, Gerber e Excellon e gera trajetórias de marcação, retirada de material e furos para CNC Laser. A conexão, o Frame e a execução pertencem ao MultiCNC.

## Fluxo da interface

1. **Importar:** abra vários Gerbers e os arquivos PTH/NPTH. Confira a função de cada camada; a detecção usa atributos X2 e nomes/extensões. Um SVG inicia um trabalho vetorial. Placas feitas no **MakePCB** chegam como uma pasta: `laserpcb --file <pasta>` (botão "Abrir no LaserPCB") importa todos os Gerber/Excellon dela e, em face simples, já seleciona o lado Bottom.
2. **Posicionar:** configure mesa, margem e espaçamento. Arraste a placa, ajuste X/Y, rotação e escala, duplique, trave ou distribua as cópias. O botão Placas mostra a contagem e a lista das camadas de cobre e cria uma placa vazia com largura/altura em mm: face simples (Top ou Bottom), face dupla (Top/Bottom) ou N camadas (1 a 64, com Inner entre as faces externas). A lista de prévia é preenchida automaticamente ao escolher o modelo. Na opção personalizada, use Anterior/Próxima ou selecione cada camada para revisá-las antes de criar. Bottom começa espelhada em X; selecione e processe uma face por vez. Criar substitui o trabalho atual; Ajustar zoom mantém o enquadramento do conjunto. Importe depois os Gerbers de cada camada; arquivos X2 com Copper,Ln preenchem a posição correspondente da pilha. As camadas de cobre são distintas das operações de gravação; Mesa abre a mesma configuração do LaserArt: escolha um laser salvo no MultiCNC (inclusive CUSTOM) ou informe as dimensões manualmente. Aplicar ajusta a área útil e o zoom; depois gere novamente as trajetórias. O S máximo continua configurável manualmente, pois não faz parte do cadastro dos equipamentos.
3. **Camadas:** a tabela "Cortes / Camadas" (estilo LightBurn) lista os processos do trabalho com cor, nome, modo, velocidade/potência e as chaves Saída e Ver. Ao importar, o LaserPCB cria as camadas típicas: isolação do cobre, marcar furos, máscara, serigrafia e contorno da placa (o contorno fica por último). Só a isolação começa com Saída ligada, e toda camada nova começa com potência e velocidade zeradas ("calibrar"). Selecione uma camada para editar processo, camada de origem, tratamento (tinta/verniz, cobre direto ou marcação), potência em percentual ou watts nominais, velocidade, passadas, sobreposição e marcação; a paleta 00–29 abaixo da prévia muda a cor da camada. Nova camada, Excluir, Subir e Descer organizam a ordem de corte. Feixe, S-max, resolução e espelhamento Bottom ficam em Máquina. Atualizar trajetórias gera todas as camadas com Saída ou Ver ligada; a prévia mostra cada camada na sua cor, o cobre Top em vermelho e o Bottom em verde, com réguas em mm.
4. **Saída:** confira o resumo das camadas com Saída e o tempo estimado, corrija os erros (cada erro cita a camada, ex.: "C03 Mascara Top: potencia nao calibrada"), gere o G-code e use Abrir no MultiCNC. As camadas saem num único arquivo, na ordem da tabela, cada uma com sua potência e velocidade. Alterações nos parâmetros ou posições invalidam o arquivo disponível para envio.
5. **Furos laser:** filtre diâmetro e PTH/NPTH e crie uma camada para marcar centros, percorrer contornos ou gerar anéis de corte. Cada camada tem seu tratamento, potência, velocidade e passadas. A interface não apresenta profundidade, spindle ou troca de broca.


## Processos

| Entrada/processo | Resultado |
|---|---|
| SVG / Vetores | Linhas, polígonos, retângulos, elipses, curvas e arcos, com unidades, viewBox e transformações |
| Gerber / Isolação | Anéis ao redor do cobre, compensados pelo raio do feixe |
| Gerber / Remoção | Varredura na área da placa sem cobre |
| Gerber / Preencher camada | Varredura da camada de origem, incluindo máscara ou serigrafia |
| Gerber / Contorno da placa | Linha sobre o contorno (marcação ou corte de material fino) |
| Excellon / Marcar furos (laser) | Centro, contorno ou corte de cada furo/rasgo pelo laser |

Na isolação, passadas são anéis de offset; o G-code percorre cada anel uma vez. Nos demais processos, passadas repetem as trajetórias daquela camada. A compensação é recalculada depois da escala, mantendo o diâmetro físico do feixe. O espelhamento Bottom não modifica a geometria importada.

Gerber requer contorno fechado. Contornos internos e furos são excluídos da placa. O CAM recorta cada segmento na máscara, sem ligar trechos através de furos. A borda recebe recuo de meio feixe. Precisão depende da resolução raster; o limite é 16 milhões de pixels por máscara.

## Limites e parâmetros

Potência, velocidade e diâmetro do feixe precisam de calibração da máquina/material. Confira S-max com `$30` e modo laser com `$32=1` no MultiCNC. Não há presets universais de potência/velocidade. Mesa carrega os W ópticos do equipamento salvo, quando informados, sem alterar a janela compartilhada do LaserArt. Em Camadas, os W também podem ser informados manualmente. A conversão nominal usa W do laser × percentual / 100 e S-max × percentual / 100; não é uma medição da saída nem garante o mesmo resultado em lasers diferentes.

A opção **Tabela de referências (web)** apresenta dados publicados com fonte e parâmetros ausentes identificados. Consulte [REFERENCIAS_LASER.md](docs/REFERENCIAS_LASER.md). Só referências com watts e velocidade conhecidos podem ser aplicadas explicitamente à camada; dados de sistemas UV industriais não viram presets para diodos azuis.

A validação bloqueia trajetórias vazias, parâmetros inválidos, S arredondado para zero, potência acima de S-max, placas fora da mesa, colisões e zonas proibidas. Recursos de importação ignorados geram avisos e bloqueiam exportação. SVG com texto, imagens, referências `use`, máscaras ou recortes precisa ser convertido para vetores suportados.

Colisão e nesting usam caixas envolventes conservadoras, inclusive após rotação livre. Zonas proibidas reservam espaço para as placas; os deslocamentos rápidos entre trajetórias não são roteados ao redor dessas zonas. Confira os movimentos no MultiCNC.

Alinhamento manual usa dois fiduciais, com coordenadas do arquivo original e coordenadas medidas em mm. O solver aplica escala, rotação e translação; considera origem e espelhamento Bottom. A câmera continua indisponível.

Perfis JSON preservam feixe, potência óptica nominal em watts, potência S, velocidade, S-max, passadas e tipo de processo laser. A sessão completa de camadas e posicionamento não é salva pelo perfil.

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

## Componentes compartilhados com o MakePCB

O botão **Componentes**, ao lado de Mesa, abre a mesma galeria de footprints e o mesmo editor de criação usados pelo MakePCB. A biblioteca do usuário é compartilhada em `%LOCALAPPDATA%\makepcb\makepcb_componentes.json` no Windows. **Importar biblioteca** lê conjuntos JSON no formato `makepcb-library`; os componentes criados pelo editor ficam disponíveis também no MakePCB ao reabrir o programa.

Escolha um componente na galeria e clique na placa, ou use **Adicionar escolhido**. Arraste para posicionar, ajuste X/Y em mm, rotação de 90 em 90 graus e face Top/Bottom. **Aplicar na placa** transforma pads, contornos e furos em geometria de cobre, serigrafia e marcação para o laser. O CAM preserva os Gerbers e Excellons importados e aplica o espelho Bottom configurado para a placa. Pads passantes aparecem nas faces externas; pads SMD ficam na face escolhida, sem criar cobre nas camadas internas.

**Salvar conjunto** grava componentes e posições em `.mpcb`, incluindo as definições personalizadas. **Abrir conjunto** substitui a montagem em edição pelos componentes desse arquivo, mantendo as dimensões da placa atual. Projetos MakePCB também podem ser abertos como conjunto: o LaserPCB aproveita apenas os componentes, ignorando trilhas, redes, esquema e outras funções. **Cancelar** descarta as alterações de posicionamento; componentes salvos na biblioteca permanecem disponíveis. Salve o conjunto para reutilizá-lo após fechar o LaserPCB.

Teste da integração: `lazbuild laserpcb/tests/test_components.lpi`, seguido de `laserpcb/tests/test_components.exe` no Windows.
