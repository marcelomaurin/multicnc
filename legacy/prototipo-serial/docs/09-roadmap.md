# 09 — Plano de implementação e validação

Atualização: o controlador inicial Lazarus foi implementado com simulador e testes, antecipando partes de M1/M2. A homologação física de M2 continua pendente. Consulte `../OBJETIVO_CONTROLADOR.md` para não interpretar os marcos abaixo como concluídos.

## Sequência de entrega

| Marco | Implementação | Condição de saída |
| --- | --- | --- |
| M0 — Inventário | Modelos, controladores, versões, portas, parâmetros e processos | Matriz dos equipamentos reais preenchida e stack avaliada |
| M1 — Núcleo | Cadastro, persistência, threads, exclusão de portas e simulador serial | Testes concorrentes e falhas isoladas aprovados |
| M2 — Primeiro equipamento | Adaptador do firmware efetivamente disponível, fila e execução | Homologação em bancada de um equipamento |
| M3 — Contrato comum | Pacote, validação, perfis e pós-processamento | Uma aplicação produtora entrega trabalho ao Control |
| M4 — Burn | Editor básico e gravação vetorial/raster | Trabalho de queima validado no laser |
| M5 — PCB | Importação, polaridade, escala e processo confirmado | Placa de referência produzida e avaliada |
| M6 — Slice | Motor selecionado, perfis e prévia de camadas | Impressão de referência via Control homologada |
| M7 — Wood | CAD/CAM 2,5D, ferramentas e passes | Peça de referência no router homologado |
| M8 — Integração | Instaladores, recuperação, diagnósticos e documentação | Operação simultânea validada nas três categorias |

Ordem sugerida, ajustável à disponibilidade física. M6/M7 dependem dos adaptadores específicos, não apenas do adaptador entregue em M2. PCB depende da definição do processo de fabricação. Não há prazo fechado sem inventário, escolha de bibliotecas e dimensionamento da equipe.

## Backlog inicial do Control

1. Definir entidades, estados e esquema do cadastro.
2. Enumerar portas e implementar reserva/exclusão.
3. Criar worker por equipamento com sessões e mensagens correlacionadas.
4. Implementar transporte serial simulado com respostas programáveis.
5. Exercitar fragmentação, atrasos, erros, desconexão e buffers limitados.
6. Implementar o primeiro adaptador e suas capacidades reais.
7. Construir fila, pré-validação, início explícito e registro de execução.
8. Acrescentar pausa/cancelamento apenas com semântica comprovada.
9. Homologar em bancada e publicar perfil com versão e evidências.

## Estratégia de testes

| Nível | Casos essenciais |
| --- | --- |
| Domínio | Transições válidas/inválidas, exclusão de porta, compatibilidade |
| Protocolo | Fragmentação, múltiplas respostas, erro, timeout, reset, reenvio permitido |
| Concorrência | Três workers, uma falhando, nenhuma contaminação de filas |
| Persistência | Reinício durante execução, migração e disco indisponível |
| Pacotes | Hash incorreto, versão desconhecida, caminho malicioso e excesso de tamanho |
| Geometria | Unidades, espelhamento, offset, profundidade e envelope |
| Integração | Cada aplicação exporta e Control aceita/recusa conforme perfil |
| Bancada | Conexão, identificação, preparação, execução, pausa/falha e resultado |

Simulação de protocolo testa comunicação e estados, não comprova segurança mecânica, qualidade de impressão ou resultado de fabricação. Registrar a diferença no relatório de cada marco.

## Definição de pronto

Funcionalidade documentada, comportamento de erro definido, testes pertinentes aprovados, formato versionado e interface em português. Recursos físicos só são anunciados para combinações homologadas. Instalação precisa ser validada em uma máquina limpa antes da distribuição.

## Riscos e respostas

- Protocolos diferentes sob a mesma marca: perfis separados por firmware e versão.
- Abertura serial causando reset: política por perfil e ensaio antes de execução.
- Operações pesadas travando comunicação: processos de cálculo separados e buffers limitados.
- Falsa conclusão por acknowledgment: critério de término específico do adaptador.
- Divergência de escala/origem: metadados explícitos e prévia dimensional.
- Motor/biblioteca sem redistribuição adequada: avaliar licença antes de adoção.
- Escopo excessivo de CAD/CAM: entregar subconjuntos verificáveis por aplicação.
