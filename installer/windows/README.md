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
Instala MultiSuite, MultiCAD, MultiPCB, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt, MultiCNC e Central de Testes.

Cria a pasta MultiSuite Projects em Documentos, menu Iniciar e opcionalmente atalho na area de trabalho. Registra .msuite como projeto MultiSuite.

## Regra de release
Nao distribuir um instalador se build_release.bat falhar. A existencia do script nao significa que os onze executaveis compilam atualmente; o build deve ser executado em Windows com Lazarus e as falhas corrigidas antes da publicacao.
