# MultiCNC

Plataforma desktop para controle, projeto, preparação, simulação e testes de máquinas e sistemas de fabricação digital.

O repositório reúne várias aplicações. **Elas não são o mesmo programa.** Cada ferramenta possui uma finalidade específica e pode compartilhar bibliotecas e modelos com as demais.

## Qual aplicação devo usar?

| Aplicação / módulo | O que faz | Use quando quiser |
|---|---|---|
| **MultiCNC** | Controle de máquinas CNC e execução de G-code | Operar Router, Laser CNC ou outros equipamentos suportados |
| **MultiSuite** | Gestor unificado da suíte | Abrir e organizar as diferentes ferramentas do projeto a partir de um único ponto |
| **MultiPhysics** | Simulação física multidomínio | Estudar eletricidade, eletrônica, mecânica, térmica, magnetismo, materiais, sensores, motores, energia e falhas |
| **Ferramentas de projeto mecânico** | Projeto e preparação de peças e conjuntos | Trabalhar com geometria, peças mecânicas, montagem e preparação para CNC Router |
| **Ferramentas de PCB/eletrônica** | Projeto de circuitos e placas | Trabalhar com esquemas, componentes, conexões e PCB |
| **Ferramentas Laser** | Preparação de desenhos, imagens, logos e trabalhos para laser | Criar ou preparar arte para corte e gravação a laser |
| **Ferramentas CNC Router/CAM** | Preparação de usinagem mecânica | Preparar operações, trajetórias e trabalhos para Router |
| **Montagem eletromecânica** | Visualização conjunta de mecânica e eletrônica | Ver componentes mecânicos, placas, sensores, motores e conexões no mesmo projeto |
| **Central de Testes** | Compilação e validação das funcionalidades | Desenvolver, testar e diagnosticar os módulos da suíte |

> **Resumo rápido:** MultiCNC controla a máquina; MultiPhysics simula o comportamento físico; as ferramentas de projeto criam/preparam o projeto; MultiSuite reúne e chama as aplicações.

## Novidades (modernização de 2026)

Cada ferramenta recebeu recursos que hoje são padrão nos softwares de referência da área, mantendo a função original de cada uma e o Object Pascal (FPC/Lazarus), sem dependências externas novas.

| Ferramenta | O que entrou |
|---|---|
| **MultiCNC** | Telemetria Grbl/grblHAL/FluidNC (status `<...>`, `ALARM`/`error` com texto), overrides em tempo real, envio por *character-counting* (Grbl) e linhas numeradas com checksum/`Resend` (Marlin), drivers **grblHAL** e **FluidNC**, transporte **TCP/telnet**, análise prévia de G-code com estimativa de tempo pelo modelo de *junction deviation* do Grbl e verificação do envelope da máquina (`multicnc_cli --check arquivo.nc`). |
| **MultiCAM** | Fresamento **trocoidal**, pocket por **offsets** com entrada helicoidal, perfil com **compensação de raio**, rampa e tabs, calculadora de avanços e rotações com **afinamento de cavaco**, pós-processador modal com **arc fitting G2/G3** (perfil típico cai de 516 para 190 linhas). |
| **LaserArt / LaserPCB** | Rasterização em **escala de cinza** (potência variável), dithering Floyd-Steinberg, Jarvis, Stucki, Atkinson, Sierra, Burkes e Bayer com varredura serpentina, **overscan**, varredura bidirecional, salto de áreas brancas, modo laser dinâmico `M4` e G-code modal. |
| **MultiSlicer** | Contornos com furos, **perímetros**, topo/fundo sólidos, infill **gyroid**, **altura de camada adaptativa**, extrusão volumétrica, sabores **Marlin** e **Klipper** (`M73`, `M486`/`EXCLUDE_OBJECT`, pressure advance), retração só ao cruzar perímetros, arcos nos perímetros, STL binário e **3MF**. |
| **MultiPCB** | **Gerber X2** com netlist embutida e funções de abertura, **Gerber Job** (`.gbrjob`), Excellon com tabela de ferramentas, **DRC de clearance** e **autorouter A\*** de duas camadas com vias. |
| **MultiPhysics** | Solver de circuitos **Newton-Raphson global** (diodo e MOSFET dentro da MNA, *gmin/source stepping*, regra trapezoidal) e integradores **RK4**, **Dormand-Prince 45** adaptativo e **Velocity Verlet**. |
| **MultiCAD** | **Solver de restrições** (Levenberg-Marquardt) com análise de **graus de liberdade** e detecção de conflitos, extrusão para malha fechada com furos, exportação **STL** e **3MF** (lida diretamente pelo MultiSlicer). |
| **MultiAssembly** | **ERC eletromecânico** (drivers sem STEP/DIR, tensões incompatíveis, E-stop...), **BOM** CSV/JSON e geração dos parâmetros **Grbl `$100`–`$132`** e do YAML do **FluidNC** a partir da cinemática. |
| **Geometria compartilhada** | `src/shared/multisuite_geometry` (offset, recorte, contornos) e `multisuite_arcfit` (G2/G3), usadas por CAM, Slicer e CAD. |

