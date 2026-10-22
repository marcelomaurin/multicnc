# Manuais do usuário

Exercícios com arquivos prontos para todos os programas: [`models/README.md`](../../models/README.md) (na instalação, `documentation\models`).

## MultiCAD

[Abrir o manual em português](Manual_do_Usuario_MultiCAD_0.0.8.4_PT-BR.pdf)

- Versão de referência do aplicativo: **0.0.8.4**.
- Edição: **12/10/2026**.
- Formato: PDF A4, 34 páginas, 33 seções e 16 figuras, com marcadores de navegação.
- Conteúdo: interface, arquivos, navegação, esboços, cotas, relações, apoio, Trim, chanfro, padrões, texto vetorial, operações 3D, histórico, materiais, avaliação, exportação e integração com o MultiSlicer.
- Inclui procedimentos, parâmetros, exercício guiado, solução de problemas e atalhos.

[Capturas usadas e complementares](../../imgs/manual_multicad_0_0_8_4/README.md) · [Guia do MultiCAD](../../multicad/README.md)

**Atualização:** o executável atual é o **MultiCAD 0.0.8.5**; o manual descreve a 0.0.8.4 (as diferenças são correções internas). Exercícios: [`models/multicad`](../../models/multicad/README.md).

A versão é a do executável MultiCAD. O número do instalador da MultiSuite é uma referência diferente. As imagens antigas `Multicad01.png` a `Multicad08.png` mostram 0.0.8.0 e permanecem identificadas como históricas.

## LaserArt

[Abrir o manual em português](Manual_do_Usuario_LaserArt_0.02.1_PT-BR.pdf)

- Versão de referência: **LaserArt 0.02.1**; versão do arquivo Windows **0.2.0.1**.
- Edição: **12/10/2026**.
- Formato: PDF A4, 30 páginas, 28 capítulos de uso, sumário, 19 figuras e marcadores de navegação.
- Conteúdo: interface, arquivos, mesa, navegação, seleção, formas, polilinhas, texto vetorial, transformações, SVG, imagens, dithering, vetorização, camadas, parâmetros, modos de produção, ordem, teste de material, biblioteca de materiais, origens, prévia, G-code e integração com o MultiCNC.
- Inclui exercício guiado, solução de problemas e atalhos.

[16 capturas completas](../../imgs/manual_laserart_0_02_1/README.md) · [Guia do LaserArt](../../laserart/README.md) · [Exercícios](../../models/laserart/README.md)

**Atenção:** o PDF não cobre os recursos acrescentados depois da edição: **Caixa com encaixes...** (gerador de caixa com dentes, kerf e tampa), pontes de fixação no corte e **Estimar potência pelo laser...**. Eles estão descritos no [Guia do LaserArt](../../laserart/README.md) e usados nos exercícios.

## MultiCNC

[Abrir o manual ilustrado em português](Manual_do_Usuario_MultiCNC_0.1.0.3_PT-BR.pdf) · [Versão em texto](Manual_do_Usuario_MultiCNC_0.1.0.3_PT-BR.md)

- Versão de referência: **MultiCNC 0.1.0.3**, Windows x64.
- Edição: **12/10/2026**; fontes conferidas no commit **687756e**.
- Formato: PDF A4, **33 páginas**, **31 capítulos**, sumário clicável, **22 figuras** e marcadores de navegação.
- Conteúdo: interface, perfis, equipamentos salvos, serial/TCP, SimuCNC, simulador local, arquivos, busca, trajetória, análise, jog, homing/HOME/zero, execução, Console, router/spindle, laser, Frame/Outline, impressão 3D, temperaturas, joystick, compatibilidade e integrações.
- Inclui exercício guiado, solução de problemas, atalhos e comportamento dos campos ainda incompletos do processamento laser.

[17 capturas completas](../../imgs/manual_multicnc_0_1_0_3/README.md) · [Guia do painel](../../src/app/README.md) · [Exercício (quadrado.nc)](../../models/multicnc/README.md)

## MakePCB

