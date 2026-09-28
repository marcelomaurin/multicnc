# 11 — Estado do protótipo existente

Antes da definição detalhada da suíte, foi criado um protótipo Node.js com painel no navegador. Ele permanece na raiz para referência e experimentação. Não é a implementação do controlador serial proposto.

## O que existe

- `server.mjs`: serviço local, cadastro em arquivo JSON, simulação e recepção TCP.
- `index.html`: painel em português com cartões por equipamento.
- `server.test.mjs`: validação, ciclo de simulação, persistência e restrição de operações.
- `package.json`: inicialização e testes, sem dependências externas.

Requer Node.js 22+. Executar `npm start` e abrir `http://127.0.0.1:3210`; executar `npm test` para as verificações existentes.

## Limitações

Simulação conta linhas de G-code sem interpretar movimentos. Não implementa threads seriais, adaptadores de firmware, CAM ou fatiamento. TCP apenas recebe dados; não identifica protocolo nem envia comandos. Desconectar não para um equipamento que já esteja operando.

Cadastros ficam em `data/machines.json`; trabalhos simulados não persistem. Não há autenticação e o serviço deve permanecer local. Os testes existentes não verificam hardware ou a futura arquitetura desktop.

## Transição prevista

Usar o painel como referência de fluxo, sem acoplar o novo domínio ao serviço atual. Implementar a estrutura alvo em novos módulos e retirar o TCP do produto final. Quando o Control serial estiver utilizável, mover o protótipo para uma pasta de exemplos ou removê-lo em alteração própria, atualizando as instruções de execução.

O controlador Lazarus foi acrescentado em `apps/control/`, com código de comunicação serial e gráfico. Sua implementação e limitações estão em `OBJETIVO_CONTROLADOR.md`; nenhuma máquina física foi homologada. O protótipo Node.js continua inalterado.
