# Objetivo vivo — MultiCNC Control

**Repositório:** `C:\projetos\maurinsoft\multicnc`

**Tecnologia decidida pelo usuário:** Lazarus / Object Pascal / Free Pascal.

**Atualização:** 2026-09-28.

**Documento de continuidade:** ler antes de alterar o controlador; atualizar junto de cada entrega.

## 1. Objetivo do produto

Construir um controlador desktop único para CNC laser, CNC router e impressora 3D. O operador cadastra porta **somente serial**, tipo, marca e modelo. Cada equipamento conectado recebe uma thread independente e uma aba com estados, logs e gráfico vetorial da operação acompanhada.

O controlador é a primeira aplicação da suíte. Fatiamento 3D, PCB a laser, queima e CAD/CAM de madeira permanecem aplicações separadas, detalhadas em `docs/`. Não incluir suas funções dentro do controlador por conveniência.

## 2. Requisitos obrigatórios

- Lazarus com LCL; núcleo em Object Pascal. A proposta anterior de C++/Qt está substituída para o controlador.
- Uma `TThread` por equipamento conectado. A serial pertence exclusivamente à thread.
- Interface nunca escreve diretamente na serial. Solicitações passam por fila; a interface recebe snapshots copiados.
- Cadastro de nome, tipo, marca, modelo, porta e protocolo; marca comercial não determina firmware de modo infalível.
- Apenas serial com equipamentos; simulador é um transporte de teste, não uma conexão TCP.
- Menu curto: equipamentos, operação e ajuda, com botões de acesso direto.
- Gráfico vetorial por equipamento, com XY/XZ/YZ, posição e histórico de amostras.
- Separar estado físico observado, posição informada pelo firmware, posição projetada e simulação. Nunca apresentar avanço do arquivo como prova de movimento executado.

## 3. Estado implementado nesta revisão

| Parte | Situação concreta |
| --- | --- |
| Projeto Lazarus | `apps/control/multicnc.lpi`, compilado Win64 |
| Cadastro | Criar, editar e excluir; modelos pesquisados; porta enumerada/editável |
| Persistência | INI em `%LOCALAPPDATA%\MultiCNC\devices.ini`, com backup `.bak` |
| Serial | Win32 API, abertura exclusiva, 8N1, baud e DTR/RTS configuráveis |
| Concorrência | Worker por aba, fila limitada e snapshots independentes |
| GRBL | Identificação 1.1, consulta de estado, posição, envio linear limitado, hold/resume e reset |
| Marlin/Prusa | Identificação e monitoramento de posição; sem envio de impressão |
| Gráfico | Rastro amostrado, posição atual, projeções XY/XZ/YZ, autoajuste e prévia linear |
| Simulador | Demonstração vetorial e execução simplificada dos pontos importados |
| Testes | 40 verificações aprovadas: parser, persistência, concorrência, GRBL/Marlin falsos e rejeição de firmware desconhecido; captura da janela em modo de teste |
| Hardware | **Nenhuma máquina física homologada nesta revisão** |

Cadastro é persistente. Programa carregado, histórico vetorial e logs são apenas de sessão. Não há fila persistente de trabalhos, banco SQLite, instalador ou migração do protótipo Node.js nesta entrega.

## 4. Parâmetros atuais

### Configuráveis pelo operador

| Parâmetro | Regra/default |
| --- | --- |
| `name`, `kind`, `brand`, `model` | Nome, categoria e identificação comercial |
| `port` | `COMn`; simulador usa identificação livre e não abre porta |
| `protocol` | `grbl`, `marlin` ou `simulator` |
| `baud` | Sugestão inicial 115200; confirmar no firmware; aceita 1200..1000000 |
| `dtr`, `rts` | Desativados por padrão; confirmar efeitos ao abrir a placa |
| `status_inches` | GRBL: marcar se `$13=1`; converte relatório para mm |
| `marlin_realtime` | Desmarcado; marcar apenas após comprovar suporte a `M114 R` |

Baud sugerido não é especificação universal dos modelos. 8N1 e ausência de controle de fluxo são as únicas opções implementadas. Não alterar configurações persistentes do firmware automaticamente.

### Constantes da implementação

- GRBL: consulta a cada 250 ms; Marlin: consulta a cada 1 s, sem sobrepor solicitações aguardando `ok`.
- Identificação: aguarda 2 s após abertura e falha após 12 s sem completar o reconhecimento.
- Ack pendente: timeout de 30 s; escrita serial: até 500 ms, sem repetição cega após escrita parcial.
- Relatório GRBL ausente por mais de 5 s interrompe a sessão; interface marca posição antiga após 2,5 s ou desconexão.
- Programa: até 1 MB; linha normalizada de até 79 caracteres.
- Recepção: linha de até 8192 bytes; fila de até 8 solicitações; log de 100 linhas; rastro de até 10000 pontos, descartando os 1000 mais antigos ao atingir o limite.

Esses valores são limites operacionais iniciais, não limites mecânicos. Antes de transformá-los em campos de configuração, documentar unidade, intervalo, persistência, valor padrão e efeito sobre compatibilidade.

## 5. Semântica do gráfico

