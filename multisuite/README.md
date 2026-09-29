# MultiSuite

Gestor unificado da suite MultiCNC.

## Missao
MultiSuite e a porta de entrada do ambiente. Ele nao substitui as ferramentas especializadas: organiza projetos e permite abrir MultiCAD, MultiPCB, MultiAssembly, MultiCAM, MultiSlicer, LaserPCB, LaserArt e MultiCNC.

## Ferramentas
- MultiCAD: CAD mecanico.
- MultiPCB: EDA/PCB.
- MultiAssembly: montagem eletromecanica.
- MultiCAM: CAM CNC Router e simulacao.
- MultiSlicer: impressao 3D.
- LaserPCB: PCB por laser.
- LaserArt: arte geral por laser.
- MultiCNC: controle da maquina fisica.

## Arquitetura
O registro central descreve ferramentas. O gerenciador representa o projeto global. O launcher inicia executaveis independentes e pode repassar o diretorio do projeto com --project.

## Regra
MultiSuite orquestra. A logica de CAD, EDA, CAM, slicing, laser, assembly e controle permanece em seus respectivos modulos.

## Workspace unificado
A interface principal possui arvore de artefatos, lista de ferramentas e acompanhamento do fluxo Projeto -> Eletronica -> Montagem -> Fabricacao -> Simulacao -> Execucao. O formato `.msuite` persiste contexto, artefatos e estado do workflow sem substituir os formatos especializados de cada ferramenta.

## Abertura contextual
Os artefatos da arvore possuem uma ferramenta proprietaria. Duplo clique resolve essa ferramenta no registro e inicia o executavel com:
`--project <diretorio-do-workspace> --file <artefato>`.

O modulo `multisuite_context.pas` define o parser comum desses argumentos. Cada aplicacao especializada deve incorporar esse contrato ao seu fluxo de inicializacao. Enquanto um formato ainda nao possuir loader, a aplicacao deve preservar o contexto recebido e informar que a abertura daquele formato ainda nao esta implementada; nunca deve fingir que carregou o documento.
