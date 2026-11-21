# Setup 012 — MultiSuite 0.12

Edição de **17/10/2026**, para **Windows x64**.

[Instalador](../setup/setup_multcnc_012.exe) · [Cópia em bin](../bin/setup_multcnc_012.exe) · [SHA-256](../setup/SHA256SUMS)

## Novidades do Setup 012

### 1. MultiAssembly — peças com geometria real
- A vista mecânica 3D desenha cilindros, tubos, cones, prismas com perfil e furos, com sombreamento e rotação, em vez de caixas.
- Biblioteca ampliada de 50 para **135 componentes** com dimensões de norma/datasheet: perfis V-Slot e C-Beam, parafusos, porcas, arruelas, T-nuts, rolamentos e mancais, guias MGN/HGR com carros, fusos T8/SFU e castanhas, motores NEMA 17/23/34, DC, spindles, laser, acoplamentos, polias e correias GT2, rodas V-Slot, drivers, controladoras, fontes, inversor, relé, sensores, ventoinhas e conectores.
- Peças sem geometria (projetos antigos ou criadas no programa) recebem uma forma gerada pelo tipo; projetos antigos recuperam a geometria pelo arquivo de origem.
- A biblioteca é instalada em `models\components\mec`, ao lado do `multiassembly.exe`.

### 2. MultiAssembly — Unir Peças por face, furo e eixo
- Botão **Unir Peças**: clique na face, furo ou eixo da peça que se move e na referência da outra; a união é sugerida e mostrada em prévia.
- Tipos: **Inserir** (concêntrico + coincidente), **Concêntrico**, **Coincidente**, **Distância** e **Paralelo**.
- Atalhos: `Enter` confirma, `F` inverte, `R` gira 90°, `I`/`O`/`C`/`D`/`P` trocam o tipo, `+`/`-` ajustam a distância, `Esc` cancela.
- As referências ficam salvas no projeto e o solver reencaixa a peça quando a referência se move.

---

## Aplicativos e DLL

Inclui os 13 aplicativos da suíte compilados para Windows x64:
- **MultiSlicer 0.1.0.1**
- **MultiCAD 0.0.8.5** (com `mcad_occt.dll`, OpenCascade 7.6.3)
- **MultiCNC 0.1.0.5**
- **LaserArt 0.02.1**
- **MakePCB 0.1.0.0**
- **MakeRouter 0.1.0.0**
- **RouterPCB 0.1.0.0**
- **LaserPCB 0.1.0.0**
- **MultiAssembly 0.1.0.0**
- **MultiCAM 0.1.0.0**
- **MultiPhysics 0.1.0.0**
- **SimuCNC 0.1.0.0**
- **MultiSuite Tray 0.1.0.0**

## Rastreabilidade

O processo exige compilação x64, validação da suíte de testes de console e geração de manifesto antes da criação do instalador.
- [Manifesto de compilação](../setup/build-manifest-012.json)
- [Resultados de testes QA](../setup/qa-tests-012.json)
