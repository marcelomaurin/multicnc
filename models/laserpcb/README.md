# Exercício do LaserPCB

Usa os Gerbers do pisca 555 em [`../makepcb/pisca_555_gerber`](../makepcb/README.md).

1. No LaserPCB, **Abrir arquivos...** e selecione os arquivos da pasta
   `models/makepcb/pisca_555_gerber` (ou, no MakePCB, **Abrir no LaserPCB**).
   Esperado: 4 camadas (cobre, máscara, contorno, serigrafia) e 2 arquivos de furação.
2. **1 Placa:** confira o tamanho (50,8 × 38,1 mm) e a posição na mesa.
3. **2 Posicionar componentes** e **3 Trilhas:** visualização das camadas importadas.
4. **4 Camadas e laser:** escolha o que gravar (remoção da tinta/verniz em volta do cobre, ou
   máscara) e a potência/velocidade do laser.
5. **5 Validar e gerar:** **Gerar G-code** e **Salvar G-code...**; **Abrir no MultiCNC** para
   simular.

Os furos não são feitos pelo laser de diodo: use a furação do RouterPCB ou uma furadeira.
