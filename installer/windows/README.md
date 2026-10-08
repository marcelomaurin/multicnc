# Instalador Windows MultiSuite

## Requisitos de build
- Windows 64-bit.
- Lazarus/Free Pascal com lazbuild no PATH.
- Inno Setup 6 com ISCC no PATH.

## Gerar instalador
Execute:
installer\windows\build_release.bat

O script compila todas as aplicacoes, interrompe no primeiro erro, copia somente executaveis gerados com sucesso para dist\app e chama o Inno Setup.

## Pacote
Instala MultiSuite, MultiSuite Bandeja, MultiCAD, MultiPCB, MakePCB, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt, MultiCNC, SimuCNC e Central de Testes.

A bandeja pode iniciar com o Windows (tarefa "Iniciar a MultiSuite Bandeja com o Windows"); a desinstalacao fecha a bandeja e remove esse registro.

Versao atual: 0.02 (`setup_multcnc_002.exe`, telas em portugues do Brasil). Gerar: `installer\windows\build_release.bat 0.02 002`.

Cria a pasta MultiSuite Projects em Documentos, menu Iniciar e opcionalmente atalho na area de trabalho. Registra .msuite como projeto MultiSuite.

## Regra de release
Nao distribuir um instalador se build_release.bat falhar. A existencia do script nao significa que os catorze executaveis compilam atualmente; o build deve ser executado em Windows com Lazarus e as falhas corrigidas antes da publicacao.
