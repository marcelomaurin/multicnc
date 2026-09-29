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
- ampliar MNA para C/L no sistema global e iteracao de dispositivos nao lineares; co-simulacao SPICE;
- spindle parametrizado, correia/polia e juntas multi-corpo;
- fim de curso discreto por posicao;
- curto e circuito aberto por net;
- sobrecorrente/sobretemperatura com protecoes;
- co-simulacao SPICE;
- malha FEM e CFD reais.

Nenhum desses itens deve ser marcado como fisicamente validado sem benchmark ou ensaio.
