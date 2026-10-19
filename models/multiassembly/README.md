# Exercício do MultiAssembly

`cnc_demo.massembly` (CC0-1.0): montagem de uma CNC de demonstração com 11 componentes
(estrutura, eixos, motores, fusos, eletrônica).

1. No MultiAssembly, **Abrir** → `cnc_demo.massembly` (ou pela Central da suíte; a partir
   desta versão o arquivo passado em `--file` é aberto direto).
2. Percorra as etapas **1 Projeto → 2 Componentes → 3 Montagem → 4 Conexões → 5 Verificar →
   6 Documentar**.
3. Em **5 Verificar**, confira as interferências e as ligações sem par.
4. Em **6 Documentar**, gere a lista de peças e as instruções de montagem.
5. Clique **MultiPhysics**: a montagem é salva e aberta no MultiPhysics. Lá, fixe a face
   `zmin` da peça `FRAME`, ligue a gravidade e resolva a estática
   (ver [`../multiphysics`](../multiphysics/README.md)).
