# MultiPCB roadmap

## Implementado na fundação
- Modelo de projeto, componentes, pinos, pads e nets
- Biblioteca CSV extensível
- Catálogo inicial Arduino/ESP/AVR/RP2040/STM32/PIC e componentes comuns
- Persistência JSON
- ERC/DRC inicial
- Gerber inicial
- Excellon inicial
- G-code de contorno
- Aplicação Lazarus inicial
- Gerber X2 por camada (cobre, máscara, perfil) com netlist embutida e funções de abertura
- Gerber Job (.gbrjob) e Excellon 2 com tabela de ferramentas
- DRC geométrico de clearance (trilha, pad, via, borda)
- Autorouter A* de duas camadas com vias
- Compensação Z bilinear para height-map em grade

## Próximas camadas de engenharia
- Canvas gráfico de esquemático
- Editor gráfico PCB multicamada
- símbolos/footprints geométricos completos
- ratsnest e roteamento interativo
- zonas de cobre
- importação KiCad
- zonas de cobre em Gerber (regiões com alívio térmico)
- isolamento/trilhas para CNC
- integração direta com MultiCNC
- testes automatizados e validação de fabricação

A fundação não deve ser tratada como substituto validado de um EDA de produção até que esses itens sejam concluídos e testados.
