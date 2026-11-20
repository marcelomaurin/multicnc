# MultiPhysics 0.2.1: entrega de melhorias

Data: 09/11/2026. Base: `d95aafb`, branch principal `fila`.

## Implementado

- **MP-3.8, escopo 0.2:** STL ASCII e binario, entrada em mm convertida para SI,
  preview de superficie separado do projeto FEM. Volume apenas se cada aresta
  tiver duas faces com orientacao oposta; massa estimada por densidade uniforme.
  Arquivos truncados, triangulos degenerados e coordenadas nao finitas sao recusados.
  Nenhum tetraedro ficticio e criado: FEM volumetrico a partir de STL permanece 0.3.
- **MP-6.7:** abertura `.mphys`, `.massembly` e alias `.massembly`; `--new destino.mphys`
  guarda o destino e so cria arquivo ao salvar. `--project` e `--task` sao preservados
  como contexto no log. Arquivo existente tem precedencia sobre `--new`.
- **Historico:** desfazer/refazer de pecas, materiais, cargas, contatos e configuracoes
  do documento; limite de 100 estados e descarte do ramo refeito apos nova edicao.
  Botoes e Ctrl+Z/Ctrl+Y (editores de texto mantem seu historico local).
  Restaurar invalida resultados antigos; salvar mantem o destino do documento.
- **CalculiX:** FindCCX le `active.txt` somente dentro de `versions`, respeitando
  CALCULIX_EXE e a configuracao manual. A interface detecta, instala/atualiza em
  segundo plano e restaura. A maior versao numerica aprovada no catalogo dispensa
  manifesto manual; sem catalogo aprovado permanece a alternativa explicita.
- **Gerenciador Windows:** HTTPS, SHA256, inspecao de todas as entradas ZIP antes
  da extracao, bloqueio de traversal/symlink/nomes duplicados, limites de tamanho,
  arquivo de licenca e dependencias do manifesto. Lock por diretorio, instalacao
  lado a lado, ponteiros atomicos e preservacao da versao ativa em falha.
  Instalacao e rollback executam um benchmark C3D4 com deslocamento conhecido
  antes de ativar. Logs registram versao, origem, hash, teste e falha.
- **Atualizador MultiSuite:** compara versoes normalizadas (0.19 = 0.19.0.0), prefere
  o asset cujo nome coincide com a versao e oferece `-CheckOnly`, sem download.
  Validacao de hash usa .NET e nao depende do carregamento de Get-FileHash.
- **Publicacao:** um unico workflow Windows para tags numericas de 2 a 4 partes;
  instalador por versao e checksum sao enviados antes de publicar a Release.
  Reexecucoes atualizam assets existentes. Versao padrao do proximo setup: 0.19.
- **Compatibilidade i386:** contador de indices do Cholesky usa SizeInt,
  eliminando o erro de compilacao de Int64 como contador for no FPC 32 bits.

## Verificacao

- 36 testes de console MultiPhysics aprovados em Windows x64 e i386; benchmarks
  FEM existentes preservados. O teste ccx pode ignorar a comparacao externa quando
  o solver real nao existe; isso nao foi contabilizado como homologacao externa.
- `test_document_workflow`: historico, STL fechado/aberto/binario/truncado,
  ausencia de elementos FEM no preview, selecao de catalogo e descoberta gerenciada.
- `test_document_ui`: janela real, `--new`, adicionar peca, salvar, desfazer/refazer,
  salvar estado desfeito, mudanca de malha em SI e reabertura por `--file`.
- 16 testes Windows do gerenciador com ZIPs locais e **executavel sintetico**:
  instalacao, troca, rollback, idempotencia, catalogo aprovado, hash, ZIP malicioso,
  licenca/dependencia ausente, erro/timeout do processo, offline, concorrencia
  e falha ao trocar o ponteiro ativo.
- 5 testes do script PowerShell de atualizacao da suite, com rede e processo
  substituidos por fixtures; nenhum instalador real foi executado nesses testes.
- 10 testes existentes de inspecao ZIP e 7 de consulta de Releases aprovados.
- 13 testes das ferramentas de release, incluindo preservacao de versao de quatro
  partes no manifesto e no include do Inno Setup.
- Build Lazarus Windows x64 e capturas reais de cargas e montagem importada.

Comandos principais:

```powershell
$env:FPC='C:\lazarus\fpc\3.2.2\bin\i386-win32\fpc.exe'
$env:MULTICNC_TEST_FLAGS='-Px86_64 -Twin64'
python tools/verify_suite.py console multiphysics
lazbuild --cpu=x86_64 --os=win64 --ws=win32 multiphysics/tests/test_document_ui.lpi
multiphysics/tests/test_document_ui.exe
python -m unittest discover -s multiphysics/tools -v
python -m unittest discover -s tools -p test_windows_updater.py -v
python -m unittest discover -s tools -p test_check_multicnc_release.py -v
python -m unittest discover -s tests -p test_release_tools.py -v
```

O caminho do compilador depende da instalacao Lazarus. Para i386, usar
`MULTICNC_TEST_FLAGS='-Pi386 -Twin32'` e uma pasta MULTICNC_BUILD separada.

## Pendencias que permanecem abertas

1. Homologacao de ZIPs CalculiX reais: SHA256/proveniencia, licenca, DLLs e
   comparacao com solver real. O catalogo distribuido continua sem entradas approved.
   A tentativa de baixar o ZIP oficial nesta sessao falhou por conexao SSL.
2. Ensaio de atualizacao entre duas Releases publicadas, instalacao UAC e preservacao
   de configuracoes numa instalacao real. Testes com fixtures nao substituem esse ensaio.
3. Verificacao periodica/cancelamento/retomada de downloads do CalculiX e selecao de
   versao aprovada diretamente no Inno Setup. A integracao atual do instalador
   continua opcional e baseada em manifesto selecionado pelo usuario.
4. MakePCB -> contrato unificado, refinamentos de transmissao/inercia, SPICE externo,
   CFD real e FEM sobre STL: evolucoes do roadmap; nao implementadas nesta entrega.
5. Falhas anteriores do CI Linux em outros modulos/dependencias nao foram resolvidas
   por este trabalho. O instalador completo novo depende do build de toda a suite.

Os planos historicos foram conciliados para nao repetir como pendentes os modelos
reduzidos de fim de curso e protecoes que ja estavam implementados.
