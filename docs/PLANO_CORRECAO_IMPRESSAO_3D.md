# Plano de correção e melhoria — Impressão 3D (MultiCNC / MultiSlicer)

- **Data:** 14/10/2026
- **Repositório:** `marcelomaurin/multicnc`
- **Branch de trabalho:** `fila`
- **Estado:** **CORREÇÕES DE SOFTWARE IMPLEMENTADAS E TESTADAS** — 39 testes de regressão, 2 de interface e integração TCP real aprovados; validação física e release pendentes (seção 13)
- **Prioridade geral:** P0 — confiabilidade e segurança na impressão FDM/FFF
- **Aplicações:** MultiSlicer (preparação e geração de G-code), MultiCNC (protocolo, execução e monitoramento), SimuCNC (simulação).

## 1. Objetivo e contexto

Concluir e validar o fluxo **STL/3MF → MultiSlicer → G-code → MultiCNC → impressora 3D**, com parâmetros coerentes de velocidade, extrusão, material e temperatura, operação segura e qualidade reproduzível.

**Problema relatado:** movimentação aparentemente rápida demais durante impressão; suspeita de que a deposição do filamento e os parâmetros de velocidade não estejam sendo respeitados. **Hipótese ainda não confirmada no código.** Não presumir que a causa seja exclusivamente o fatiador: comparar o G-code gerado, o planejador da controladora, os limites do firmware e a resposta real da máquina.

### Estado conhecido na documentação do projeto

- O MultiSlicer documenta perfis de máquina e filamento, fatiamento, infill, suportes, retração, temperaturas e geração de G-code Marlin/Klipper.
- O MultiCNC documenta conexão serial/TCP, monitoramento e recepção de trabalho do MultiSlicer.
- Há registro de teste de G-code do MultiSlicer concluído no **simulador Marlin**, mas isso **não comprova** uma impressão real bem-sucedida.
- A disponibilidade de código, testes automatizados e instalador não substitui os testes de bancada com impressora física.

**Referências internas:** `multislicer/README.md`, `multislicer/docs/PLANO_TAREFAS.md`, `src/app/README.md`, `setup/qa-tests-010.json`.

## 2. Regras de desenvolvimento

1. Preservar o layout compartilhado da MultiSuite, os módulos existentes e os formatos de projeto.
2. Separar responsabilidade: **MultiSlicer gera G-code; MultiCNC controla a execução**. Não duplicar cálculos de fatiamento no controlador.
3. Toda correção deve vir com teste reproduzível, comportamento esperado, resultados obtidos e rastreabilidade do commit.
4. Não interpretar `ok` do Marlin como conclusão física de movimento; distinguir aceitação do comando, esvaziamento de buffer e conclusão do movimento quando aplicável.
5. Nenhum teste de bancada deve eliminar intertravamentos ou substituir o botão físico de parada de emergência.
6. Antes de alterar um módulo, localizar a unidade/função real na branch `fila` e registrar no relatório de implementação. As unidades apontadas abaixo são **pontos de investigação**, não diagnósticos conclusivos.

## 3. Quadro de prioridades

