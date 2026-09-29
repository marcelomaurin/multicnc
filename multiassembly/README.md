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
