# MakeRouter - Guia para IA

## Finalidade
Projeto e usinagem de pecas de madeira (e acrilico/MDF/compensado) na CNC Router: desenho
2D, relevo (mapa de alturas), percursos (perfil, bolsao, furacao, gravacao, V-Carve, 3D),
simulacao e G-code para o MultiCNC.

Estado: primeira versao 2,5D (08/10/2026). Faltam V-Carve (fase 5), relevo 3D (fase 6) e
importacao DXF/SVG. Andamento em `TAREFA.md`.

## Unidades (como implementado)
- src/core/makerouter_types: material, 9 pontos de zero, ferramentas, padroes, validacao.
- src/core/makerouter_project: formas parametricas (TMRShape), percursos (TMRToolpath),
  projeto, zero virtual (DatumPoint/ToOutput), JSON `.mrouter`, exemplo.
- src/geom/makerouter_clip: ponte com a Clipper2 (`src/shared/clipper2`).
- src/cam/makerouter_cam: perfil, bolsao, furacao, gravacao (movimentos no espaco do projeto).
- src/sim/makerouter_sim: material como mapa de alturas e imagem sombreada.
- src/export/makerouter_gcode: programas com o emissor comum `src/shared/multisuite_gcode_writer`.
- src/ui/makerouter_view: vista 2D/simulacao; src/app/makerouter_main: tela (6 etapas).
- tests/test_makerouter (92 checks) e tests/test_makerouter_ui (21 checks).

## Regras
1. Projeto em mm, origem no canto inferior esquerdo do material, Z = 0 no topo do material.
2. Saida sempre relativa ao **zero virtual** (9 pontos XY, Z topo ou mesa). Nunca gere
   coordenadas da maquina (`G53`, `G28` com coordenadas, `G54..G59` fixos, `G92`).
3. Cabecalho conforme `docs/CONTRATO_GCODE.md` (linha 1 `; MakeRouter -> MultiCNC (CNC Router)`
   e linhas `; MS-...`).
4. Vetores sao a fonte da verdade; percursos referenciam vetores por Id e ficam
   "desatualizados" quando eles mudam. Previa, simulacao e exportacao usam os mesmos movimentos.
5. Validar antes de gravar; erro nunca cria ou sobrescreve arquivo.
6. Nao inventar parametros de corte "seguros": padroes sao exemplo e a interface diz isso.
7. Teste para toda logica nova; G-code conferido por `multicnc_safety` e pelo analisador do
   MultiCNC nos testes.

## Reuso (nao duplicar)
Geometria/ordenacao do LaserPCB, campo de distancias para V-Carve, pontes do RouterPCB,
emissor de G-code comum (`src/shared`, decisao D4), SVG do LaserArt, controles e icones da
MultiSuite. Ver `ARCHITECTURE.md`, secao 5.

## Limites
- MakePCB/RouterPCB: placas de circuito. MakeRouter: madeira, letreiros, moveis, entalhe.
- MultiCAM: simulacao da maquina e CAM de pecas mecanicas do MultiCAD (decisao D1).
- MultiCNC: unico dono da maquina, do zero real, do Frame e da execucao.
