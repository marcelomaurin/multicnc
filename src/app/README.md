# Painel MultiCNC

O projeto `src/app/multicnc.lpi` abre o painel Lazarus/LCL.

## Operação

1. Abra um `.nc`, `.gcode`, `.tap` ou `.ngc` de até 5 MB pelo diálogo, arrastando um arquivo ou pelo launcher (`--file`).
2. Revise a aba **Trajetória e análise**, escolha XY/XZ/YZ e configure os limites no sistema de coordenadas do programa.
3. Confira os avisos, os limites calculados e a estimativa de duração. Exporte o relatório quando necessário.
4. Escolha máquina/protocolo e conecte o simulador. Erros da análise bloqueiam **Iniciar**.
5. Use Iniciar/Pausar/Retomar/PARAR e acompanhe comandos enviados no rodapé.
6. Consulte o Console; comandos manuais e jog ficam bloqueados durante execução/pausa.

Comentários e linhas vazias permanecem no texto exibido e na numeração da análise. A sessão remove comentários completos e delimitadores apenas da lista de comandos a enviar. `Ctrl+F`, `F3` e Enter no campo de busca encontram comandos no texto original; `Ctrl+O` abre outro arquivo quando permitido. O console mantém as últimas 1.000 linhas e permite salvar/limpar o registro.

## Modelo e limites

A trajetória vem de `TGCodeAnalyzer`, também usado pela CLI, com G0/G1, arcos G2/G3, unidades, coordenadas absolutas/relativas e planos. Não existe um segundo interpretador na tela. A prévia projeta os segmentos em 2D; não é simulação de remoção de material, colisão ou cinemática.

O analisador assume origem de trabalho X0 Y0 Z0. Homing, G53, G92 e probe tornam a análise parcial; segmentos com posição desconhecida são omitidos até recuperar coordenadas lógicas absolutas. Offsets de múltiplos sistemas de trabalho e compensações de ferramenta não são uma transformação completa da máquina. A estimativa não inclui espera de aquecimento nem confirma tempo físico.

A prévia conserva até 200.000 segmentos. A análise possui limite de 1.000.000 segmentos para limitar memória e processamento; quando atingido, o relatório indica análise parcial com erro e bloqueia a simulação. Arquivos extensos devem ser divididos em trabalhos menores.

A interface usa transporte **simulado**. Contagem de comandos não significa movimento físico concluído. PARAR interrompe a sessão simulada. Protocolos, streamer e TCP existentes no núcleo ainda precisam de integração com conexão, telemetria, confirmação e estado do controlador na GUI.

## Organização e validação

- `mainform.pas`: telas e fluxo de carregamento/análise.
- `multicnc_preview.pas`: desenho dos segmentos, sem interpretar G-code.
- `multicnc_session.pas`: máquina/protocolo simulados e estados de execução.
- `multicnc_gcode_analyzer.pas`: análise, segmentos, limites e estimativa.

```bash
lazbuild src/app/multicnc.lpi
bash tests/run_all.sh .
lazbuild tests/test_app.lpi
xvfb-run -a tests/test_app  # Linux GTK2
```

O teste da tela cobre conexão, arquivo recebido, prévia de arco, limites editáveis, bloqueio de erro, preservação de comentários, busca/UTF-8, drag/drop e bloqueios de estado. Execução em hardware exige validação própria.
