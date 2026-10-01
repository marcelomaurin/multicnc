# MultiAssembly

Ambiente eletromecanico da suite MultiCNC.

## Objetivo
Unificar componentes mecanicos e eletricos em um mesmo projeto. Um componente possui um ID unico e pode aparecer simultaneamente na montagem mecanica e no esquema eletrico.

## Primeira versao
- modelo de componentes e portas;
- posicao/rotacao/tamanho mecanico;
- conexoes eletricas;
- relacoes mecanicas;
- biblioteca basica;
- duas vistas sincronizadas;
- CNC Router de demonstracao;
- projeto Lazarus independente.

## Integracao prevista
MultiCAD fornece geometria/pecas. MultiPCB fornece placas. MultiAssembly define montagem, motores, drivers, fontes, sensores e relacoes. MultiCAM usa a geometria para fabricar. MultiCNC usa o perfil eletromecanico para simulacao e controle.

Valores da demonstracao sao ilustrativos e nao devem ser usados como configuracao de seguranca ou potencia de uma maquina real.

## Engenharia (multiassembly_engineering)
- **ERC eletromecânico**: drivers sem STEP/DIR/VMOT/motor, motores sem acionamento, sinais em portas de tipo errado, tensões incompatíveis, alimentação em curto com o terra, E-stop ausente ou desligado, componentes soltos e IDs inexistentes. O tipo da porta é inferido pelo nome quando o componente não declara portas.
- **BOM** agrupada em CSV e JSON.
- **Firmware a partir da cinemática**: passos/mm por fuso, correia ou relação direta, velocidade máxima pela rotação útil do motor e curso pela estrutura; gera `$100`–`$132` (Grbl/grblHAL) e o bloco `axes` do YAML do FluidNC.
