# MultiSuite

Gestor visual e ponto de entrada da suite MultiCNC.

## Missao

O **MultiSuite** organiza o ecossistema MultiCNC por objetivo do usuario. Ele nao substitui as ferramentas especializadas: apresenta o fluxo de trabalho, mantem o contexto do projeto e abre a aplicacao adequada para cada etapa.

A ideia central da interface e simples:

```text
IDEIA -> PROJETO -> SIMULACAO -> PREPARACAO -> VALIDACAO -> FABRICACAO
```

## Nova interface com menu lateral

A tela principal foi reorganizada como um hub visual. O menu lateral permanece disponivel durante toda a navegacao e separa as funcoes por finalidade:

- **Visao geral:** apresenta a proposta da suite, fluxo de fabricacao e atalhos.
- **Projeto atual:** mostra artefatos e o estado das etapas do workspace.
- **Projetar:** MultiCAD, MultiPCB, LaserPCB e LaserArt.
- **Preparar:** MultiCAM e MultiSlicer.
- **Simular:** MultiPhysics e MultiAssembly.
- **Fabricar:** MultiCNC.
- **Ferramentas:** acesso direto a todos os modulos e a Central de Testes.
- **Configuracoes:** informacoes e futura centralizacao de preferencias, idioma, caminhos e integracoes.

A area central utiliza cartoes para apresentar cada aplicacao com nome, finalidade e botao de abertura. O objetivo e que o usuario escolha **o que deseja fazer**, sem precisar conhecer previamente a estrutura interna do repositorio.

## Visao geral

A pagina inicial apresenta:

- identidade do MultiCNC Suite;
- fluxo completo da ideia a fabricacao;
- acesso rapido ao MultiCNC;
- criacao do projeto demonstracao;
- acesso a Central de Testes;
- cartoes de todas as aplicacoes registradas.

## Projeto atual

O workspace continua independente das aplicacoes especializadas. A pagina **Projeto atual** mostra:

- nome e diretorio do projeto;
- arvore de artefatos;
- ferramenta proprietaria de cada artefato;
- estado das etapas do workflow;
- abertura contextual do artefato por duplo clique.

O formato `.msuite` persiste o contexto global sem substituir os formatos de cada modulo.

## Aplicacoes

- **MultiCAD:** CAD mecanico.
- **MultiPCB:** esquematico e PCB.
- **MultiAssembly:** montagem eletromecanica.
- **MultiPhysics:** simulacao fisica multidominio.
- **MultiCAM:** CAM e simulacao CNC Router.
- **MultiSlicer:** fatiamento para impressao 3D.
- **LaserPCB:** preparacao de PCB para laser.
- **LaserArt:** imagem, vetor e arte para laser.
- **MultiCNC:** controle e execucao da maquina fisica.

## Regra de arquitetura

**MultiSuite orquestra.** A logica de CAD, EDA, CAM, slicing, laser, assembly, simulacao e controle permanece em seus respectivos modulos.

O registro central descreve as ferramentas, o workspace representa o projeto global e o launcher inicia executaveis independentes repassando o contexto quando disponivel.

## Abertura contextual

Os artefatos da arvore possuem uma ferramenta proprietaria. O duplo clique resolve essa ferramenta no registro e inicia o executavel com:

```text
--project <diretorio-do-workspace> --file <artefato>
```

O modulo `multisuite_context.pas` define o parser comum desses argumentos. Cada aplicacao especializada deve incorporar esse contrato ao seu fluxo de inicializacao.

Enquanto um formato ainda nao possuir loader, a aplicacao deve preservar o contexto recebido e informar que a abertura daquele formato ainda nao esta implementada; nunca deve fingir que carregou o documento.