[Abrir o manual ilustrado em português](Manual_do_Usuario_MakePCB_0.1.0.0_PT-BR.pdf) · [Versão em texto](Manual_do_Usuario_MakePCB_0.1.0.0_PT-BR.md)

- Versão de referência: **MakePCB 0.1.0.0**, Windows x64.
- Edição: **13/10/2026**.
- Formato: PDF A4, **30 páginas**, **28 capítulos**, sumário, **6 figuras** e marcadores de navegação.
- Conteúdo: fluxo de trabalho, interface, dimensões da placa, editor esquemático e biblioteca de símbolos, fios e redes (nets), conversão de esquema para placa, ligação pad a pad, galeria de componentes, componentes SMD e montagem na face inferior, editor de componentes (footprints do usuário), biblioteca pessoal, 4 vistas de inspeção (Normal, Mundo Real, Sem Componentes e Arte Final), traçado manual de trilhas, áreas de cobre e planos de terra, textos vetoriais, seleção múltipla e blocos, roteamento automático A*, verificação de regras de projeto (DRC), lista de materiais (BOM CSV), exportação Gerber RS-274X e Excellon, impressão 1:1 com calibração em DPI e repetição na folha, integração direta com LaserPCB e RouterPCB.
- Inclui exercício guiado do oscilador 555 astável, resolução de problemas, atalhos de teclado e especificações técnicas.