Verde representa segmentos entre amostras recebidas. Cinza representa a trajetória linear prevista do arquivo carregado. O marcador destaca a última posição recebida. Não há interpolação física entre amostras, leitura de encoder ou garantia de registrar todos os movimentos rápidos.

GRBL pode reportar coordenadas de máquina ou de trabalho. O aplicativo mantém o referencial recebido e limpa o rastro se ele mudar; não reaproveita offsets antigos. Com coordenadas de máquina, a prévia do programa em coordenadas de trabalho fica oculta para evitar sobreposição incorreta.

Marlin `M114` pode informar posição projetada. `M114 R` depende de opção do firmware e só é consultado quando o operador marca suporte confirmado. Mesmo assim, a informação não é comprovação de posição mecânica por encoder. Não classificar detecção por nome de marca como detecção dessa capacidade.

## 6. Comandos e restrições do primeiro envio GRBL

Aceita palavras de movimento linear `G0/G1`, modos `G17/G21/G54/G90/G94`, `M3/M4/M5`, eixos XYZ, avanço F e potência S. Exige G21/G90 antes de coordenadas, primeiro movimento com XYZ explícitos e última linha M5. Arcos, movimentos relativos, polegadas no programa, extrusão, macros, probing e comandos desconhecidos são recusados.

O operador ainda precisa confirmar origem, modos complementares do controlador, limites, material e potência. Não há verificação completa de envelope mecânico, compensação, fixações ou colisões. O arquivo de exemplo deve ser testado primeiro no simulador.

Envio usa uma linha por acknowledgment. Final de arquivo aceito não conclui imediatamente: aguarda estado Idle após a drenagem. Pausa usa solicitação GRBL e retomada exige Hold:0. Cancelar/reset encerra a sessão e exige reconexão. Uma confirmação `ok` não significa que a ferramenta terminou o movimento.

Na falha durante um envio GRBL, tenta hold sem prometer sucesso; desconectar/fechar não garante parada física. Não criar retomada automática após erro ou reinicialização.

## 7. Mapa de arquivos

| Arquivo | Função |
| --- | --- |
| `apps/control/src/uMain.pas` | Formulários, menu, abas e renderização vetorial |
| `apps/control/src/uDomain.pas` | Cadastros, catálogo, snapshots e persistência |
| `apps/control/src/uSerialTransport.pas` | Portas Windows e serial exclusiva |
| `apps/control/src/uProtocol.pas` | Fragmentação, parsing e subconjunto G-code |
| `apps/control/src/uWorker.pas` | Thread, identificação, telemetria e execução |
| `apps/control/tests/test_core.lpr` | Testes sem hardware com transporte falso |
| `apps/control/build.ps1` | Compilação Win64 e testes |
| `docs/12-modelos-e-protocolos.md` | Pesquisa de modelos e fontes oficiais |
| `docs/13-controlador-lazarus.md` | Guia de uso, compilação e homologação |

## 8. Próximas entregas, em ordem

1. Obter marca, modelo, placa, firmware/versão e parâmetros seriais das máquinas do usuário.
2. Homologar leitura serial e reconhecimento na bancada, sem envio inicial de movimentos.
3. Registrar relatórios reais sanitizados como fixtures de protocolo e expandir testes de estados.
4. Acrescentar limites de trabalho e validação do estado modal antes de habilitar um perfil para produção.
5. Implementar persistência de sessões/logs e fila por equipamento, sem retomada automática.
6. Implementar envio Marlin com política de numeração, checksum/reenvio, busy/keepalive, aquecimento e conclusão; só então anunciar impressão controlada.
7. Expandir prévia para arcos e outros códigos com cobertura de parser e sem descartar comandos silenciosamente.
8. Conectar as aplicações de preparação ao contrato `.mcncjob` descrito na proposta.

## 9. Instruções para o próximo robô/agente

- Ler este arquivo, `AGENTS.md`, `docs/12-modelos-e-protocolos.md` e o código afetado.
- Manter este documento atualizado no mesmo commit de qualquer mudança de parâmetro, protocolo, comportamento ou escopo.
- Para cada parâmetro novo, registrar nome, significado, unidade, default, intervalo, onde fica salvo e quais perfis suportam.
- Adicionar fontes oficiais às afirmações de compatibilidade. Separar **pesquisado**, **implementado**, **testado em simulador** e **homologado em hardware**.
- Compilar o projeto Lazarus e executar testes relevantes. Não usar o painel Node.js como prova de funcionamento do controlador.
- Não conectar nem comandar máquinas físicas automaticamente durante testes de software. Testes padrão usam simulador/transporte falso.
- Ao terminar, atualizar o histórico abaixo, limitações e próximos passos; registrar no Git apenas arquivos do projeto, sem dados locais de equipamentos nem binários gerados.

## 10. Histórico de evolução

| Data | Alteração | Evidência/limitação |
| --- | --- | --- |
| 2026-09-28 | Definida suíte com cinco aplicações e serial exclusiva | Proposta em `docs/01` a `docs/11` |
| 2026-09-28 | Usuário escolheu Lazarus para o controlador | Substitui proposta de stack do controlador |
| 2026-09-28 | Implementados cadastro, workers, gráfico e adaptadores iniciais | Compilação Win64 e testes sem hardware; homologação física pendente |