| ID | Prioridade | Tema | Entrega e critério de aceite | Estado |
|---|---|---|---|---|
| IMP3D-001 | P0 | Auditoria do G-code | Identificar modo de extrusão, unidades, `F`, `E`, temperaturas e velocidades em arquivo representativo, sem comandos incoerentes | [x] Auditoria sintética; defeito físico não reproduzido |
| IMP3D-002 | P0 | Velocidade e vazão | Garantir consistência de mm/s ↔ mm/min, limites por recurso e vazão volumétrica do hotend por material | [x] Núcleo e templates limitados; pontes dedicadas não implementadas |
| IMP3D-003 | P0 | Extrusão | Volume depositado calculado a partir de largura, altura, trajetória e diâmetro real do filamento; retração/recuperação coerentes | [x] Cálculo e modos testados no núcleo |
| IMP3D-004 | P0 | Protocolo Marlin | Envio com controle de fluxo, tratamento de `ok`, `busy`, erros, timeouts, reconexão e estados previsíveis | [x] Fluxo/falhas, pausa e TCP testados; política de Resend na seção 13 |
| IMP3D-005 | P0 | Segurança | Homing, volume útil, limites térmicos, bloqueios de movimento e parada segura testados | [~] Bloqueios de software; bancada pendente |
| IMP3D-006 | P1 | Temperatura | Inicialização ordenada com espera `M109`/`M190` conforme máquina e material; leitura efetiva monitorada | [x] Espera/monitoramento testados em software |
| IMP3D-007 | P1 | Perfil máquina/filamento | Bico, filamento, extrusora, limites de avanço, aceleração, retração e temperaturas persistidos e validados | [~] Perfis persistidos; calibração/aceleração pendentes |
| IMP3D-008 | P1 | Simulador e regressão | Executar mesmo G-code no simulador, validar estados/progresso e não introduzir regressões router/laser | [x] TCP real: 84 comandos, aquecimento e posição final; 39 regressões aprovadas |
| IMP3D-009 | P1 | Testes físicos | Primeiro movimento sem extrusão; depois calibração, primeira camada e cubo 20 mm, com registro das medidas | [ ] Ender 3 informada; bancada pendente |
| IMP3D-010 | P2 | Interface e logs | Mostrar temperatura alvo/real, linha confirmada, estado térmico, avisos, progresso e motivo de falha | [x] Temperaturas, avanço/ventilação solicitados, estados, progresso e log integral |
| IMP3D-011 | P2 | Documentação e release | Manual de impressão, matriz de compatibilidade, evidências, hashes e instalador rastreável | [~] Manual/evidências; release pendente |

## 4. Etapa 0 — Reproduzir e isolar a falha (P0)

- [ ] Identificar modelo de impressora, versão do firmware, extrusora (Bowden ou direta), diâmetro do bico e do filamento, material e conexão.
- [ ] Preservar um STL simples, o perfil utilizado, o `.mslice` e o G-code exato que reproduz o comportamento.
- [ ] Coletar parâmetros de qualidade: altura de camada, largura de linha, velocidades (primeira camada, perímetro, infill, viagem), fluxo, retração e temperatura.
- [ ] Salvar log integral da sessão MultiCNC e qualquer resposta de erro/timeout da controladora.
- [ ] Comparar G-code equivalente produzido por um slicer comercial **com o mesmo perfil**, sem supor igualdade bit a bit.
- [ ] Distinguir: velocidade solicitada pelo programa, velocidade efetiva da máquina, extrusão insuficiente e falhas térmicas.

**Aceite:** defeito reproduzível ou explicitamente classificado como não reproduzido, com artefatos e condições registrados.

## 5. Etapa 1 — Corrigir cálculos no MultiSlicer (P0)

### 5.1 Velocidade e vazão

- [x] Rastrear conversões de velocidade: entrada da UI em **mm/s**, saída `F` em **mm/min** quando o sabor do G-code assim exigir.
- [ ] Validar separadamente primeira camada, perímetro externo/interno, infill, suporte, ponte, deslocamento e retração.
- [x] Introduzir/validar **vazão volumétrica máxima (mm³/s) por perfil de material/hotend** e limitar velocidade da extrusão sem alterar indevidamente movimentos de viagem.
- [x] Garantir que perfis não gerem `F=0`, valores negativos, números inválidos ou velocidades acima de limites de segurança configurados.
- [x] Considerar limites de aceleração/jerk ou junction deviation como restrições do firmware, sem prometer controle que não esteja implementado.

Aproximação para diagnóstico: `Q ≈ velocidade (mm/s) × altura (mm) × largura (mm)` em trajetórias regulares. Para o cálculo final de extrusão, usar a geometria efetiva da seção de cordão, coerente com o gerador de trajetórias.

### 5.2 Extrusão

