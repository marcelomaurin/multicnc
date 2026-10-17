# MultiSlicer - Plano de etapas e tarefas

Base: [REQUISITOS.md](REQUISITOS.md). Referencia funcional: UltiMaker Cura.
Objetivo: posicionar a peca na mesa, ajustar temperatura e filamento, posicionar
as hastes de apoio, gerar e salvar o G-code e despachar para o MultiCNC imprimir.

Regras para todas as etapas
- Object Pascal / Lazarus; compila no Windows e no Linux; sem OpenGL obrigatorio.
- Padrao visual da suite (igual a MakeRouter, LaserPCB, MakePCB, RouterPCB).
- O MultiSlicer prepara; o MultiCNC conecta e imprime. Nada de serial aqui.
- Numeros no G-code com `InvariantFS`.
- Ao fim de cada etapa: compilar, rodar os testes, commit e push na branch `fila`.
- Marcar `[x]` nas tarefas concluidas neste arquivo.

Legenda: **Arq.** = arquivos a criar/alterar. **Aceite** = como verificar.

---

## Etapa 0 - Preparacao

- [x] 0.1 Incluir `../../../multisuite/src/core` em `OtherUnitFiles` de `multislicer.lpi`
      (necessario para `multisuite_controls`, `multisuite_icons`, `multisuite_registry`,
      `multisuite_launcher`).
- [x] 0.2 Garantir que `multislicer.lpi` e `tests/test_modern_slicer.lpr` compilam com `lazbuild`.
- [x] 0.3 (resolvida na Etapa 2 com `multislicer_printers` e `multislicer_materials`, em vez de uma unidade unica) Criar `src/core/multislicer_settings.pas` concentrando os tipos de configuracao
      (impressora, material, qualidade, suporte, aderencia) hoje espalhados entre
      `multislicer_types`, `multislicer_profile` e `multislicer_pipeline`.
- [x] 0.4 Marcar como legado (sem uso pela tela) `multislicer_engine.pas` e
      `multislicer_gcode.pas`; nao apagar ainda (Etapa 9).

**Aceite:** projeto e testes compilam sem alterar o comportamento atual.

---

## Etapa 1 - Tela principal no padrao da suite

**Arq.:** `src/app/multislicer_main.pas` (reescrita), `src/app/multislicer.lpr`.

- [x] 1.1 Formulario `inherited CreateNew(AOwner, 1)`, `Font.Name := SUITE_FONT`, `Color := clSuiteSurface`,
      1280x860, minimo 1060x680, caption `MultiSlicer • MultiSuite`.
- [x] 1.2 `TSuiteHeader.Setup('MultiSlicer', 'Preparacao para impressao 3D  /  MultiSuite', sikSlicer)`.
- [x] 1.3 Barra lateral (`clSuiteCard`, 214 px) com as etapas em `TSuiteButton`:
      1 Impressora, 2 Modelo, 3 Material, 4 Qualidade, 5 Suportes, 6 Previa, 7 Saida.
      Botoes Novo / Abrir / Salvar / Importar abaixo; lista de objetos (`TListBox`).
- [x] 1.4 Painel de parametros a direita: `TPageControl` sem abas (336 px), um `TScrollBox`
      por etapa, com os helpers `LabelAt`, `Field`, `Combo`, `Button` no mesmo estilo do MakeRouter.
- [x] 1.5 Barra superior da vista: Mesa / Camadas, Ajustar, Ampliar, Reduzir, deslizante de camada;
      roda do mouse amplia no cursor, arrastar desloca. Vistas padrao (frente, lado, iso) ficam para a Etapa 3.
- [x] 1.6 Rodape (`clSuiteCard`, 66 px): status, coordenadas, indicador de estado
      (`clSuiteWarning` aguardando / `clSuiteInfo` fatiado / `clSuiteSuccess` G-code gerado /
      `clSuiteDanger` erro) e botoes **Validar**, **Fatiar** (solido, `clSuitePrimary`) e
      **Abrir no MultiCNC** (`sikSend`, desabilitado ate exportar).
- [x] 1.7 Ligar o pipeline atual (`TModernSlicer`) aos novos campos, mantendo a regra:
      qualquer alteracao invalida o G-code anterior.
