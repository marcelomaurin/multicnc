# Controle de colisao XYZ — primeira versao

O simulador MultiCAM verifica cada segmento **antes** de atualizar a posicao,
a eletronica e o material. A verificacao abrange o caminho da posicao inicial
ate o primeiro movimento. Ao encontrar contato, conserva a ultima posicao
segura (inicio do segmento), pausa o player e desliga os sinais simulados via
EStop. A posicao prevista de primeiro contato aparece no log e em vermelho.
Nao ha execucao parcial ate o contato nesta versao.

## Uso

1. Carregue a demonstracao. Ela usa um porta-ferramenta de exemplo de 20 x
   35 mm; esses valores nao descrevem automaticamente uma maquina real.
2. Abra **Configurar ferramenta e fixacoes**. Informe diametros, comprimento
   de corte, comprimento exposto, porta-ferramenta, posicao inicial, plano
   protegido da mesa e margem. Todos os valores estao em mm nas mesmas
   coordenadas de trabalho. A base e o topo das fixacoes sao coordenadas Z.
3. Uma fixacao por linha: `nome;X;Y;largura;altura;baseZ;topoZ`.
   Exemplo: `Grampo;40;0;10;20;-10;8`.
4. Clique **Verificar colisoes** para analisar numa copia independente do
   material. A verificacao para no primeiro problema e nao modifica a peca
   que esta sendo reproduzida.
5. **Play** e **Passo** usam a mesma verificacao. Ao bloquear, corrija a
   montagem/programa e reinicie. **Stop** ou **Reset eletronica** restauram
   o material inicial e o estado de verificacao.

A montagem editada permanece em memoria nesta versao; reabra a configuracao
apos carregar outra demonstracao ou reiniciar o aplicativo. Dimensoes
incompletas bloqueiam a verificacao em vez de indicar ausencia de colisao.

## Geometria e regras

- Segmento contra caixas expandidas pelos volumes de corte, haste e
  porta-ferramenta. Intersecao continua por intervalos, independente do
  temporizador ou da velocidade de reproducao: obstaculos finos nao sao
  ignorados entre os pontos.
- Envelopes retangulares conservadores para ferramentas de secao circular:
  podem indicar contato antecipado nos cantos. A margem e configuravel;
  nao e uma tolerancia para atravessar obstaculos.
- G0 contra material restante e corte com spindle desligado sao bloqueados.
  Contato da parte cortante em avanco com spindle ativo e permitido.
  Haste e porta-ferramenta nunca removem material.
- Retirada estritamente vertical ascendente imediatamente apos um corte
  validado pode atravessar a mesma secao ja ocupada pela ferramenta. Isso
  evita falso bloqueio pelas celulas de borda do mapa; todos os demais
  volumes e obstaculos continuam sendo verificados.
- O plano protegido da mesa vale para toda a montagem. Para uma placa de
  sacrificio, configure o plano na profundidade maxima autorizada.
- O modo de colisao usa a trajetoria XYZ comandada e tempo de segmento
  calculado por distancia/avanco. O modo dinamico legado continua disponivel
  pela API sem ConfigureCollision; nao constitui verificacao de colisao.

## Limites conhecidos

A peca e um mapa de alturas 2.5D, com resolucao de max(0,25 mm, diametro/8).
Nao representa reentrancias laterais, cavidades sobrepostas, STL arbitrario,
rotacao de eixos ou deformacao. O spindle completo e a estrutura da maquina
nao sao modelados: configure o porta-ferramenta com um envelope conservador
quando aplicavel. Nao ha suporte novo a arcos: o job usa segmentos lineares.

A lista identifica o indice do movimento; o modelo atual nao guarda a linha
original do G-code. O SimuCNC serial/TCP e os componentes CHATGPT ainda nao
consomem este nucleo. Esta mudanca se aplica ao simulador MultiCAM.

O antigo TSimulationEngine.Run/ValidatePath gera apenas diagnosticos basicos;
a verificacao interativa/preflight usa TCollisionChecker e a sessao. Nao
interpretar a ausencia de mensagens do caminho antigo como validacao completa.

## Manutencao e testes

- `multicam_collision.pas`: geometria, tipo de ocorrencia, objeto, fracao e
  ponto de contato. Sem dependencia LCL ou serial.
- `TSimulationSession.ConfigureCollision/TryMove`: material atual, bloqueio
  persistente e reset. Notificacoes repetidas nao executam novamente o trecho.
- `TSimulationPlayer.BeforeMove`: impede avancar indice/posicao antes da
  autorizacao. Eventos visuais nao alteram a simulacao.
- `test_collision.lpr`: grampo entre endpoints, raio, porta-ferramenta,
  material, spindle, haste, mesa, curso, retirada, reset e veto do player.
- CI MultiCAM executa o teste e inclui o caminho de exportacao ausente.

Validacao local: dez programas de teste do MultiCAM passaram com FPC 3.2.2,
verificacao de intervalos e overflow habilitadas. Interface compilada com
Lazarus 3.0/LCL nogui; sem validacao visual em desktop ou maquina real.
