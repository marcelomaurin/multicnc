# Plano de correção e melhoria — Impressão 3D (MultiCNC / MultiSlicer)

- **Data:** 14/10/2026
- **Repositório:** `marcelomaurin/multicnc`
- **Branch de trabalho:** `fila`
- **Estado:** plano elaborado; ações abaixo **não executadas** por este documento
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
| IMP3D-001 | P0 | Auditoria do G-code | Identificar modo de extrusão, unidades, `F`, `E`, temperaturas e velocidades em arquivo representativo, sem comandos incoerentes | [ ] |
| IMP3D-002 | P0 | Velocidade e vazão | Garantir consistência de mm/s ↔ mm/min, limites por recurso e vazão volumétrica do hotend por material | [ ] |
| IMP3D-003 | P0 | Extrusão | Volume depositado calculado a partir de largura, altura, trajetória e diâmetro real do filamento; retração/recuperação coerentes | [ ] |
| IMP3D-004 | P0 | Protocolo Marlin | Envio com controle de fluxo, tratamento de `ok`, `busy`, erros, timeouts, reconexão e estados previsíveis | [ ] |
| IMP3D-005 | P0 | Segurança | Homing, volume útil, limites térmicos, bloqueios de movimento e parada segura testados | [ ] |
| IMP3D-006 | P1 | Temperatura | Inicialização ordenada com espera `M109`/`M190` conforme máquina e material; leitura efetiva monitorada | [ ] |
| IMP3D-007 | P1 | Perfil máquina/filamento | Bico, filamento, extrusora, limites de avanço, aceleração, retração e temperaturas persistidos e validados | [ ] |
| IMP3D-008 | P1 | Simulador e regressão | Executar mesmo G-code no simulador, validar estados/progresso e não introduzir regressões router/laser | [ ] |
| IMP3D-009 | P1 | Testes físicos | Primeiro movimento sem extrusão; depois calibração, primeira camada e cubo 20 mm, com registro das medidas | [ ] |
| IMP3D-010 | P2 | Interface e logs | Mostrar temperatura alvo/real, linha confirmada, estado térmico, avisos, progresso e motivo de falha | [ ] |
| IMP3D-011 | P2 | Documentação e release | Manual de impressão, matriz de compatibilidade, evidências, hashes e instalador rastreável | [ ] |

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

- [ ] Rastrear conversões de velocidade: entrada da UI em **mm/s**, saída `F` em **mm/min** quando o sabor do G-code assim exigir.
- [ ] Validar separadamente primeira camada, perímetro externo/interno, infill, suporte, ponte, deslocamento e retração.
- [ ] Introduzir/validar **vazão volumétrica máxima (mm³/s) por perfil de material/hotend** e limitar velocidade da extrusão sem alterar indevidamente movimentos de viagem.
- [ ] Garantir que perfis não gerem `F=0`, valores negativos, números inválidos ou velocidades acima de limites de segurança configurados.
- [ ] Considerar limites de aceleração/jerk ou junction deviation como restrições do firmware, sem prometer controle que não esteja implementado.

Aproximação para diagnóstico: `Q ≈ velocidade (mm/s) × altura (mm) × largura (mm)` em trajetórias regulares. Para o cálculo final de extrusão, usar a geometria efetiva da seção de cordão, coerente com o gerador de trajetórias.

### 5.2 Extrusão

- [ ] Verificar conversão entre volume extrudado e comprimento do filamento: `L = V / (π (d/2)²)`.
- [ ] Verificar uso consistente de `M82` (E absoluto), `M83` (E relativo) e `G92 E0`.
- [ ] Validar extrusão por segmento, espessura de parede, largura de linha e fluxo (multiplicador).
- [ ] Verificar retração, desretração, priming, viagens e costuras para evitar acúmulo ou falta de plástico.
- [ ] Conferir valores de `E` em exemplos numéricos e em testes unitários com tolerância conhecida.

**Aceite:** testes determinísticos passam para várias larguras, alturas e diâmetros; valores `F/E` coerentes em cada movimento; sem regressão no fatiamento de múltiplas peças.

**Arquivos para iniciar auditoria:** `multislicer/src/core/multislicer_pipeline.pas`, unidades de perfis e materiais localizadas na árvore atual, geradores de G-code e testes de `multislicer/tests/`.

## 6. Etapa 2 — Protocolo e execução no MultiCNC (P0)

- [ ] Revisar máquina de estados: desconectado → conectando → pronto → aquecendo → imprimindo → pausado → finalizado/falha.
- [ ] Confirmar protocolo de `ok` e filas; evitar envio excessivo que sobrecarregue buffers da controladora.
- [ ] Avaliar fluxo Marlin com `busy`, `Resend`/numeração/checksum **quando exigidos pelo firmware**, mensagens assíncronas e erros.
- [ ] Tratamento de timeouts durante `M109` e `M190`: aguardar aquecimento sem declarar travamento prematuramente.
- [ ] Diferenciar comandos aceitos e movimentos terminados; usar sincronização apropriada (por exemplo, `M400` quando suportado).
- [ ] Ao perder conexão, entrar em estado de falha e impedir retomada cega; preservar log e orientações de recuperação.
- [ ] Validar pausa, cancelamento, resfriamento controlado e finalização; não prometer retomada após energia cortada sem suporte explícito.
- [ ] Monitorar temperaturas reais e metas sem confundir `M104`/`M140` com espera.

