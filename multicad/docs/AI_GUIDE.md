# MultiCAD - Guia para IA

## Missao
MultiCAD e o autor CAD da suite. Seu objetivo e criar e editar a geometria que representa pecas mecanicas. A direcao funcional e um CAD parametrico simplificado, semelhante conceitualmente a ferramentas como SolidWorks, sem tentar duplicar CAM ou controle de maquina.

## Estado (10/10/2026)
Em implementacao: decisoes D1 a D10 aprovadas, fases 0 (base, Ids, JSON, unidades,
materiais, malha rotulada, ICadKernel), 1 (esboco com solver, graus de liberdade e perfis),
2 (extrusao, corte, revolucao, planos, booleanas, reconstrucao) e 3 (vista 3D por software,
arvore, PropertyManager, modo esboco) e 4 (STL/DXF, medir, Abrir no MultiSlicer) concluidas;
e 5A (cotas em mm, digitar medidas, grade, inferencia, arcos, filete/chanfro de esboco,
mouse do SolidWorks) concluidas; 459 checks no nucleo + teste de interface. Proxima: 5B
(furo, padroes, espelho); pendencias da vista na 3E. Limites em TAREFA.md.
O plano completo esta em `TAREFA.md` (fases 0 a 8) e o projeto tecnico em `ARCHITECTURE.md` (modelo `.mcad`, solver
Newton/LM, nucleo em malha rotulada + CSG BSP atras de `ICadKernel`, OpenGL, exportacao).
Referencia de fluxo: SolidWorks 2014 (sketch com restricoes e cotas, arvore de operacoes,
reconstrucao), sem copiar.

## O que pertence aqui
Documento CAD, features, sketches, extrusoes, transformacoes geometricas, viewport e futuras operacoes de modelagem.

## Fontes atuais
- src/core/multicad_types.pas: vetores, matrizes, referenciais dos planos (Y para cima), UTF-8.
- src/core/multicad_units.pas: unidades e expressoes nas cotas (CadEval, CadFmt).
- src/core/multicad_materials.pas: biblioteca de materiais e massa.
- src/core/multicad_feature.pas: base das operacoes (Id persistente, estado, registro de tipos).
- src/core/multicad_document.pas: documento, arquivo .mcad, dependencias, retrocesso.
- src/features/multicad_refgeom.pas: origem, planos e eixos de referencia.
- src/features/multicad_extrude.pas: parametros de Ressalto/Base e Corte extrudado.
- src/sketch/multicad_sketch.pas: entidades com Id, restricoes e cotas, ranhura, poligono.
- src/sketch/multicad_solver.pas: solver (CadSolveSketch), graus de liberdade, estados.
- src/sketch/multicad_profile.pas: lacos fechados, regioes com ilhas (CadSketchProfiles).
- src/kernel/multicad_kernel.pas: interface ICadKernel e nucleo Pascal.
- src/kernel/multicad_mesh.pas: malha com faces rotuladas, solda, malha fechada, volume.
- src/kernel/multicad_triangulate.pas: poligono com furos -> triangulos.
- src/kernel/multicad_sweep.pas: extrusao (inclinacao) e revolucao com faces rotuladas.
- src/kernel/multicad_csg.pas: booleanas BSP + fusao de faces planas + reparo de juncoes T.
- src/features/multicad_revolve.pas: parametros da revolucao.
- src/features/multicad_bridge.pas: perfis do esboco -> regioes de varredura.
- src/features/multicad_rebuild.pas: TCadRebuilder (arvore -> corpos, referencias, cache).
- src/features/multicad_export.pas: STL (orientacao Y->Z / face na mesa) e DXF R12.
- src/features/multicad_measure.pas: Medir (area, diametro, distancias, angulos).
- src/sketch/multicad_sketchtools.pas: ferramentas do modo esboco sem LCL (cliques -> entidades,
  captura, inferencia, grade, H/V automaticas, cota inteligente e desenho das cotas, medida
  digitada, arcos, filete/chanfro com canto virtual, relacoes, construcao, apagar).
- src/ui/multicad_camera.pas: camera (vistas padrao, Normal a, orbitar, zoom no cursor, raio).
- src/ui/multicad_softrender.pas: z-buffer por software, 5 estilos, arestas, Id por pixel, secao.
- src/ui/multicad_view3d.pas: controle TCadView3D (mouse, teclado, cubo, triade, planos, esbocos).
- src/ui/multicad_sketchedit.pas: liga a sessao de esboco a vista (desenho, cotas na tela).
- src/ui/multicad_depthdrag.pas: projecao e conversao pixels/mm da alca de profundidade, sem LCL; perspectiva e alternativa para vista normal.
- src/ui/multicad_extrudeedit.pas: arraste da profundidade na vista, integrado ao PropertyManager e ao ciclo de OK/Cancelar.
- src/ui/multicad_propman.pas: PropertyManager (extrusao, corte, revolucao, plano).
- src/app/multicad_main.pas: janela principal (abas, arvore, PropertyManager, arquivo).
- tests/test_multicad.lpr: testes do nucleo (sem LCL).
- tests/test_multicad_ui.lpr: teste da janela (Xvfb/Wine), grava capturas e o exemplo.
- examples/suporte.mcad: peca de exemplo.

