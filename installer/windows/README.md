# Instalador Windows MultiSuite

## Requisitos

Windows 64 bits, Git, Python 3.9+, Lazarus/Free Pascal (`lazbuild` e `fpc` no PATH), Inno Setup 6 (`iscc`) e árvore Git limpa.

## Gerar

```bat
set VERSION=0.1.1-dev
installer\windows\build_release.bat
```

O script compila os onze aplicativos, compila/executa os testes de console, copia os testes e a documentação para o pacote e valida os cabeçalhos PE como amd64. Em seguida gera `build-manifest.json`, `qa-tests.json`, o instalador e `SHA256SUMS`.

`MyAppVersion` e a versão numérica do executável do instalador vêm do mesmo valor VERSION. O manifesto registra o commit de origem e os hashes dos arquivos antes do Inno Setup. A versão padrão de desenvolvimento não substitui os binários históricos 0.1.0.

## Instalação

Inclui MultiSuite, MultiCAD, MultiPCB, MultiAssembly, MultiPhysics, MultiCAM, MultiSlicer, LaserPCB, LaserArt, MultiCNC e Central de Testes com seus testes de console. O projeto `.msuite` pode ser aberto pela associação de arquivos.

Projetos, histórico e relatórios pertencem ao usuário; a Central não depende de escrever em Program Files. A pasta de testes acompanha a instalação.

## CI e publicação

`Windows Installer` disponibiliza instalador, checksum, manifesto e relatório como artefatos do Actions. Um run aprovado confirma compilação/empacotamento e execução dos testes de console. Instalação interativa e hardware precisam de verificação própria. Publicar uma GitHub Release/tag continua uma etapa separada.
