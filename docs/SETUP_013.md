# Setup 013 — MultiSuite 0.13

Edição de **18/10/2026**, para **Windows x64**.

[Instalador](../setup/setup_multcnc_013.exe) · [Cópia em bin](../bin/setup_multcnc_013.exe) · [SHA-256](../setup/SHA256SUMS)

## Novidades do Setup 013

### 1. LaserArt — caixa com encaixes (finger joint)
- Botão **Caixa com encaixes...** na barra superior.
- Campos: largura, profundidade e altura (internas ou externas), espessura do material, largura do dente, kerf e com ou sem tampa.
- Gera 5 faces (sem tampa) ou 6 (com tampa) como vetores lado a lado na mesa, na camada atual em modo Linha.
- Cada aresta tem número ímpar de segmentos; as faces vizinhas se revezam e cada canto da caixa pertence a uma face só.
- O kerf é compensado deslocando o contorno para fora em kerf/2: dentes kerf mais largos, fendas kerf mais estreitas.

### 2. LaserArt — corte, potência e imagem
- Pontes no corte (camadas Linha) para segurar a peça na chapa.
- Estimativa de potência, velocidade e passadas pelos W do laser, material e espessura.
- Foto recorte (estêncil), retícula de jornal, gravura riscada e esboço; texto inclinado e em arco; engrenagem por módulo.

### 3. LaserPCB e MakePCB
- LaserPCB: estimativa de potência pelo laser e espessura do cobre; gabarito de teste de material (potência × passadas).
- MakePCB: travar componente e menu de contexto com clique direito.

---

## Aplicativos e DLL

Inclui os 13 aplicativos da suíte compilados para Windows x64 (MultiSlicer, MultiCAD com `mcad_occt.dll`, MultiCNC, LaserArt, MakePCB, MakeRouter, RouterPCB, LaserPCB, MultiAssembly, MultiCAM, MultiPhysics, SimuCNC e MultiSuite Tray) e a biblioteca de 135 componentes 3D do MultiAssembly.

## Rastreabilidade

O processo exige compilação x64, validação da suíte de testes de console e geração de manifesto antes da criação do instalador.
- [Manifesto de compilação](../setup/build-manifest-013.json)
- [Resultados de testes QA](../setup/qa-tests-013.json)
