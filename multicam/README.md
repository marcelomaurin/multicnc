# MultiCAM

CAM/fatiador para CNC Router integrado ao MultiCNC.

## Fluxo
Modelo/contorno -> stock -> ferramenta -> operações -> passes Z -> toolpath -> simulação -> G-code -> MultiCNC.

## Operações alvo
- perfil externo/interno
- pocket
- furação
- faceamento
- gravação
- V-carve (evolução)
- 2.5D por camadas
- relevo 3D (evolução)

## Segurança
MultiCAM prepara trajetórias; MultiCNC controla a máquina. Dimensões, origem, ferramenta, profundidades, spindle e feeds devem ser conferidos antes da execução física.

### Colisoes no simulador

O simulador permite configurar ferramenta/porta-ferramenta e fixacoes, verificar
o percurso antes de reproduzir e bloquear o primeiro segmento com colisao.
Consulte [uso e limites da verificacao XYZ](docs/COLLISION_DETECTION.md).
