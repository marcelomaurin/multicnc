# MultiSlicer

Fatiador para impressão 3D integrado ao ecossistema MultiCNC.

## Fluxo
STL/3MF -> malha -> orientação/escala -> camadas -> perímetros/infill/suportes -> preview -> G-code -> MultiCNC.

## Separação
MultiSlicer prepara o trabalho. MultiCNC conecta e controla a impressora.

## Primeira base
- modelo geométrico de triângulos
- importação STL ASCII
- perfil de impressora/material
- cálculo de planos de camada
- interseção triângulo/plano
- segmentos 2D por camada
- exportação G-code inicial
- aplicação Lazarus inicial

Não deve ser tratado como slicer de produção até receber união de contornos, perímetros, infill, suportes, retração e validação dimensional.