- [x] Verificar conversão entre volume extrudado e comprimento do filamento: `L = V / (π (d/2)²)`.
- [x] Verificar uso consistente de `M82` (E absoluto), `M83` (E relativo) e `G92 E0`.
- [x] Validar extrusão por segmento, espessura de parede, largura de linha e fluxo (multiplicador).
- [ ] Verificar retração, desretração, priming, viagens e costuras para evitar acúmulo ou falta de plástico.
- [x] Conferir valores de `E` em exemplos numéricos e em testes unitários com tolerância conhecida.

**Aceite:** testes determinísticos passam para várias larguras, alturas e diâmetros; valores `F/E` coerentes em cada movimento; sem regressão no fatiamento de múltiplas peças.

**Arquivos para iniciar auditoria:** `multislicer/src/core/multislicer_pipeline.pas`, unidades de perfis e materiais localizadas na árvore atual, geradores de G-code e testes de `multislicer/tests/`.

## 6. Etapa 2 — Protocolo e execução no MultiCNC (P0)

- [x] Revisar máquina de estados: desconectado → conectando → pronto → aquecendo → imprimindo → pausado → finalizado/falha.
- [x] Confirmar protocolo de `ok` e filas; evitar envio excessivo que sobrecarregue buffers da controladora.
- [x] Avaliar fluxo Marlin com `busy`, `Resend`/numeração/checksum **quando exigidos pelo firmware**, mensagens assíncronas e erros.
- [x] Tratamento de timeouts durante `M109` e `M190`: aguardar aquecimento sem declarar travamento prematuramente.
- [x] Diferenciar comandos aceitos e movimentos terminados; usar sincronização apropriada (por exemplo, `M400` quando suportado).
- [x] Ao perder conexão, entrar em estado de falha e impedir retomada cega; preservar log e orientações de recuperação.
- [x] Validar em software pausa, cancelamento, comandos de resfriamento e finalização; não prometer retomada após energia cortada sem suporte explícito.
- [x] Monitorar temperaturas reais e metas sem confundir `M104`/`M140` com espera.

**Aceite:** sessão completa em simulador, teste de atrasos, desconexão e mensagens malformadas; comandos nunca duplicados silenciosamente e estado da UI coerente.

**Pontos de auditoria:** unidades de sessão, transporte serial/TCP, parser Marlin e a interface em `src/app/`. Identificar nomes reais dos fontes antes de editar.

## 7. Etapa 3 — Segurança, perfis e preparação (P0/P1)

- [ ] Validar homing `G28` e referencial da mesa antes de iniciar a impressão; não iniciar fora do volume.
- [ ] Verificar posição da origem (canto/centro), offsets de bico, dimensão útil e eixo Z.
- [ ] Impedir extrusão a frio quando o firmware a proíbe; não recomendar desabilitar proteção térmica.
- [ ] Respeitar temperaturas máximas do equipamento e do filamento, com confirmação de aquecimento efetivo.
- [x] Identificar perfil de firmware: Marlin e Klipper **não são protocolos idênticos**; suporte a envio direto deve ser testado separadamente.
- [x] Verificar G-code inicial/final (aquecimento, purga, desligamento, retração final e estacionamento), mantendo opções por máquina.
- [ ] Testar parada de emergência de hardware, sensores de fim de curso e comportamento do firmware sob falha em ambiente controlado.

**Aceite:** não inicia arquivo incompatível com máquina selecionada; rejeita configurações perigosas; explica erros ao operador.

## 8. Etapa 4 — Testes automatizados e em simulador

- [x] Criar casos para conversão 60 mm/s → `F3600`, incluindo múltiplas velocidades.
- [x] Criar casos para volume de deposição, diâmetro 1,75/2,85 mm, fluxo 100% e limites de vazão.
- [x] Testar modo E relativo/absoluto, viagens, retração e valores de `G92`.
- [x] Testar cabeçalhos do contrato MultiSuite e seleção automática do equipamento, incluindo volume incompatível.
- [x] Reproduzir respostas Marlin `ok`, `busy`, `Resend`, aquecimento prolongado e perda de conexão.
- [x] Executar `multislicer/tests/` e testes pertinentes do MultiCNC e do simulador; anexar saídas e versões.
- [x] Executar testes de regressão dos fluxos Laser e Router.

