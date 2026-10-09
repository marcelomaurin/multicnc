# 10 — Decisões e pontos em aberto

## Decisões de escopo informadas pelo usuário

| ID | Decisão | Consequência |
| --- | --- | --- |
| D01 | Um controlador comum | Nenhuma aplicação de preparação acessa equipamentos diretamente |
| D02 | Uma thread por equipamento | Propriedade exclusiva da serial e estados independentes |
| D03 | Somente serial | TCP do protótipo não integra a arquitetura alvo |
| D04 | Seleção de porta, tipo, marca e modelo | Cadastro explícito e persistente |
| D05 | Fatiador 3D específico | Aplicação Slice separada |
| D06 | PCB e queima em aplicações distintas | Aplicações PCB e Burn separadas |
| D07 | Desenvolvimento de peças de madeira próprio | Aplicação Wood separada |
| D08 | Controlador em Lazarus | Object Pascal/LCL; substitui sugestão C++/Qt |
| D09 | Gráfico vetorial por equipamento | Amostras de posição e qualidade da informação explícitas |

## Propostas técnicas desta documentação

| ID | Proposta | Situação |
| --- | --- | --- |
| P01 | Lazarus/Object Pascal no controlador | Decisão do usuário implementada; outras aplicações a definir |
| P02 | SQLite e arquivos para armazenamento futuro | MVP do cadastro usa INI com backup |
| P03 | Pacote `.mcncjob` e importação antes de IPC | Contrato conceitual; esquema executável em M3 |
| P04 | Integrar motor de fatiamento existente | Seleção técnica e de licença pendente |
| P05 | FDM/FFF inicialmente | Confirmar tecnologia da impressora |
| P06 | PCB por remoção de máscara inicialmente | Confirmar processo e laser disponível |
| P07 | Router 2D/2,5D inicialmente | Confirmar necessidades de superfícies 3D |
| P08 | Windows inicial | Confirmar necessidade de Linux/macOS |

## Informações necessárias para implementar os adaptadores

Preencher uma linha por equipamento; não inferir firmware pela marca.

| Equipamento | Marca/modelo | Placa/controlador | Firmware/versão | Porta/baud/parâmetros | Dimensões e recursos |
| --- | --- | --- | --- | --- | --- |
| CNC laser | A informar | A informar | A informar | A informar | A informar |
| CNC router | A informar | A informar | A informar | A informar | A informar |
| Impressora 3D | A informar | A informar | A informar | A informar | A informar |

Também confirmar: tipo/potência do laser e processo de PCB; tecnologia da impressora; quantidade máxima de equipamentos simultâneos; recursos de pausa/alarme; troca de ferramenta; prioridade entre as quatro aplicações de preparação.

## Política de revisão

Alterações de arquitetura devem registrar contexto, decisão e impacto neste documento ou em ADR próprio. Atualizar contratos e testes junto com mudanças que afetem integração. A documentação descreve propostas; apenas validação e código entregues podem promover um recurso a implementado.
