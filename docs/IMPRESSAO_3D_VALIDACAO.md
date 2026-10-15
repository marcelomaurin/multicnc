# Impressão 3D — correções e validação de 14–15/10/2026

## Configuração e uso

No MultiSlicer, escolha a variante correta da Ender 3 em **Impressora**. O usuário informou Ender 3, mas ainda não identificou variante, firmware, bico, material, extrusora ou conexão. Não substituir esses dados por suposições.

O painel Impressora agora permite salvar limites de impressão, viagem, eixo Z e temperaturas. O painel Material permite salvar **Vazão máxima do hotend (mm³/s)**. Os valores padrão (8 mm³/s, TPU 3 mm³/s) são pontos de partida, não medições da máquina. Use um perfil por combinação material/hotend quando necessário. Projetos `.mslice` guardam esses campos; arquivos antigos recebem valores padrão.

Nas trajetórias geradas pelo núcleo, a velocidade de impressão é limitada pelo menor valor entre velocidade do recurso, limite da máquina e vazão máxima dividida pela seção efetiva multiplicada pelo fluxo. O cálculo usa seção arredondada, não apenas largura × altura. A viagem usa seu limite próprio; o eixo Z tem avanço separado. O firmware continua responsável por aceleração, jerk, limites elétricos e proteções térmicas.

O arquivo usa G21, G90, M83 e G92 E0. No Marlin, também normaliza M200 D0 (E em comprimento), M220 S100 e M221 S100; esses comandos precisam ser suportados pelo firmware escolhido. Depois do bloco inicial personalizado, esses modos de unidades/posição/extrusão são restaurados. Antes de extrusão positiva, a auditoria exige G28 completo e M109 com alvo positivo; M104 sozinho não equivale a espera. M302 é recusado. Essa análise estática não confirma fisicamente homing ou temperatura: isso depende da controladora e de suas proteções.

O MultiCNC valida o arquivo antes do primeiro envio e recusa temperaturas acima do perfil, limites geométricos conhecidos excedidos e arquivos Klipper identificados como incompatíveis com Marlin. Configure o volume real no equipamento: dimensão zero significa desconhecida, portanto não oferece proteção geométrica nesse eixo. O núcleo do MultiSlicer também verifica saia, suporte, brim e altura da jangada.

No encerramento Marlin, a sessão aguarda a confirmação de M400 antes de declarar conclusão. `ok` de G1 indica aceitação, não parada física. Mensagens `busy` e temperaturas não liberam a fila. Silêncio de 120 segundos com comando pendente interrompe o trabalho; não existe reenvio automático de movimentos após timeout, perda de conexão ou reset.

O painel mostra temperatura real e alvo informado pelo firmware. A indicação “Aquecendo” significa que uma leitura está mais de 2 °C abaixo do alvo; não certifica estabilidade térmica. O botão existente **Save Log** exporta agora o registro integral da sessão: comandos TX, respostas RX sem o filtro do console, horários com milissegundos, conexão, arquivo e perfil do cabeçalho. O registro é gravado continuamente em arquivo temporário exclusivo `multicnc-{GUID}.log`, preservado ao fechar a sessão; exporte-o para guarda permanente. O console continua limitado às últimas 1000 linhas, mas essa limitação não afeta o arquivo integral. Falhas de gravação são informadas e impedem exportar o log como se estivesse completo.

Os templates de início/fim recebem limites de purga, avanço, Z e volume. A expansão `{park_z}` no bloco final limita o estacionamento ao topo útil; o template padrão usa essa expansão. Arcos em templates, macros, G92 XYZ e comandos que alteram as premissas do cálculo são recusados. Arcos do corpo gerado continuam disponíveis, mas não foram validados no servidor TCP. Não copiar um template com mesh/pressure advance para firmware sem esses recursos.

A pausa Marlin bloqueia a fila no host; movimentos já aceitos pelo firmware podem terminar. Retomar libera os comandos preservados uma vez. Cancelar descarta a fila e solicita M410, M104 S0, M140 S0 e M107. A confirmação e o comportamento físico dependem do firmware. O log inclui M410 mesmo enviado fora da fila. O painel mostra avanço/ventilador **solicitados**, não medidos, e porcentagem das linhas confirmadas; a conclusão depende da barreira final.

## Diagnóstico

| Mensagem/sintoma | Ação |
|---|---|
| Trajetória fora do volume | Reposicionar peça e revisar saia/brim, suporte, jangada e estacionamento do template. Conferir a área útil do equipamento. |
| Temperatura excede o perfil | Conferir perfil do equipamento e faixa do fabricante do material; não aumentar limites sem verificar o hardware. |
| Extrusão exige G28/M109 | Corrigir o bloco inicial; comandos de macros não demonstram essas condições à auditoria. |
| Marlin sem resposta | Inspecionar a máquina e a conexão; o host não sabe quais movimentos chegaram a executar. Reiniciar somente após recuperação supervisionada. |
| Continua rápido ou subextrudando | Preservar G-code, perfil e log; conferir overrides M220/M221 e modo volumétrico M200 no firmware, bico, filamento e vazão medida. A causa física original permanece não reproduzida. |

