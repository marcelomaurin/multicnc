# Gerador dos arquivos de exercício

`make_exercises.lpr` cria os arquivos de exercício dos programas da suíte em `models/`, usando
os mesmos núcleos dos programas, e recarrega cada arquivo para conferir. Rode de novo quando o
formato de algum projeto mudar.

```
C:\lazarus\lazbuild.exe --cpu=x86_64 --os=win64 --ws=win32 tools\exercises\make_exercises.lpi
tools\exercises\make_exercises.exe models
```

Saída esperada: `PASS exercicios gerados`.

| Pasta | Arquivos | Conferência |
|---|---|---|
| `models/laserart` | caixa com encaixes, placa de identificação, engrenagem + estrela | recarrega e gera G-code |
| `models/makepcb` | pisca 555 sem trilhas, roteado e Gerbers | 0 falhas no roteamento, DRC limpo; RouterPCB e LaserPCB importam os Gerbers |
| `models/makerouter` | demonstração e porta-copos | recarrega desenhos e percursos |
| `models/multicad` | placa com furos, cantoneira L | reconstrução sem erros |
| `models/multiassembly` | montagem da CNC de demonstração | 11 componentes |
| `models/multicnc` | `quadrado.nc` (manual do MultiCNC, cap. 27) | — |

Os exemplos do MultiPhysics (`models/multiphysics`) vêm dos testes do próprio MultiPhysics.
