# MultiPCB - Guia para IA

## Missao
MultiPCB e a ferramenta EDA da suite para esquematico e placa de circuito impresso.

## O que pertence aqui
Componentes e bibliotecas, esquematico, netlist, board, ratsnest, roteamento, DRC, regras eletricas/geometricas, posicionamento para fabricacao e exportacao Gerber/Excellon/G-code quando aplicavel ao processo PCB.

## Estrutura atual
- src/core/: modelo, tipos, regras, biblioteca e IO.
- src/eda/: board, schematic, netlist, router, ratsnest e DRC.
- src/positioning/: fixture, alinhamento, heightmap, probe plan e compensacao Z.
- src/export/: Gerber, Excellon e G-code.
- src/ui/: canvas de placa/esquematico/posicionamento.
- docs/: compensacao Z, heightmap e posicionamento CNC.
- tests/: EDA, routing, alinhamento e Z compensation.

## Entradas e saidas
Entrada: projeto eletronico e bibliotecas.
Saida: placa, netlist, dados de componentes e arquivos de fabricacao.

## Integracao
MultiAssembly pode incorporar a PCB como componente fisico e usar seus conectores/netlist. LaserPCB pode receber dados para fabricacao laser. O MakePCB (`makepcb/`) e o editor de placa simples, estilo PCB Wizard, que gera Gerber + Excellon direto para o LaserPCB; os dois nao compartilham formato de arquivo. A fresagem de PCB na router (isolacao, furacao, recorte, heightmap) sera do RouterPCB (`routerpcb/`, planejado); o heightmap/compensacao de `src/positioning` e um esboco que deve convergir para a versao do RouterPCB. MultiCNC executa o trabalho fisico.

## Nao pertence aqui
Montagem completa da maquina, dinamica de motores, controle serial da CNC ou modelagem mecanica geral.

## Regra importante
Nao confundir conexao eletrica do circuito projetado com o cabeamento eletromecanico do equipamento. O primeiro pertence ao MultiPCB; o segundo ao MultiAssembly.