**Aceite:** testes automatizados reproduzíveis, com resultado e ambiente de execução registrados. Não marcar “passou” sem execução.

## 9. Etapa 5 — Validação física e qualidade

Executar **somente com impressora identificada e operação supervisionada**.

1. **Sem extrusão:** conexão, homing, posicionamento e percursos dentro dos limites.
2. **Térmico:** medir tempo e estabilidade de aquecimento, comparar alvo/real e observar erros.
3. **Primeira camada:** peça simples, verificando aderência, altura de Z, continuidade e excesso/ausência de material.
4. **Cubo 20 mm:** conferir X/Y/Z com instrumento adequado; registrar medidas, fotos e material.
5. **Geometria funcional:** paredes, preenchimento, pontes, suportes, retração e uma peça com múltiplas ilhas.
6. **Robustez:** pausa/cancelamento, falha de comunicação simulada com procedimento seguro, reinício e limpeza dos estados.
7. **Comparativo:** imprimir mesmo modelo com slicer de referência, mesmo filamento e parâmetros equivalentes, registrando tempo, massa e acabamento.

### Modelo de evidência

| Campo | Valor |
|---|---|
| Data/commit | A preencher |
| Impressora/firmware | A preencher |
| Bico/filamento/material | A preencher |
| Perfil e arquivo G-code | A preencher |
| Resultado da sessão | A preencher |
| Dimensões medidas | A preencher |
| Problemas/reprodução | A preencher |
| Log, fotos e responsável | A preencher |

**Aceite físico mínimo:** imprimir um modelo de calibração e uma peça com retrações sem falhas críticas, com medidas e evidências. Os limites dimensionais devem ser definidos para a máquina antes do teste, não inventados neste plano.

## 10. Etapa 6 — Interface, documentação e entrega

- [x] Painel de impressora (avanço/ventilação solicitados, não medidos): temperatura atual/alvo, estado do aquecimento, posição, avanço, ventilação, porcentagem e estado do trabalho.
- [x] Exibir claramente “aguardando resposta”, “aquecendo”, “executando”, “pausado”, “falhou” e “finalizado”.
- [x] Salvar log da sessão com hora, máquina, perfil, arquivo, comandos/retornos relevantes e erro final, evitando informações sensíveis desnecessárias. Registro TX/RX em arquivo temporário e exportação pelo Save Log; mensagens RX incluem falhas do firmware.
- [x] Alertar sobre perfil incompatível e G-code que requer verificação.
- [x] Atualizar manual do usuário, diagnóstico de problemas e matriz Marlin/Klipper por firmware realmente testado.
- [x] Atualizar testes do CI e manifesto de desenvolvimento; CI remoto ainda não executado.
- [ ] Versão e instalador de release **somente depois** dos critérios físicos e de compatibilidade.
- [x] Registrar arquivos alterados, testes, hashes, commit-base e limitações em documentação de desenvolvimento. Alterações locais sem commit; não constitui release.

## 11. Critérios de conclusão

Marcar o trabalho como **PRONTO PARA TESTES DE CAMPO** apenas se:

- [ ] IMP3D-001 a IMP3D-008 aprovados com evidência reproduzível.
- [x] Um G-code completo termina no simulador e o MultiCNC trata falhas previsivelmente (escopo/limitações na seção 13).
- [ ] Perfis têm limites térmicos, geométricos e de vazão coerentes.
- [x] Documentação e logs permitem reproduzir o resultado de software.

Marcar como **VALIDADO EM EQUIPAMENTO** somente se:

