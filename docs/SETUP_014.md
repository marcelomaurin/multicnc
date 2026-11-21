# Setup 014 — MultiSuite 0.14

Edição de **19/10/2026**, para **Windows x64**.

[Instalador](../setup/setup_multcnc_014.exe) · [Cópia em bin](../bin/setup_multcnc_014.exe) · [SHA-256](../setup/SHA256SUMS)

## Novidades do Setup 014: MultiPhysics 0.2

### 1. Simulação por elementos finitos própria
- Análises **estática linear**, **térmica permanente**, **termomecânica** e **modal** em tetraedros TET4/TET10.
- Fixação, deslocamento, força, pressão, gravidade, temperatura, fluxo, convecção e potência dissipada.
- Reações, fator de segurança, frequências naturais e massa efetiva por modo.
- Conferido contra soluções analíticas (flecha de viga, aleta térmica, tensão térmica, frequências).

### 2. Fidelidade sempre visível
- **ENGENHARIA** só com estudo de convergência de malha (variação < 5%); o resto sai como **ESTIMATIVA**.

### 3. Montagem do MultiAssembly
- O botão **MultiPhysics** do MultiAssembly salva a montagem e abre o MultiPhysics com ela.
- Peças, geometria, posições, material sugerido, fixos, gravidade e **contatos colados** entram sozinhos.

### 4. Interface nova
- 10 etapas no padrão da suíte, vista 3D com mapa de cores, deformada e modos animados, seleção de face pelo clique.
- Cálculo em segundo plano com **Cancelar**; relatório HTML, CSV e VTK (ParaView).

### 5. Sistema, máquina, circuitos e ambiente
- Motor DC com indutância e controle PI; CNC virtual com rampa, curva de torque, homing e falhas.
- Circuitos por netlist SPICE; atmosfera ISA; flutuação com calado e altura metacêntrica.
- CalculiX opcional para comparação (não incluído no instalador).

Exemplos em `documentation/models/multiphysics` e manual em `documentation/multiphysics/docs/MANUAL.md`.

## Rastreabilidade
- [Manifesto de compilação](../setup/build-manifest-014.json)
- [Resultados de testes QA](../setup/qa-tests-014.json)