- [x] 1.8 Abrir pelo contexto da suite (`ReadSuiteContext`) como hoje.

**Aceite:** a tela fica visualmente igual as demais ferramentas; abrir um STL, fatiar e exportar
continua funcionando; `test_slicer_app` atualizado passa.

**Entregue (2026-10-12):** `multislicer_main.pas` reescrito; nova vista `src/ui/multislicer_view.pas`
(mesa vista de cima com grade de 10 mm e projecao da peca, parte fora da mesa em vermelho; previa de
camadas colorida por papel em coordenadas da mesa). Extras ja adiantados: abre STL e 3MF; ao abrir, a
peca e centralizada na mesa e assentada em Z = 0 (antes era fatiada nas coordenadas cruas do arquivo);
perfis fixos Creality Ender-3 (Bowden, retracao 5 mm) e Generic Marlin; Validar confere mesa X/Y/Z;
botao Abrir no MultiCNC ja chama o MultiCNC (a troca automatica para Impressora 3D depende da tarefa 8.7).
`multislicer_layerpreview.pas` deixou de ser usado pela tela.

---

## Etapa 2 - Perfis de impressora e material

**Arq.:** `src/core/multislicer_printers.pas`, `src/core/multislicer_materials.pas`,
`src/core/multislicer_userdata.pas`. Perfis prontos no codigo; perfis do usuario em JSON na pasta de
configuracao (`GetAppConfigDir`, no Windows `%LOCALAPPDATA%\multislicer\printers|materials`), trocavel
pela variavel `MULTISLICER_PROFILE_DIR`.

### 2A Impressora
- [x] 2.1 (origem no centro ficou para depois: o pipeline gera sempre com origem no canto) Registro `TPrinterDef`: nome, volume X/Y/Z, origem (canto/centro), bico,
      diametro do filamento, firmware (Marlin/Klipper), mesa aquecida, tipo de extrusora
      (Bowden/direta), G-code inicial e final (texto com variaveis `{hotend}`, `{bed}`).
- [x] 2.2 Ler/gravar perfis em JSON (`fpjson`), lista de perfis no combo da etapa 1.
- [x] 2.3 Perfil pronto **Creality Ender-3** (220 x 220 x 250, Marlin, 1,75 mm, Bowden, bico 0,4).
- [x] 2.4 Perfis "Generic Marlin" e "Generic Klipper"; editar os campos e Salvar com outro nome = duplicar;
      Excluir so para perfis do usuario (mesmo nome de um pronto substitui o pronto).
- [x] 2.5 Pagina "Impressora": campos acima + memos de G-code inicial/final.

### 2B Material
- [x] 2.6 Registro `TMaterialProfile`: nome, tipo, bico 1a camada e demais, mesa 1a camada e demais,
      ventoinha min/max e camada de inicio, densidade g/cm3, fluxo %, retracao comprimento/velocidade
      (Bowden e direta), custo por kg.
- [x] 2.7 Biblioteca padrao: PLA, PETG, ABS, ASA, TPU, Personalizado.
- [x] 2.8 Pagina "Material": combo de material; ao trocar, preenche os campos (editaveis);
      salvar como material do usuario.
- [x] 2.9 Pipeline usa temperatura de 1a camada e demais, densidade, ventoinha e retracao do material
      (retracao conforme o tipo de extrusora da impressora).

**Aceite:** trocar PLA -> PETG altera M104/M140/M106 e a retracao no G-code gerado;
perfis sobrevivem ao reabrir o programa.

**Entregue (2026-10-12):** pagina Impressora com perfil, firmware, extrusora (Bowden/direta), mesa aquecida,
volume, bico, filamento e G-code inicial/final com variaveis (`{first_layer_bed_temp}`, `{bed_y}`...);
Ender-3 com linha de purga e final que traz a mesa para frente. Pagina Material com PLA, PETG, ABS, ASA,
TPU e Personalizado: bico/mesa da 1a camada e demais, ventoinha %, fluxo, retracao (do tipo de extrusora),
densidade e custo (aparece no resumo da previa). Ultima impressora/material lembrados. Pipeline:
temperatura da 1a camada com troca na 2a, M106 proporcional, fluxo, mesa nao aquecida, cabecalho com
impressora e `filament_type`. Teste de GUI cobre o aceite.