- [ ] IMP3D-009 executado com pelo menos uma impressora física identificada.
- [ ] Testes de primeira camada, cubo, retração, parada/cancelamento e fim de impressão documentados.
- [ ] Nenhum problema crítico de segurança ou perda de controle aberto.

Marcar como **RELEASE PARA USUÁRIOS** somente após regressão dos demais modos, matriz de compatibilidade, instalador verificável e limitações públicas.

## 12. Ordem de execução sugerida

`IMP3D-001 → IMP3D-002/003 → IMP3D-004/005 → IMP3D-006/007 → IMP3D-008 → IMP3D-009 → IMP3D-010/011`

**Nota atualizada:** a seção 13 registra as correções executadas e suas evidências. Nenhum teste físico foi realizado. `[~]` significa implementação parcial; `[x]` nas linhas de software não equivale a validação física.


## 13. Registro de implementação — 14/10/2026

Base: `903bd19`, branch `fila`. Alterações locais ainda sem commit.

### Auditoria e correções em andamento

- `multislicer/src/core/multislicer_pipeline.pas`: `TGCodeWriter.SetF` já convertia mm/s em mm/min; `ExtrusionPerMM` já usava seção arredondada e diâmetro do filamento. Não há evidência da falha física original. Faltavam limite de vazão, validação numérica no núcleo e limite Z separado.
- `multislicer_materials.pas` / `multislicer_main.pas`: adicionada vazão máxima persistida no perfil/material e projeto, editável na tela. Valores iniciais são estimativas para calibração, não caracterização de hotend.
- `multicnc_session.pas`: a interface executa por `TMultiCNCMachine`, não por `TGCodeStreamer`. Acrescentada barreira M400 ao concluir impressão Marlin.
- `multicnc_machine.pas`: reset com fila pendente passa a ser falha; sem retomada automática.
- `multicnc_streamer.pas` / `multicnc_marlin.pas`: validação de Resend e do token ok.
- Testes: ainda não executados nesta etapa. Marcas de aprovação serão atualizadas somente após execução.
- Dependências de bancada: modelo/firmware, configuração real, G-code que reproduz o defeito e responsável pela operação ainda não fornecidos. IMP3D-009 não pode ser concluído por simulação.


### Atualização intermediária

Usuário identificou a impressora como **Ender 3**. Variante, firmware, bico, filamento, modificações e conexão ainda não confirmados.

Primeira rodada: 28 testes aprovados, 2 falhas, 1 teste TCP externo não executado. A falha do novo teste Marlin era ausência da espera de boot no transporte falso; corrigida, teste aprovado. O teste joystick usava igualdade exata de Double com constante estendida no compilador i386; ajustado para tolerância de 1e-12. Não houve alteração de produção no joystick. Nova rodada após correções ainda pendente.

Testes específicos já executados: streaming (ok malformado, busy, M400 e reset fragmentado) e controller (Resend inválido) aprovados. Novo teste de fatiamento verificou F/E, vazão, diâmetros e limites; corrigida a busca do segundo bloco modal no teste, aguardando nova execução completa.

### Resultado consolidado

- **39 testes de console aprovados, zero falhas**, em Windows x86_64; 1 teste TCP externo explicitamente não executado. Módulos: MultiSlicer, MultiCNC, LaserPCB e MakeRouter.
- **2 testes GUI aprovados**: MultiSlicer (incluindo persistência de vazão/limites em `.mslice`) e MultiCNC. Ambas as aplicações compiladas para 64 bits. A validação é automatizada, sem revisão visual manual da tela.
- Amostra: caixa 20 × 20 × 3 mm, perfil de teste Ender-3 S1, 3732 comandos carregados no simulador na rodada x86_64. Não é reprodução do defeito da Ender 3 física do usuário.
- Cabeçalho de limites passa a incluir trajetórias de saia, suporte e brim. O teste antigo que esperava somente o envelope da peça foi atualizado para verificar a ampliação correta.
- Auditoria compartilhada: `src/shared/multisuite_print_audit.pas`, `AuditPrintProgram`; núcleo valida números, temperatura e envelope; sessão valida antes de enviar. `TSimulationSession.FeedJob` usa M400 e `TMultiCNCMachine.CheckCommunicationTimeout` falha após 120 s sem dados com comando pendente. `mainform.pas` mostra alvo real do firmware.
- Perfis: `multislicer_printers.pas` e `multislicer_materials.pas` persistem limites; campos na interface e projeto foram testados. Nada foi enviado a hardware.
- Evidências: [relatório e limitações](IMPRESSAO_3D_VALIDACAO.md), [resultados](qa/impressao-3d-2026-10-14/qa-tests.json), logs, amostra e manifesto SHA-256 na mesma pasta. Base Git `903bd19`; alterações locais identificadas por hash no manifesto.