Correções incluídas: compensação Z do PCB passou a usar interpolação **bilinear** em grade (o IDW anterior subestimava a inclinação: 0,04 mm de erro num desnível de 0,2 mm), leitura de STL ASCII em sistemas com vírgula decimal (pt-BR), workspace do MultiSuite salvo sem diretório, remoção de material com espessura de stock não informada e relação mecânica não inicializada na demonstração do MultiAssembly.

### Testes

```bash
bash tests/run_all.sh            # todos os módulos
bash tests/run_all.sh multicam   # um módulo
```

O script compila com `fpc` e executa os 66 testes de console; os executáveis ficam ao lado de cada `.lpr`, onde a Central de Testes os encontra. O workflow **Suite CI** roda os testes e compila todos os projetos `.lpi` com `lazbuild` a cada push.

---

## 1. MultiCNC — controle da máquina

O **MultiCNC** é a aplicação voltada ao controle e operação de máquinas de fabricação digital.

Seu núcleo separa quatro conceitos: **tipo de máquina**, **protocolo/firmware**, **transporte** e **execução de G-code**.

### Máquinas previstas

- **CNC Router:** XYZ, spindle, RPM, probe, zero da peça e ferramentas.
- **Laser CNC:** XY, potência, velocidade, frame, foco e air assist quando suportado.
- **Impressora 3D:** XYZ, hotend, mesa, extrusor, fan e temperaturas.

### Arquitetura

```text
UI
 |
Machine Manager
 |
CNC Core
 |-- Machine Profile
 |-- Machine State
 |-- Safety
 |-- Job Manager
 |-- G-code Engine
 |
Protocol Drivers            Streaming
 |-- GRBL                    |-- character-counting (Grbl/grblHAL/FluidNC)
 |-- grblHAL                 |-- send-response
 |-- FluidNC                 |-- Marlin: checksum + Resend
 |-- Marlin
 |
Transport
 |-- Serial (CHATGPT/TAISerialModem)
 |-- TCP/IP (FluidNC/grblHAL via telnet)
 |-- Simulator
```

### Regra fundamental

Tipo de máquina, protocolo e transporte são independentes. Por exemplo, Router e Laser podem utilizar GRBL, enquanto diferentes máquinas podem utilizar Serial, TCP/IP ou simulador.

Use o **MultiCNC** quando o objetivo final for **controlar ou operar uma máquina**.

---

## 2. MultiSuite — gestor unificado

O **MultiSuite** é o ponto central para reunir as aplicações do projeto.

Sua função é facilitar o acesso às ferramentas sem obrigar o usuário a conhecer a estrutura interna do repositório ou procurar cada executável manualmente.

A proposta é permitir selecionar o tipo de trabalho e abrir a ferramenta apropriada: controle CNC, projeto mecânico, PCB, Laser, Router, montagem, simulação ou testes.