---

## Etapa 3 - Cena com varios objetos e vista 3D da mesa

**Arq.:** `src/core/multislicer_scene.pas`, `src/ui/multislicer_view3d.pas`,
`src/layout/multislicer_transform3d.pas` (matriz completa), unidades de render compartilhadas.

- [x] 3.1 (decidido: o `.lpi` referencia `multicad/src/core;kernel;ui`, sem mover arquivos nem mexer no MultiCAD) Mover `multicad_camera` e `multicad_softrender` (ou um nucleo comum deles) para
      `src/shared/` sem quebrar o MultiCAD; ou referenciar a pasta do MultiCAD no `.lpi`.
      Decidir e documentar.
- [x] 3.2 `TSliceObject`: malha original, nome, arquivo, posicao, rotacao, escala, espelho, travado,
      cor; `WorldMesh` (malha transformada em cache) e caixa envolvente real (dos vertices).
- [x] 3.3 `TSliceScene`: lista de objetos, volume da impressora, adicionar/remover/duplicar,
      `MergedMesh` para o fatiamento.
- [x] 3.4 `TSlicerView3D`: mesa com grade de 10 mm, volume em linhas, triedro, malhas sombreadas,
      objeto selecionado em destaque, objeto fora do volume em vermelho.
- [x] 3.5 Navegacao igual ao MultiCAD (meio gira, Ctrl+meio desloca, roda zoom no cursor, F enquadrar,
      cubo de vistas).
- [x] 3.6 Selecionar objeto por clique (raio x triangulo); Ctrl soma a selecao.
- [x] 3.7 Desempenho: malha de 200 mil triangulos navega sem travar (reduzir a malha durante o arraste se preciso).

**Aceite:** abrir dois STL, ve-los na mesa da Ender-3 em 3D, girar a camera e selecionar cada um.

**Entregue (2026-10-12):** `src/core/multislicer_scene.pas` (pecas com malha original + transformacao,
malha na mesa em cache, assentada em Z = 0, lugar livre ao abrir, validacao de volume e sobreposicao,
malha unica para o fatiamento) e `src/ui/multislicer_view3d.pas` (mesa, grade de 10 mm, volume tracejado,
eixos, pecas sombreadas; azul = selecionada, vermelho = fora do volume; selecao exata pelo buffer de Id;
Frente/Topo/Iso, F enquadra). Navegacao: direito ou meio gira, Shift/Ctrl desloca, roda amplia no cursor,
esquerdo no vazio gira. Malha de 200 mil triangulos: abre em ~1,5 s, quadro completo ~250 ms e, ao girar,
quadro rapido de ~13 ms com malha reduzida (agrupamento de vertices) em meia resolucao. A previa de
camadas continua 2D (`multislicer_view.pas`) ate a Etapa 7. Testes: `tests/test_scene.lpr` e o teste de GUI.
Adiantado da Etapa 4: arrastar a peca na mesa, duplicar, remover (Delete), centralizar, limpar mesa;
abrir varios arquivos de uma vez pela linha de comando.

---

## Etapa 4 - Posicionamento da peca

**Arq.:** `src/layout/multislicer_layout3d.pas` (adaptar a cena), `src/app/multislicer_main.pas`
(pagina "Modelo"), `src/ui/multislicer_view3d.pas` (gizmos).

- [x] 4.1 (campos X/Y do centro; Z e sempre assentado na mesa) Ferramenta Mover: arrastar no plano da mesa; campos X/Y/Z; "Cair na mesa" (Z min = 0) sempre ligado por padrao.
- [x] 4.2 Ferramenta Girar: campos X/Y/Z em graus, botoes +90 (em torno dos eixos da mesa); aneis na vista ficam para depois.
- [x] 4.3 Ferramenta Escalar: uniforme ou por eixo, em mm ou %; mostra tamanho final.
- [x] 4.4 Espelhar X/Y/Z.
- [x] 4.5 **Deitar face na mesa** (lay flat): por clique numa face e automatico (maior area plana).
- [x] 4.6 Centralizar, duplicar (N copias), travar, apagar.
- [x] 4.7 Auto-arranjo usando a caixa envolvente real; validacao de colisao e de volume.
- [x] 4.8 Desfazer/refazer das transformacoes (posicao, rotacao, escala, espelho, travar; nao recupera peca removida).
- [x] 4.9 O fatiamento usa `Scene.MergedMesh` (coordenadas da mesa); cada objeto recebe rotulo
      proprio no G-code (`M486` / `EXCLUDE_OBJECT`) para cancelar uma peca durante a impressao.