## Compatibilidade realmente verificada

| Destino | Evidência | Situação |
|---|---|---|
| Transporte falso Marlin | `test_multislicer_print` | Contrato/fila aprovados; responde imediatamente e não simula física/temperatura/arcos. |
| Simulador em processo | `test_simulator`, testes térmicos | Testes de componentes aprovados, sem qualificação de firmware físico. |
| Controladora falsa Marlin | `test_streaming`, `test_controller` | Fluxo, busy, erros, reset fragmentado, M400, silêncio e Resend exercitados. |
| GRBL/router/laser | Suíte core + LaserPCB + MakeRouter | Regressões automatizadas aprovadas. |
| Ender 3 física | Apenas modelo informado pelo usuário | Não testada; versão do firmware desconhecida. |
| Klipper | Geração existente; envio incompatível a Marlin bloqueado | Envio direto não implementado/validado nesta entrega. |
| SimuCNC TCP real | `verify_print_tcp.py`: 84 comandos, duas camadas, aquecimento e Z final 5,4 mm | Aprovado em Windows x86_64; movimentos lineares, inicialização padrão. M73/M486 são metadados confirmados em ordem; M200 D0 seleciona o único modo E modelado. Mesh, pressure advance e arcos não simulados. |

## Evidências e reprodução

Evidência final em `docs/qa/impressao-3d-2026-10-15/`: 39 regressões, 2 testes de interface, integração TCP, log TX/RX, G-code de duas camadas (4 × 4 × 0,4 mm) e manifesto SHA-256. A pasta de 14/10 preserva a rodada anterior e a caixa de 20 × 20 × 3 mm usada pelo transporte falso com perfil Ender-3 S1. Nenhuma amostra é o arquivo original do defeito ou perfil calibrado para a Ender 3 do usuário; não enviá-las automaticamente à máquina.

Ambiente: Windows, Free Pascal 3.2.2, Lazarus instalado em C:/lazarus, alvo x86_64-win64. A tentativa inicial de GUI i386 falhou em loops Int64 preexistentes de `multicad_mesh.pas`; as aplicações e os testes GUI compilaram e passaram em 64 bits.

Com FPC e dependências do projeto disponíveis:

```powershell
$env:FPC='C:/lazarus/fpc/3.2.2/bin/i386-win32/fpc.exe'
$env:MULTICNC_TEST_FLAGS='-Px86_64 -Twin64'
python tools/verify_suite.py console multislicer . laserpcb makerouter
python tools/verify_print_tcp.py
```

O CI existente descobre todos os testes `.lpr` de console, incluindo `test_print_safety.lpr`. A integração TCP também foi adicionada ao CI, com coleta de evidências. Não foi executado CI remoto. Compilar `multislicer/tests/test_slicer_app.lpi` e `tests/test_app.lpi` para x86_64 e executar os binários reproduz os testes de interface. Esses testes usam perfis temporários.

## Limitações e próximos critérios

- A limitação de vazão cobre trajetórias do núcleo e comandos lineares de purga/start/end suportados pelo verificador. Templates não verificáveis são recusados. Os tempos estimados do fatiador não incluem integralmente aquecimento, templates e desacelerações do firmware.
- Auditoria é parcial: não interpreta macros, todos os offsets, G-code arbitrário ou estados prévios do firmware; não substitui validação física. Não há suporte novo dedicado a pontes.
- A interface usa envio de uma linha com resposta, sem numeração/checksum; Resend nela resulta em falha, não reprodução cega. O componente separado `TGCodeStreamer` tem checksum e retransmite somente a linha pendente válida.
- Silêncio significa ausência de dados. Um firmware que emite mensagens indefinidamente sem terminar um comando exige intervenção; não há timeout total de aquecimento calibrado para a Ender 3 do usuário.
- Aceleração/jerk e limites por material ainda precisam de calibração e caracterização; os novos limites configuráveis não provam capacidade física.
- Pendente: primeira camada, cubo 20 mm, retrações, pausa/cancelamento, intertravamentos e parada de emergência em equipamento físico identificado. A integração TCP real foi concluída.
- Nenhum instalador/release foi gerado. Estado: software corrigido e testado no escopo acima; não validado em equipamento e não liberado para usuários como release de impressão 3D.

Executáveis de desenvolvimento atualizados em `bin/multislicer.exe`, `bin/multicnc.exe` e `bin/SimuCNC.exe`; não constituem instalador/release validado em equipamento. Integração TCP final: 84 comandos em **58,532 s**, sem falhas.
