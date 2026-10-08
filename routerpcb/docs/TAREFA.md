# TAREFA: implementar o RouterPCB (MakePCB -> RouterPCB -> MultiCNC CNC Router)

- **Aberta em:** 08/10/2026
- **Branch:** `fila`
- **Objetivo:** fechar o gap da suíte. Hoje o MakePCB exporta Gerber + Excellon e só o
  LaserPCB os consome; não existe caminho para fresar a placa na CNC Router.
- **Visão da ferramenta:** [../README.md](../README.md)
- **Decisões técnicas:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Guia para IA:** [AI_GUIDE.md](AI_GUIDE.md)

Regras do projeto, que valem para todas as fases:

- Padrão visual da suíte, igual ao LaserPCB/MakePCB: `TSuiteHeader`, barra lateral de
  etapas com `TSuiteButton`, painel à direita em `TScrollBox`, prévia ao centro, rodapé com
  Validar / Gerar G-code / Abrir no MultiCNC.
- Commit e push no `fila` ao fim de cada fase. Use `git -c user.name="Marcelo Maurin"
  -c user.email="marcelomaurinmartins@gmail.com"`.
- Não duplicar código do LaserPCB: reutilizar via `OtherUnitFiles`, como o LaserPCB já faz
  com o LaserArt.
- Rodar os testes de verdade antes de marcar uma fase como concluída.

---

## Fase 0: preparação (≈ 30 min)

- [ ] Mover `DetectLayerRole`, `TLPLayerRole` e `LayerRoleName` de
      `laserpcb/src/core/laserpcb_project.pas` para a nova
      `laserpcb/src/import/laserpcb_roles.pas`. `laserpcb_project` passa a usá-la.
- [ ] Recompilar e rodar os testes do LaserPCB (`test_pipeline`, `test_drill`, `test_ui`),
      que não podem mudar de resultado.
- [ ] Criar a árvore `routerpcb/src/{core,cam,level,export,ui,app}` e `routerpcb/tests`.
- [ ] Gerar uma pasta de exemplo para os testes: exemplo 555 do MakePCB, exportada para
      `routerpcb/tests/fixtures/astable_gerber/`, com camadas B_Cu, Edge_Cuts, PTH e NPTH.

## Fase 1: núcleo (≈ 2 h)

- [ ] `routerpcb_types.pas`: registros de opções com padrões e `Validate(Errors)`.

  | Parâmetro | Padrão |
  |---|---|
  | Fresa V | 30°, ponta 0,1 mm, profundidade -0,08 mm, avanço 150 mm/min, mergulho 50 mm/min, 12000 RPM |
  | Isolação | 2 passadas, sobreposição 30 %, concordante |
  | Brocas | 0,6 / 0,8 / 1,0 / 1,2 / 1,5 / 2,0 / 3,0 mm, tolerância ±0,1 mm |
  | Furação | profundidade -1,8 mm, bicada 0 (direto), mergulho 60 mm/min |
  | Recorte | fresa de topo 2,0 mm, espessura 1,6 mm, passo -0,6 mm, avanço 200 mm/min, 4 pontes de 3 mm com 0,6 mm de altura |
  | Máquina | SafeZ 5 mm, TravelZ 2 mm, espera do spindle 2 s, troca de ferramenta com M0 |
  | Nivelamento | grade 5×4, margem 2 mm, ProbeDepth -2 mm, ProbeFeed 50, MaxSegment 1 mm, MaxCorrection 0,5 mm |

- [ ] `routerpcb_project.pas`:
  - `ImportFolder`/`ImportFile` com os leitores do LaserPCB;
  - lado (placa de face simples abre em Bottom);
  - `OutputMatrix`;
  - `RebuildMasks` (resolução 0,02 mm);
  - `Warnings`.
- [ ] `routerpcb_isolation.pas`: largura efetiva da fresa V, `GenerateIsolation`,
      verificação de folga (ilhas que se unem) e sentido de corte.
- [ ] `routerpcb_drillmap.pas`: biblioteca de brocas, ajuste diâmetro → broca, avisos e
      furos fresados.
- [ ] `routerpcb_cutout.pas`: contorno externo (+R), recortes internos (−R), passos de
      profundidade e pontes por altura.
