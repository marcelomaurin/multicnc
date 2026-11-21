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
MultiCAD fornece geometria/pecas. MakePCB fornece placas. MultiAssembly define montagem, motores, drivers, fontes, sensores e relacoes. MultiCAM usa a geometria para fabricar. MultiCNC usa o perfil eletromecanico para simulacao e controle.

Valores da demonstracao sao ilustrativos e nao devem ser usados como configuracao de seguranca ou potencia de uma maquina real.

## Geometria realista e união de peças

- **Vista 3D realista:** cada componente da biblioteca traz um bloco `geometry`
  (ver [models/components/README.md](../models/components/README.md)); peças sem
  geometria recebem uma forma gerada pelo tipo.
- **Unir Peças** (barra da vista, botão *Unir Peças*, ou aba Montagem), no estilo
  do SolidWorks Composer: clique na face, furo ou eixo da peça que vai se mover e
  depois na referência da outra peça. A união é sugerida pelo par escolhido:
  - **Inserir** (concêntrico + coincidente): face circular com face circular/furo
    — motor no suporte, parafuso no furo;
  - **Concêntrico:** eixo/furo com eixo/furo;
  - **Coincidente / Distância:** face plana com face plana;
  - **Paralelo:** só alinha as direções.

  Atalhos na prévia: `Enter` confirma, `F` inverte o lado, `R`/`Shift+R` gira
  ±90° em torno do eixo, `I`/`O`/`C`/`D`/`P` trocam o tipo, `+`/`-` ajustam a
  distância (Shift = 10 mm), `Esc` cancela. A relação guarda as referências
  (`ref_a`, `ref_b`) no projeto e o solver a reaplica quando a peça de
  referência se move.

## Engenharia (multiassembly_engineering)
- **ERC eletromecânico**: drivers sem STEP/DIR/VMOT/motor, motores sem acionamento, sinais em portas de tipo errado, tensões incompatíveis, alimentação em curto com o terra, E-stop ausente ou desligado, componentes soltos e IDs inexistentes. O tipo da porta é inferido pelo nome quando o componente não declara portas.
- **BOM** agrupada em CSV e JSON.
- **Firmware a partir da cinemática**: passos/mm por fuso, correia ou relação direta, velocidade máxima pela rotação útil do motor e curso pela estrutura; gera `$100`–`$132` (Grbl/grblHAL) e o bloco `axes` do YAML do FluidNC.

## Requisitos e plano de desenvolvimento

O plano do MultiAssembly usa o SolidWorks como referência funcional e mantém o
layout da MultiSuite. Define montagem 3D e relações, biblioteca de fixadores,
rolamentos e motores DC/AC, listagem de peças e elaboração de manual de montagem
ilustrado, com fases e critérios de aceite.

Consulte [docs/TAREFA.md](docs/TAREFA.md). Os requisitos novos estão documentados
para implementação; a interface atual continua sendo demonstrativa.
