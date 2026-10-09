# Conciliacao das branches em fila

Integracao de 2026-10-09. Base: origin/fila c4e743e.

- funcionalidades-suite-2026-10-02 incorpora modernizacao-2026 (b30b22d); a integracao preserva os dois historicos.
- master ja estava contida em fila.
- backup-local-fila (1480387), com historico independente, e preservada integralmente em legacy/prototipo-serial. E um prototipo separado, nao substitui o controlador atual em src/app nem entra no instalador da suite.

## Resolucao dos conflitos

O controlador mantém suas interfaces de confirmacao, estado, temperaturas, homing, limites, parada e framing. GRBL/grblHAL/FluidNC e Marlin oferecem tambem a interface de streaming da modernizacao. A analise modal e a previa usam multicnc_gcode_preflight; multicnc_gcode_analyzer mantém a API de bounds/framing e delega a analise detalhada ao novo nucleo.

A interface atual do MultiCNC recebe uma aba de trajetoria/analise e a opcao Simulador local. Erros de analise bloqueiam o inicio nesse modo. As verificacoes ja existentes de hardware continuam no fluxo de execucao. A simulacao nao e homologacao fisica.

O MultiSuite mantém a navegacao por categorias e incorpora abertura, salvamento, historico, arquivos e atualizacao manual de etapas de projetos. O launcher funciona na arvore de desenvolvimento, em bin e na instalacao.

O CAD atual mantém IDs persistentes, documento, solver e kernel. As APIs anteriores usadas pelo solver LM e pelas exportacoes STL/3MF ficam em multicad/src/compat, com nomes multicad_compat_*, evitando colisao com o kernel atual. test_parametric valida essa compatibilidade e o fluxo ate o fatiador. Os recursos novos nao substituem automaticamente a interface CAD atual.

MultiCAM mantém a exportacao original com numeros invariantes e oferece o pos-processador avancado com arcos. LaserPCB mantém a validacao de potencia/S-max e o exportador original; BuildProgram oferece saida modal validada para os jobs raster. MultiSlicer recebe o fluxo completo de fatiamento e previa. MakePCB, MakeRouter, RouterPCB e bandeja permanecem na suite e no instalador Windows.

## Validacao

Compilacao Win64 com Lazarus/FPC 3.2.2; testes de console, testes graficos sem hardware e ferramentas de release. Os logs da execucao ficam fora do repositorio. tools/verify_suite.py console descobre as dependencias em MULTICNC_CHATGPT_DIR (padrao: ../CHATGPT) e LAZARUS_DIR. O teste test_multicnc_tcp exige SimuCNC local ativo e so entra no lote com --integration; tests/test_simucnc_tcp.py inicia o simulador para o fluxo TCP completo.

A compilacao Linux/ARM e o empacotamento final dependem dos respectivos ambientes de CI. Os executaveis historicos versionados nao foram regenerados por esta integracao.
