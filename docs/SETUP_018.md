# Setup 018 — MultiSuite 0.18

Edição de **01/11/2026**, para **Windows x64**.

[Instalador](../setup/setup_multcnc_0.18.exe) · [Cópia em bin](../bin/setup_multcnc_0.18.exe) · [SHA-256](../setup/SHA256SUMS)

## MultiCNC 0.1.0.7

- Aba **Calibração** para ajuste manual da mesa pelos quatro cantos.
- Distância da base Z: **2 mm**; margens X/Y: **5 mm**, configuráveis.
- Altura Z de movimentação: **10 mm**, configurável com mínimo de 10 mm.
- **Iniciar calibração**, **Próximo canto**, **Canto anterior** e **Finalizar**.
- Antes de mover X/Y, a ferramenta sobe até a altura de movimentação. Ao
  chegar ao canto, desce até a distância da base e espera a ação do operador.
- Elevação inicial somente em Z permite iniciar após homing Marlin com X/Y
  negativos, como X −3 e Y −10, mantendo os limites nos movimentos X/Y.
- Movimento em milímetros, posição absoluta e avanço de 300 mm/min, com
  spindle/laser desligado e confirmação de término pela controladora.
- Correção dos acentos corrompidos no cadastro de equipamentos e nas mensagens.

Defina o zero Z na base e confira a origem X/Y e os cursos úteis do perfil.
A função auxilia a regulagem manual; não gera malha de compensação automática.
[Guia do MultiCNC](../src/app/README.md).

## MultiCAD e demais aplicativos

Inclui **MultiCAD 0.0.9.0**, com rosca em hélice, engrenagens externas, internas
e cremalheiras, dentes retos, helicoidais e espinha de peixe, além de medidas
com expressões e variáveis. [Guia do MultiCAD](../multicad/README.md).

O pacote inclui os 14 aplicativos da suíte, a ponte OpenCascade, documentação
offline e os modelos distribuídos na versão anterior.

## Rastreabilidade

- [Manifesto de compilação](../setup/build-manifest-018.json): commit das fontes,
  arquitetura e hashes dos arquivos distribuídos.
- [Relatório de testes de console](../setup/qa-tests-018.json).
- Testes específicos de calibração incluem quatro cantos, retorno, espera,
  altura mínima e posição negativa após homing Marlin.
- Não inclui ensaio com máquina real.
