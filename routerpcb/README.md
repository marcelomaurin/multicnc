# RouterPCB

> **Estado:** planejado (08/10/2026). A ferramenta está documentada e a implementação
> está descrita passo a passo em [docs/TAREFA.md](docs/TAREFA.md). Ainda não há código
> nem executável.

O **RouterPCB** é a ponte que faltava entre o **MakePCB** e o **MultiCNC no modo CNC Router**.
Ele recebe a pasta Gerber + Excellon exportada pelo MakePCB e gera os programas G-code
para **fresar a placa** na router. Isso inclui a isolação das trilhas, a furação e o recorte
do contorno, com nivelamento opcional da superfície por sondagem (*autolevel*).

```text
                         +--> LaserPCB  (isolação a laser) ----> MultiCNC (CNC Laser)
MakePCB --Gerber+Excellon+
                         +--> RouterPCB (fresagem mecânica) ---> MultiCNC (CNC Router)
```

O **LaserPCB** cobre quem tem laser. O **RouterPCB** cobre quem tem uma router (CNC 3018,
fresadora de bancada etc.) e quer produzir a placa com fresa V e broca, como no FlatCAM.

## O que a ferramenta faz

| Etapa | O que acontece |
|---|---|
| **1 Importar** | Abre a pasta `<nome>_gerber` do MakePCB (ou arquivos soltos). Reconhece cobre Top/Bottom, contorno (Edge_Cuts) e furos PTH/NPTH pelo nome no padrão KiCad e pelo atributo X2. Escolhe o lado a fresar; placa de face simples abre em Bottom. |
| **2 Isolação** | Contorna o cobre com fresa em V (ângulo, ponta e profundidade definem a largura do corte) ou com fresa de topo. Tem número de passadas, sobreposição e sentido de corte (concordante ou discordante). Avisa quando a folga entre cobres é menor que a largura da fresa. |
| **3 Furação** | Agrupa os furos por diâmetro e ajusta cada um à broca disponível mais próxima. Ordena o percurso, faz bicadas e rasgos, pausa (M0) na troca de broca ou gera um arquivo por broca. Furos maiores que a maior broca podem ser fresados em círculo. |
| **4 Recorte** | Fresa o contorno da placa por fora, com a compensação do raio da fresa, em várias profundidades. Deixa pontes (*tabs*) com largura e altura configuráveis. Recortes internos são fresados por dentro. |
| **5 Nivelamento** | Gera o programa de sondagem em grade (G38.2) e importa as alturas medidas: linhas `[PRB:...]` do log salvo no MultiCNC ou um CSV X;Y;Z. A correção de Z é aplicada à isolação, com interpolação bilinear e segmentos subdivididos. |
| **6 Saída** | Valida tudo, estima o tempo e grava os programas na ordem de execução: `0_sondagem`, `1_isolacao`, `2_furos_T1...`, `3_recorte`. O botão "Abrir no MultiCNC" abre o primeiro programa já em CNC Router. |

## Princípios

- **Zero da máquina:** X/Y no canto inferior esquerdo da placa (já espelhada, quando o lado é
  Bottom) e Z na superfície do cobre. É o mesmo zero em todos os programas, para trocar a fresa
  sem perder a referência X/Y.
- **G-code GRBL puro:** `G0`, `G1`, `G4`, `M0`, `M3`, `M5` e `G38.2` (só na sondagem). Não usa
  ciclos fixos, ponto decimal sempre e linhas com até 127 caracteres. Isso vale para o
  GRBL e para o SimuCNC.
- **Cabeçalho:** `; RouterPCB -> MultiCNC (CNC Router)`, para o MultiCNC abrir em modo Router.
- **Segurança:** o RouterPCB só prepara trajetórias e não fala com a máquina. Conexão, limites,
  parada e execução continuam no MultiCNC. Parâmetros inválidos nunca gravam nem sobrescrevem
  um arquivo de G-code.
- **Reuso:** os importadores Gerber/Excellon, as máscaras raster, a isolação, as pontes e o plano de
  furação vêm do LaserPCB (`laserpcb/src/{geom,import,cam,drill}`). O RouterPCB não duplica
  esse código.
- **Visual:** segue o padrão da suíte, igual ao LaserPCB e ao MakePCB: cabeçalho
  `TSuiteHeader`, barra lateral de etapas, painel de parâmetros à direita, prévia no centro e
  rodapé com Validar, Gerar G-code e Abrir no MultiCNC.

## Documentação

- [docs/TAREFA.md](docs/TAREFA.md): plano de implementação, com fases, arquivos, critérios de
  aceite e checklist de integração.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): unidades, dados e algoritmos.
- [docs/AI_GUIDE.md](docs/AI_GUIDE.md): responsabilidades e limites, para quem for alterar o
  código.
