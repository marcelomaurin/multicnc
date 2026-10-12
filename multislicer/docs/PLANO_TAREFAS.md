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

- [ ] 4.1 (arrastar na mesa e assentar em Z = 0 ja entregues na Etapa 3; faltam os campos X/Y/Z) Ferramenta Mover: arrastar no plano da mesa; campos X/Y/Z; "Cair na mesa" (Z min = 0) sempre ligado por padrao.
- [ ] 4.2 Ferramenta Girar: campos X/Y/Z em graus, botoes +-90; aneis na vista (fase posterior).
- [ ] 4.3 Ferramenta Escalar: uniforme ou por eixo, em mm ou %; mostra tamanho final.
- [ ] 4.4 Espelhar X/Y/Z.
- [ ] 4.5 **Deitar face na mesa** (lay flat): por clique numa face e automatico (maior area plana).
- [ ] 4.6 (centralizar, duplicar 1 copia e apagar ja entregues na Etapa 3; faltam N copias e travar na tela) Centralizar, duplicar (N copias), travar, apagar.
- [ ] 4.7 Auto-arranjo usando a caixa envolvente real; validacao de colisao e de volume.
- [ ] 4.8 Desfazer/refazer das transformacoes.
- [ ] 4.9 O fatiamento usa `Scene.MergedMesh` (coordenadas da mesa); cada objeto recebe rotulo
      proprio no G-code (`M486` / `EXCLUDE_OBJECT`) para cancelar uma peca durante a impressao.
- [ ] 4.10 Retirar o executavel separado `multislicer_position` (funcionalidade migrou para a tela principal).

**Aceite:** girar a peca 90 graus em X e fatiar gera camadas na nova orientacao; peca movida
para o canto sai com as coordenadas X/Y corretas no G-code; validacao barra peca fora da mesa.

---

## Etapa 5 - Qualidade e preenchimento (modo recomendado + personalizado)

**Arq.:** `src/app/multislicer_main.pas` (pagina "Qualidade"), `src/core/multislicer_settings.pas`.

- [ ] 5.1 Modo recomendado: perfis Fino 0,1 / Normal 0,2 / Rascunho 0,3; barra de preenchimento %;
      caixas "Gerar suporte" e "Aderencia" (atalho para a etapa 5/6).
- [ ] 5.2 Modo personalizado: paredes, topo/fundo, padrao (gyroid/retilineo), velocidades,
      altura adaptativa, arcos, z-hop, pressure advance, saia.
- [ ] 5.3 Validacoes: altura de camada <= 80% do bico; largura de linha coerente; velocidades > 0.
- [ ] 5.4 Salvar/carregar perfil de qualidade.

**Aceite:** trocar Fino/Normal/Rascunho muda o numero de camadas e o tempo estimado.

---

## Etapa 6 - Suportes (hastes de apoio) e aderencia

**Arq.:** `src/core/multislicer_support.pas`, `src/core/multislicer_pipeline.pas`,
`src/ui/multislicer_view3d.pas`, pagina "Suportes".

### 6A Deteccao e posicionamento
- [ ] 6.1 Detectar faces em saliencia pelo angulo (padrao 50 graus, configuravel) na malha da cena.
- [ ] 6.2 Destacar as saliencias em vermelho na vista 3D.
- [ ] 6.3 **Suporte manual:** clicar na peca adiciona uma haste (cilindro/quadrado com diametro configuravel)
      do ponto ate a mesa ou ate a peca abaixo; lista de hastes; remover; mover.
- [ ] 6.4 **Bloqueador de suporte:** caixa onde o suporte automatico nao e gerado.
- [ ] 6.5 Opcoes: automatico / somente manual / desligado; "tocando a mesa" x "em toda parte".

### 6B Geracao por camada
- [ ] 6.6 Regiao de suporte por camada = projecao das saliencias (e hastes) - contorno da peca expandido
      pela folga XY; respeitar distancia Z de topo e de fundo.
- [ ] 6.7 Preenchimento do suporte: linhas ou grade, densidade %, largura de linha.
- [ ] 6.8 Camadas de interface (topo do suporte) mais densas.
- [ ] 6.9 Novos papeis `prSupport` e `prSupportInterface`; `;TYPE:Support material` /
      `;TYPE:Support material interface` no G-code; velocidade propria.
- [ ] 6.10 Fase posterior: suporte em arvore.

### 6C Aderencia
- [ ] 6.11 Aba (brim): largura/numero de voltas, so na 1a camada.
- [ ] 6.12 Jangada (raft): camadas base/meio/topo, folga ate a peca.
- [ ] 6.13 Saia (ja existe) passa para esta pagina.

**Aceite:** modelo em "T" ou Benchy gera suporte sob as saliencias e nao na peca; haste manual aparece
na previa e no G-code; aba visivel na 1a camada.

