# LaserArt - Guia para IA

## Finalidade
Conteudo grafico geral para laser: imagens, logos, textos, arte vetorial e raster, materiais, teste de material e construcao do trabalho/G-code.

## Estrutura
- src/core/laserart_model.pas: camadas, objetos, documento `.lart` (JSON).
- src/core/laserart_geom.pas: contornos, preenchimento, simplificacao, ordenacao.
- src/core/laserart_imaging.pas: imagem, dithering, texto -> contornos, vetorizacao.
- src/core/laserart_svgimport.pas: importador SVG.
- src/core/laserart_output.pas: BuildJob + JobToGCode.
- src/core/laserart_materials.pas: biblioteca de materiais.
- src/core/laserart_calibration.pas: matriz do teste de material.
- src/ui/: editor e widgets.
- src/app/: tela principal e dialogo do teste de material.

## Regras
- Nao abrir porta serial nem controlar a maquina (isso e do MultiCNC).
- Camadas novas com velocidade/potencia zeradas; bloquear G-code sem calibracao.
- Nunca ligar o laser automaticamente. Biblioteca de materiais comeca vazia.
- G-code com cabecalho `; LaserArt` (o MultiCNC usa isso para abrir em CNC Laser), ponto decimal invariante e linhas < 127 caracteres.

## Limite com o LaserPCB
Fabricacao de PCB e no LaserPCB (`laserpcb/`). Arte geral e no LaserArt.

## Integracao
LaserArt prepara o job -> MultiCNC executa (abre o arquivo via `--file`).

## Documentação e regressão de saída

- Referência atual: LaserArt 0.02.1; versão do arquivo Windows 0.2.0.1.
- [Manual ilustrado do usuário em português](../../docs/Manuals/Manual_do_Usuario_LaserArt_0.02.1_PT-BR.pdf).
- [Catálogo das capturas atuais](../../imgs/manual_laserart_0_02_1/README.md); os recortes do PDF vêm destas telas completas.
- `test_laserart_output`: 29 verificações. O preenchimento deve funcionar com overflow/invalid desmascarados; a primeira aproximação é G0 com S zero. Não reintroduzir MaxDouble como ponto anterior do preenchimento.
- Testes de matriz e de Mesa também aprovados no Windows em 12/10/2026.