- [x] 4.10 Retirar o executavel separado `multislicer_position` (funcionalidade migrou para a tela principal).

**Aceite:** girar a peca 90 graus em X e fatiar gera camadas na nova orientacao; peca movida
para o canto sai com as coordenadas X/Y corretas no G-code; validacao barra peca fora da mesa.

**Entregue (2026-10-12):** pagina Modelo com Mover (X/Y), Girar (campos e +90 nos eixos da mesa),
Deitar (auto, pela face plana com maior apoio) e Escolher face (clique na vista), Escalar (% ou mm,
uniforme ou por eixo), Espelhar, copias, travar, Organizar mesa e Desfazer/Refazer (Ctrl+Z / Ctrl+Y).
Cena: rotacao composta por matriz e convertida de volta para X/Y/Z; historico por Id da peca.
Pipeline: com varias pecas, cada camada sai agrupada por peca entre `M486 S<n>` (Marlin) ou
`EXCLUDE_OBJECT_START/END` (Klipper), com `M486 T<n>` / `EXCLUDE_OBJECT_DEFINE` por peca no cabecalho,
para cancelar uma peca durante a impressao. Executavel `multislicer_position` removido.
Testes: `test_scene` (deitar, Euler, desfazer, organizar, copias, travar, rotulos) e o teste de GUI (aceite).

---

## Etapa 5 - Qualidade e preenchimento (modo recomendado + personalizado)

**Arq.:** `src/app/multislicer_main.pas` (pagina "Qualidade"), `src/core/multislicer_quality.pas`.

- [x] 5.1 ("Gerar suporte" fica desabilitado ate a Etapa 6; "Aderencia" liga/desliga a saia) Modo recomendado: perfis Fino 0,1 / Normal 0,2 / Rascunho 0,3; barra de preenchimento %;
      caixas "Gerar suporte" e "Aderencia" (atalho para a etapa 5/6).
- [x] 5.2 Modo personalizado: paredes, topo/fundo, padrao (gyroid/retilineo), velocidades,
      altura adaptativa, arcos, z-hop, pressure advance, saia.
- [x] 5.3 Validacoes: altura de camada <= 80% do bico; largura de linha coerente; velocidades > 0.
- [x] 5.4 Salvar/carregar perfil de qualidade.

**Aceite:** trocar Fino/Normal/Rascunho muda o numero de camadas e o tempo estimado.

**Entregue (2026-10-12):** `multislicer_quality.pas` com Fino 0,1 / Normal 0,2 / Rascunho 0,3 (1a camada,
largura de linha %, paredes, topo/fundo, preenchimento, padrao, velocidades separadas, adaptativa, arcos,
z-hop, pressure advance) e perfis do usuario em JSON (pasta `quality`). Pagina Qualidade com modo
Recomendado (cartoes, barra de preenchimento, aderencia) e Personalizado (todos os campos, salvar/excluir,
aviso de perfil alterado); modo e perfil lembrados. Validacoes: camada e 1a camada ate 80% do bico,
largura de linha 80 a 150% e maior que a camada, velocidades > 0, 1a camada lenta. Medido na caixa
30 x 10 x 15: Fino 149 camadas / ~24 min, Normal 75 / ~10 min, Rascunho 50 / ~5 min.

---

## Etapa 6 - Suportes (hastes de apoio) e aderencia

**Arq.:** `src/core/multislicer_support.pas`, `src/core/multislicer_clip.pas` (Clipper2),
`src/core/multislicer_pipeline.pas`, `src/core/multislicer_scene.pas`, `src/ui/multislicer_view3d.pas`,
pagina "Suportes".

