# MultiSlicer - Requisitos (revisao 2026-10)

Referencia funcional: UltiMaker Cura (preparar -> previa -> enviar). Nao e copia:
o MultiSlicer segue o padrao visual e a divisao de papeis da MultiSuite.

## Objetivo (como definido pelo autor)
Posicionar a peca na mesa da impressora, ajustar temperatura e tipo de filamento,
posicionar as hastes de apoio (suportes), gerar o G-code, salvar o codigo e
despachar para o MultiCNC, que executa a impressao.

Regra de separacao (mantida): o MultiSlicer prepara; o MultiCNC conecta e imprime.

## 1. Conformidade das especificacoes atuais com o objetivo

| Item do objetivo | Situacao no codigo | Conforme? |
|---|---|---|
| Papel prepara/MultiCNC executa | README, AI_GUIDE, ARCHITECTURE | Sim |
| Importar peca | STL ASCII/binario e 3MF no nucleo; a tela so abre STL | Parcial |
| Posicionar a peca na mesa | `multislicer_layout3d` existe, mas em executavel separado, 2D, com caixas ficticias de 30 mm, sem ligacao com o fatiamento | Nao |
| Ajustar temperatura | Spin de bico e mesa | Sim (basico) |
| Tipo de filamento | Inexistente (densidade fixa PLA 1,24 g/cm3) | Nao |
| Hastes de apoio (suportes) | Declarado como nao implementado no pipeline | Nao |
| Fatiar | `TModernSlicer`: perimetros, gyroid, topo/fundo, adaptativo, retracao, arcos, Marlin/Klipper | Sim |
| Salvar o codigo | Exportar G-code | Sim |
| Despachar para o MultiCNC | Sem botao; o MultiCNC nao reconhece o cabecalho do MultiSlicer e nao troca para Impressora 3D | Nao |
| Padrao estetico da suite | Tela feita com TPanel/TButton simples, sem `TSuiteHeader`, `TSuiteButton`, cores `clSuite*`, etapas e rodape | Nao |

Conclusao: o motor de fatiamento esta adiantado; faltam a tela, o posicionamento
real, materiais, suportes, o projeto salvo e a integracao com o MultiCNC.

## 2. Requisitos funcionais

### RF01 - Tela no padrao da suite
Mesmo layout de MakeRouter/LaserPCB/MakePCB: `TSuiteHeader` (titulo, subtitulo,
`sikMultiSlicer`), barra lateral de etapas com `TSuiteButton`, parametros a direita
em `TPageControl` sem abas, vista ao centro, rodape com status e os botoes
**Validar / Fatiar (Gerar G-code) / Abrir no MultiCNC**. Fonte `SUITE_FONT`, cores
`clSuiteSurface`, `clSuiteCard`, `clSuitePrimary`, indicador de estado com
`clSuiteSuccess/Warning/Danger`.
Etapas: 1 Impressora, 2 Modelo (posicionar), 3 Material, 4 Qualidade, 5 Suportes e
aderencia, 6 Previa, 7 Saida.

### RF02 - Vista 3D da mesa (estilo Cura)
- Mesa do perfil com grade de 10 mm, volume de impressao em linhas, eixos XYZ.
- Malha sombreada; selecionada em destaque; fora do volume em vermelho/listrado.
- Navegacao igual ao MultiCAD (meio gira, Ctrl+meio desloca, roda zoom, cubo de vistas).
- Renderizacao por software reaproveitando `multicad_camera`/`multicad_softrender`
  (sem dependencia de OpenGL/driver), movidos ou referenciados como unidade compartilhada.

### RF03 - Posicionamento da peca
- Varios objetos; lista de objetos (como o "Object list" do Cura).
- Mover (arrastar na mesa e campos X/Y/Z), girar (X/Y/Z em graus), escalar
  (uniforme ou por eixo, mm ou %), espelhar, centralizar, **cair na mesa** (Z min = 0),
  **deitar face na mesa** (lay flat por clique ou automatico), duplicar, travar.
- Auto-arranjo e validacao de colisao/volume antes de fatiar.
- A transformacao de cada objeto e aplicada aos vertices antes do fatiamento
  (`TransformVertex`); o fatiamento usa a cena inteira, nao o arquivo cru.

### RF04 - Perfil de impressora
- Perfis salvos (JSON) com volume X/Y/Z, bico, diametro do filamento, firmware
  (Marlin/Klipper), mesa aquecida, G-code inicial e final editaveis.
- Perfil pronto **Creality Ender-3** (220 x 220 x 250, Marlin, 1,75 mm, Bowden).
- O mesmo perfil deve existir/ser compativel com o equipamento cadastrado no MultiCNC.

