# MultiPhysics Simulation Runtime

O runtime executa uma montagem energizada em passos de tempo.

Ordem atual de cada passo:
1. controle le o sensor e calcula PWM;
2. circuito fonte/motor calcula corrente, queda de tensao e torque;
3. eixo/carga calcula aceleracao, velocidade e posicao;
4. perdas I2R alimentam o modelo termico;
5. sensor recebe o novo estado mecanico;
6. relogio avanca.

O primeiro modelo integrado e propositalmente simples e deterministico: fonte DC + motor DC + carga rotacional + PID/PWM + sensor + modelo termico concentrado. Ele prova o acoplamento eletrico -> mecanico -> termico -> sensor -> controle.

Motor DC: com `Inductance > 0` a corrente segue L di/dt = V - R i - Ke w (Euler implicito, estavel para qualquer passo); com 0 a corrente e quase estatica. `Dt` configuravel; com o controle desligado (`ControlEnabled = False`) vale o `ManualPWM` (malha aberta). Controle padrao PI (Kp 0,02, Ki 0,01): a velocidade chega a referencia. Conferido em `tests/test_system_models.lpr` (velocidade final V/Ke e constante de tempo J R/(Kt Ke)).

Maquina CNC: perfil trapezoidal (v <= sqrt(2 a d)), torque do passo a passo caindo com a velocidade ate `NoLoadSpeed`, estol com passos perdidos, homing pelo fim de curso, falhas que mudam o modelo (curto e sobrecorrente desarmam, eixo travado estola, sensor com erro para no lugar errado, fim de curso preso zera errado, corrosao/oxidacao aquecem mais).

Acoplamento com o FEM: `multiphysics_coupling.ApplyRuntimeHeat` leva as perdas I2R do instante para a peca do motor como potencia dissipada (analise termica).

## Agendador multifisico (`multiphysics_scheduler`)
Para grafos com atuadores (passo a passo, servo, BLDC, engrenagem, fuso) o passo e dividido em fases fixas,
nesta ordem: 1 eletrica (MNA), 2 controle, 3 atuadores, 4 mecanica, 5 termica, 6 sensores, 7 protecao.
Cada fase le o estado deixado pela anterior no mesmo passo; sensores e protecao veem o estado ja integrado.

## MCU virtual
Programa sequencial com Delay ou eventos com hora marcada (`AddAt`, `AddPulseTrain`); `StepPulse` gera um
pulso de um passo e conta as bordas por pino. PWM com a resolucao do perfil (ATmega328P 8 bits, ESP32 10,
RP2040/STM32 16) e ADC com a resolucao e a referencia. Teste: `tests/test_mcu_graph.lpr`.

## Validacao do grafo
Erros: grafo vazio, componente ou porta inexistente, tipos de porta diferentes. Avisos: componente sem
ligacao, conexao repetida.

## Limites
Nao e SPICE. Nao simula semicondutores em nivel fisico.
Nao e FEM transitorio.
Nao substitui modelos de motores reais sem parametrizacao.
Resultados permanecem de fidelidade ESTIMATIVA ate validacao.

## Evolucao
- grafo de componentes e conexoes do contrato unificado;
- fontes, resistores, capacitores, indutores, diodos, MOSFETs, relés;
- stepper, servo, BLDC, spindle;
- engrenagem, correia, fuso, mola, amortecedor e junta;
- sensores fim de curso, encoder, temperatura, corrente e pressao;
- falhas: circuito aberto, curto, motor travado, sobrecorrente, sobretemperatura;
- co-simulacao SPICE;
- cargas FEM/CFD devolvidas ao runtime.


## Grafo executavel
A maquina passa a ser descrita por componentes, portas e conexoes tipadas.
Dominios de porta atuais: eletrico, mecanico rotacional, termico e sinal.
Biblioteca inicial: fonte, driver PWM, motor DC, carga/eixo, sensor de velocidade e controlador.
A demonstracao fecha o ciclo PSU -> driver -> motor -> carga e motor -> sensor -> controlador -> driver.

O grafo e a base para importar no futuro a conectividade do MakePCB (integracao ainda pendente) e os vinculos fisicos do MultiAssembly.
