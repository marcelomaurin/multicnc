# Posicionamento na mesa

A tela principal integra placa, cobre, furos e trajetórias ao posicionamento. Todas as coordenadas são em mm, com Y para cima.

- Área útil, margem, espaçamento, X/Y, rotação livre, escala X/Y, espelhamento Bottom e trava.
- Cópias, arraste com snap, zoom, ajuste à mesa ou às placas.
- Caixas envolventes calculadas depois da rotação/escala; transformações preservam potência e velocidade.
- Nesting considera placas travadas e zonas proibidas, verifica as cópias e preserva posições ao falhar.
- Keep-outs e colisões usam caixas conservadoras; deslocamentos rápidos não recebem roteamento entre obstáculos.
- A compensação CAM mantém o diâmetro físico do feixe depois da escala.
- Alinhamento manual por dois fiduciais na tela Posicionar. Câmera permanece indisponível.

Fluxo: importar -> posicionar -> configurar processo -> atualizar trajetórias -> validar -> exportar -> MultiCNC.

Pendente: nesting por polígonos, múltiplas chapas, câmera e persistência completa da sessão. A aplicação laserpcb_layout_app continua sendo um demonstrador legado; use laserpcb para o trabalho integrado. O movimento físico, Frame e execução permanecem no MultiCNC.
