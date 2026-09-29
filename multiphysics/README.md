# MultiPhysics
Ferramenta da suite MultiSuite para simular fisicamente uma montagem proveniente do MultiAssembly.

## Dominios
- Estrutural: tracao, compressao, flexao, cisalhamento, deslocamento, tensao de von Mises e deformacao.
- Termico: calor, frio, conducao, conveccao, expansao termica e acoplamento termo-mecanico.
- Contato: contato entre pecas, pressao de contato e atrito.
- Dinamico: vibracao, frequencias naturais/modal, cargas variaveis e aceleracao.
- Fluido: ambiente, velocidade, densidade, viscosidade e arrasto; CFD/FSI sera backend separado.

## Arquitetura
MultiAssembly define a montagem. MultiPhysics acrescenta materiais, malha, contatos, cargas e condicoes de contorno. O solver produz campos de temperatura, deslocamento, tensao, deformacao, contato e frequencias.

O primeiro backend preparado e CalculiX. O programa nao inventa resultado se nao houver malha/solver: o solve permanece bloqueado ate o pre-processamento produzir uma malha FEM valida.

## Proximas etapas numericas
1. importar geometria/assembly;
2. gerar malha tetraedrica;
3. mapear faces/volumes para sets FEM;
4. gerar deck CalculiX completo;
5. executar ccx;
6. importar FRD/DAT;
7. mapa de cores sobre a montagem;
8. animacao de deformacao e modos de vibracao;
9. backend CFD/FSI para arrasto;
10. validacao contra casos analiticos.
