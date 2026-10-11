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
