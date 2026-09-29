# Posicionamento de PCB para CNC

Módulo específico para fabricação de PCB em CNC Router.

## Objetivos
- definir dimensões físicas da placa
- origem X/Y
- rotação e escala
- face Top/Bottom
- espelhar automaticamente Bottom quando configurado
- registro por dois ou mais furos/fiduciais
- alinhamento por dois pontos medidos
- keep-outs para grampos
- validar os quatro cantos da PCB contra a área segura

## Fabricação dupla face
Fluxo recomendado:
1. Fixar placa.
2. Definir origem.
3. Fazer furos de registro.
4. Usinar/furar primeira face.
5. Virar a placa conforme o gabarito.
6. Reposicionar pelos pinos de registro.
7. Selecionar Bottom.
8. Aplicar espelhamento/alinhamento.
9. Validar antes de gerar/enviar o trabalho.

MultiPCB define a geometria e registro; MultiCAM gera trajetórias de corte/furação; MultiCNC executa fisicamente.

## Próximos passos
Canvas visual da mesa; seleção dos furos diretamente no PCB; probing Z/height-map; alinhamento de três pontos para diagnóstico de erro; geração de gabarito; preview Top/Bottom; integração direta com operações de isolamento, drilling e board cutout.
