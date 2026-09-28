# 12 — Pesquisa de modelos e protocolos

Pesquisa realizada em 2026-09-28. A seleção cobre famílias conhecidas de equipamentos de bancada e suas interfaces documentadas; **não é um ranking de vendas nem uma lista exaustiva do mercado**. Placa ou firmware substituídos podem alterar completamente a compatibilidade.

## Catálogo inicial

| Categoria | Marca/modelo de referência | Evidência e interpretação | Situação no MultiCNC |
| --- | --- | --- | --- |
| Router | SainSmart Genmitsu 3018-PRO | Fabricante fornece firmware GRBL para a família | Perfil GRBL inicial; não homologado |
| Router | SainSmart Genmitsu 3018-PROVer | Documentação do fabricante descreve software e firmware GRBL | Perfil GRBL inicial; modelo antigo, não homologado |
| Router | SainSmart Genmitsu 4040-PRO | Guia do fabricante descreve operação GRBL | Perfil GRBL inicial; não homologado |
| Laser | SCULPFUN S9 | Fabricante disponibiliza firmware e software para a família | Perfil GRBL candidato; confirmar revisão da placa |
| Laser | SCULPFUN S30 | Documentação de suporte e processo com GRBL | Perfil GRBL candidato; confirmar variante |
| Laser | ORTUR Laser Master 2 | Suporte oficial lista LaserGRBL | Perfil candidato; equivalência completa de protocolo ainda depende de identificação e bancada |
| Laser | xTool D1 Pro | Fabricante descreve controlador baseado em G-code GRBL | Perfil candidato; possíveis particularidades do fabricante |
| Impressora 3D | Creality Ender-3 original | Repositório oficial contém firmware Marlin | Monitoramento Marlin inicial; não estender automaticamente a todas as Ender |
| Impressora 3D | Prusa i3 MK3S / MK3S+ | Fabricante documenta uso por serial USB/Pronterface | Monitoramento candidato; firmware derivado com particularidades |

Todos os perfis sugerem baud inicial editável; o catálogo não certifica baud, dimensões, potência ou opções do firmware. O aplicativo exige reconhecimento do protocolo e não usa apenas o nome comercial para liberar operação.

## Como os protocolos entram na implementação

**GRBL 1.1:** foi implementada identificação, leitura de relatórios de posição/estado, controle de fluxo por confirmação de linha e comandos de pausa/retomada/reset. A referência oficial define mensagens de estado e comandos em tempo real. [Interface oficial GRBL](https://github.com/gnea/grbl/blob/master/doc/markdown/interface.md).

**Marlin:** `M115` identifica firmware/capacidades; nesta etapa, o aplicativo reconhece a família e monitora posição. [M115 oficial](https://marlinfw.org/docs/gcode/M115.html).

**Posição Marlin:** a consulta comum pode retornar destino projetado. A variante `M114 R` depende de recurso compilado no firmware, por isso é configuração explícita, sem detecção automática presumida. [M114 oficial](https://marlinfw.org/docs/gcode/M114.html).

## Fontes oficiais dos modelos

1. [Genmitsu 3018-PRO/PROVer: firmware oficial](https://docs.sainsmart.com/article/zn73h7h6b6-uploading-firmware-on-a-sain-smart-cnc-controller).
2. [Genmitsu 3018-PROVer: central de recursos](https://docs.sainsmart.com/article/x6sr565m5g-3018-prover).
3. [Genmitsu 4040-PRO: configuração](https://www.sainsmart.com/blogs/news/setting-up-the-genmitsu-4040-pro).
4. [SCULPFUN: downloads oficiais no Brasil](https://br.sculpfun.com/pages/centro-de-downloads).
5. [SCULPFUN: guia de parâmetros e GRBL](https://www.sculpfun.com/blogs/blog/settings-guide).
6. [ORTUR: suporte OLM2](https://orturtech.com/pages/olm2-support).
7. [xTool: D1 Pro com LightBurn e GRBL](https://uk.xtool.com/blogs/how-to/lightburn-software-manual).
8. [Creality: Ender-3 e firmware](https://github.com/Creality3DPrinting/Ender-3).
9. [Prusa: USB e Pronterface, incluindo MK3S/MK3S+](https://help.prusa3d.com/article/pronterface-and-usb-cable_2222?product=mk3s-2).

## Famílias que não devem ser tratadas como GRBL/Marlin genéricos

- **Klipper:** sua comunicação host–microcontrolador usa um protocolo próprio; não enviar G-code textual diretamente à serial da MCU. Fora desta primeira implementação. [Protocolo oficial](https://www.klipper3d.org/Protocol.html).
- **Smoothieware/Smoothieboard:** há interface serial e aplicação em laser, mas exigiria adaptador próprio e homologação; não está no catálogo executável inicial. [Guia oficial](https://smoothieware.org/laser-cutter-guide).
- Equipamentos com controladores proprietários ou outra interface: dependem de documentação e identificação exatas. A presença de USB não comprova que exista porta serial com protocolo compatível.

## Registro de homologação a preencher

Para cada equipamento: marca/modelo, revisão de placa, firmware/versão, driver, porta, baud, 8N1, efeitos de DTR/RTS, unidade/referencial do relatório, amostras de identificação, testes de estados, resultado e data. Nenhuma linha deste registro foi preenchida como aprovada em hardware nesta revisão.
