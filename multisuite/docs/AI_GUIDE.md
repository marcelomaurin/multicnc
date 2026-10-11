# MultiSuite - Guia para IA

## Papel
MultiSuite Bandeja e um menu simples de aplicativos. No Windows, somente multisuite_tray.exe e distribuido como lancador.

## Pode fazer
A bandeja apenas lista e abre aplicativos. Nao adicionar painel central, busca ou configuracoes ao menu. O nucleo de workspace permanece para compatibilidade dos projetos legados.

## Nao pode fazer
Nao implementar internamente CAD, PCB, CAM, slicing, Laser, montagem ou controle CNC. Deve delegar.

## Registro
multisuite_registry.pas e a fonte central das ferramentas disponiveis.

## Projeto global
O projeto deve fornecer contexto compartilhado sem forcar todos os modulos a usar o mesmo formato interno. Cada ferramenta continua dona de seus documentos especializados.

## Launcher
Ferramentas sao executaveis independentes. O launcher envia --project <diretorio> e --file <arquivo absoluto>, preservando argumentos com espacos. Procura executaveis lado a lado na instalacao e no diretorio do .lpi em desenvolvimento. Um artefato ausente deve ser recusado antes de executar a ferramenta.

## Ferramentas registradas
MultiCAD, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt, MultiCNC e MakePCB.
O registro tem 12 ferramentas, incluindo RouterPCB, MakeRouter e SimuCNC. A bandeja lista os aplicativos em um menu simples.

Novas ferramentas entram no FIM de `TSuiteToolID` (`multisuite_types.pas`): o workspace `.msuite` grava o ordinal.
Na bandeja, o menu e construido do registro e inclui somente aplicativos com executavel disponivel.
MultiCAD, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt e MultiCNC.

## Persistencia
TWorkspace e dono de .msuite. O formato 2 usa caminhos relativos para arquivos internos e separadores portaveis; metadados escapam %, | e quebras de linha. Load valida enums e publica o estado somente depois de validar todo o documento. Arquivos legados continuam legiveis. Nao renumere enums de artefatos/ferramentas. Novos tipos de artefato ficam no fim.

O workflow e manual: lancar uma ferramenta nao marca um processo como concluido. Projetos, historico e relatorios nao devem ser gravados na pasta de instalacao. O catalogo da Central deve acompanhar os testes de console incluidos pelos instaladores.

## Seguranca
MultiSuite nunca envia diretamente movimento ou acionamento fisico. Execucao real continua exclusiva do MultiCNC.
