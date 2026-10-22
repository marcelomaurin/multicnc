# MultiProject — verificação da fase 6

22/10/2026 · MultiProject 0.2.0.0 · MultiSuite 0.16 / setup 016.

## Windows x64

- FPC 3.2.2 e Lazarus 4.4; 14 aplicativos compilados pelo build oficial Windows.
- 119 programas de teste de console aprovados, 1 integração com SimuCNC separada.
- `test_multiproject_rules`: 145 verificações de regras, transações, gate, origem,
  revisão sem ciclos, modelos, folha de torno e extração do checklist do manual.
- `test_multiproject_rules_ui`: 34 verificações de sugestões, decisões, desfazer,
  origem, filtro, modelo e layout em 1024 × 768.
- `test_multiproject_ui`: 84 verificações; `test_multiproject_toolctx`: 6.
- Capturas reais geradas pelos testes de interface em `imgs/multiproject_*.png`.
- Manifesto conferido para executável, modelos, guia e capturas.

## Linux

Console do MultiProject aprovado no Linux; a validação das interfaces segue no [MultiProject CI](https://github.com/marcelomaurin/multicnc/actions/runs/39825699966).

O [Suite CI](https://github.com/marcelomaurin/multicnc/actions/runs/39824939751)
aprovou os sete testes de console do MultiProject: core (103), grafo (88), links (36),
recursos (116), regras (145), cronograma (82) e estados (21).
O resultado global desse workflow é falha por outros módulos: TCP usa Winsock2 no
Linux, teste do catálogo FDM e teste de escala de fonte do MultiCAD.

## Pacote

- Fonte de compilação: `5fe749d81d5a404d9b19cdc48febc1cf7027cef9`, sem alterações locais na geração.
- Arquitetura dos aplicativos: amd64; instalador Inno Setup 6.3.3, versão 0.16.0.0.
- Modelos acompanham o componente MultiProject mesmo com documentação opcional desmarcada.
- Instalador: `setup/setup_multcnc_016.exe` (39718740 bytes).
- SHA-256: `3af23dbcf00a5d7a226396d4fdc9b9350b5c74f07f42aec09b58ec4eb715800a`; cópia em `bin` conferida.
- QA de console: [qa-tests-016.json](../../setup/qa-tests-016.json).

Não foram executados testes com máquinas reais.
