# Catálogo de impressoras FDM/FFF

Pesquisa e implementação: 15/10/2026. Modelos de resina excluídos por solicitação do usuário.

Foram acrescentados 11 modelos a uma base compartilhada pelos aplicativos. O MultiCNC passa de 15 para 26 modelos; o catálogo técnico do MultiSlicer, de 17 para 28. A lista de perfis prontos do MultiSlicer passa de 3 para 14 (inclui os genéricos).

## Seleção e fontes

A seleção prioriza modelos de marcas amplamente presentes no segmento de entrada e em comparativos de impressoras. Não é um ranking de unidades instaladas: não foi encontrada uma base pública comparável por modelo. As especificações abaixo vêm dos fabricantes, e não de anúncios de revendedores. A Creality K2 foi incluída por pedido explícito, com Pro e Plus separados.

Referências de seleção: [comparativo atual de modelos](https://www.creativebloq.com/buying-guides/best-3d-printers) e [contexto de participação das marcas](https://www.tomshardware.com/3d-printing/bambu-lab-overtakes-creality-as-the-worlds-top-selling-budget-3d-printer-brand). Nenhuma classificação de vendas foi atribuída a um modelo individual.

| Marca / modelo | Volume nominal X × Y × Z (mm) | Bico máximo (°C) | Mesa máxima (°C) | Velocidade máxima publicada (mm/s) | Fonte oficial |
|---|---|---:|---:|---:|---|
| Creality K2 | 260 × 260 × 260 | 300 | 100 | 600 | [Ficha/manual](https://www.creality.com/es/support/k2-series-3d-printer) |
| Creality K2 Pro | 300 × 300 × 300 | 300 | 110 | 600 | [Ficha/manual](https://www.creality.com/support/k2-series) |
| Creality K2 Plus | 350 × 350 × 350 | 350 | 120 | 600 | [Ficha/manual](https://www.creality.com/products/creality-k2-plus-cfs-combo) |
| Creality K1C | 220 × 220 × 250 | 300 | 100 | 600 | [Ficha/manual](https://www.creality.com/products/k1c-carbon-3d-printer) |
| Bambu Lab A1 mini | 180 × 180 × 180 | 300 | 80 | 500 | [Ficha/manual](https://us.store.bambulab.com/products/a1-mini?id=543566369394393101) |
| Bambu Lab A1 | 256 × 256 × 256 | 300 | 100 | 500 | [Ficha/manual](https://us.store.bambulab.com/products/a1?variant=41583355232392) |
| Bambu Lab P1S | 256 × 256 × 256 | 300 | 100 | 500 | [Ficha/manual](https://us.store.bambulab.com/products/p1s?id=583855874739507213) |
| Bambu Lab X1 Carbon | 256 × 256 × 256 | 300 | 110 | 500 | [Ficha/manual](https://public-cdn.bambulab.com/store/bambulab-X1-carbon-tech-specs.pdf?v=20250715085516) |
| Prusa Research Original Prusa MK4S | 250 × 210 × 220 | 290 | 120 | Não cadastrada | [Ficha/manual](https://www.prusa3d.com/product/original-prusa-mk4s-3d-printer-7/?gQT=2) |
| Elegoo Neptune 4 Pro | 225 × 225 × 265 | 300 | 110 | 500 | [Ficha/manual](https://www.elegoo.com/en-gb/products/elegoo-neptune-4-pro-fdm-3d-printer) |
| Anycubic Kobra 3 V2 | 255 × 255 × 260 | 300 | 110 | 600 | [Ficha/manual](https://www.anycubic.com/en/kobra-3-v2-combo) |

Todos os novos perfis usam bico padrão de 0,4 mm e filamento de 1,75 mm. Temperaturas e velocidades da tabela são máximos publicados, não recomendações para qualquer material. Não foi alterada a vazão do material nem aplicada a velocidade máxima como velocidade inicial de impressão. A velocidade ausente da MK4S não é convertida em avanço zero: a prévia usa os limites locais padrão, sem atribuí-los ao fabricante.

- K2: 260 × 260 × 260 mm, bico 300 °C, mesa 100 °C; K2 Pro: 300 × 300 × 300 mm, 300/110 °C; K2 Plus: 350 × 350 × 350 mm, 350/120 °C. O limite publicado da Plus não aumenta o teto de 300 °C do controlador Marlin genérico.
- X1 Carbon: a ficha informa mesa até 110 °C em 220 V e 120 °C em 110 V. Foi cadastrado 110 °C, com a diferença registrada na observação.
- P1S/X1 Carbon: volume nominal não elimina a área de exclusão do cortador; essa geometria deve vir do perfil oficial.
- Neptune 4 Pro: área útil 225 × 225 mm, diferente da placa PEI de 235 × 235 mm.
- Kobra 3 V2: 255 × 255 × 260 mm; não reutiliza as dimensões da Kobra 3 original.

## O que está disponível

Os novos modelos aparecem em **MultiCNC → Impressora 3D → Marca/Modelo** e **MultiSlicer → Impressora → Perfil**. Dimensões, bico, filamento e limites ficam disponíveis para consulta e preparação/prévia. Os modelos existentes continuam com o comportamento anterior.

A ampliação do catálogo não implementa os protocolos de rede dos fabricantes, AMS/CFS/ACE, macros de inicialização, calibração de malha ou zonas de exclusão. Por isso os novos perfis são identificados como **catálogo dimensional**. O MultiSlicer preserva essa identificação em JSON e `.mslice` e não exporta um programa genérico como se fosse um perfil oficial. O MultiCNC informa o software indicado antes de tentar conexão serial/TCP; o simulador local continua disponível. Prusa MK4S e Neptune 4 Pro também aguardam a validação dos respectivos perfis de inicialização e envio nesta aplicação.

| Modelos | Fluxo indicado para imprimir |
|---|---|
| Creality K2, K2 Pro, K2 Plus e K1C | Creality Print |
| Bambu Lab A1 mini, A1, P1S e X1 Carbon | Bambu Studio |
| Original Prusa MK4S | PrusaSlicer |
| Elegoo Neptune 4 Pro | Elegoo Cura / perfil Klipper oficial |
| Anycubic Kobra 3 V2 | Anycubic Slicer Next |

A busca dá prioridade ao modelo exato. “K2 Pro Combo” encontra K2 Pro; “K2 Unknown” não herda silenciosamente o perfil K2. Nenhum teste físico foi executado e nenhum dispositivo recebeu comandos.

## Implementação e verificação

- Fonte única dos novos dados: `src/shared/multisuite_fdm_catalog.pas`.
- Adaptadores: `multicnc_printer_profiles.pas`, `multislicer_machines.pas` e `multislicer_printers.pas`.
- Metadados de origem e fluxo persistidos; seleção e bloqueio de exportação/conexão indevida cobertos por testes de interface.
- Testes específicos: `test_fdm_catalog`, `test_machines`, `test_printer_temperatures`, `test_equipment`, `test_print_safety`, `test_multislicer_print`, além dos testes de interface de ambos os aplicativos.
- Resultados finais e hashes em `docs/qa/catalogo-fdm-2026-10-15/`. Reproduzir os testes de console com `tools/verify_suite.py console multislicer .` (TCP externo requer servidor próprio e não é necessário para validar este catálogo).

O estacionamento do catálogo antigo passou a usar `{park_z}`, respeitando o limite de Z já implementado no fatiador.

Resultado final: **8 testes aprovados** (6 de console e 2 de interface); MultiCNC e MultiSlicer recompilados e atualizados em `bin/`. Alterações locais, sem commit ou push. Validação física da Ender 3 permanece pendente.