- [ ] `tests/test_routerpcb.lpr`, primeira parte, cobrindo:
  - largura da fresa V (30°/0,1/0,08 → 0,143);
  - isolação não vazia sobre o fixture;
  - nenhum ponto da isolação a menos de W/2 − res do cobre;
  - Bottom espelhado, com a caixa começando em (0,0);
  - furos agrupados e ajustados à broca;
  - recorte a R da placa (±res);
  - pontes subindo para a altura certa;
  - aviso de folga em duas trilhas próximas.
- [ ] Commit: "RouterPCB: nucleo (importacao, isolacao, furacao, recorte)".

## Fase 2: nivelamento e G-code (≈ 1 h 30)

- [ ] `routerpcb_heightmap.pas`:
  - grade;
  - `ProbeProgram`;
  - `LoadProbeLog` (`[PRB:x,y,z:1]`, ignora o resto do log);
  - `LoadCSV`;
  - `Bilinear`;
  - `CompensatePaths` (subdivisão + limite).
- [ ] `routerpcb_gcode.pas`:
  - emissor único com cabeçalho;
  - `Programs` na ordem `0_sondagem`, `1_isolacao`, `2_furos_T<n>_<d>mm`, `3_recorte`;
  - opção de arquivo único com M0;
  - estimativa de tempo.
- [ ] `tests/test_routerpcb.lpr`, segunda parte, cobrindo:
  - bilinear exata num plano inclinado;
  - fora da grade dá erro;
  - correção acima do limite dá erro;
  - segmentos subdivididos ≤ MaxSegment;
  - leitura de log real do GRBL;
  - G-code só com os códigos permitidos, sem vírgula decimal e com linhas ≤ 127;
  - primeira linha com o cabeçalho;
  - parâmetro inválido não grava arquivo.
- [ ] Rodar o G-code no SimuCNC (router) ou no analisador `multicnc_gcode_analyzer`.
- [ ] Commit: "RouterPCB: nivelamento por sondagem e G-code".

## Fase 3: interface (≈ 2 h)

- [ ] `routerpcb_preview.pas`:
  - placa e cobre (Top vermelho, Bottom verde, como no LaserPCB);
  - isolação, furos com cor por broca, recorte e pontes;
  - mapa de altura em cores;
  - réguas em mm, zoom/pan e "ajustar".
- [ ] `routerpcb_main.pas` com 6 etapas:
  1. **Importar**;
  2. **Isolação**;
  3. **Furação**;
  4. **Recorte**;
  5. **Nivelamento**;
  6. **Saída**.

  No rodapé: Validar, Gerar G-code (escolhe a pasta) e Abrir no MultiCNC.
  O rodapé mostra o status e o badge de estado.
- [ ] Linha de comando: `routerpcb.exe <pasta_gerber>` abre a pasta direto (para o MakePCB
      e o launcher).
- [ ] `routerpcb.lpi`, `.lpr`, `.manifest`, `.ico` (novo ícone: placa + fresa) e `.res`.
- [ ] `tests/test_routerpcb_ui.lpr`: abre o fixture, gera tudo, valida e exporta para uma
      pasta temporária. Rodar no Linux (GTK2, Xvfb) e no Win64 (Wine).
- [ ] Capturas de tela para `imgs/Routerpcb01..04.png`.
- [ ] Commit: "RouterPCB: interface no padrao da suite".

## Fase 4: integração na suíte (≈ 1 h)

- [ ] `multisuite/src/core/multisuite_types.pas`: acrescentar `stiRouterPCB` **no fim** do enum,
      porque o `.msuite` grava ordinais.
- [ ] `multisuite_registry.pas`: `Add(stiRouterPCB,'RouterPCB','Fresagem de PCB na CNC Router','routerpcb','routerpcb/src/app/routerpcb.lpi')`.
- [ ] `multisuite/tests/test_registry.lpr`: Count = 11 e `Find(stiRouterPCB)`.
- [ ] `multisuite_icons.pas`: `sikRouterPCB` no fim do enum (ord 64) e desenho de placa + fresa.
- [ ] Bandeja (`multisuite_tray_form.pas`):
  - `ToolIcon` → `sikRouterPCB`;
  - `ToolAccent`, por exemplo `C(217,119,6)`;
  - `AddGroup('PREPARAR', [stiMultiCAM, stiRouterPCB, stiMultiSlicer])`.
