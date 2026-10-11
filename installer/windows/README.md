# Instalador Windows MultiSuite 007

Windows 64 bits, Git, Python 3.9+, Lazarus/Free Pascal 64 bits e Inno Setup 6 ou 7.

## Gerar

    installer\windows\build_release.bat -Version 0.07 -SetupSeq 007

O script procura as ferramentas nas pastas usuais. Os caminhos podem ser definidos
por LAZBUILD, FPC, PYTHON e ISCC. MULTICNC_CHATGPT_DIR aponta para as dependencias
AI/AISerial quando estiverem fora da pasta CHATGPT ao lado do repositorio.

A publicacao exige arvore Git limpa. Para gerar e testar um setup local antes do
commit, acrescente -AllowDirty; o manifesto registra source_dirty=true.

O build compila os 13 executaveis, executa os testes de console, inclui relatorio de testes e
documentacao, valida a arquitetura amd64 e gera manifesto, relatorio e SHA256SUMS.
Os executaveis atualizados ficam em bin. setup_multcnc_007.exe fica em setup e bin; a copia de staging
e os logs ficam em dist. Feche os aplicativos da suite antes de substituir bin.

## Conteudo e inicializacao

Inclui MultiSuite Bandeja, MultiCAD, MultiAssembly,
MultiPhysics, MultiCAM, MultiSlicer, MakePCB, MakeRouter, RouterPCB, LaserPCB,
LaserArt, MultiCNC, SimuCNC.

O multisuite_tray.exe e somente um painel de atalhos ao lado do relogio, com o padrao visual restaurado.
Clique no icone para abrir os programas; o menu de contexto oferece Abrir painel e Sair.
Inclui MultiCAD, SimuCNC e os demais aplicativos disponiveis. O painel permite buscar
aplicativos; nao inclui o hub MultiSuite separado ou opcoes de configuracao no menu. O executavel multisuite.exe nao faz parte
do pacote Windows. MultiPCB tambem foi retirado. A atualizacao remove as copias
antigas desses executaveis e seus atalhos.

A instalacao basica inclui MultiCNC e bandeja. A tarefa "Iniciar a MultiSuite
Bandeja com o Windows" vem marcada por padrao e registra multisuite_tray.exe
--tray no Run do usuario. Pode ser desmarcada na instalacao ou desativada nas
configuracoes de inicializacao do Windows. A desinstalacao remove esse registro.

## Imagens

prepare_images.ps1 gera os bitmaps temporarios a partir de imgs, preservando as
proporcoes das capturas. A abertura mostra tres_maquinas_3d.png; durante a copia
dos arquivos aparecem multicnc_novo_layout.png, Makepcb01.png, Makerouter01.png
simucnc_router_ao_vivo.png, Laserpcb01.png e Laserart01.png. As imagens sao incorporadas ao setup e nao dependem
da pasta imgs existir no computador de destino.

## Validacao e publicacao

Nao distribuir um instalador se o build falhar. Compilacao e testes de console
nao substituem verificacao interativa da instalacao ou ensaio com hardware.
Projetos e relatorios pertencem ao usuario, fora de Program Files.
Publicar uma GitHub Release/tag continua uma etapa separada.
## Setup 007 gerado

[Instalador Windows x64](../../setup/setup_multcnc_007.exe) · [Notas e validação](../../docs/SETUP_007.md) · [Galeria de imagens](../../imgs/README.md)

| LaserPCB | LaserArt |
|---|---|
| ![Placas e camadas para laser](../../imgs/Laserpcb01.png) | ![Arte e vetores para laser](../../imgs/Laserart01.png) |
