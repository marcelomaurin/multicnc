# 01 — Proposta do projeto

## Objetivo

Concentrar a operação de diferentes equipamentos em um controlador comum, preservando aplicações específicas para o trabalho de criação e preparação de cada processo. Cada equipamento terá porta serial, tipo, marca e modelo definidos pelo usuário e será atendido por uma thread própria.

O uso de “ambas” na descrição inicial foi interpretado como controle comum das três categorias: laser, router e impressora 3D, em continuidade ao objetivo original. PCB e queima compartilham a categoria de equipamento laser, mas têm aplicações e parâmetros de fabricação distintos.

## Fluxo principal

1. Cadastrar o equipamento no Control: nome, tipo, marca, modelo, porta e perfil de comunicação.
2. Criar ou importar o projeto na aplicação especializada.
3. Escolher material, processo e perfil compatível; gerar e revisar trajetórias/camadas.
4. Exportar um pacote de trabalho imutável ou encaminhá-lo à caixa de entrada local do Control.
5. No Control, selecionar a máquina de destino e revisar a preparação física e o resumo.
6. Iniciar explicitamente; acompanhar execução, respostas e falhas por equipamento.
7. Registrar resultado e histórico. Reexecução cria uma nova execução do mesmo pacote.

Enviar para a fila não inicia a máquina. Cada equipamento executa no máximo um trabalho por vez; equipamentos distintos podem trabalhar simultaneamente, com estados e filas independentes.

## Limites entre aplicações

| Etapa | Responsável | Resultado |
| --- | --- | --- |
| Preparação geométrica/processo | Slice, PCB, Burn ou Wood | Projeto editável e prévia |
| Geração | Aplicação especializada + pós-processador | Trabalho para um perfil de controlador |
| Compatibilidade e operação | Control | Trabalho validado, selecionado e acompanhado |
| Comunicação | Thread serial + adaptador de protocolo | Comandos e respostas correlacionados |

## Escopo inicial

- Windows como plataforma inicial, a confirmar para futuras distribuições.
- Comunicação física somente serial, incluindo portas seriais apresentadas pelo sistema por USB.
- Cadastro persistente, biblioteca de perfis versionados, histórico e logs por equipamento.
- Interface em português e funcionamento local, sem dependência de conta na nuvem.
- Suporte declarado por combinação de controlador, firmware e versão validada; marca/modelo comercial não bastam para determinar protocolo.
- Aplicações independentes dentro de um único repositório e com componentes comuns.

## Fora da primeira entrega

Conexão de equipamentos por TCP/Wi-Fi, colaboração em nuvem, CAD mecânico paramétrico completo, projeto eletrônico completo de esquemáticos, usinagem simultânea de cinco eixos e retomada automática após falha. Controle remoto da operação também não faz parte do escopo inicial.

## Critérios globais de aceite

- Dois ou mais equipamentos simulados operam simultaneamente sem mistura de comandos ou logs.
- Uma porta serial tem um único proprietário; tentativas de abertura duplicada são rejeitadas.
- A queda de um equipamento não encerra o controlador nem interfere nos demais.
- Trabalho incompatível, perfil desconhecido ou erro de integridade impede o início.
- Nenhuma conexão, importação, reconexão ou inicialização de software provoca movimento ou energização automática.
- As cinco aplicações preservam projetos e conseguem trocar trabalhos pelo contrato documentado.

## Entregáveis

Controlador operacional, quatro aplicações de preparação, componentes compartilhados, catálogo inicial de perfis homologados, instaladores, exemplos, testes automatizados e roteiros de validação em bancada. A homologação física depende do acesso aos equipamentos reais.