### 6A Deteccao e posicionamento
- [x] 6.1 Detectar faces em saliencia pelo angulo (padrao 50 graus, configuravel) na malha da cena.
- [x] 6.2 Destacar as saliencias em vermelho na vista 3D.
- [x] 6.3 **Suporte manual:** clicar na peca adiciona uma haste (cilindro/quadrado com diametro configuravel)
      do ponto ate a mesa ou ate a peca abaixo; lista de hastes; remover; mover.
- [x] 6.4 **Bloqueador de suporte:** caixa onde o suporte automatico nao e gerado.
- [x] 6.5 Opcoes: automatico / somente manual / desligado; "tocando a mesa" x "em toda parte".

### 6B Geracao por camada
- [x] 6.6 Regiao de suporte por camada = projecao das saliencias (e hastes) - contorno da peca expandido
      pela folga XY; respeitar distancia Z de topo e de fundo.
- [x] 6.7 Preenchimento do suporte: linhas ou grade, densidade %, largura de linha.
- [x] 6.8 Camadas de interface (topo do suporte) mais densas.
- [x] 6.9 Novos papeis `prSupport` e `prSupportInterface`; `;TYPE:Support material` /
      `;TYPE:Support material interface` no G-code; velocidade propria.
- [ ] 6.10 Fase posterior: suporte em arvore.

### 6C Aderencia
- [x] 6.11 Aba (brim): largura/numero de voltas, so na 1a camada.
- [x] 6.12 Jangada (raft): camadas base/meio/topo, folga ate a peca.
- [x] 6.13 Saia (ja existe) passa para esta pagina.

**Aceite:** modelo em "T" ou Benchy gera suporte sob as saliencias e nao na peca; haste manual aparece
na previa e no G-code; aba visivel na 1a camada.

**Entregue (2026-10-12):** suporte por camadas: saliencia = o que a camada de baixo, alargada por
h*tan(angulo), nao sustenta; a coluna desce com fechamento de frestas ("join distance" 2 mm, necessario em
superficies curvas), desconta a peca com folga XY e para a folga Z abaixo dela; "tocando a mesa" para se
encontrar a peca; bloqueadores (caixas) e hastes manuais (cilindros ate o ponto clicado, presos a peca:
acompanham ao arrastar e caem se a peca girar/escalar); interface densa nas camadas logo abaixo; linhas
cruzadas 0/90 graus. Aderencia: nenhuma / saia (envolve peca e suporte) / aba (brim) / jangada (raft:
base, meio e 2 de topo, folga de ar). Vista 3D: saliencias em vermelho, hastes laranja, bloqueadores
translucidos; "Adicionar hastes" fica ativo ate Esc. Modo de suporte e tipo de aderencia lembrados.
Testes: `tests/test_support.lpr` (T, C, esfera, bloqueador, haste, aba, jangada, saia) e o teste de GUI.

**Observacao (desempenho):** o suporte quase nao custa tempo, mas o motor de fatiamento ja existente leva
~100 s numa malha de 200 mil triangulos (esfera de 80 mm, 400 camadas) - resolvido na tarefa 7.6.

---

## Etapa 7 - Previa

**Arq.:** `src/ui/multislicer_preview3d.pas`, `src/app/multislicer_layerpreview.pas` (manter 2D como opcao).

- [x] 7.0 Combo de equipamento no topo (como no MultiCNC/LaserArt): lista as impressoras 3D do
      cadastro do MultiCNC + "Ajuste manual"; marca/modelo completam o perfil pelo catalogo
      `multislicer_machines` (17 modelos, dados do Cura e das fichas dos fabricantes); a porta e so
      informativa (usada pelo MultiCNC); temperatura acima do limite da maquina reprova a validacao.
      Entregue (2026-10-12), versao 0.0.6.1.
- [x] 7.1 Fatiamento em thread com barra de progresso e Cancelar (tela nao congela).
      Entregue (2026-10-12): TSliceThread + barra no rodape com a fase (camadas, suportes,
      preenchimento, G-code), Cancelar/Esc para em menos de 1 s e mantem a previa anterior;
      fechar a janela no meio cancela e fecha.
