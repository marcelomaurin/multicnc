# Arquitetura MultiCNC

## Objetivo
Uma aplicação para controlar Router CNC, Laser CNC e Impressora 3D.

## Dependência CHATGPT
A comunicação serial real usa `TAISerialModem` da suíte `marcelomaurin/CHATGPT`, encapsulado por `TChatGPTSerialTransport`.

## Camadas
1. UI/CLI
2. controladores específicos Router/Laser/Printer3D
3. Machine + Safety + Job + ToolPath
4. protocolos GRBL/Marlin
5. transportes CHATGPT Serial/Simulator

## Regra
UI não acessa porta serial diretamente. Drivers não dependem de Forms. Recursos de IA não podem contornar a camada de segurança.

## Fluxo de um comando
UI/Sessão → `TMultiCNCMachine.SendGCode` → `TSafetyValidator.CheckCommand` → fila → envio quando o buffer da controladora permite → `ok`/`error:` liberam a fila. As respostas são interpretadas pelo protocolo (`TMultiCNCProtocolBase`), que informa confirmações, erros, alarmes, estado e posição.

Comandos de tempo real do GRBL (`?`, `!`, `~`, `Ctrl-X`) não entram na fila. O SimuCNC trata esses bytes antes de repassar as linhas ao simulador.

## Estado da primeira versão
Há base para perfis, segurança, jobs, visualização de percurso, simulador, GRBL, Marlin e comandos específicos. Validação em máquinas físicas permanece necessária antes de uso operacional.
