# MultiCAD - Guia para IA

## Missao
MultiCAD e o autor CAD da suite. Seu objetivo e criar e editar a geometria que representa pecas mecanicas. A direcao funcional e um CAD parametrico simplificado, semelhante conceitualmente a ferramentas como SolidWorks, sem tentar duplicar CAM ou controle de maquina.

## O que pertence aqui
Documento CAD, features, sketches, extrusoes, transformacoes geometricas, viewport e futuras operacoes de modelagem.

## Fontes atuais
- src/core/multicad_types.pas: tipos geometricos basicos.
- src/core/multicad_feature.pas: abstracao de feature.
- src/core/multicad_document.pas: documento e colecao de features.
- src/sketch/multicad_sketch.pas: sketch.
- src/features/multicad_extrude.pas: extrusao.
- src/ui/multicad_viewport.pas: visualizacao.
- src/app/: aplicacao Lazarus.
- tests/test_document.lpr: teste do documento.

## Entradas e saidas
Entrada: comandos de modelagem e, futuramente, formatos CAD/mesh suportados.
Saida: geometria/pecas reutilizaveis pelo MultiAssembly e MultiCAM.

## Nao pertence aqui
G-code, comunicacao serial, GRBL/Marlin, STEP/DIR, controle de spindle, PCB, slicing ou execucao fisica.

## Integracao
MultiAssembly referencia as pecas CAD na montagem. MultiCAM consome geometria para criar operacoes de usinagem.

## Regras para alteracao
Mantenha geometria independente da UI. Nao acople o documento CAD a uma maquina fisica. Preserve compatibilidade de dados e crie testes para operacoes geometricas.
