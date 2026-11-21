# MultiProject - Guia para IA

## Missao
MultiProject e o planejador da suite. A partir de um objetivo (ex.: construir um motor),
organiza tarefas de peca, eletronica, montagem, validacao, fabricacao e teste em um grafo de
dependencias, calcula o cronograma e liga cada tarefa ao arquivo da ferramenta que a executa.
Referencia funcional: Microsoft Project. Requisitos em `REQUISITOS.md` (IDs `PJ-*`).

## Antes de editar
1. Leia `TAREFA.md` (decisoes D1..D12 e a fase atual) e `ARCHITECTURE.md`.
2. Confira em `REQUISITOS.md` o ID e a prioridade do que vai implementar.
3. Leia o `AI_GUIDE.md` da outra ferramenta antes de mexer na integracao com ela.

## Regras
1. Nucleo (`src/core`, `src/io`, `src/integration`, `src/ai`) sem LCL e com teste de console.
2. O `.mproj` e a unica fonte do plano. Arquivos das outras ferramentas sao referenciados por
   caminho relativo e hash; nunca copie nem altere o conteudo deles.
3. Tipo de tarefa -> ferramenta/extensao/pasta/verificador so em `multiproject_kinds`.
   Novos valores de enum entram no fim.
4. O grafo e sempre aciclico. Recuse o vinculo que fecha ciclo; reprovacao gera tarefa de
   revisao nova, nunca aresta de volta.
5. Regras de geracao e IA so produzem tarefas `suggested`. Nao aplique, nao apague e nao altere
   tarefa concluida sem acao do usuario. Aceitar uma proposta e um unico passo de desfazer.
6. MultiProject nunca executa maquina. Fabricacao abre o MultiCNC com `--file`; posicionamento,
   Frame e execucao ficam no MultiCNC (regras 2 e 3 do guia da suite).
7. Maquinas vem de `multicnc.json` em somente leitura (`multicnc_equipment`).
8. Datas calculadas, EAP e margens nao sao gravados; recalcule ao abrir.
9. Numeros com ponto decimal e datas ISO no arquivo (`multisuite_numfmt`).
10. Verificador sem informacao suficiente responde "nao verificado", nunca "aprovado".
11. Tela no padrao da suite (`LAYOUT.md`): `TSuiteHeader`, lateral 214 px, painel 336 px,
    rodape 66 px, `TSuiteButton`, cores `clSuite*`, janela criada com `Application.CreateForm`.
12. Use primeiro o que existe na suite CHATGPT. Funcionalidade generica (grafo, calendario,
    cronograma, duracao, desfazer, JSON, contrato de plano da IA) vira componente em
    `CHATGPT/pacote/AI Project Core` (somente FCL, com teste), e o MultiProject so adapta.
    Depois sincronize a copia `third_party/chatgpt/AIProjectCore`.
13. Nao declare fase concluida sem compilar e rodar os testes no Linux e no Win64; registre o
    progresso em `TAREFA.md`.

## Nao pertence aqui
Modelar peca, desenhar placa, montar, simular, gerar toolpath, fatiar ou enviar G-code.
Essas tarefas pertencem a MultiCAD, MakePCB, MultiAssembly, MultiPhysics, MultiCAM/MakeRouter,
MultiSlicer, LaserArt/LaserPCB/RouterPCB e MultiCNC.
