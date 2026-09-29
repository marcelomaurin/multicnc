# MultiCNC Core

Núcleo independente da interface gráfica.

## Unidades

- `multicnc_types.pas`: tipos, estados, eixos, posição e capacidades.
- `multicnc_interfaces.pas`: contratos de transporte, protocolo e máquina.
- `multicnc_machine.pas`: implementação base que conecta os contratos.

A UI nunca deve acessar Serial/USB/TCP diretamente. Protocolos como GRBL e Marlin também não devem acessar Forms.

Este núcleo é a base para os transportes, simulador e drivers das próximas tarefas.
