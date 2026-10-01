# MultiCNC Core

Núcleo independente da interface gráfica.

## Unidades

- `multicnc_types.pas`: tipos, estados, eixos, posição e capacidades.
- `multicnc_interfaces.pas`: contratos de transporte, protocolo e máquina.
- `multicnc_machine.pas`: implementação base que conecta os contratos.

A UI nunca deve acessar Serial/USB/TCP diretamente. Protocolos como GRBL e Marlin também não devem acessar Forms.

Este núcleo é a base para os transportes, simulador e drivers das próximas tarefas.

## Comunicação com o controlador
- `multicnc_grbl_status`: interpreta status `<...>` (estado, MPos/WPos/WCO, Bf, Ln, FS, Ov, A, Pn), `ok`, `error:N`, `ALARM:N` (com texto) e o banner (Grbl, grblHAL, FluidNC).
- `multicnc_realtime`: bytes de tempo real do Grbl 1.1 e extensões do grblHAL; sequência mínima de overrides de avanço/spindle.
- `multicnc_streamer`: envio por *character-counting*, *send-response* ou Marlin com checksum e `Resend`; erros do controlador interrompem o envio.
- `multicnc_gcode_analyzer`: análise prévia com limites, tempo estimado (planejador com *junction deviation*), arcos e avisos de segurança.
- `multicnc_tcp`: transporte TCP/telnet (FluidNC, grblHAL em rede, pontes serial-TCP).
