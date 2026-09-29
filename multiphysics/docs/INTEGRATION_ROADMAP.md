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
- teste CNC X=100 mm.\n- runtime CNC independente para X/Y/Z e spindle;\n- instrumentacao por eixo;\n- injecao de circuito aberto, curto, eixo travado, sensor e fim de curso;\n- integracao inicial na interface MultiPhysics.
- scheduler por fases eletrica, controle, atuadores, mecanica, termica, sensores e protecao;
- instrumentos e gravador CSV;
- interface de cargas runtime -> solver FEM/CFD;
- CNC virtual de referencia.
- exportacao da netlist real TPCBProject do MultiPCB;
- merge por ID/refdes entre MultiPCB e MultiAssembly;
- importacao do contrato unificado para o grafo MultiPhysics.

## MultiPCB
A integracao deve exportar a netlist real do modelo do MultiPCB para o contrato unificado. Nao criar uma segunda copia do esquema. O ID/refdes deve ser preservado.

## MultiAssembly
As relacoes mecanicas sao exportadas como links rotacionais ou lineares. O proximo refinamento e mapear ratio/pitch e propriedades de inercia para os links.

## Modelos ainda necessarios
- integrar diodo/MOSFET diretamente na iteracao global MNA; co-simulacao SPICE;
- spindle parametrizado, correia/polia e juntas multi-corpo;
- fim de curso discreto por posicao;
- curto e circuito aberto por net;
- sobrecorrente/sobretemperatura com protecoes;
- co-simulacao SPICE;
- malha FEM e CFD reais.

Nenhum desses itens deve ser marcado como fisicamente validado sem benchmark ou ensaio.
