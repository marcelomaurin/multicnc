# MultiCNC

Suíte local para preparar e executar trabalhos em CNC laser, CNC router e impressora 3D, com um controlador comum e conexão **exclusivamente serial** com os equipamentos.

## Aplicações propostas

| Aplicação | Responsabilidade |
| --- | --- |
| MultiCNC Control | Cadastro, conexão serial, uma thread por equipamento, filas e execução |
| MultiCNC Slice | Preparação e fatiamento de peças para impressão 3D |
| MultiCNC PCB | Preparação de placas de circuito para fabricação com laser |
| MultiCNC Burn | Desenho e preparação de gravação/queima a laser |
| MultiCNC Wood | Projeto de peças de madeira e geração de trajetórias para router |

As quatro aplicações de preparação não abrem portas seriais. Elas entregam trabalhos ao Control, que valida o perfil e executa na máquina selecionada.

## Documentação do projeto

1. [Proposta e escopo](docs/01-proposta.md)
2. [Arquitetura e threads](docs/02-arquitetura.md)
3. [Controlador serial](docs/03-controlador.md)
4. [Fatiador 3D](docs/04-slice.md)
5. [PCB a laser](docs/05-pcb.md)
6. [Gravação e queima](docs/06-burn.md)
7. [Router para madeira](docs/07-wood.md)
8. [Contratos e dados compartilhados](docs/08-contratos.md)
9. [Plano de implementação e validação](docs/09-roadmap.md)
10. [Decisões e pontos em aberto](docs/10-decisoes.md)
11. [Estado do protótipo existente](docs/11-prototipo.md)
12. [Modelos pesquisados e protocolos](docs/12-modelos-e-protocolos.md)
13. [Controlador Lazarus: uso e compilação](docs/13-controlador-lazarus.md)

## Controlador Lazarus

O desenvolvimento começa pelo **MultiCNC Control**, em Lazarus/Object Pascal. Abra `apps/control/multicnc.lpi`. Compile pelo Lazarus ou execute `apps/control/build.ps1 -Test` no PowerShell. O executável é gerado em `apps/control/bin/multicnc.exe`.

Há cadastro serial de marca/modelo, uma thread por equipamento, abas com gráfico vetorial XY/XZ/YZ, simulador, monitoramento GRBL/Marlin e envio linear limitado para GRBL 1.1. Não houve homologação em máquinas físicas.

**Documento vivo para continuidade:** [OBJETIVO_CONTROLADOR.md](OBJETIVO_CONTROLADOR.md). Agentes devem lê-lo e atualizá-lo junto das alterações, conforme [AGENTS.md](AGENTS.md).

## Estado atual

Esta revisão entrega a proposta da suíte e a primeira implementação do controlador Lazarus. As quatro aplicações de preparação continuam planejadas. O estado exato e as limitações do controlador estão no documento vivo. Os arquivos Node.js na raiz são um protótipo anterior, com simulação e recepção TCP, que **não atende à arquitetura serial definida nesta proposta**. Seu comportamento foi preservado.

Para experimentar esse protótipo: Node.js 22+, `npm start`, endereço `http://127.0.0.1:3210`. Verificações: `npm test`. Veja suas limitações antes de utilizá-lo em [Estado do protótipo](docs/11-prototipo.md).
