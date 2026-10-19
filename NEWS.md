# MultiSuite — Notas de Lançamento / News

## [0.14] — Setup 014 (19/10/2026)

### 🧪 MultiPhysics: simulação física de verdade
- **FEM próprio** (tetraedros TET4/TET10) para análise **estática**, **térmica**, **termomecânica** e **modal**, com reações, fator de segurança e massa efetiva. Conferido contra soluções analíticas: flecha de viga 0,6%, frequência 0,4%, aleta térmica 0,01%.
- **Fidelidade sempre visível**: ENGENHARIA só com estudo de convergência de malha (< 5%); o resto sai como ESTIMATIVA.
- **Montagem do MultiAssembly**: o botão MultiPhysics abre a montagem direto; peças, geometria, fixos, gravidade e contatos colados entram sozinhos.
- **Interface nova** no padrão da suíte: 10 etapas, vista 3D com mapa de cores, deformada e modos animados, seleção de face pelo clique, cálculo em segundo plano com Cancelar, relatório HTML, CSV e VTK (ParaView).
- **CalculiX opcional** para comparação (deck `.inp`, execução e leitura do `.frd`).
- **Sistema e máquina**: motor DC com indutância e controle PI, CNC virtual com rampa, curva de torque, homing e falhas; circuitos por netlist SPICE; atmosfera ISA; flutuação com calado e altura metacêntrica.
- Exemplos em `models/multiphysics` e manual em `multiphysics/docs/MANUAL.md`.

---

## [0.13] — Setup 013 (18/10/2026)

### 🌟 Destaques da Versão 0.13

O **LaserArt** ganha recursos pensados para corte e gravação a laser: caixa com encaixes, pontes no corte, estimativa de potência e novos efeitos de imagem. O **LaserPCB** estima potência pelo laser e grava um gabarito de teste de material.

---

### 📦 LaserArt: caixa com encaixes (finger joint)
- Botão **Caixa com encaixes...** na barra superior: medidas internas ou externas, espessura do material, largura do dente, compensação de kerf e com ou sem tampa.
- Gera as 5 ou 6 faces lado a lado na mesa, na camada atual em modo Linha. Os dentes de faces vizinhas se complementam e cada canto pertence a uma face só.
- O kerf alarga os dentes e estreita as fendas; depois do corte as medidas voltam ao nominal. Teste `laserart/tests/test_laserart_box.lpr` confere a parede inteira em 3D.

### 🔥 LaserArt: corte, potência e imagem
- **Pontes no corte** por camada Linha (largura e distância), para a peça não cair da chapa.
- **Estimar potência pelo laser...**: potência, velocidade e passadas pelos W do laser, material e espessura.
- **Foto recorte (estêncil)**, retícula de jornal, gravura riscada e esboço nas imagens; texto inclinado e em arco; engrenagem por módulo; nova camada/excluir camada na lista.

### 🔌 LaserPCB e MakePCB
- **LaserPCB:** estimativa de potência pela potência óptica do laser e espessura do cobre; **gabarito de teste de material** (grade potência × passadas); menu de componentes.
- **MakePCB:** travar componente, menu de contexto com clique direito e galeria atualizada.

---

## [0.12] — Setup 012 (17/10/2026)

### 🌟 Destaques da Versão 0.12

O **MultiAssembly** passa a mostrar as peças com geometria real e a unir peças clicando em faces, furos e eixos, no estilo do SolidWorks Composer. O setup instala a biblioteca de 135 componentes 3D.

---


### 🔩 MultiAssembly: componentes com aparência real
- **Vista mecânica 3D:** as peças deixam de ser caixas. Cilindros, tubos, cones, setores, prismas com perfil e decalques (furos, LEDs) são desenhados com sombreamento, brilho especular, rotação e ordenação por face.
- **Biblioteca ampliada de 50 para 135 componentes** com dimensões de norma/datasheet: perfis V-Slot 2020–4040 e C-Beam, parafusos DIN 912/ISO 7380/ISO 10642/DIN 933, porcas, arruelas, T-nuts, rolamentos (608, 625, 623, 6000, 6205, F623, LM8UU/LM8LUU/LM12UU), mancais KP08/KFL08/BK12/BF12/SK/SCS, guias MGN12H e HGR15 com carros, fusos T8 e SFU com castanhas, NEMA 17/23/34, DC 775, motorredutor, spindles 500 W e 1,5 kW, laser 10 W, acoplamentos, polias e correias GT2, rodas V-Slot, drivers TB6600/DM542/A4988/DRV8825/TMC2209, controladoras grblHAL/FluidNC/Arduino CNC Shield, ESP32, fontes, inversor VFD, relé, sensores, ventoinhas e conectores.
- **Formas por tipo:** peças sem geometria (projetos antigos e componentes criados no programa) recebem uma forma coerente com o tipo; projetos antigos recuperam a geometria pelo arquivo de origem.
- **Formato:** bloco `geometry` documentado em `models/components/README.md`, gerado por `tools/components/generate_components.py`.

