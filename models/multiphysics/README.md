# Exemplos do MultiPhysics

| Arquivo | Etapa | Resultado de referencia (MultiPhysics 0.2) |
|---|---|---|
| `viga_balanco.mphys` | Resolver: estatica / modal | flecha 0,201 mm; f1 204,6 Hz, f2 406,0 Hz (ENGENHARIA) |
| `suporte_motor_termico.mphys` | Resolver: termica / termomecanica | 25,0 a 29,3 C; termomecanica 0,0041 mm, 7,4 MPa |
| `casco_flutuacao.mphys` | Ambiente: Flutuacao da montagem | calado 0,195 m, GM 0,016 m (estavel) |
| `cnc_demo.massembly` | Montagem: Importar montagem | 11 pecas; fixe FRAME/zmin e resolva com gravidade |
| `filtro_rc.cir`, `retificador.cir` | Circuito | carga RC com tau = 1 ms; retificador meia onda |

Passo a passo em `multiphysics/docs/MANUAL.md`.
