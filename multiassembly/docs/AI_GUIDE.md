# MultiAssembly - Guia para IA

## Missao
MultiAssembly e o integrador eletromecanico da suite. Ele representa o produto ou maquina completa, relacionando componentes mecanicos e eletricos no mesmo projeto.

## Conceito fundamental
Um componente possui um ID unico. O mesmo Motor X, por exemplo, aparece na montagem mecanica e no esquema eletrico. Nunca crie copias independentes para cada vista.

## Modelo atual
- multiassembly_types.pas: componentes, portas, conexoes e relacoes.
- multiassembly_project.pas: documento da montagem.
- multiassembly_library.pas: criacao/biblioteca.
- multiassembly_demo.pas: CNC demonstrativa.
- view/: vistas mecanica e eletrica sincronizaveis.
- app/: aplicacao Lazarus.
- tests/: validacao basica.

## Componentes previstos
Pecas CAD, motores, spindle, fuso, guias, rolamentos, polias, correias, controladores, drivers, fontes, VFD, reles, sensores, endstops, E-Stop, conectores e PCBs.

## Relacoes
Eletricas: power, ground, STEP, DIR, ENABLE, PWM, entradas/saidas e comunicacao.
Mecanicas: fixed, axis, coupled, belt e lead screw.

## Integracao
MultiCAD fornece referencias de pecas. MultiPCB fornece placas/conectores. MultiAssembly descreve a montagem. MultiCNC futuramente pode derivar perfil da maquina dessa descricao.

## Nao pertence aqui
Gerar toolpath, fatiar STL, enviar comando para hardware ou substituir o CAD/EDA.

## Proximos requisitos
Persistencia do projeto, editor de propriedades, drag/drop, desenho grafico de fios, importacao MultiCAD/MultiPCB, montagem 3D, BOM e validacao de compatibilidade eletrica/mecanica.