Use o **MultiSuite** quando quiser **entrar na suíte por uma única aplicação e escolher o que deseja fazer**.

---

## 3. MultiPhysics — simulador físico

O **MultiPhysics** é o ambiente experimental de simulação física e de engenharia.

Ele procura representar uma máquina ou sistema completo, permitindo que diferentes domínios físicos participem da mesma simulação.

### Eletricidade e eletrônica

Inclui modelos e bibliotecas para fontes, baterias, resistores, capacitores, indutores, transformadores, LEDs, diodos, transistores, MOSFETs, IGBTs, amplificadores, fusíveis, relés, conversores, ponte H, drivers e circuitos digitais.

### Processadores e controle

Há modelos orientados a periféricos para **ATmega328P/Arduino, ESP32, RP2040, STM32 e MCU genérico**, incluindo GPIO, ADC, PWM, memória, clock e interfaces de controle.

### Motores, atuadores e sensores

O ambiente contempla motores DC, stepper, servo, BLDC e AC, além de solenoides, atuadores lineares, eletroímãs, bombas, ventiladores, aquecedores e diversos sensores de posição, velocidade, temperatura, corrente, tensão, pressão, força, Hall, proximidade, encoder, aceleração e outras grandezas.

### Mecânica

Os modelos incluem massa, força, torque, posição, velocidade, aceleração, gravidade, tração, atrito estático/cinético, resistência ao rolamento, transmissão mecânica, carga e movimento.

### Térmica e materiais

A biblioteca inclui propriedades de materiais como aço, ferro, inox, alumínio, cobre, latão, bronze, titânio, ouro, prata, chumbo, ABS, PLA, PETG, nylon, PVC, PTFE, acrílico, vidro, borracha, silicone, FR-4, silício, cerâmica e madeira.

As propriedades podem participar de cálculos de massa, elasticidade, transferência térmica, expansão e comportamento elétrico.

### Eletromagnetismo

Existem modelos para bobinas, núcleos magnéticos, ímãs permanentes, campo magnético, fluxo, indutância, indução de Faraday, força magnética, efeito Hall e acoplamento entre bobinas.

### Energia

A simulação possui modelos de baterias, painéis solares e combustíveis, permitindo estudar armazenamento, consumo e fornecimento de energia em nível de sistema.

### Degradação e falhas

Também estão sendo modelados fenômenos que normalmente não aparecem em uma simulação puramente ideal, como:

- curto-circuito;
- sobrecorrente;
- aquecimento por efeito Joule;
- atuação de fusível/proteção;
- corrosão;
- oxidação;
- degradação de propriedades ao longo do tempo.

Use o **MultiPhysics** quando quiser responder perguntas como: **“o que acontece fisicamente com este projeto quando ele é ligado?”**

> O MultiPhysics está em desenvolvimento. A existência de um componente na biblioteca não significa que ele já esteja completamente acoplado ao solver geral. Os resultados atuais são experimentais e não substituem ferramentas certificadas, ensaios físicos ou cálculos de segurança.

---

## 4. Ferramentas de projeto mecânico

As ferramentas mecânicas são destinadas à criação e preparação de **peças e conjuntos**.

A proposta é aproximar o fluxo de trabalho de ferramentas CAD mecânicas: criar a geometria, definir dimensões e materiais, organizar peças e posteriormente utilizar essas informações na fabricação ou simulação.

Use essas ferramentas quando o trabalho começar pela **peça mecânica ou pela montagem física**.

---

## 5. Ferramentas de PCB e eletrônica

Esse conjunto é voltado ao desenvolvimento de **circuitos e placas eletrônicas**.

A finalidade é permitir organizar componentes, ligações elétricas e PCB, aproximando o fluxo de ferramentas tradicionais de projeto eletrônico.

Os projetos eletrônicos podem posteriormente participar da montagem eletromecânica e da simulação MultiPhysics.