## Entradas e saidas
Entrada: comandos de modelagem e, futuramente, formatos CAD/mesh suportados.
Saida: geometria/pecas reutilizaveis pelo MultiAssembly e MultiCAM; STL para MultiSlicer,
DXF (sketch ou face plana) para MakeRouter e LaserArt, propriedades de massa para
MultiPhysics (decisao D8).

## Nao pertence aqui
G-code, comunicacao serial, GRBL/Marlin, STEP/DIR, controle de spindle, PCB, slicing ou execucao fisica.

## Integracao
MultiAssembly referencia as pecas CAD na montagem. MultiCAM consome geometria para criar operacoes de usinagem.

## Regras para alteracao
Mantenha geometria independente da UI (camera, renderizador e ferramentas de esboco nao usam
LCL e tem testes no test_multicad). Nao acople o documento CAD a uma maquina fisica. Preserve compatibilidade de dados e crie testes para operacoes geometricas.
- Ids persistentes no arquivo (nunca endereco de objeto) e referencias a faces/arestas por
  nome estavel (`Extrude2/topo`).
- O nucleo geometrico so e acessado por `ICadKernel`.
- Toda booleana deixa a malha fechada; teste com volume analitico.
- Corte extrudado entra na peca por padrao (contra a normal do esboco), como no SolidWorks.
- Referencias por texto: plane:<id>, face:<nome>, axis:<id>, sketch:<id>/<entidade>[.<ponto>],
  body:<nome>, origin.
- Programas: `Application.CreateForm` no `.lpr` (regra 12 de `docs/AI_TOOLS_GUIDE.md`).

## Edicao de profundidade na vista
A alca usa TCadRebuilder.ExtrudeHandle, resolvendo as referencias nos corpos anteriores a operacao. TCadPropManager.SetExtrudeDepth atualiza o valor e o campo sem reler outros controles, e dispara a reconstrucao existente. Nunca derive a profundidade do tamanho da caixa do solido ou altere a malha diretamente. Esc cancela primeiro o gesto em curso; OK/Cancelar continuam operando sobre a mesma fotografia dos parametros. Condicoes automaticas nao exibem alca de profundidade. Testes: test_extrude_ui e TestExtrudeHandles em test_multicad.


## Diagnostico e selecao de esbocos (11/10/2026)
- Ao sair de um esboco, a arvore e a vista 3D selecionam o esboco finalizado.
  Extrusao/corte respeita uma selecao explicita antes do ultimo esboco lembrado;
  abrir ou criar outra peca limpa esse historico de selecao.
- O executavel 0.3.1.0 cria/acrescenta `%LOCALAPPDATA%\Maurinsoft\MultiCAD\multicad.log`
  antes de criar a janela. Cada sessao tem data/hora e PID; cada registro e fechado
  imediatamente. O historico nao e apagado ao abrir novamente.
- Registra comandos, selecoes, parametros, alteracoes de esboco, arraste de profundidade,
  OK/Cancelar, reconstrucao/cache, estados de erro/aviso, arquivos, entradas invalidas,
  dialogos e excecoes (classe, mensagem, endereco e pilha quando disponivel).
  Falhas de gravacao do proprio log nao interrompem o CAD; ficam disponiveis em Sobre.
- O CommandManager segue a referencia SolidWorks 2014: icones acima dos textos,
  grupos separados e abas retangulares abaixo dos comandos, mantendo a paleta MultiSuite.
  Menus classicos Arquivo/Editar/Exibir/Inserir/Ferramentas/Sobre usam os mesmos comandos.
- A aba **Sobre** acompanha o CommandManager.
  **Sobre o MultiCAD** mostra a versao lida do recurso do executavel, compilacao e
  caminhos; **Abrir log** abre o arquivo no visualizador associado do Windows.
- A janela principal usa `Application.CreateForm`, para fechar o processo com a janela.
- `tests/test_log.lpi`: criacao, preservacao de sessoes, erros/excecoes, caminhos sem permissao.
- `tests/test_selection_ui.lpi`: regressao da selecao antiga, prioridade de selecao explicita,
  esboco ativo, comando bloqueado, aba Sobre, informacoes de versao e diagnostico.


## Visibilidade do perfil e clique nos comandos (0.3.2.0)
- O esboco da extrusao/corte/revolucao em edicao permanece visivel, mesmo consumido,
  ocultado manualmente ou atras/dentro do solido. A visibilidade temporaria termina
  no OK/Cancelar; a preferencia de ocultacao do usuario e preservada.
- Um esboco selecionado e desenhado sobre o solido, permitindo reconhecer o contorno
  antes de iniciar a operacao. A geometria e a direcao da extrusao nao sao alteradas.
