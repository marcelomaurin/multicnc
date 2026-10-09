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

## Relação com o MakeRouter
Peças de madeira, letreiros e móveis (desenho, relevo e percursos no mesmo programa) ficam no **MakeRouter** (`makerouter/`, em desenvolvimento). Ver `makerouter/docs/TAREFA.md`, decisão D1.

## Segurança
MultiCAM prepara trajetórias; MultiCNC controla a máquina. Dimensões, origem, ferramenta, profundidades, spindle e feeds devem ser conferidos antes da execução física.

### Colisoes no simulador

O simulador permite configurar ferramenta/porta-ferramenta e fixacoes, verificar
o percurso antes de reproduzir e bloquear o primeiro segmento com colisao.
Consulte [uso e limites da verificacao XYZ](docs/COLLISION_DETECTION.md).
## Estratégias modernas (multicam_hsm, multicam_feeds)
- **Trocoidal** (`THSMCAM.TrochoidalSlot`): laços circulares com avanço por volta, engajamento radial baixo e constante, usando toda a altura de corte.
- **Pocket por offsets** (`OffsetPocket`): anéis paralelos ao contorno, de dentro para fora, sem retração, com entrada helicoidal (rampa quando a hélice não cabe).
- **Perfil compensado** (`CompensatedProfile`): offset arredondado pelo raio da fresa, sobremetal, entrada em rampa de 3° ao longo do contorno, passe de acabamento e tabs.
- **Feeds & speeds** (`ComputeFeedsAndSpeeds`): rotação por Vc, avanço por dente, fator de afinamento de cavaco, MRR e potência, limitados pelo spindle.
- **Pós-processador** (`TCamGCode.BuildProgram`): saída modal, cabeçalho com ferramenta e limites, `G4` para o spindle e *arc fitting* G2/G3 (`src/shared/multisuite_arcfit`).

Convenção de sentido com `M3`: concordante = anti-horário em paredes internas e horário em contornos externos.