### RF05 - Material (filamento)
- Biblioteca: PLA, PETG, ABS, ASA, TPU, e personalizado.
- Por material: temperatura do bico (1a camada e demais), mesa, ventoinha (%),
  densidade (g/cm3), retracao (comprimento/velocidade, considerando Bowden x direto),
  fluxo, custo por kg (opcional).
- Ao trocar o material, os campos sao preenchidos e podem ser ajustados.

### RF06 - Qualidade e preenchimento (modo recomendado + personalizado)
- Recomendado (como no Cura): perfis Fino 0,1 / Normal 0,2 / Rascunho 0,3; barra
  de preenchimento %; caixa "Suporte"; caixa "Aderencia".
- Personalizado: paredes, topo/fundo, padrao, velocidades, altura adaptativa,
  arcos, retracao, z-hop, pressure advance (o que o pipeline ja suporta).

### RF07 - Suportes (hastes de apoio)
- Deteccao automatica de saliencias pelo angulo (padrao 50 graus), com destaque na vista 3D.
- **Posicionamento manual**: clicar na peca para adicionar haste/bloqueador; remover;
  areas de bloqueio de suporte.
- Geracao por camada: regiao de suporte = projecao da saliencia - peca (com folga XY),
  distancia Z de topo/fundo, padrao linhas/grade, densidade, camadas de interface,
  "somente apoiado na mesa" x "em toda parte". Fase posterior: suporte em arvore.
- Novo papel de caminho `prSupport`/`prSupportInterface` no pipeline, na previa e no G-code (`;TYPE:Support material`).

### RF08 - Aderencia a mesa
Saia (ja existe), aba (brim) e jangada (raft), com distancia e numero de voltas.

### RF09 - Previa
- Previa por camada em 3D (deslizante de camadas) com cores por papel, igual ao
  G-code exportado (mesmo `TModernSlicer`), opcao de mostrar deslocamentos.
- Cartao de resumo: tempo estimado, filamento (m e g), custo, numero de camadas.

### RF10 - Saida, salvar e despachar
- Salvar G-code (`.gcode`).
- Cabecalho no contrato da suite (`multisuite_gcode_writer`/`SuiteParseHeader`) com
  origem `MultiSlicer`, tipo de maquina Impressora 3D, perfil, material, temperaturas
  e caixa do trabalho; linha de identificacao `; MultiSlicer -> MultiCNC (Impressora 3D)`.
- **Abrir no MultiCNC** via `TSuiteLauncher.LaunchArtifact(stiMultiCNC, ...)`, como no MakeRouter.
- **Alteracao necessaria no MultiCNC** (`mainform.pas`, deteccao de origem): reconhecer o
  MultiSlicer, selecionar `mtPrinter3D`, conferir o volume do equipamento contra a caixa
  do trabalho e registrar no log material/temperaturas/tempo.

### RF11 - Projeto
Arquivo de projeto (ex.: `.mslice`, JSON) com caminhos das malhas, transformacoes,
suportes manuais, impressora, material e configuracoes; Novo/Abrir/Salvar como nas
demais ferramentas; abertura pelo contexto da suite (`ReadSuiteContext`).

### RF12 - Importacao
Tela abre STL e 3MF (o importador 3MF ja existe); recebe malha exportada pelo MultiCAD.
Aviso de malha nao fechada/normais invertidas.

## 3. Requisitos nao funcionais
- Object Pascal / Lazarus, Windows e Linux, sem OpenGL obrigatorio.
- Fatiamento em thread com progresso e cancelamento (a tela nao congela).
- Numeros no G-code com `InvariantFS` (ponto decimal).
- Toda mudanca de cena/configuracao invalida o G-code anterior (regra ja existente).
- Testes: transformacao, lay flat, deteccao de saliencia, geracao de suporte,
  cabecalho/contrato, cena com varios objetos, regressao do `test_modern_slicer`.
- Remover/isolar o legado (`multislicer_engine`, `multislicer_gcode`, executavel
  `multislicer_position`) apos a migracao.

## 4. Ordem de implementacao proposta
1. Tela no padrao da suite + perfil/material + abrir STL/3MF (pipeline atual).
2. Cena com varios objetos, vista 3D, posicionamento e transformacoes ligadas ao fatiamento.
3. Contrato de cabecalho + botao Abrir no MultiCNC + ajuste da deteccao no MultiCNC.
4. Suportes automaticos e manuais, brim/raft.
5. Previa 3D por camada, resumo, projeto `.mslice`, fatiamento em thread.
6. Testes e remocao do legado.