- [x] 7.6 Desempenho do fatiamento em malhas grandes: medir onde vai o tempo (corte das camadas,
      encadeamento de segmentos, solido/preenchimento por amostragem de pontos) e otimizar
      (indice de triangulos por faixa de Z, teste de solido por poligonos em vez de pontos).
      Entregue (2026-10-12). Esfera de 80 mm, 400 camadas, gyroid 20%:
      | malha | antes | depois |
      | --- | --- | --- |
      | 3.200 triangulos | 13,6 s | 4,1 s |
      | 80.000 triangulos | 63,1 s | 5,5 s |
      - topo/fundo por regioes (Clipper): interior = intersecao das camadas vizinhas (antes: teste de
        ponto a cada 2 linhas) - tambem acha as faixas de topo finas das superficies curvas;
      - linhas de preenchimento recortadas todas de uma vez pela Clipper (antes: cada linha contra
        todas as arestas);
      - arc fitting (multisuite_arcfit) com busca dobrando + bissecao: O(n log n) (6,2 s -> 0,3 s);
      - paredes por offset da Clipper com cantos vivos sobre a regiao unida da camada;
      - encadeamento de segmentos por grade de hash (multisuite_geometry) e varredura em Z dos
        triangulos;
      - gyroid simplificado com desvio de 0,02 mm.
- [x] 7.2 Previa 3D das trajetorias por camada com deslizante de camada (e de movimento dentro da camada).
      Entregue (2026-10-12): `src/ui/multislicer_toolpath3d.pas`, fitas com largura de linha e altura
      de camada na mesma vista 3D da mesa (mesma camera); abre na ultima camada; opcao so a camada.
      Falta o deslizante de movimento dentro da camada.
- [x] 7.3 Cores por papel (parede externa, interna, solido, preenchimento, suporte, interface, saia/aba)
      com legenda; opcao de mostrar deslocamentos e retracoes. Entregue: legenda e deslocamentos
      da camada (retracoes ainda nao marcadas).
- [x] 7.4 Cartao de resumo (como no Cura): tempo estimado, filamento em m e g, custo, camadas, avisos.
- [x] 7.5 A previa usa exatamente o mesmo resultado que gera o G-code (teste: Z de cada camada = ;Z: do
      ;LAYER_CHANGE correspondente).

**Aceite:** a camada exibida corresponde ao bloco `;LAYER_CHANGE` correspondente no G-code.

**Etapa 7 entregue (2026-10-12), versao 0.0.7.0.** Pendente para depois: deslizante de movimento dentro
da camada e marcas de retracao na previa.

---

## Etapa 8 - Saida, projeto e despacho ao MultiCNC

### 8A Contrato do G-code
**Arq.:** `src/shared/multisuite_gcode_writer.pas`, `src/core/multislicer_pipeline.pas`.
- [x] 8.1 Aceitar `Machine = 'printer3d'` em `TSuiteGCodeHeader` / `SuiteParseHeader`
      (hoje so `router` e `laser`), mantendo compatibilidade.
- [x] 8.2 Cabecalho do MultiSlicer no contrato: origem `MultiSlicer`, maquina `printer3d`, titulo,
      impressora, material, temperaturas, tempo, filamento e caixa do trabalho;
      linha de identificacao `; MultiSlicer -> MultiCNC (Impressora 3D)`.
- [x] 8.3 Manter as linhas reconhecidas por OctoPrint/Moonraker (`;TIME:`, `;Filament used:`, `;FLAVOR:`).

### 8B Salvar
- [x] 8.4 Salvar G-code (`.gcode`) com nome sugerido pelo projeto.
- [x] 8.5 Projeto `.mslice` (JSON): objetos (arquivo, transformacao), hastes e bloqueadores, impressora,
      material, qualidade, suporte, aderencia. Novo / Abrir / Salvar / Salvar como; aviso de alteracoes nao salvas.

### 8C Despacho
**Arq.:** `src/app/multislicer_main.pas`.
- [x] 8.6 Botao **Abrir no MultiCNC**: `TSuiteLauncher.LaunchArtifact(Registry.Tool(Registry.Find(stiMultiCNC)), ...)`
      com o G-code exportado (mesmo codigo do MakeRouter); exporta antes se necessario.