- ShowTab oculta os controles antigos e usa Application.ReleaseComponent: nao libera
  o botao ainda em uso por WMLButtonUp. Regressao reproduzida com mensagens nativas
  de pressionar/soltar, incluindo troca de ferramenta e corte direto do modo esboco.
- O log continua escrito e fechado a cada registro; nao forca FlushFileBuffers em
  cada linha no Windows, evitando pausas perceptiveis durante cliques/reconstrucoes.
- Teste: tests/test_sketch_visibility_ui.lpi (perfil sobre solido, visibilidade
  temporaria, esboco selecionado e ciclo real de clique).

## Aviso de operacao com erro (0.3.3.0)
- PMOK atualiza os caches da vista imediatamente depois de RB.Rebuild e antes
  de abrir o dialogo de confirmacao. A reconstrucao substitui as malhas; o
  dialogo processa eventos de pintura e nao pode usar os enderecos anteriores.
- Responder Nao mantem a edicao aberta; Sim aceita a feature marcada com erro.
  Cancelar restaura os parametros. Nenhum desses caminhos usa malhas liberadas.
- Teste: tests/test_cut_failure_ui.lpi, com pintura durante o dialogo,
  respostas Nao/Sim, restauracao e correcao posterior. Excecoes da aplicacao
  fazem o teste falhar, inclusive antes do retorno do dialogo.
- Esta correcao nao altera o algoritmo BSP: o caso de furos cilindricos cruzados
  registrado em 11/10/2026 ainda pode falhar na booleana. A ultima geometria
  valida continua disponivel para corrigir os parametros ou cancelar a edicao.

## Cancelar edicao de planos e eixos (0.3.4.0)
- LoadParams invalida o referencial calculado do plano e a geometria do eixo,
  mesmo quando Cancelar restaura parametros identicos. O cache da reconstrucao
  guarda corpos, nao esses dados derivados: so e reutilizado se FrameValid/Valid
  tambem estiver valido. Caso contrario, recalcula a referencia e seus dependentes.
- Isso evita plano marcado como correto, mas recusado ao iniciar um esboco ou
  criar um plano deslocado. Referencias realmente perdidas continuam gerando erro.
- Testes: TestReferenceCacheRestoration no nucleo e test_plane_cancel_ui.lpi,
  cobrindo Cancelar sem/com alteracoes, plano dependente, novo esboco e reabrir.

## Cota inteligente e referencias entre esbocos (0.3.5.0)
- Durante a colocacao de uma cota de reta ou entre pontos, a posicao do cursor
  escolhe a direcao: acima/abaixo entre as coordenadas X = horizontal; ao lado
  entre as coordenadas Y = vertical; fora dos dois intervalos = comprimento real.
  Retas horizontais/verticais conservam seu eixo valido. A previa muda antes do
  clique final; o texto da previa nao intercepta esse clique. Cotas ja colocadas
  continuam conservando seu tipo quando o texto e arrastado.
- Na ferramenta de cota, extremidades, pontos medios de retas e centros de
  esbocos anteriores visiveis podem servir para posicionar o esboco ativo.
  As referencias sao projetadas no plano ativo e aparecem com a geometria
  anterior tracejada, usando as mesmas cores da interface.
- reference_point guarda sketch:<id>/<entidade>.<ponto> em um ponto de construcao
  local constante no solver. A reconstrucao atualiza sua projecao antes de resolver
  o esboco. O vinculo entra em Dependencies, persiste no .mcad e nao altera a
  geometria fonte. Fonte posterior, suprimida, com erro ou ponto perdido gera
  erro explicito; nao ha reconexao por indice de entidade. Escape remove proxies
  sem restricoes. A selecao de novas referencias ignora esbocos ocultos/futuros.
- Testes: test_smart_dimension (X/Y/alinhada, valor dirigente, projecao em outro
  plano, atualizacao associativa, persistencia, referencia perdida e Escape) e
  test_smart_dimension_ui (cliques reais, previa, selecao de outro esboco,
  valor numerico, ocultacao e reabertura). Incluidos na CI Linux/Windows.

## Painel contextual do esboco (0.3.6.0)
- O painel mostra a ferramenta ativa, selecao e orientacao correspondente.
  Cota, Filete e Chanfro ocultam o seletor de tipo de linha. Selecionar mostra
  esse controle somente com geometria editavel selecionada; ferramentas de
  desenho mantem a escolha normal/apoio, com termos de geometria para curvas.
- UpdateSketchPanel sincroniza os botoes existentes com Session.Tool, inclusive
  ao voltar a Selecionar por Esc, sem reconstruir os comandos durante o evento.
- Textos usam a largura disponivel; a orientacao ocupa a area liberada pelo
  seletor oculto. Mantidos paleta, dimensoes do painel e posicao da arvore.
- test_smart_dimension_ui cobre troca pelos botoes, Esc, selecao de linha,
  Filete/Chanfro/Circulo e retorno a Linha, alem dos testes existentes de cotas.
