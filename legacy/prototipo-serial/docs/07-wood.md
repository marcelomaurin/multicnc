# 07 — MultiCNC Wood

## Finalidade

Desenvolver peças de madeira e preparar trajetórias para CNC router. Começar por CAD/CAM 2D e 2,5D; superfícies 3D são evolução posterior. O produto não pretende oferecer um modelador mecânico paramétrico completo no primeiro marco.

## Fluxo e telas

Definir estoque → desenhar/importar contornos → estabelecer origem → cadastrar ferramenta → criar operações → ordenar trajetórias → visualizar remoção e deslocamentos → exportar trabalho.

Editor geométrico, árvore de operações, biblioteca de ferramentas, painel do estoque e prévia de trajetórias com alturas Z.

## Módulos e operações

- Desenho simples com dimensões, formas, encaixes e repetição.
- Importação SVG inicialmente; DXF por subconjunto documentado após seleção da biblioteca.
- Estoque com largura, altura e espessura; origem de trabalho explícita.
- Ferramentas com diâmetro, comprimento útil e parâmetros do processo.
- Contorno interno/externo, bolsão e furação com estratégias homologadas.
- Profundidade por passe, avanço de corte/mergulho, altura de segurança, rampas e pontes de fixação.
- Planejamento e pós-processamento por perfil, com prévia do envelope de movimento.

## Restrições da primeira versão

Um trabalho usa uma única ferramenta. Peças com várias ferramentas geram trabalhos separados com preparação explícita entre eles. Troca automática/manual dentro do mesmo programa entra depois de definir suporte do controlador. Compensação de raio é calculada no CAM inicialmente; não depender de compensação do firmware sem homologação.

A prévia inicial mostra trajetórias e limites conhecidos; não deve ser anunciada como detecção completa de colisões ou simulação física da usinagem. Fixações e regiões proibidas precisam ser modeladas para qualquer análise posterior.

## Validações

Recusar geometrias abertas em operações que exigem contorno fechado, ferramenta incompatível com o bolsão, profundidade além do comprimento útil conhecido e movimentos fora do envelope configurado. Origem, espessura e altura livre são parâmetros obrigatórios; não inferi-los do desenho silenciosamente.

## Aceite

Peça de referência com contorno, bolsão e furos; offsets comparados a resultados esperados; passes com profundidade limitada; recuos e deslocamentos coerentes; exportação com perfil registrado. Teste físico começa com execução sem corte conforme roteiro do equipamento, seguido de peça de validação em material escolhido.