**8A-8C entregues (2026-10-12), versao 0.0.7.1.** O `SuiteParseHeader` ja lia qualquer `MS-MACHINE`;
o G-code comeca com `; MultiSlicer -> MultiCNC (Impressora 3D)`, `MS-CONTRACT`, `MS-MACHINE: printer3d`,
`MS-BOUNDS` (caixa das pecas), `MS-PRINTER`, `MS-MATERIAL`, `MS-TEMP`, `MS-PRINT` (tempo, camadas,
filamento) e segue com `;FLAVOR:`, `;TIME:`, `;Filament used:`. Projeto: `src/core/multislicer_project.pas`
(modelos por caminho relativo ao projeto e absoluto; pasta movida inteira continua abrindo), botoes na
etapa Saida, Ctrl+S / Ctrl+Shift+S / Ctrl+O, nome no titulo com `*` quando alterado, pergunta antes de
descartar. G-code com o nome do projeto. Abrir no MultiCNC gera o G-code antes se preciso.

### 8D Alteracao no MultiCNC
**Arq.:** `src/app/mainform.pas` (deteccao de origem do arquivo aberto).
- [x] 8.7 Reconhecer `; MultiSlicer -> MultiCNC (Impressora 3D)` / `Machine = printer3d` e selecionar `mtPrinter3D`.
- [x] 8.8 Conferir a caixa do trabalho contra o volume do equipamento cadastrado; avisar se nao couber.
- [x] 8.9 Registrar no log: impressora, material, temperaturas, tempo e filamento.
- [x] 8.10 Testar com o simulador (SimuCNC) em modo impressora 3D.

**8D entregue (2026-10-13), MultiCNC 0.1.0.4 e MultiSlicer 0.1.0.0.** `SuiteParseHeader` le
`MS-PRINTER/MATERIAL/TEMP/PRINT`; `OpenProgramFile` (tambem ao arrastar e no botao Abrir) seleciona
Impressora 3D/Marlin, registra impressora, material, temperaturas, tempo e filamento e confere a caixa
contra o volume do equipamento. Achados no teste real: o analisador do MultiCNC acusava erro em
`M84 X Y E` (letra sem valor, valido no Marlin) e mais de 200 avisos de avanco porque usava limites de
router (5000 mm/min) para impressora - corrigidos. Testes: `tests/test_app` (contrato, volume, analise sem
erros) e `tests/test_multislicer_print` (G-code real do fatiador executado ate o fim no simulador Marlin).
Os testes do MultiCNC que usam a sessao so compilam para Windows (Winsock2 e AISerial do repositorio
CHATGPT); aqui foram rodados com Wine.

**Aceite:** gerar no MultiSlicer, clicar em Abrir no MultiCNC: o MultiCNC abre com o programa carregado e
maquina Impressora 3D selecionada; simulacao executa ate o fim.

---

## Etapa 9 - Importacao, testes e limpeza

- [x] 9.1 Abrir STL e 3MF na tela; arrastar arquivo para a janela.
- [x] 9.2 Aviso de malha nao fechada, normais invertidas, peca fora da escala (ex.: polegadas).
- [x] 9.3 Receber malha exportada pelo MultiCAD (contexto da suite).
- [x] 9.4 Testes automatizados (`tests/`): transformacao e caixa envolvente, lay flat, cena com varios objetos,
      deteccao de saliencia, geracao de suporte, brim, cabecalho/contrato, perfis JSON, regressao do
      `test_modern_slicer`.
- [x] 9.5 Registrar os testes no Centro de Testes da suite (`multisuite_test_catalog`).
- [x] 9.6 Remover `multislicer_engine.pas`, `multislicer_gcode.pas`, `multislicer_position.*`,
      `multislicer_positionform.pas` e `multislicer_bedcanvas.pas` se nao forem mais usados.
- [x] 9.7 Atualizar `README.md`, `docs/ARCHITECTURE.md`, `docs/AI_GUIDE.md`, `docs/POSICIONAMENTO_3D.md`
      e as capturas em `screenshots/`.
- [x] 9.8 Gerar `bin/multislicer.exe` e incluir no instalador.

