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

## Estratégias modernas (multicam_hsm, multicam_feeds)
- **Trocoidal** (`THSMCAM.TrochoidalSlot`): laços circulares com avanço por volta, engajamento radial baixo e constante, usando toda a altura de corte.
- **Pocket por offsets** (`OffsetPocket`): anéis paralelos ao contorno, de dentro para fora, sem retração, com entrada helicoidal (rampa quando a hélice não cabe).
- **Perfil compensado** (`CompensatedProfile`): offset arredondado pelo raio da fresa, sobremetal, entrada em rampa de 3° ao longo do contorno, passe de acabamento e tabs.
- **Feeds & speeds** (`ComputeFeedsAndSpeeds`): rotação por Vc, avanço por dente, fator de afinamento de cavaco, MRR e potência, limitados pelo spindle.
- **Pós-processador** (`TCamGCode.BuildProgram`): saída modal, cabeçalho com ferramenta e limites, `G4` para o spindle e *arc fitting* G2/G3 (`src/shared/multisuite_arcfit`).

Convenção de sentido com `M3`: concordante = anti-horário em paredes internas e horário em contornos externos.
