# MultiSuite - Guia para IA

## Papel
MultiSuite e o gestor/orquestrador da suite. Deve ser a primeira interface vista pelo usuario.

## Pode fazer
Criar/abrir projeto global, mostrar ferramentas, abrir ferramentas, acompanhar artefatos do projeto, centralizar configuracoes comuns e futuramente registrar estado/workflow.

## Nao pode fazer
Nao implementar internamente CAD, PCB, CAM, slicing, Laser, montagem ou controle CNC. Deve delegar.

## Registro
multisuite_registry.pas e a fonte central das ferramentas disponiveis.

## Projeto global
O projeto deve fornecer contexto compartilhado sem forcar todos os modulos a usar o mesmo formato interno. Cada ferramenta continua dona de seus documentos especializados.

## Launcher
Ferramentas sao executaveis independentes. O launcher pode enviar --project <diretorio>. Cada aplicacao deve futuramente aceitar esse argumento.

## Ferramentas registradas
MultiCAD, MultiPCB, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt, MultiCNC e MakePCB.
RouterPCB (`stiRouterPCB`) e MakeRouter (`stiMakeRouter`, ultimo do enum, tela provisoria; o registro tem 12 ferramentas) fica na secao/grupo Preparar, ao lado do MultiCAM. Novas ferramentas sempre no FIM de `TSuiteToolID` e de `TSuiteIconKind` (o `.msuite` e caches gravam ordinais).

Novas ferramentas entram no FIM de `TSuiteToolID` (`multisuite_types.pas`): o workspace `.msuite` grava o ordinal.
Na bandeja (`multisuite_tray_form.pas`) cada ferramenta precisa de icone (`ToolIcon`), cor (`ToolAccent`) e grupo (`AddGroup`).

## Seguranca
MultiSuite nunca envia diretamente movimento ou acionamento fisico. Execucao real continua exclusiva do MultiCNC.