### 🧩 MultiAssembly: Unir Peças por face, furo e eixo (estilo SolidWorks Composer)
- Clique na face/furo/eixo da peça que se move e na referência da outra: a união é sugerida (Inserir, Concêntrico, Coincidente, Distância, Paralelo) e mostrada em prévia antes de confirmar.
- Realce da referência sob o mouse (contorno da face, eixo tracejado, círculo do furo e normal), inverter lado, girar 90° e distância pelo teclado.
- Relações por referência salvas no projeto e reaplicadas pelo solver; teste automatizado `multiassembly/tests/test_mates.lpr`.

---

## [0.11] — Setup 011 (15/10/2026)

### 🌟 Destaques da Versão 0.11

A versão 0.11 traz avanços significativos na experiência de impressão 3D da suíte com a atualização do **MultiSlicer 0.1.0.1**, introduzindo seletores de marca e modelo tanto para equipamentos quanto para filamentos comerciais com parâmetros térmicos reais de fábrica, além de persistência de ajustes de preenchimento.

---

### 🖨️ 1. MultiSlicer: Impressoras 3D por Marca e Modelo (Etapa 1)
- **Seleção Direta:** O painel lateral da Etapa 1 agora oferece seletores rápidos de **Marca da impressora** e **Modelo**, consultando o catálogo integrado (`multislicer_machines`).
- **Marcas Suportadas:** Creality (Ender-3, Ender-3 V2, S1, V3 SE, CR-10, Ender-5 Pro), Prusa Research (MK3S+, MK4, Mini+), Anycubic (Mega S, Kobra Neo, Chiron), Elegoo (Neptune 3 Pro/Plus, 2S) e Artillery (Sidewinder X2).
- **Criação de Perfil a partir do Modelo:** Com um clique no botão *"Criar perfil a partir do modelo..."*, o usuário gera um perfil nomeado e cadastrado com dimensões da mesa (X, Y, Z), tipo de extrusora (Bowden ou Direta), diâmetro de bico e filamento, velocidades e G-code inicial/final.
- **Persistência:** A Marca e o Modelo selecionados são lembrados na próxima vez que o software for aberto.

---

### 🧵 2. MultiSlicer: Catálogo Comercial de Filamentos (Etapa 3)
- **Catálogo Especializado (`multislicer_filaments`):** Base de dados com marcas e linhas consagradas no mercado brasileiro e internacional:
  - **Voolt3D:** PLA Premium, PLA High Speed, PLA Silk, ABS Premium, PETG Premium, TPU 95A, ASA.
  - **3D Fila:** PLA EasyFill, PLA Standard Puro, ABS Premium+, ABS Alta Fluidez, PETG XT, PETG High Speed, TPU Flex, ASA.
  - **eSun:** PLA+, ePLA-HS, ABS+, PETG, eTPU-95A, eASA.
  - **Creality:** CR-PLA, Hyper PLA, Ender-PLA, CR-ABS, CR-PETG, CR-TPU.
  - **Sunlu:** PLA+, ABS, PETG, TPU 95A.
  - **Prusament:** Prusament PLA, Prusament PETG, Prusament ASA.
  - **Genérico:** Padrões industriais para PLA, ABS, PETG, TPU e ASA.
- **Seleção Dinâmica por Tipo (Polímero):** O usuário escolhe o tipo de plástico e a interface filtra instantaneamente as marcas e modelos compatíveis.
- **Aplicação Automática de Temperaturas:** Bico na 1ª camada, bico nas demais camadas, mesa aquecida na 1ª camada e demais camadas são configurados de acordo com a ficha técnica de cada material, otimizando adesão e acabamento sem tentativa e erro.
- **Persistência:** A escolha do filamento é salva automaticamente em `multislicer.json`.

---

### 🧱 3. MultiSlicer: Preenchimento Salvo para o Próximo Uso (Etapa 4)
- **Infill Memorizado:** O percentual de preenchimento configurado na Etapa 4 (seja no modo Recomendado via barra deslizante ou no modo Personalizado) é automaticamente persistido para as próximas sessões.
- **Edição Flexível:** O valor salvo serve de ponto de partida e pode ser facilmente ajustado a qualquer momento de acordo com a resistência exigida para a peça.

---

### 📦 4. Instalador e Qualidade
- **Setup 011 Oficial:** Gerado e testado para Windows x64 em `setup/setup_multcnc_011.exe` e `bin/setup_multcnc_011.exe`.
- **Validação de Testes:** 98 testes de console e integração executados e aprovados.
- **Manifestos Rastreáveis:** `setup/build-manifest-011.json` e `setup/qa-tests-011.json` acompanham o lançamento com hashes SHA-256 no arquivo `setup/SHA256SUMS`.