**Aceite:** sessão completa em simulador, teste de atrasos, desconexão e mensagens malformadas; comandos nunca duplicados silenciosamente e estado da UI coerente.

**Pontos de auditoria:** unidades de sessão, transporte serial/TCP, parser Marlin e a interface em `src/app/`. Identificar nomes reais dos fontes antes de editar.

## 7. Etapa 3 — Segurança, perfis e preparação (P0/P1)

- [ ] Validar homing `G28` e referencial da mesa antes de iniciar a impressão; não iniciar fora do volume.
- [ ] Verificar posição da origem (canto/centro), offsets de bico, dimensão útil e eixo Z.
- [ ] Impedir extrusão a frio quando o firmware a proíbe; não recomendar desabilitar proteção térmica.
- [ ] Respeitar temperaturas máximas do equipamento e do filamento, com confirmação de aquecimento efetivo.
- [ ] Identificar perfil de firmware: Marlin e Klipper **não são protocolos idênticos**; suporte a envio direto deve ser testado separadamente.
- [ ] Verificar G-code inicial/final (aquecimento, purga, desligamento, retração final e estacionamento), mantendo opções por máquina.
- [ ] Testar parada de emergência de hardware, sensores de fim de curso e comportamento do firmware sob falha em ambiente controlado.

**Aceite:** não inicia arquivo incompatível com máquina selecionada; rejeita configurações perigosas; explica erros ao operador.

## 8. Etapa 4 — Testes automatizados e em simulador

- [ ] Criar casos para conversão 60 mm/s → `F3600`, incluindo múltiplas velocidades.
- [ ] Criar casos para volume de deposição, diâmetro 1,75/2,85 mm, fluxo 100% e limites de vazão.
- [ ] Testar modo E relativo/absoluto, viagens, retração e valores de `G92`.
- [ ] Testar cabeçalhos do contrato MultiSuite e seleção automática do equipamento, incluindo volume incompatível.
- [ ] Reproduzir respostas Marlin `ok`, `busy`, `Resend`, aquecimento prolongado e perda de conexão.
- [ ] Executar `multislicer/tests/` e testes pertinentes do MultiCNC e do simulador; anexar saídas e versões.
- [ ] Executar testes de regressão dos fluxos Laser e Router.

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

- [ ] Painel de impressora: temperatura atual/alvo, estado do aquecimento, posição, avanço, ventilação, porcentagem e estado do trabalho.
- [ ] Exibir claramente “aguardando resposta”, “aquecendo”, “executando”, “pausado”, “falhou” e “finalizado”.
- [ ] Salvar log da sessão com hora, máquina, perfil, arquivo, comandos/retornos relevantes e erro final, evitando informações sensíveis desnecessárias.
- [ ] Alertar sobre perfil incompatível e G-code que requer verificação.
- [ ] Atualizar manual do usuário, diagnóstico de problemas e matriz Marlin/Klipper por firmware realmente testado.
- [ ] Atualizar testes do CI, versão e manifesto; gerar instalador **somente depois** dos testes mínimos.
- [ ] Registrar arquivos alterados, testes executados, hashes, commit e limitações conhecidas em documentação da release.

## 11. Critérios de conclusão

Marcar o trabalho como **PRONTO PARA TESTES DE CAMPO** apenas se:

- [ ] IMP3D-001 a IMP3D-008 aprovados com evidência reproduzível.
- [ ] Um G-code completo termina no simulador e o MultiCNC trata falhas previsivelmente.
- [ ] Perfis têm limites térmicos, geométricos e de vazão coerentes.
- [ ] Documentação e logs permitem reproduzir o resultado.

Marcar como **VALIDADO EM EQUIPAMENTO** somente se:

- [ ] IMP3D-009 executado com pelo menos uma impressora física identificada.
- [ ] Testes de primeira camada, cubo, retração, parada/cancelamento e fim de impressão documentados.
- [ ] Nenhum problema crítico de segurança ou perda de controle aberto.

Marcar como **RELEASE PARA USUÁRIOS** somente após regressão dos demais modos, matriz de compatibilidade, instalador verificável e limitações públicas.

## 12. Ordem de execução sugerida

`IMP3D-001 → IMP3D-002/003 → IMP3D-004/005 → IMP3D-006/007 → IMP3D-008 → IMP3D-009 → IMP3D-010/011`

**Nota:** esta é uma especificação de trabalho e validação. Nenhuma correção está declarada como aplicada, e nenhum teste físico está declarado como realizado por sua elaboração.
