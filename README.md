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
Protocol Drivers
 |-- GRBL
 |-- Marlin
 |-- futuros: FluidNC / grblHAL
 |
Transport
 |-- Serial
 |-- TCP/IP
 |-- Simulator
```

### Regra fundamental

Tipo de máquina, protocolo e transporte são independentes. Por exemplo, Router e Laser podem utilizar GRBL, enquanto diferentes máquinas podem utilizar Serial, TCP/IP ou simulador.

Use o **MultiCNC** quando o objetivo final for **controlar ou operar uma máquina**.

### SimuCNC e porta serial virtual

O **SimuCNC** é uma aplicação separada. Ele funciona como uma impressora 3D com
firmware Marlin: recebe comandos pela serial, responde aos comandos e apresenta
os movimentos e a peça em uma visualização 3D. O MultiCNC continua sendo o
cliente/controlador que se conecta ao equipamento.

Para usar o SimuCNC com o MultiCNC no Windows, é obrigatório instalar um driver
de par de portas seriais virtuais. O componente suportado pelo projeto é o
**com0com**. Ele cria duas pontas da mesma ligação, por exemplo:

```text
MultiCNC  -> COM3  <->  COM4 <- SimuCNC
```

O SimuCNC abre uma ponta e o MultiCNC abre a outra. As duas portas não
representam duas máquinas; são as duas extremidades da mesma porta virtual.

#### Instalação do com0com

1. Baixe o instalador assinado para Windows no [SourceForge do com0com](https://sourceforge.net/projects/com0com/files/com0com/3.0.0.0/).
2. Execute o instalador como administrador.
3. No SimuCNC, informe o caminho do `setupc.exe` instalado. Normalmente:
   `C:\Program Files\com0com\setupc.exe`.
4. Informe as portas, por exemplo `COM4` para o SimuCNC e `COM3` para o MultiCNC.
5. Clique em **Criar par virtual** no SimuCNC.
6. Clique em **Iniciar Marlin** no SimuCNC e conecte o MultiCNC na outra porta.

O driver com0com é um requisito obrigatório para o modo serial do SimuCNC; sem
ele o Windows não possui uma porta virtual que possa ser aberta pelo MultiCNC.
No Windows 11, Secure Boot e as políticas de assinatura podem bloquear versões
antigas do driver. Se as portas não aparecerem no Gerenciador de Dispositivos,
verifique o status do driver antes de configurar o SimuCNC.

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