### Pendências remanescentes — atualizado em 15/10/2026

1. Confirmar variante/firmware da Ender 3, bico, filamento, material, extrusora e conexão; preservar o caso original. A causa física relatada permanece **não reproduzida**.
2. Calibrar vazão, retração e limites na máquina; validar offsets/nivelamento e qualidade de pontes/costuras. Não foi acrescentado um gerador dedicado de pontes nem controle de aceleração/jerk; esses limites continuam no firmware.
3. Executar bancada supervisionada da etapa 5, inclusive pausa/cancelamento físico, parada/intertravamentos, primeira camada, cubo e comparação com slicer de referência. TCP real concluído; ele não substitui bancada.
4. Qualificar versões de firmware, inclusive suporte aos comandos dos perfis. Envio direto a Klipper continua sem validação.
5. Somente depois desses critérios: versão/instalador de release. Não marcar VALIDADO EM EQUIPAMENTO ou RELEASE PARA USUÁRIOS. Os critérios de campo 001–008 ainda dependem da qualificação do perfil real nos itens 005/007.

As correções de software, os templates, o log integral, o painel, a pausa e a integração TCP estão concluídos no escopo descrito abaixo.


### Encerramento da rodada — log integral

Implementado `TSimulationSession.Trace` e `SaveSessionLog`, com observadores TX/RX em `TMultiCNCMachine` antes do processamento da resposta, nome de arquivo exclusivo, data/hora, arquivo e perfil do cabeçalho. Save Log exporta o registro integral, sem truncamento de 1000 linhas nem filtro de temperaturas. O teste `TestIntegralSessionLog` preservou 1105 respostas e conferiu primeira/última mensagens e temperaturas. Após a mudança: repetidos **25 testes core aprovados**, zero falhas e 1 TCP externo não executado; teste GUI MultiCNC aprovado; ambas as aplicações recompiladas para x86_64. Consolidado permanece **39 console + 2 GUI aprovados**. Os hashes foram regenerados após esta alteração. Não houve commit nem push; base Git e hashes dos arquivos locais identificam esta rodada.


### Continuação — 15/10/2026

- Templates iniciais/finais agora têm limite de vazão na purga, velocidade em Z, movimentos dentro da mesa e estacionamento com `{park_z}` limitado à altura útil. Macros/offsets e arcos em templates sem análise segura são bloqueados. O corpo gerado mantém suporte a arcos.
- Marlin começa com M200 D0, M220 S100 e M221 S100; templates que alteram esses pressupostos são rejeitados. Auditoria rejeita coordenadas/temperaturas malformadas.
- Primeira integração TCP real aprovada: **84 comandos, 58,563 s, bico 179,9 °C e mesa 30,0 °C, posição final Z=5,4 mm**, duas camadas de 4 × 4 × 0,4 mm, com espera térmica e barreira M400. Valores são do simulador, não da Ender 3.
- O teste rápido anterior usa transporte que responde ok imediatamente; ele verifica o contrato/fila, **não** a física ou a temperatura. A nova integração usa o servidor real, sem privilégios para instalar drivers.
- SimuCNC TCP confirma M73/M486 e M200 D0 pela fila; não simula malha, pressure advance, modo volumétrico ou arcos. A amostra TCP usa movimentos lineares e inicialização padrão.
- Novo executor reproduzível `tools/verify_print_tcp.py`, ligado ao CI. Regressão completa e builds finais em andamento.

