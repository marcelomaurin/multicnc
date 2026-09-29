# MultiCNC

Plataforma desktop unificada para controle de máquinas de fabricação digital.

## Objetivo

O MultiCNC terá uma única interface capaz de conectar, configurar, monitorar e controlar:

- CNC Router
- Laser CNC
- Impressora 3D

A aplicação separa quatro conceitos: tipo de máquina, protocolo/firmware, transporte e execução de G-code.

## Arquitetura

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
 |-- TCP/IP (futuro)
 |-- Simulator
```

### Tipos de máquina

- Router: XYZ, spindle, RPM, probe, zero da peça, ferramentas.
- Laser: XY, potência, velocidade, frame, foco e air assist quando suportado.
- Impressora 3D: XYZ, hotend, mesa, extrusor, fan e temperaturas.

### Regra fundamental

Tipo de máquina, protocolo e transporte são independentes. Exemplo: Router e Laser podem usar GRBL; diferentes máquinas podem usar Serial ou TCP/IP.

## Primeira versão

1. Núcleo independente da interface.
2. Perfis de máquina.
3. Transporte Serial.
4. Simulador.
5. Driver GRBL.
6. Driver Marlin.
7. Console e executor de G-code.
8. Jog/Home/Zero.
9. Controles específicos por tipo.
10. Monitoramento, pausa, retomada, cancelamento e emergência.
11. Validações e limites de segurança.
12. Visualização do trabalho.

## Segurança

Comandos físicos passam pelo núcleo de segurança. O sistema deve bloquear comandos incompatíveis com o estado da máquina, validar limites e manter parada/cancelamento acessíveis. Recursos de IA, se adicionados, não devem controlar diretamente movimento, laser, spindle ou aquecedores.

## Evolução

Após o controle direto estar estável, poderão ser adicionados importação/conversão, integração com CAM/slicer, macros, descoberta automática de capacidades, FluidNC/grblHAL e assistência por IA.


## Instalador Windows
A suite possui empacotamento Inno Setup em `installer/windows`. O script `build_release.bat` compila todas as ferramentas antes de gerar o instalador. O workflow `Windows Installer` permite gerar o pacote no GitHub Actions e publica o EXE como artefato somente se todo o build for concluido com sucesso.
