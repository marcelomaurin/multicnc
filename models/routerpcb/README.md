# Exercício do RouterPCB

Usa os Gerbers do pisca 555 em [`../makepcb/pisca_555_gerber`](../makepcb/README.md)
(placa 50,8 × 38,1 mm, face simples, cobre na face inferior).

1. No RouterPCB, **Abrir pasta...** → `models/makepcb/pisca_555_gerber`
   (ou, no MakePCB, **Abrir no RouterPCB**; ou **Abrir pasta do MakePCB...**).
   Esperado: 6 arquivos lidos, placa 50,8 × 38,1 mm.
2. **2 Isolação:** fresa em V, 1 a 3 passadas de isolação em volta das trilhas.
3. **3 Furação:** os furos do PTH/NPTH agrupados por diâmetro (uma troca de broca por grupo).
4. **4 Recorte:** contorno da placa com pontes de fixação.
5. **5 Nivelamento:** malha de sondagem para compensar o empeno da placa (opcional).
6. **6 Saída:** **Validar agora** e **Gerar G-code...**; **Abrir no MultiCNC** para simular
   antes de fresar.

Na face simples, o cobre é inferior: o RouterPCB espelha a isolação para a placa ser fresada
virada para cima.