- Revisão final encontrou que a pausa Marlin interrompia o abastecimento da sessão, mas ainda liberava a fila interna ao receber `ok`. Corrigido `TMultiCNCMachine.Pause` para bloquear essa fila; teste cobre confirmação durante pausa, retomada sem duplicação e cancelamento. Movimentos já aceitos pelo firmware podem terminar.

### Fechamento de software — 15/10/2026

- **39 regressões de console, 2 testes de interface e 1 integração TCP real aprovados**, sem falhas. Os testes de streaming/sessão/GRBL foram repetidos após a correção da pausa; streaming também verifica o log de M410 e avanço/ventilação solicitados. MultiSlicer, MultiCNC e SimuCNC compilados para Windows x86_64.
- Painel: estados em português, espera de resposta, temperatura real/alvo, progresso confirmado, avanço solicitado em mm/s e ventilador 0 solicitado em %. Não são medidas de velocidade ou rotação. Pausa mantém aquecedores como estavam; cancelamento solicita M410 e desligamento. A execução desses comandos depende do firmware e não substitui parada física.
- Evidência final em `docs/qa/impressao-3d-2026-10-15/`: relatório consolidado, logs, G-code TCP e manifesto SHA-256. A pasta de 14/10 permanece como histórico; seus resultados não caracterizam teste físico.
- Reprodução TCP: `python tools/verify_print_tcp.py` ou `tests/run_tcp_tests.ps1` no Windows; no Linux, `xvfb-run -a python3 tools/verify_print_tcp.py`. O executor compila o servidor real de teste e o cliente; recusa porta 9000 ocupada e encerra apenas o processo que criou. CI configurado, mas sem execução remota nesta sessão.
- Base Git `903bd19`; alterações de impressão locais, sem commit/push. Alterações paralelas de MultiAssembly não foram incluídas no manifesto desta entrega.
- **IMP3D-009 e liberação física permanecem pendentes.** Não foi feita conexão com a Ender 3 nem enviado comando a hardware.

Executáveis de desenvolvimento atualizados em `bin/multislicer.exe`, `bin/multicnc.exe` e `bin/SimuCNC.exe`; não constituem instalador/release validado em equipamento. Integração TCP final: 84 comandos em **58,532 s**, sem falhas.


### Ampliação posterior do catálogo FDM — 15/10/2026

Incluídos 11 modelos pesquisados, entre eles Creality K2, K2 Pro e K2 Plus, sem resina. Dados de fabricantes, limites e status de integração registrados em [CATALOGO_IMPRESSORAS_FDM.md](CATALOGO_IMPRESSORAS_FDM.md). Os novos modelos estão disponíveis como catálogo dimensional; fluxo proprietário e inicialização específicos não são apresentados como envio Marlin validado. Essa ampliação não encerra a bancada física pendente do plano.

### Filamentos comerciais — 15/10/2026

Implementados 12 filamentos de sete marcas, com seleção de família PLA/ABS e filtro de marca/linha, opção Customizado preservando os padrões anteriores, preenchimento de bico/mesa e ajuste manual. Fonte, faixa publicada e temperatura inicial estão documentadas em [FILAMENTOS_COMERCIAIS.md](FILAMENTOS_COMERCIAIS.md). Marca, família e ajustes persistem em perfis e projetos; limites térmicos da impressora continuam válidos. **4 testes aprovados** (3 de console e 1 de interface), incluindo temperaturas no G-code, filtro PLA/ABS, persistência e bloqueio por limite térmico. MultiSlicer recompilado e atualizado em `bin/multislicer.exe`; evidências em `docs/qa/filamentos-comerciais-2026-10-15/`. Validação prévia também confere os limites editáveis do perfil, além da proteção já existente na geração. Bancada física permanece pendente.
