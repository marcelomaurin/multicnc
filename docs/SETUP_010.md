# Setup 010 — MultiSuite 0.10

Edição de **13/10/2026**, para **Windows x64**.

[Instalador](../setup/setup_multcnc_010.exe) · [Cópia em bin](../bin/setup_multcnc_010.exe) · [SHA-256](../setup/SHA256SUMS)

## Aplicativos e DLL

Inclui os 13 aplicativos da suíte compilados a partir dos fontes registrados,
com **MultiSlicer 0.1.0.0**, **MultiCAD 0.0.8.5**, **MultiCNC 0.1.0.5** e
**LaserArt 0.02.1** (versão do arquivo Windows 0.2.0.1).

O MultiSlicer inclui escolha do equipamento salvo no MultiCNC, prévia 3D por
camada, projeto `.mslice`, importação STL/3MF e fatiamento em segundo plano
com progresso e cancelamento. O MultiCNC reconhece o cabeçalho exportado pelo
MultiSlicer e restaura as informações do programa de impressão.

A **mcad_occt.dll**, com OpenCascade **7.6.3**, é instalada na mesma pasta do
MultiCAD. A geração rejeita a ausência da DLL ou uma arquitetura incompatível;
o componente MultiCAD sempre inclui o arquivo.

## Documentação na Área de Trabalho

O componente **Documentação e Manuais do Sistema** vem selecionado nas instalações
completa e básica. Mantendo esse componente, o instalador cria a pasta
**Documentacao MultiSuite** na Área de Trabalho, com os atalhos:

- **Abrir documentacao**: página local com os PDFs e instruções do MultiSlicer.
- **Manual MultiCAD 0.0.8.4**: PDF ilustrado em português.
- **Manual MultiCNC 0.1.0.3**: PDF ilustrado em português.
- **Manual LaserArt 0.02.1**: PDF ilustrado em português.

Os arquivos ficam em `documentation` dentro da pasta instalada. Os guias,
manuais, capturas e imagens são incluídos para consulta sem internet, preservando
a estrutura das referências relativas. A versão de referência de cada manual é
independente da versão do setup. A desinstalação remove os atalhos gerados.

## Imagem do MultiSlicer

A sequência de imagens durante a instalação inclui a prévia 3D do MultiSlicer,
além das imagens dos demais aplicativos já presentes no setup anterior.

![Prévia 3D do MultiSlicer com suportes](../imgs/ms_preview3d.png)

## Zero pelo bloco no MultiCNC 0.1.0.5

O assistente de router permite marcar o canto do bloco e o topo do material,
calcular o zero do programa e conferir a profundidade de corte com a folga
mínima. Inclui reconhecimento de `MS-DATUM`/`MS-STOCK` e programas sem cabeçalho.

## Modelos de teste

Inclui os 12 exemplos GRBL de CNC Router em `documentation/models/cnc_router`:
movimentação sem corte, quadrado, círculos, furação, bolsão, contorno arredondado,
hélice, gravação vetorial, cópias, coordenadas incrementais, superfície 3D e placa
combinada. Acompanham catálogo visual, instruções e relatório de validação.

Os modelos foram verificados no analisador e simulador local; os parâmetros são
demonstrativos e não constituem preparação CAM para usinagem física.

## Rastreabilidade

O processo exige compilação, testes de console e validação amd64 antes de gerar
o instalador. `build-manifest.json` e `qa-tests.json` acompanham o pacote e
registram o commit, hashes e os resultados efetivamente executados.
As cópias externas ficam em [manifesto](../setup/build-manifest-010.json) e
[testes](../setup/qa-tests-010.json). A instalação não inicia uma impressão.
