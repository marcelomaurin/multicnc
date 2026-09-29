# MultiCAM - Guia para IA

## Missao
MultiCAM prepara fabricacao por CNC Router. Ele transforma geometria e operacoes em trajetorias e G-code, com simulacao antes da execucao.

## Nucleo
- core/multicam_types.pas: tipos de CAM, ferramenta, stock e movimentos.
- core/multicam_job.pas: TCamJob.
- core/multicam_engine.pas: operacoes base.
- core/multicam_validator.pas: validacao.
- mechanical/: facing, pocket, drilling, slot, contour, ramp, helix, tabs, setup e biblioteca de ferramentas.
- export/multicam_gcode.pas: G-code.
- simulation/: modelo da maquina, motores, spindle, eletronica, heightmap, remocao de material, sinais e sessao integrada.
- app/multicam_simulator*: simulador independente.
- mechanical/multicam_demo_job.pas: demonstracao pocket + furos + contorno.

## Responsabilidade
Definir ferramenta, stock, zero, operacao, profundidade, stepdown/stepover, feed/plunge/RPM; produzir toolpath; validar; simular; exportar.

## Simulacao
A simulacao atual inclui cinemática, eletronica virtual, dinamica simplificada de motor/spindle, trace de sinais e remocao por heightmap. Parte do modelo ainda e aproximada; nao trate resultados como simulacao industrial validada.

## Integracao
MultiCAD fornece geometria. MultiAssembly pode fornecer perfil eletromecanico da maquina. MultiCAM produz o trabalho. MultiCNC e responsavel por executar fisicamente.

## Nao pertence aqui
Abrir porta serial, controlar GRBL/Marlin diretamente ou substituir MultiCNC.

## Seguranca
Nunca transforme parametros de demonstracao em recomendacoes automaticas para maquina real. Validar limites, ferramenta, stock e trajetoria antes de exportar/executar.