[Guia e galeria do MakePCB](../../makepcb/README.md) · [Capturas da interface](../../imgs/README.md#makepcb) · [Exercícios: pisca 555, RouterPCB e LaserPCB](../../models/makepcb/README.md)

O capítulo 25 da versão em texto foi revisado em 19/10/2026: o botão é **Rotear automaticamente** e os arquivos de cada fase estão em `models/makepcb`.

## MakeRouter

[Abrir o manual ilustrado em português](Manual_do_Usuario_MakeRouter_0.1.0.0_PT-BR.pdf) · [Versão em texto](Manual_do_Usuario_MakeRouter_0.1.0.0_PT-BR.md)

- Versão de referência: **MakeRouter 0.1.0.0**, Windows x64.
- Edição: **13/10/2026**.
- Formato: PDF A4, **30 páginas**, **28 capítulos**, sumário, **5 figuras** e marcadores de navegação.
- Conteúdo: fluxo de trabalho CAM 2.5D, interface e vistas ortogonais/isométrica, definição de matéria-prima (bloco) e 9 pontos de zero virtual, biblioteca e cadastro de ferramentas (topo reto, esférica, cônica/V-bit), parâmetros de usinagem (feed rate, plunge rate, spindle RPM, stepover, stepdown), estratégias de contorno (Profile interno/externo com abas de retenção - Tabs), estratégias de desbaste e cavidades (Pocket com ilhas e rampa em hélice), furação e furação profunda pica-pau (Peck Drilling com retração), gravação V-Carve e chanfros, simulação 3D sombreada e verificação volumétrica, validação de limites físicos e colisões de haste, pós-processamento e geração de G-code GRBL, envio e integração direta com o MultiCNC.
- Inclui exercício guiado de usinagem de placa com rebaixo, solução de problemas, atalhos de teclado e especificações técnicas.

[Guia do MakeRouter](../../makerouter/README.md) · [Capturas da interface](../../imgs/README.md#makerouter) · [Exercícios](../../models/makerouter/README.md)

## MultiSlicer

[Abrir o manual ilustrado em português](Manual_do_Usuario_MultiSlicer_0.1.0.0_PT-BR.pdf) · [Versão em texto](Manual_do_Usuario_MultiSlicer_0.1.0.0_PT-BR.md)

- Versão de referência: **MultiSlicer 0.1.0.0**, Windows x64.
- Edição do PDF: **13/10/2026**; **manual Markdown revisado em 17/10/2026** com o novo parâmetro **Degrau inicial Z (mm)**.
- Formato do PDF anterior: A4, **30 páginas**, **28 capítulos**, sumário, **5 figuras** e marcadores de navegação.
- **Atenção:** o PDF ainda não inclui o degrau Z. Consulte a versão em texto atualizada para configurar esse recurso.
- Conteúdo: fluxo de trabalho de fatiamento 3D FDM/FFF, interface e navegação na mesa virtual, importação de modelos STL (ASCII/binário), 3MF e integração com MultiCAD, conferência e reparo automático de malhas (não-manifold, normais invertidas), manipulação espacial (posição, escala, rotação, espelho), arranjo automático (auto-arrange) de lotes de peças, perfis de impressoras 3D integrados ao catálogo do MultiCNC e ajuste manual, configuração de filamentos (PLA, PETG, ABS, TPU), gestão térmica (bico, mesa, ventilação de peça), alturas de camada fixas e adaptativas (Cusp Height), perímetros/paredes e alinhamento de costura (Z-seam), superfícies sólidas de topo/fundo e anti-pillowing, padrões de preenchimento estrutural (Gyroid isotrópico, retilíneo), suportes automáticos e manuais (hastes pontuais e bloqueadores de exclusão), estratégias de adesão (saia/skirt, aba/brim e jangada/raft), controle de retração, Z-hop e anti-stringing, motor de fatiamento em segundo plano (não-bloqueante), inspeção da prévia 3D por camada com legenda de cores, estimativas de tempo e massa de filamento, projeto nativo .mslice, pós-processamento para firmwares Marlin e Klipper (M73, M486, Exclude Object, Arc Fitting G2/G3), contrato de metadados MultiSuite e envio direto ao MultiCNC com verificação de limites da mesa.
- Inclui exercício guiado do suporte mecânico, guia de calibração de fluxo, diagnóstico de problemas e tabela de atalhos.

[Guia do MultiSlicer](../../multislicer/README.md) · [Capturas da interface](../../imgs/README.md#multislicer) · [Exercícios](../../models/multislicer/README.md)

O executável atual é o **MultiSlicer 0.1.0.1**. A versão em texto ganhou em 19/10/2026 o capítulo 26 (exercício guiado), que constava no sumário mas faltava.

## Programas sem manual próprio

- **RouterPCB** e **LaserPCB:** guias em [`routerpcb`](../../routerpcb/README.md) e [`laserpcb`](../../laserpcb/README.md); exercícios em [`models/routerpcb`](../../models/routerpcb/README.md) e [`models/laserpcb`](../../models/laserpcb/README.md).
- **MultiAssembly:** exercício em [`models/multiassembly`](../../models/multiassembly/README.md).
- **MultiCAM:** exercício em [`models/multicam`](../../models/multicam/README.md).

## MultiPhysics

[Abrir o manual ilustrado em português](Manual_do_Usuario_MultiPhysics_0.2.0.0_PT-BR.pdf) · [Versão em texto](Manual_do_Usuario_MultiPhysics_0.2.0.0_PT-BR.md)

- Versão de referência: **MultiPhysics 0.2.0.0**, Windows x64 (setup 014).
- Edição: **19/10/2026**.
- Formato: PDF A4, **33 páginas**, **29 capítulos**, sumário clicável, **12 figuras** e marcadores de navegação.
- Conteúdo: fidelidade dos resultados, interface, vista 3D, projetos, peças, importação do MultiAssembly, contatos colados, materiais, cargas e fixações, faces, malha, resolver, resultados, exportação (CSV, HTML, VTK), sistema eletromecânico, CNC virtual e falhas, circuitos por netlist, ambiente, atmosfera ISA, flutuação e CalculiX.
- Inclui quatro exercícios guiados com resultados de referência, mensagens e solução de problemas, boas práticas, termos e limites.

[12 capturas completas](../../imgs/manual_multiphysics_0_2_0_0/README.md) · [Guia do MultiPhysics](../../multiphysics/README.md) · [Exemplos](../../models/multiphysics/README.md)

## MultiProject

[Guia rápido do MultiProject](MultiProject_Guia_Rapido.md): tarefas, sugestões, modelos, arquivos e folha de torno.
