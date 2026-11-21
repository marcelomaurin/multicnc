# Referências de potência para PCB

Consulta: 10/10/2026. Dados declarados por fabricantes; watts ópticos não são a potência elétrica da fonte.

| Processo publicado | Equipamento / tecnologia | Ajuste óptico declarado | Velocidade | Aplicação no LaserPCB |
|---|---|---:|---:|---|
| Marcação da placa | J Tech, kit de 1,7 W | 1 W | 125 mm/min | Referência explícita por camada |
| Remoção de serigrafia | J Tech, mesmo ensaio | 1 W | 250 mm/min no resumo | Referência explícita; o texto também menciona 225 mm/min |
| Remoção de tinta sobre cobre | J Tech, tutorial PCB | Não informado no ensaio | 100 mm/min | Consulta; não completa watts automaticamente |
| Cobre nu | Endurance 5,6 W / 445 nm | Sem ajuste publicado | Sem valor | Consulta; a tabela não apresenta suporte para cobre |
| Processamento de placas | LPKF MicroLine 5000, UV pulsado / 355 nm | Fonte de 10 ou 15 W, sem ajuste de processo | Não informado no documento | Consulta; não usar como preset de diodo azul |

Fontes primárias:

- J Tech, ensaio de marcação e serigrafia: https://jtechphotonics.com/?p=1164
- J Tech, remoção de tinta antes da corrosão química: https://jtechphotonics.com/?p=2536
- Endurance, tabela do módulo de 5,6 W: https://www.endurance-lasers.com/products/5-6-watt-laser-attachment
- LPKF, especificações da MicroLine 5000: https://www.lpkf.com/fileadmin/mediafiles/user_upload/products/pdf/EQ/PCB-Depaneling-Processing/flyer_lpkf_microline_5000_en.pdf
- LightBurn, calibração por matriz de material: https://docs.lightburnsoftware.com/latest/Reference/MaterialTest/

## Uso por camada

Escolha a geometria do processo (vetores, isolamento, retirada, preenchimento ou furos) e o tratamento do material (tinta/verniz, cobre direto ou marcação). Configure potência, velocidade e passadas testadas para esse conjunto. O tratamento é preservado por operação; não determina sozinho uma receita de material.

A tabela não fornece parâmetros de furação através de FR4 nem valores de retirada direta de cobre por GLYPHO 5/10 W. Essas combinações permanecem manuais. Não transformar ausência de dados em velocidade ou potência inventada.

O botão de referência preenche somente os watts e a velocidade declarados; mantém as passadas já configuradas, pois o ensaio não informa esse número. A geometria da camada não é substituída. Aplicar a referência não executa nem conecta equipamento.

## Conversão nominal

Com a potência óptica nominal Wmax informada e S-max conferido em $30:

- Potência nominal solicitada = Wmax × percentual / 100.
- Comando S = S-max × percentual / 100.
- Energia nominal por passada = potência nominal × 60 / velocidade em mm/min.

Exemplo aritmético: 1 W nominal em módulo de 10 W corresponde a 10%; com S-max 1000, S100. Não é comprovação de linearidade do driver, medição de saída, nem equivalência de processo entre comprimentos de onda. M4 pode reduzir a saída durante as acelerações. Velocidade, foco, revestimento, substrato e passadas continuam exigindo calibração.

## Estimativa pela potência do laser

Em **Camadas e laser**, o botão **Estimar pela potência do laser...** calcula um ponto de partida para cada processo (`src/core/laserpcb_powerest.pas`):

- Energia necessária por mm = Ev × largura do sulco × profundidade. A profundidade vem da tinta (0,02 mm), da espessura do cobre (18/35/70/105 µm) ou da espessura da PCB (corte).
- Ev (J/mm³) depende do tipo de laser: diodo azul, IR 1064 nm pulsado ou CO2. Tinta e marcação foram ancoradas nos ensaios J Tech acima. O cobre usa a energia de vaporização (~53 J/mm³) dividida pela absorção e pela eficiência térmica. O FR4 usa a ordem de grandeza dos relatos de corte. O CO2 não remove cobre.
- Tinta e marcação: uma passada, com a potência ajustada para a velocidade preferida. Cobre e corte: potência cheia, com as passadas necessárias para chegar perto da velocidade preferida.
- Na isolação, **Passadas** continuam sendo anéis. A estimativa preenche **Repetições (isolação)**, que repete cada anel.
- Os valores aplicados ficam marcados como estimados no resumo e na validação, até serem alterados manualmente.

## Gabarito de teste (aferição)

O botão **Gabarito de teste (aferir)...** gera uma grade numa placa pequena (padrão 100 × 50 mm): linhas de potência (40/60/80/100%) × colunas de passadas (1/2/4/6/8), todas a 1 mm/s. Os rótulos com os W do laser, a velocidade, as potências e as passadas são gravados primeiro, com potência baixa. Depois vêm as células, da menor para a maior energia (`src/core/laserpcb_testgrid.pas`).

Depois de executar, clique em cada célula da prévia para marcar **Nada / Marcou / Trilha (cobre removido) / Cortou**. **Aplicar aferição** pega a menor energia que fez trilha e a menor que cortou, acrescenta 15% de margem e grava Ev de cobre e de corte no perfil (`copper_ev`, `cut_ev`). A partir daí, a estimativa de cobre e de corte passa a usar esses valores e mostra "Aferido". **Salvar relatório...** grava a grade e os resultados em CSV.
