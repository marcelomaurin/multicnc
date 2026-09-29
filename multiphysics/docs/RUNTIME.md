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

## Limites
Nao e SPICE. Nao simula semicondutores em nivel fisico.
Nao e FEM transitorio.
Nao substitui modelos de motores reais sem parametrizacao.
Resultados permanecem de fidelidade ESTIMATIVA ate validacao.

## Evolucao
- grafo de componentes e nets importado do MultiPCB;
- fontes, resistores, capacitores, indutores, diodos, MOSFETs, relés;
- stepper, servo, BLDC, spindle;
- engrenagem, correia, fuso, mola, amortecedor e junta;
- sensores fim de curso, encoder, temperatura, corrente e pressao;
- falhas: circuito aberto, curto, motor travado, sobrecorrente, sobretemperatura;
- co-simulacao SPICE;
- cargas FEM/CFD devolvidas ao runtime.
