# Integracao executavel da suite

## Implementado
- contrato de ID unico e componente compartilhado;
- dominios eletrico, eletronico, mecanico, termico, sensor e controle;
- exportador MultiAssembly -> contrato unificado;
- grafo executavel MultiPhysics;
- fonte, driver PWM, motor DC, carga/eixo, sensor e controlador;
- runtime eletrico -> mecanico -> termico -> sensor -> controle;
- falhas basicas;
- modelos reduzidos R/C/L, diodo, MOSFET e rele;
- stepper, servo e BLDC;
- engrenagem, fuso e mola/amortecedor;
- CNC stepper de referencia;
- solver MNA linear para redes DC;
- modelos companheiros transitorios para capacitor e indutor;
- modelos reduzidos nao lineares de diodo e MOSFET;
- scheduler executando stepper, servo, BLDC, engrenagem e fuso;
- comando de eixo por posicao em mm;
- fim de curso por posicao;
- perda de passo quando torque de carga excede torque disponivel;
- protecao por sobrecorrente e sobretemperatura;
- teste CNC X=100 mm.\n- runtime CNC independente para X/Y/Z e spindle;\n- instrumentacao por eixo;\n- injecao de circuito aberto, curto, eixo travado, sensor e fim de curso;\n- integracao inicial na interface MultiPhysics.\n- biblioteca comum: LED, Zener, Schottky, ponte retificadora, BJT NPN/PNP, chave, potenciometro, fusivel, bateria, fonte AC, transformador, LDO, op-amp e comparador.\n- logica digital: AND/OR/NOT/NAND/NOR/XOR, flip-flop e 555;\n- conversao: ADC, DAC e optoacoplador;\n- potencia: SCR, TRIAC, IGBT, buck, boost e ponte H;\n- acionamento: driver STEP/DIR com VMOT, enable e fases A/B.\n- MCU virtual orientado a perifericos;\n- perfis ATmega328P/Arduino Uno, ESP32, RP2040, STM32 e MCU generico;\n- GPIO, ADC, PWM e inventario UART/SPI/I2C;\n- RAM, ROM, EEPROM e clock como componentes;\n- executor simples de programa/eventos de perifericos;\n- teste ESP32 gerando 200 pulsos STEP/DIR.
- scheduler por fases eletrica, controle, atuadores, mecanica, termica, sensores e protecao;
- instrumentos e gravador CSV;
- interface de cargas runtime -> solver FEM/CFD;
- CNC virtual de referencia.
- contrato eletrico unificado independente do editor de placas;
- importacao da montagem e complemento dos dominios no contrato unificado;
- importacao do contrato unificado para o grafo MultiPhysics.

## Solver de circuitos e integradores
- `multiphysics_circuit_newton`: MNA com Newton-Raphson global, limitacao de juncao (pnjlim), gmin stepping, source stepping, transitorio trapezoidal ou Euler implicito, fontes senoidais, diodo e NMOS nivel 1.
- `multiphysics_ode`: RK4, Dormand-Prince 5(4) adaptativo com FSAL, Velocity Verlet e Euler simpletico.

## MakePCB (integracao futura)
O exportador de componentes e redes do MakePCB para o contrato unificado ainda precisa ser implementado. Preservar ID/refdes sem criar uma segunda copia do esquema.

## MultiAssembly
As relacoes mecanicas sao exportadas como links rotacionais ou lineares. O proximo refinamento e mapear ratio/pitch e propriedades de inercia para os links.

## Modelos ainda necessarios
- co-simulacao SPICE (diodo/MOSFET ja estao na iteracao global: multiphysics_circuit_newton);
- spindle parametrizado, correia/polia e juntas multi-corpo;
- fim de curso discreto por posicao;
- curto e circuito aberto por net;
- sobrecorrente/sobretemperatura com protecoes;
- co-simulacao SPICE;
- malha FEM e CFD reais.

Nenhum desses itens deve ser marcado como fisicamente validado sem benchmark ou ensaio.

## Biblioteca fisica
- atuadores: solenoide, atuador linear, eletroima, ventilador, bomba e aquecedor;
- motores: DC, stepper, servo, BLDC e AC;
- sensores: velocidade, posicao, fim de curso, corrente, tensao, temperatura, pressao, forca, celula de carga, Hall, proximidade, foto, ultrassom, encoder, acelerometro, giroscopio e umidade;
- emissores: LED, laser, lampada e buzzer;
- resistivos: resistor, potenciometro, NTC, PTC, LDR, strain gauge e resistencia aquecedora.
Modelos sao reduzidos e destinados a simulacao de sistema; nao substituem modelos SPICE/FEM calibrados.

## Energia, combustiveis e substancias
- combustiveis: gasolina, diesel, etanol, GLP e hidrogenio com densidade e poder calorifico;
- baterias: chumbo-acido, Li-ion, LiFePO4 e NiMH com SOC, capacidade, resistencia interna e limites de corrente;
- solar: painel fotovoltaico com potencia nominal, irradiancia e coeficiente de temperatura;
- quimicos de referencia: agua, etanol, alcool isopropilico, acetona, NaCl e HCl aquoso;
- classificacao basica de perigo para uso na simulacao e interface;
- reservatorios de combustivel e substancias no grafo.
Os modelos sao de engenharia de sistema e nao modelam sintese ou cinetica de reacoes perigosas.

## Degradacao e falhas dependentes do tempo
- corrosao ambiental: temperatura, umidade, oxigenio, cloretos e acidez como fatores de aceleracao;
- perda de espessura e integridade com aumento da resistividade efetiva;
- oxidacao: crescimento simplificado de camada de oxido dependente de temperatura e oxigenio;
- curto-circuito persistente: resistencia de falha, corrente, I2R, energia e temperatura;
- protecao: limite de corrente, atraso de disparo e acumulacao I2t de fusivel;
- estado de dano quando a temperatura de falha excede o limite simplificado.
Modelos sao reduzidos para simulacao de sistema e precisam de calibracao experimental para previsao quantitativa.
