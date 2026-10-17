# MultiSuite — Notas de Lançamento / News

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