- [ ] `multisuite/src/app/multisuite_main.pas` (linha ~388): incluir na categoria certa.
- [ ] `multisuite/src/testing/multisuite_test_catalog.pas`: os dois testes do RouterPCB.
- [ ] `.github/workflows/routerpcb-ci.yml`, copiado do `makepcb-ci.yml`.
- [ ] Commit: "Suite: RouterPCB no registro, bandeja, catalogo de testes e CI".

## Fase 5: ligações com MakePCB e MultiCNC (≈ 45 min)

- [ ] MakePCB: botão "Abrir no RouterPCB" no rodapé e na etapa 5, ao lado do "Abrir no
      LaserPCB". Exporta a pasta e chama `TSuiteLauncher.LaunchArtifact(stiRouterPCB, ...)`.
- [ ] MultiCNC (`src/app/mainform.pas`, `OpenProgramFile`): reconhecer
      `; RouterPCB -> MultiCNC (CNC Router)` como `soRouter`, com mensagem própria no log.
      Para recompilar o `multicnc.exe` é preciso a biblioteca CHATGPT
      (`D:\projetos\maurinsoft\CHATGPT`). Até lá vale a linha de compatibilidade
      `; LaserPCB -> MultiCNC (CNC Router)` no cabeçalho.
- [ ] Opcional: no MultiCNC, um botão "Salvar sondagem" que grava só as linhas `[PRB:...]`.
- [ ] Commit.

## Fase 6: entrega (≈ 1 h)

- [ ] Win64: `bin/routerpcb.exe`, mais `makepcb.exe` e `multisuite_tray.exe` recompilados.
- [ ] Instalador 0.03:
  - `installer/windows/multisuite.iss` com o componente `tools\routerpcb`, o arquivo e o
    atalho;
  - `build_release.bat` e `installer/linux/build_release.sh` compilando o RouterPCB;
  - `setup_multcnc_003.exe` em `bin/`.
- [ ] Documentação:
  - em `README.md`, trocar "planejado" por "disponível" e incluir as capturas;
  - `README_*` (8 idiomas), `docs/AI_TOOLS_GUIDE.md`, `docs/PENDENCIAS.md`;
  - `multisuite/README.md`, `multisuite/docs/AI_GUIDE.md` e `multisuite/docs/TESTING.md`;
  - `makepcb/README.md`, `installer/windows/README.md`.
- [ ] Push e sincronização com `D:\projetos\maurinsoft\multicnc`: `bin\`, `imgs\`, docs.
- [ ] Teste na máquina real (Marcelo):
  1. sondagem;
  2. isolação numa placa de fenolite;
  3. furação;
  4. recorte com pontes.

  Anotar os parâmetros que funcionaram em `routerpcb/docs/PARAMETROS.md`.

---

## Critério de pronto

1. Exportar o exemplo 555 no MakePCB, clicar em "Abrir no RouterPCB", Validar e Gerar G-code
   produz 4 a 6 arquivos sem erro.
2. Os programas abrem no MultiCNC já em CNC Router e rodam no SimuCNC sem `error:`.
3. A isolação não toca o cobre: teste automatizado com tolerância de 1 pixel.
4. Testes `test_routerpcb` e `test_routerpcb_ui` passam no Linux e no Win64.
5. O RouterPCB aparece no MultiSuite, na bandeja e no instalador 0.03.

## Riscos e pontos em aberto

- **Folga do MakePCB:** o padrão é 0,4 mm. Com fresa V de 0,143 mm cabe, mas
  com várias passadas as ilhas podem se unir. A verificação de folga precisa apontar o local.
- **Sondagem:** depende do log do MultiCNC trazer as linhas `[PRB:...]`. Conferir se o
  console grava as respostas do GRBL sem filtrar. Se não gravar, a fase 5 inclui o botão
  "Salvar sondagem".
- **Dupla face:** fica fora desta tarefa. Pinos de registro existem no LaserPCB
  (`LPRegistrationHoles`) e podem ser reaproveitados depois.
- **Resolução raster:** 0,02 mm numa placa de 100×80 mm dá 20 milhões de pixels,
  acima do limite de 16 milhões do `TLPMask`. Usar 0,025 mm ou ajustar a resolução ao
  tamanho da placa automaticamente, e avisar o usuário.
