# Filamentos comerciais PLA e ABS

Pesquisa e implementação: 15/10/2026.

## Como usar

No MultiSlicer, abra **3 Material**, escolha **PLA** ou **ABS** e depois **Marca / linha (opcional)**. A lista mostra somente os filamentos daquele material. PLA+ fica em PLA; ABS+ fica em ABS. Ao trocar o material, a seleção retorna a **Customizado (padrão do material)**, evitando reaproveitar temperaturas da família anterior.

Escolher um produto preenche bico e mesa, tanto na primeira camada quanto nas demais. Todos os valores continuam editáveis. A tela mostra a faixa publicada e o botão **Fonte do fabricante** abre a referência correspondente. Projetos `.mslice` e perfis salvos conservam material, marca, linha, referência e os ajustes feitos pelo usuário. O G-code exportado leva essas temperaturas para o MultiCNC.

**Customizado** mantém os padrões anteriores do aplicativo:

| Material | Bico primeira / demais (°C) | Mesa primeira / demais (°C) |
|---|---|---|
| PLA | 205 / 200 | 60 / 60 |
| ABS | 245 / 240 | 105 / 100 |

PETG, ASA, TPU e Outro continuam disponíveis com seus perfis genéricos e perfis pessoais. Esta entrega pesquisa produtos comerciais de PLA e ABS; não inclui resina.

## Catálogo e fontes

São 12 produtos de sete marcas com presença no mercado brasileiro e internacional. A pesquisa não encontrou um ranking público auditável de vendas por produto; portanto a lista não é apresentada como classificação dos “mais vendidos”. A prioridade foi ter recomendações oficiais verificáveis e incluir fabricantes brasileiros.

**Faixa publicada não significa temperatura ideal universal.** A coluna inicial é um ponto de partida ajustável escolhido para o aplicativo dentro da faixa. A 3D Lab publica os pontos usados em seus testes, reproduzidos aqui. Nos demais produtos, o ponto inicial é uma escolha local, não uma temperatura única declarada pelo fabricante. Para os perfis comerciais usa-se o mesmo ponto inicial nas primeiras e demais camadas, sem inventar um acréscimo de primeira camada.

| Material | Marca / linha | Faixa bico (°C) | Faixa mesa (°C) | Inicial bico / mesa (°C) | Fonte oficial |
|---|---|---|---|---|---|
| ABS | 3D Lab ABS Premium | 220–240 | 110–110 | 235 / 110 | [Fabricante](https://3dlab.com.br/como-imprimir-com-filamento-abs/) |
| ABS | Bambu Lab ABS | 240–270 | 80–100 | 255 / 90 | [Fabricante](https://us.store.bambulab.com/products/abs-filament?variant=40475105460360) |
| ABS | Polymaker PolyLite ABS | 245–265 | 90–100 | 255 / 95 | [Fabricante](https://shop.polymaker.com/products/polylite-abs) |
| ABS | Voolt3D ABS Natural | 230–265 | 100–120 | 250 / 110 | [Fabricante](https://voolt3d.com.br/produtos/filamento-abs-natural-premium/) |
| ABS | eSUN ABS+ | 230–270 | 95–110 | 250 / 100 | [Fabricante](https://www.esun3d.com/abs-pro-product) |
| PLA | 3D Lab PLA | 200–220 | ambiente–70 | 210 / 60 | [Fabricante](https://3dlab.com.br/como-imprimir-com-filamento-pla/) |
| PLA | Bambu Lab PLA Basic | 190–230 | 35–45 | 210 / 40 | [Fabricante](https://bambulab-us.myshopify.com/products/pla-basic-filament) |
| PLA | Creality Hyper PLA | 190–230 | ambiente–60 | 210 / 60 | [Fabricante](https://store.creality.com/eu/blogs/basics/3d-printing-retraction) |
| PLA | Polymaker PolyLite PLA | 190–230 | 25–60 | 210 / 60 | [Fabricante](https://wiki.polymaker.com/polymaker-products/more-about-our-products/documents/technical-data-sheets/pla/polylite-tm-pla) |
| PLA | SUNLU PLA (50-100 mm/s) | 200–210 | 50–60 | 205 / 60 | [Fabricante](https://store.sunlu.com/products/over-6kg-of-pla-pla-meta-3d-filaments-1kg-2-2lbs-fit-most-of-fdm-printer?variant=50707218006298) |
| PLA | Voolt3D PLA Velvet Preto | 190–230 | 50–70 | 210 / 60 | [Fabricante](https://voolt3d.com.br/produtos/filamento-pla-preto-velvet-premium/) |
| PLA | eSUN PLA+ | 210–230 | 45–60 | 220 / 60 | [Fabricante](https://www.esun3d.com/es/pla-pro-product) |

Observações que acompanham os perfis:

- **Bambu Lab:** a página de PLA Basic informa mesa de 35–45 °C com cola; o ajuste depende da placa. ABS informa 80–100 °C com cola. Esses valores não substituem os perfis específicos de cada placa no Bambu Studio.
- **SUNLU PLA:** o produto pesquisado distingue bico de 200–210 °C para 50–100 mm/s e 210–240 °C para 100–200 mm/s. O cadastro desta entrega corresponde à primeira faixa; a velocidade não é aumentada automaticamente.
- **Voolt3D:** os dados são das linhas Velvet Preto e ABS Natural High Speed Premium. Não são generalizados para Silk, outras linhas ou formulações.
- **Creality Hyper PLA e 3D Lab PLA:** o fabricante também admite mesa sem aquecimento; o aplicativo inicia com 60 °C.
- **ABS:** observar as condições de gabinete e adesão indicadas pelo fabricante; as notas ficam disponíveis na tela.

A seleção comercial altera o perfil de material, sem aumentar limites da impressora. O validador existente continua impedindo exportação com temperatura acima dos limites cadastrados. Vazão, retração, densidade e ventilação herdam os padrões locais da família; não foram atribuídos ao fabricante. Preço não foi pesquisado e começa em zero nos perfis comerciais. Não há aquecimento ou comando enviado a hardware ao selecionar um filamento.

## Implementação e validação

- Catálogo, filtragem e serialização: `multislicer/src/core/multislicer_materials.pas`.
- Interface e restauração do projeto: `multislicer/src/app/multislicer_main.pas`.
- Testes: `test_commercial_materials` (faixas, fontes, famílias, padrões, arquivos antigos e perfis pessoais), `test_print_safety`, `test_multislicer_print` e `test_slicer_app` (eventos reais dos seletores, temperaturas no G-code, ajustes manuais, projeto e limite da mesa).
- Evidências finais: `docs/qa/filamentos-comerciais-2026-10-15/`.
- A validação física na Ender 3 permanece pendente; os resultados de software não equivalem a uma calibração de cada carretel.

Resultado final: **4 testes aprovados**, sem falhas na execução final. Tela revisada visualmente; MultiSlicer recompilado para Windows x86_64 e atualizado em `bin/multislicer.exe`. Alterações locais, sem commit/push.
