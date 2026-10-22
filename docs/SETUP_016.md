# Setup 016 — MultiSuite 0.16

Edição de **22/10/2026**, para **Windows x64**. MultiProject 0.2.0.0.

[Instalador](../setup/setup_multcnc_0.16.exe) · [Cópia em bin](../bin/setup_multcnc_0.16.exe) · [SHA-256](../setup/SHA256SUMS)

## Correcao da inclusao do SimuCNC

O SimuCNC agora e obrigatorio nas instalacoes completa, basica e personalizada, inclusive em atualizacoes. Antes ele ficava fora da selecao basica. O arquivo por versao `setup_multcnc_0.16.exe` e identico a copia `setup_multcnc_016.exe`.

## MultiProject: ferramentas, regras e modelos

- **Abrir na ferramenta** com especificações e arquivos de entrada em `.task.json`.
  MultiCAD e MakePCB recebem o destino de um arquivo novo e mostram os requisitos da tarefa.
- Vínculo e acompanhamento dos arquivos, SHA-1, diagnósticos de peça/placa/G-code/folha
  de torno e desatualização das sucessoras quando uma entrega muda.
- **Regras A01 a A08:** fabricação, compra, montagem por subsistema, validação,
  liberação, montagem física, teste funcional e revisão por reprovação.
- **Sugestões revisáveis:** aceitar/recusar individualmente ou em lote, origem e filtro,
  sem duplicação e com um único desfazer para cada decisão.
- **Liberação configurável** antes da fabricação. Ativar ou desativar a opção preserva
  os trabalhos em andamento e concluídos.
- **Modelos** de peça impressa, placa eletrônica e motor DC, com IDs novos ao criar
  um projeto; arquivos e resultados anteriores são limpos.
- **Motor DC** com 15 tarefas e 21 vínculos, além da versão inicial só com quatro projetos.
- **Folha de torno** Markdown derivada da especificação, sem inventar rotação ou avanço.
- [Guia rápido](Manuals/MultiProject_Guia_Rapido.md), capturas e exemplos na documentação offline.

Os modelos acompanham o componente MultiProject, inclusive quando os manuais opcionais
não são selecionados no instalador. Os formatos sem verificador específico continuam
como não verificados. A execução das máquinas permanece no MultiCNC.

## Verificação e rastreabilidade

- Os 14 aplicativos foram compilados para Win64 com Lazarus 4.4 / FPC 3.2.2.
- **119 testes de console aprovados; 1 teste de integração com SimuCNC separado**.
- MultiProject: **145 verificações de regras**, 34 da interface nova, 84 da interface
  existente e 6 da integração de destino/especificação no MultiCAD e MakePCB.
- Console do MultiProject aprovado no Linux; a validação das interfaces segue no [MultiProject CI](https://github.com/marcelomaurin/multicnc/actions/runs/39825699966).
- O Suite CI geral no Linux registrou falhas em outros módulos (TCP/Winsock2,
  catálogo FDM e teste de fontes), fora da entrega do MultiProject.
- Não inclui ensaios em máquinas reais.
- [Manifesto de compilação](../setup/build-manifest-016.json): fontes `5fe749d`, árvore limpa na geração.
- [Resultados de console](../setup/qa-tests-016.json).

SHA-256 do instalador:

```text
3af23dbcf00a5d7a226396d4fdc9b9350b5c74f07f42aec09b58ec4eb715800a  setup_multcnc_016.exe
```
