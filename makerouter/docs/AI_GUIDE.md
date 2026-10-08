# MakeRouter - Guia para IA

## Finalidade
Projeto e usinagem de pecas de madeira (e acrilico/MDF/compensado) na CNC Router: desenho
2D, relevo (mapa de alturas), percursos (perfil, bolsao, furacao, gravacao, V-Carve, 3D),
simulacao e G-code para o MultiCNC.

Estado: em analise. So existe a tela provisoria `src/app/makerouter_main.pas` (etapas
descritivas, botoes desabilitados) registrada na suite como `stiMakeRouter`. Leia `TAREFA.md`
(decisoes D1-D6) antes de comecar; a interface real substitui a provisoria na fase 4.

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
