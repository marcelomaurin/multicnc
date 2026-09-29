# Posicionamento 3D

Preparação dos modelos antes do slicing.

Implementado no núcleo:
- múltiplos modelos
- posição X/Y/Z
- rotação X/Y/Z
- escala por eixo
- centralização
- volume da impressora X/Y/Z
- margem e espaçamento
- detecção inicial de colisão por bounding box
- auto-arrange por linhas
- transformação 3D dos vértices

A validação deve ocorrer antes do slicing.

## Limitações atuais
O bounding box considera corretamente a rotação Z para a ocupação XY, mas ainda não recalcula o AABB completo após rotações X/Y. Auto-arrange é simples e não otimiza área. Lay Flat automático ainda será implementado a partir das faces da malha.
