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
Ferramentas sao executaveis independentes. O launcher envia --project <diretorio> e --file <arquivo absoluto>, preservando argumentos com espacos. Procura executaveis lado a lado na instalacao e no diretorio do .lpi em desenvolvimento. Um artefato ausente deve ser recusado antes de executar a ferramenta.

## Ferramentas registradas
MultiCAD, MultiPCB, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt e MultiCNC.

## Persistencia
TWorkspace e dono de .msuite. O formato 2 usa caminhos relativos para arquivos internos e separadores portaveis; metadados escapam %, | e quebras de linha. Load valida enums e publica o estado somente depois de validar todo o documento. Arquivos legados continuam legiveis. Nao renumere enums de artefatos/ferramentas. Novos tipos de artefato ficam no fim.

O workflow e manual: lancar uma ferramenta nao marca um processo como concluido. Projetos, historico e relatorios nao devem ser gravados na pasta de instalacao. O catalogo da Central deve acompanhar os testes de console incluidos pelos instaladores.

## Seguranca
MultiSuite nunca envia diretamente movimento ou acionamento fisico. Execucao real continua exclusiva do MultiCNC.