Use essas ferramentas quando estiver desenvolvendo **uma placa, circuito ou sistema eletrônico**.

---

## 6. Ferramentas Laser

As ferramentas Laser são destinadas à preparação de trabalhos para **corte e gravação a laser**.

O objetivo inclui trabalhar com desenhos, imagens, logos e arte, preparando o conteúdo para posterior geração e execução do trabalho na máquina.

Use essa área quando quiser **criar ou preparar um trabalho para Laser CNC**.

---

## 7. Ferramentas CNC Router / CAM

Essa área é destinada à preparação de trabalhos de **usinagem mecânica**.

O fluxo previsto parte da geometria da peça e das operações desejadas para chegar às trajetórias necessárias à fabricação na Router.

Use essas ferramentas quando quiser **preparar uma peça para ser usinada**.

---

## 8. Montagem eletromecânica

A ferramenta de montagem tem a função de **unir o projeto mecânico e o eletrônico em uma única visualização**.

Ela permite representar no mesmo projeto estruturas, placas, motores, sensores, atuadores, fontes, cabos e outros elementos.

Essa camada é importante porque uma máquina real não é somente mecânica nem somente eletrônica: os dois sistemas trabalham juntos.

Use essa ferramenta quando quiser **visualizar como todo o equipamento será montado fisicamente**.

---

## 9. Central de Testes

A suíte possui programas e rotinas de teste destinados principalmente ao desenvolvimento.

Eles verificam módulos como:

- eletrônica comum;
- lógica digital e potência;
- microcontroladores;
- motores e atuadores;
- materiais;
- energia;
- mecânica;
- eletromagnetismo;
- corrosão e oxidação;
- curto-circuito e outras falhas;
- integração entre subsistemas.

Use a **Central de Testes** quando estiver desenvolvendo o projeto, procurando regressões ou verificando se uma alteração quebrou outra funcionalidade.

---

## Como as aplicações se relacionam

```text
                         MultiSuite
                            |
       +--------------------+--------------------+
       |                    |                    |
       v                    v                    v
 Projeto mecânico      PCB / Eletrônica      Laser / CAM
       |                    |                    |
       +--------------------+--------------------+
                            |
                            v
                  Montagem eletromecânica
                            |
                  +---------+---------+
                  |                   |
                  v                   v
             MultiPhysics          MultiCNC
              simulação          máquina real
```

Um fluxo futuro completo pode ser entendido como:

```text
PROJETAR -> MONTAR -> SIMULAR -> VALIDAR -> FABRICAR / CONTROLAR
```

---

## Segurança

Comandos físicos passam pelo núcleo de segurança. O sistema deve bloquear comandos incompatíveis com o estado da máquina, validar limites e manter parada/cancelamento acessíveis.

Recursos de IA, quando utilizados, **não devem controlar diretamente movimento, laser, spindle ou aquecedores sem passar pelas regras de segurança do núcleo**.

---

## Estado do projeto

O MultiCNC é um projeto em evolução e reúne aplicações em diferentes níveis de maturidade.

Uma funcionalidade pode estar em uma destas etapas:

1. conceito/documentação;
2. modelo ou biblioteca implementada;
3. interface implementada;
4. teste automatizado disponível;
5. integração parcial;
6. integração completa;
7. validação prática em equipamento.

Por isso, consulte também a documentação específica de cada módulo antes de utilizar resultados para decisões de engenharia.

---

## Instalador Windows

A suíte possui empacotamento Inno Setup em `installer/windows`.

O script `build_release.bat` compila as ferramentas antes de gerar o instalador. O workflow **Windows Installer** permite gerar o pacote pelo GitHub Actions e publica o executável como artefato somente quando o processo de build é concluído com sucesso.

---

## Em uma frase

**MultiCNC controla. MultiPhysics simula. As ferramentas de projeto criam e preparam. A montagem une os sistemas. MultiSuite organiza tudo. A Central de Testes valida o desenvolvimento.**
