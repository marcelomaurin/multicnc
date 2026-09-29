# MultiSlicer Architecture

Input (STL/3MF) -> Mesh -> Transform -> Slice -> Contours -> Perimeters/Infill/Support -> Toolpath -> G-code -> MultiCNC.

A versão inicial implementa STL ASCII, interseção geométrica por camada e G-code experimental.

## Necessário antes de produção
STL binário e 3MF; reparo de malha; união/ordenação de segmentos em polígonos; perímetros; largura de extrusão; infill; top/bottom; suportes; bridge; retração; seam; velocidades/aceleração; cooling; brim/raft/skirt; multi-material; preview; estimativas; perfis; testes contra modelos de referência.

O cálculo de extrusão inicial é deliberadamente simples e deve ser substituído pelo cálculo volumétrico antes de imprimir peças reais.
