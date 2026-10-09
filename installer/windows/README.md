# Instalador Windows MultiSuite

## Requisitos

Windows 64 bits, Git, Python 3.9+, Lazarus/Free Pascal (`lazbuild` e `fpc` no PATH), Inno Setup 6 (`iscc`) e árvore Git limpa.

## Gerar

```bat
set VERSION=0.1.1-dev
installer\windows\build_release.bat
```

O script compila os onze aplicativos, compila/executa os testes de console, copia os testes e a documentação para o pacote e valida os cabeçalhos PE como amd64. Em seguida gera `build-manifest.json`, `qa-tests.json`, o instalador e `SHA256SUMS`.

## Pacote
Instala MultiSuite, MultiSuite Bandeja, MultiCAD, MultiPCB, MakePCB, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, MakeRouter, RouterPCB, LaserPCB, LaserArt, MultiCNC, SimuCNC e Central de Testes.

A bandeja pode iniciar com o Windows (tarefa "Iniciar a MultiSuite Bandeja com o Windows"); a desinstalacao fecha a bandeja e remove esse registro.

Versao atual: 0.05 (`setup_multcnc_005.exe`, telas em portugues do Brasil; MakeRouter 2,5D, RouterPCB e MultiCNC lendo o cabecalho da suite). Gerar: `installer\windows\build_release.bat 0.05 005`.
`MyAppVersion` e a versão numérica do executável do instalador vêm do mesmo valor VERSION. O manifesto registra o commit de origem e os hashes dos arquivos antes do Inno Setup. A versão padrão de desenvolvimento não substitui os binários históricos 0.1.0.

## Instalação

## Regra de release
Nao distribuir um instalador se build_release.bat falhar. A existencia do script nao significa que os dezesseis executaveis compilam atualmente; o build deve ser executado em Windows com Lazarus e as falhas corrigidas antes da publicacao.
Inclui MultiSuite, MultiCAD, MultiPCB, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt, MultiCNC e Central de Testes com seus testes de console. O projeto `.msuite` pode ser aberto pela associação de arquivos.

Projetos, histórico e relatórios pertencem ao usuário; a Central não depende de escrever em Program Files. A pasta de testes acompanha a instalação.

## CI e publicação

`Windows Installer` disponibiliza instalador, checksum, manifesto e relatório como artefatos do Actions. Um run aprovado confirma compilação/empacotamento e execução dos testes de console. Instalação interativa e hardware precisam de verificação própria. Publicar uma GitHub Release/tag continua uma etapa separada.
