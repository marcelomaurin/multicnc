# Compensação Z segmentada

Para isolamento de PCB, corrigir Z apenas nos vértices originais pode ser insuficiente quando um segmento é longo.

O segmentador divide movimentos de corte XY em trechos de no máximo MaxSegmentMM e calcula o Z da superfície para cada novo ponto.

## Proteções
- rapid e Safe-Z não são subdivididos/compensados
- pontos de corte fora dos limites do height-map são rejeitados
- MaxCorrection continua obrigatório
- erro limpa o job de destino
- o job original permanece intacto

Quanto menor MaxSegmentMM, melhor a aproximação da superfície e maior o G-code. O valor deve ser configurável e validado no processo real.