---

## Etapa 7 - Previa

**Arq.:** `src/ui/multislicer_preview3d.pas`, `src/app/multislicer_layerpreview.pas` (manter 2D como opcao).

- [ ] 7.1 Fatiamento em thread com barra de progresso e Cancelar (tela nao congela).
- [ ] 7.2 Previa 3D das trajetorias por camada com deslizante de camada (e de movimento dentro da camada).
- [ ] 7.3 Cores por papel (parede externa, interna, solido, preenchimento, suporte, interface, saia/aba)
      com legenda; opcao de mostrar deslocamentos e retracoes.
- [ ] 7.4 Cartao de resumo (como no Cura): tempo estimado, filamento em m e g, custo, camadas, avisos.
- [ ] 7.5 A previa usa exatamente o mesmo resultado que gera o G-code.

**Aceite:** a camada exibida corresponde ao bloco `;LAYER_CHANGE` correspondente no G-code.

---

## Etapa 8 - Saida, projeto e despacho ao MultiCNC

### 8A Contrato do G-code
**Arq.:** `src/shared/multisuite_gcode_writer.pas`, `src/core/multislicer_pipeline.pas`.
- [ ] 8.1 Aceitar `Machine = 'printer3d'` em `TSuiteGCodeHeader` / `SuiteParseHeader`
      (hoje so `router` e `laser`), mantendo compatibilidade.
- [ ] 8.2 Cabecalho do MultiSlicer no contrato: origem `MultiSlicer`, maquina `printer3d`, titulo,
      impressora, material, temperaturas, tempo, filamento e caixa do trabalho;
      linha de identificacao `; MultiSlicer -> MultiCNC (Impressora 3D)`.
- [ ] 8.3 Manter as linhas reconhecidas por OctoPrint/Moonraker (`;TIME:`, `;Filament used:`, `;FLAVOR:`).

### 8B Salvar
- [ ] 8.4 Salvar G-code (`.gcode`) com nome sugerido pelo projeto.
- [ ] 8.5 Projeto `.mslice` (JSON): objetos (arquivo, transformacao), hastes e bloqueadores, impressora,
      material, qualidade, suporte, aderencia. Novo / Abrir / Salvar / Salvar como; aviso de alteracoes nao salvas.

### 8C Despacho
**Arq.:** `src/app/multislicer_main.pas`.
- [ ] 8.6 Botao **Abrir no MultiCNC**: `TSuiteLauncher.LaunchArtifact(Registry.Tool(Registry.Find(stiMultiCNC)), ...)`
      com o G-code exportado (mesmo codigo do MakeRouter); exporta antes se necessario.

### 8D Alteracao no MultiCNC
**Arq.:** `src/app/mainform.pas` (deteccao de origem do arquivo aberto).
- [ ] 8.7 Reconhecer `; MultiSlicer -> MultiCNC (Impressora 3D)` / `Machine = printer3d` e selecionar `mtPrinter3D`.
- [ ] 8.8 Conferir a caixa do trabalho contra o volume do equipamento cadastrado; avisar se nao couber.
- [ ] 8.9 Registrar no log: impressora, material, temperaturas, tempo e filamento.
- [ ] 8.10 Testar com o simulador (SimuCNC) em modo impressora 3D.

**Aceite:** gerar no MultiSlicer, clicar em Abrir no MultiCNC: o MultiCNC abre com o programa carregado e
maquina Impressora 3D selecionada; simulacao executa ate o fim.

---

## Etapa 9 - Importacao, testes e limpeza

- [ ] 9.1 Abrir STL e 3MF na tela; arrastar arquivo para a janela.
- [ ] 9.2 Aviso de malha nao fechada, normais invertidas, peca fora da escala (ex.: polegadas).
- [ ] 9.3 Receber malha exportada pelo MultiCAD (contexto da suite).
- [ ] 9.4 Testes automatizados (`tests/`): transformacao e caixa envolvente, lay flat, cena com varios objetos,
      deteccao de saliencia, geracao de suporte, brim, cabecalho/contrato, perfis JSON, regressao do
      `test_modern_slicer`.
- [ ] 9.5 Registrar os testes no Centro de Testes da suite (`multisuite_test_catalog`).
- [ ] 9.6 Remover `multislicer_engine.pas`, `multislicer_gcode.pas`, `multislicer_position.*`,
      `multislicer_positionform.pas` e `multislicer_bedcanvas.pas` se nao forem mais usados.
- [ ] 9.7 Atualizar `README.md`, `docs/ARCHITECTURE.md`, `docs/AI_GUIDE.md`, `docs/POSICIONAMENTO_3D.md`
      e as capturas em `screenshots/`.
- [ ] 9.8 Gerar `bin/multislicer.exe` e incluir no instalador.

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
