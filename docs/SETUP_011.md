# Setup 011 — MultiSuite 0.11

Edição de **15/10/2026**, para **Windows x64**.

[Instalador](../setup/setup_multcnc_011.exe) · [Cópia em bin](../bin/setup_multcnc_011.exe) · [SHA-256](../setup/SHA256SUMS)

## Novidades do Setup 011

### 1. MultiSlicer 0.1.0.1 — Seleção de Impressora 3D por Marca e Modelo (Etapa 1)
- Inclusão dos seletores de **Marca** e **Modelo** integrados ao catálogo de máquinas (`multislicer_machines`), com marcas consolidadas como Creality, Prusa Research, Anycubic, Elegoo e Artillery.
- Botão **"Criar perfil a partir do modelo..."** para gerar e salvar perfis customizados diretamente a partir das dimensões, tipo de extrusora (Bowden ou Direta) e comandos da máquina.
- Persistência automática da marca e modelo selecionados para as próximas sessões.

### 2. MultiSlicer 0.1.0.1 — Catálogo de Filamentos com Temperaturas Ideais (Etapa 3)
- Catálogo especializado (`multislicer_filaments`) com suporte a marcas e modelos reais do mercado nacional e internacional: **Voolt3D**, **3D Fila**, **eSun**, **Creality**, **Sunlu**, **Prusament** e **Genérico**.
- Seleção dinâmica e hierárquica em função do **Tipo (Polímero)**: PLA, ABS, PETG, TPU e ASA.
- Ao escolher Marca e Modelo, as temperaturas de **bico** (1ª camada e demais) e de **mesa aquecida** (1ª camada e demais), além de ventoinha, densidade e retração, são preenchidas automaticamente de acordo com as especificações do fabricante.
- Memorização automática da escolha do filamento no arquivo de configuração do usuário (`multislicer.json`).

### 3. MultiSlicer 0.1.0.1 — Preenchimento Salvo para o Próximo Uso (Etapa 4)
- O percentual de preenchimento configurado na Etapa 4 (tanto no modo Recomendado quanto no modo Personalizado) é salvo automaticamente e restaurado ao reabrir o software, mantendo total flexibilidade para modificação.

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
- [Manifesto de compilação](../setup/build-manifest-011.json)
- [Resultados de testes QA](../setup/qa-tests-011.json)