**Entregue (2026-10-13), versao 0.0.9.0.** Arrastar STL/3MF/.mslice para a janela; conferencia da malha
(`multislicer_meshcheck`: malha aberta, nao manifold, normais invertidas corrigidas, peca em polegadas ou
enorme) com botao Polegadas para mm; MultiCAD ja abre a peca no MultiSlicer pelo contexto da suite
(`--file`); testes `test_meshcheck` e desempenho do suporte (`test_support`); Centro de Testes com todos os
testes do MultiSlicer; removidos `multislicer_engine`, `multislicer_gcode`, `multislicer_layerpreview` e
`src/layout` (o `test_locale_invariant` passou a usar o fatiador moderno); README, ARCHITECTURE,
AI_GUIDE e POSICIONAMENTO_3D atualizados, capturas novas em `screenshots/`. O instalador (setup) e
montado pelo processo de setup da suite com o `bin/multislicer.exe` atual.
Correcao encontrada nas capturas: o fechamento das colunas de suporte com cantos redondos acumulava
vertices e levava 3,6 s num T simples; com cantos vivos, 54 ms.

**Aceite:** todos os testes passam; documentacao reflete o programa entregue.

---

## Ordem e dependencias

| Etapa | Depende de | Entrega visivel |
|---|---|---|
| 0 Preparacao | - | compila |
| 1 Tela da suite | 0 | tela no padrao, fatiamento atual |
| 2 Impressora e material | 1 | Ender-3, PLA/PETG/... |
| 3 Cena e vista 3D | 1 | pecas na mesa em 3D |
| 4 Posicionamento | 3 | mover/girar/escalar/deitar |
| 5 Qualidade | 1, 2 | modo recomendado/personalizado |
| 6 Suportes e aderencia | 3, 4 | hastes de apoio, brim, raft |
| 7 Previa | 4, 6 | previa 3D, resumo |
| 8 Saida e MultiCNC | 2, 4 | salvar, projeto, Abrir no MultiCNC |
| 9 Testes e limpeza | todas | versao entregue |

As etapas 2 e 3 podem andar em paralelo depois da 1. A etapa 8A/8C/8D pode ser antecipada
logo apos a 2 para ja permitir imprimir pela Ender-3 com o posicionamento simples.

---

## Extensão — degrau inicial Z (17/10/2026)

**Requisito:** algumas impressoras exigem imprimir em `Z = zero + degrau`. O parâmetro de perfil `PrintStartZ` (`print_start_z` no JSON) desloca verticalmente os percursos já fatiados. A referência do zero físico permanece inalterada. Valor padrão: 0 mm.

### Implementação registrada

- [x] `multislicer_printers.pas`: campo no registro, leitura/gravação de JSON, comparação de perfis, padrão zero.
- [x] `multislicer_main.pas`: campo **Degrau inicial Z (mm)** na etapa Impressora, carregamento, edição, persistência no perfil e transmissão ao `TSliceSettings`.
- [x] `multislicer_pipeline.pas`: deslocamento de Z aplicado após o cálculo de camadas/raft, saída G-code e metadado `MS-PRINT-START-Z`; aviso quando altura do trabalho + degrau excede o limite do equipamento.

### Testes e ajustes pendentes

- [ ] Compilar os projetos MultiSlicer e testes FPC/Lazarus em Windows e Linux.
- [ ] Confirmar que a prévia e a exportação exibem o mesmo Z final, inclusive com raft e suportes.
- [ ] Testar regressão com `PrintStartZ=0` (mesmo G-code anterior) e com 3 mm (primeira camada 0,20 mm → 3,20 mm).
- [ ] Testar leitura de perfis JSON antigos sem a chave e salvar/reabrir perfis novos.
- [ ] Auditar persistência no projeto `.mslice` e perfis originados do catálogo/equipamentos MultiCNC, para não perder o degrau após troca de máquina.
- [ ] Revisar validação do envelope Z final em todas as etapas e conferir `MS-BOUNDS` também nos casos com raft.
- [ ] Verificar G-code de partida personalizado, purga, skirt e movimentos antes da primeira camada; orientar sobre offsets e a referência física.
- [ ] Validar o comportamento em impressora real supervisionada.
- [ ] Atualizar manuais ilustrados após confirmar a UI.

### Critério de aceite

Em uma máquina configurada para uma elevação física de 3 mm, com camada inicial de 0,20 mm, o G-code de impressão deve começar a depositar a peça em Z=3,20 mm; todas as outras camadas devem manter sua distância relativa; perfis antigos precisam continuar com degrau zero. **Não marcar validado em máquina** sem evidência física.
