# Painel MultiCNC

O projeto `src/app/multicnc.lpi` abre o painel desktop Lazarus/LCL.

## Operação

1. Escolha a máquina e o protocolo (GRBL ou Marlin são independentes).
2. Conecte o simulador local.
3. Abra um programa `.nc`, `.gcode`, `.tap` ou `.ngc` de até 5 MB.
4. Inspecione os comandos na aba Programa e clique em Iniciar.
5. Acompanhe a contagem de comandos enviados; use Pausar, Retomar ou PARAR.
6. Consulte a aba Console para respostas e comandos manuais.

O movimento manual permite passo de 0,01 a 100 mm e avanço de 1 a
10.000 mm/min. Os eixos são habilitados conforme a capacidade da máquina.
Durante execução ou pausa, abertura de arquivos, troca de conexão, Home,
jog e envio manual ficam bloqueados. Ao reiniciar, o programa volta ao início.
O console preserva as últimas 1.000 linhas. Arquivos inválidos não substituem
o programa carregado. Fechar uma simulação ativa solicita confirmação.

## Limites explícitos

Esta versão usa exclusivamente o transporte simulado já existente. Ela confirma
envios, sem interpretar trajetórias, estimar duração, atualizar coordenadas ou
validar a segurança geométrica do G-code. Progresso significa comandos enviados
ao simulador, não movimentos concluídos. PARAR não é um E-stop físico.
Não conecta dispositivos reais. Streaming para hardware requer confirmação
por comando, tratamento de erros/alarmes e reconciliação do estado do controlador.
Linhas vazias, comentários completos e delimitadores `%` são omitidos da lista.

## Organização

- `mainform.pas`: composição visual e interação.
- `multicnc_session.pas`: estados, carregamento transacional e execução simulada.
- Drivers de protocolo e transporte continuam nas unidades existentes.

As interfaces CORBA não fazem contagem automática de referências; a sessão
possui e libera explicitamente máquina, protocolo e transporte.

## Validação

Compilação da aplicação: `lazbuild src/app/multicnc.lpi`.

Teste independente da interface (crie `build` antes):

```text
fpc -Fusrc/app -Fusrc/core -Fusrc/protocols -Fusrc/transports -FUbuild -FEbuild -gh -gl tests/test_session.lpr
```

Execute o binário `test_session` gerado. `tests/test_simulator.lpr` mantém a
cobertura existente do núcleo. `tests/test_app.lpr` requer os caminhos das units
LCL e do widgetset local; verifica criação do formulário e habilitação dos
controles ao conectar e desconectar.

Verificado no Windows com Lazarus e FPC 3.2.2: build GUI, teste da sessão com
heap tracing (zero blocos pendentes), teste do simulador e teste de criação GUI.
Inspeção visual interativa e validação em Linux não foram realizadas.

## Inspeção e diagnóstico

- `Ctrl+O`: abre um programa quando a simulação está parada.
- `Ctrl+F`: leva o foco à busca na aba Programa.
- `F3` ou Enter no campo de busca: encontra a próxima ocorrência e retorna ao
  início ao atingir o fim. A busca de comandos ignora caixa ASCII (G1/g1).
- O resultado identifica o comando na lista carregada, não a linha do arquivo
  original: comentários e linhas vazias são removidos no carregamento.
- Arraste um único arquivo para a janela para abri-lo. Abertura por arrastar
  respeita os mesmos bloqueios durante execução/pausa que o botão Abrir.
- Na aba Console, use Salvar registro para exportar as linhas disponíveis em
  texto ou Limpar console para esvaziar a visualização. Salvar solicita
  confirmação antes de substituir um arquivo existente. O limite permanece
  em 1.000 linhas; a exportação não recupera linhas removidas anteriormente.

O teste GUI também verifica busca, retorno ao início, seleção após texto UTF-8,
atalho F3, abertura por arrastar e bloqueio durante execução e pausa.
