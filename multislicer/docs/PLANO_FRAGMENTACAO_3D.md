# Plano de implementação — Fragmentação de modelos 3D no MultiSlicer

- Data: 17/10/2026
- Status: **especificação; recurso ainda não implementado**
- Branch: `fila`
- Aplicação: MultiSlicer, etapa 2 Modelo
- Prioridade: P1 — peça maior que volume útil da impressora

## Objetivo

Dividir uma malha STL/3MF maior que o volume útil de impressão em componentes independentes e **watertight**, exportáveis como `peca_parte01.stl`, `peca_parte02.stl` etc. Cada parte deve permanecer editável (posição, rotação, escala, orientações e suportes) antes de gerar seu G-code. **Fragmentar** é uma operação de geometria 3D anterior ao **fatiamento** de impressão; os arquivos de saída das partes são STL, não fatias 2D.

## Interface

- Na etapa **2 Modelo**, após seleção de objeto: botão **Fragmentar peça...**.
- Janela modal com volume útil do perfil (X/Y/Z), dimensões atuais da peça e alerta se a peça não couber.
- Modo **Automático**: determinar cortes nos eixos X/Y/Z para maximizar tamanho das partes sem exceder volume útil, permitindo margem de segurança configurable e rotação/arranjo de cada parte.
- Modo **Manual**: selecionar eixos e planos de corte; informar posições em mm ou número de divisões por eixo.
- Exibir prévia 3D colorida com planos de corte, numeração e limites, antes de confirmar.
- Controles **Aplicar**, **Cancelar**, **Desfazer** (Ctrl+Z), **Refazer** (Ctrl+Y).
- Após confirmar, manter peça original recuperável pelo undo; criar partes individualmente selecionáveis, transformáveis e removíveis; não criar G-code automaticamente.
- Permitir salvar partes como STL binário: `<base>_parte01.stl` etc., e opcionalmente salvar um manifesto `<base>_partes.json` com origem, transformação, eixo/planos de corte, volume e relação entre peças.
- A exportação deve preservar escala e orientação das partes sem alterar o STL de origem.

## Algoritmo geométrico exigido

1. Trabalhar em coordenadas bem definidas (objeto local × cena); evitar perda de rotação ou aplicação de escala dupla.
2. Validar malha de entrada: faces degeneradas, buracos, normais inconsistentes, auto-interseções e componentes desconexos. Informar se o corte seguro não for possível.
3. Cortar triângulos por planos com tolerâncias robustas; interpolar arestas e triangularizar os polígonos recortados.
4. Reconstruir interseções planas em loops fechados, distinguindo contornos externos e furos; gerar tampas (caps) trianguladas com orientação de normais correta.
5. Remover triângulos degenerados/duplicados, soldar vértices dentro da tolerância e validar manifoldness/watertightness **de cada parte**, volume positivo e ausência de superfícies abertas.
6. Considerar que dividir por caixa sem fechar as novas superfícies não gera STL pronto para impressão. Não exportar peça com falha silenciosa: mostrar diagnóstico e pedir correção.
7. Modo automático: calcular grade de corte por limites efetivos X/Y/Z menos margens, minimizar número de partes e evitar peças minúsculas. Validar volume útil após cada transformação e possível rotação.
8. Futuro: acrescentar pinos de alinhamento, encaixes macho/fêmea e tolerâncias por material; não adicionar geometria de montagem implicitamente na primeira versão.

## Arquitetura sugerida após leitura do projeto

- **Novo núcleo**: `multislicer/src/core/multislicer_fragment.pas` para geometria de corte/caps, sem LCL/UI.
- **Entrada**: `TMesh` e `TTriangle` (`multislicer_mesh.pas`); aplicação de transformações usando `TSliceObject.WorldMesh` e `TSliceScene` (`multislicer_scene.pas`).
- **Interface**: `multislicer/src/app/multislicer_main.pas`; preferir um formulário dedicado `multislicer_fragment_form.pas` a sobrecarregar a janela principal.
- **Exportação**: reutilizar ou acrescentar módulo de escrita **STL binário**; verificar bibliotecas existentes antes de duplicar serialização.
- **Histórico**: integrar com a captura/restauração completa da cena. Verificar se undo preserva inclusão/exclusão de objetos e recursos de suporte; não presumir que o undo atual de transformação cubra mudanças estruturais.
- **Projeto**: integrar partes ao formato `.mslice` e garantir caminhos relativos/portabilidade de arquivos.
- **Limites**: conferir todos os fragmentos após rotação, escala e acomodação na mesa. Não confundir `PrintStartZ` com altura útil; considerar o degrau inicial Z ao calcular o espaço disponível.

## Plano de execução

| ID | Prioridade | Tarefa | Estado |
|---|---|---|---|
| FRAG-001 | P0 | Investigar estruturas de malha, undo de cena, import/export e testes | [ ] |
| FRAG-002 | P0 | Núcleo de corte por plano com triangulação e caps robustos | [ ] |
| FRAG-003 | P0 | Verificador de estanqueidade/manifold e diagnóstico de falhas | [ ] |
| FRAG-004 | P1 | Formulário manual com X/Y/Z, número de partes e cotas | [ ] |
| FRAG-005 | P1 | Partes como objetos editáveis, com undo/redo da operação | [ ] |
| FRAG-006 | P1 | Exportação STL individual e nomenclatura sequencial | [ ] |
| FRAG-007 | P1 | Divisão automática por volume útil e margens | [ ] |
| FRAG-008 | P1 | Prévia 3D, testes de dimensões e integração com slicer | [ ] |
| FRAG-009 | P2 | Manifesto de montagem e rastreio das posições originais | [ ] |
| FRAG-010 | P2 | Pinos e encaixes opcionais para posterior montagem | [ ] |

## Critérios de aceite

- [ ] Cubo sólido 400×200×100 mm dividido para mesa 220×220×250 mm gera no mínimo dois STLs estanques, cada qual dentro da área útil.
- [ ] Fragmentação manual permite escolher apenas X, apenas Y/Z ou qualquer combinação.
- [ ] Os planos de corte internos resultam em faces tampadas com orientação correta, não em malhas abertas.
- [ ] Partes são selecionáveis e transformáveis pelo formulário de escala (%/mm), com atualização imediata da prévia.
- [ ] Desfazer restaura exatamente a peça original, e refazer reproduz todas as partes.
- [ ] Exportar, importar novamente cada STL e fatiar com sucesso, sem alteração indevida de dimensões.
- [ ] Conservar orientação e posicionamento relativos no manifesto; suporte a reconstrução futura.
- [ ] Testar sólidos com furos, partes não convexas, peças rotacionadas e malhas inválidas, sem falhas silenciosas.
- [ ] Executar testes FPC/Lazarus e inspeção visual, e validar ao menos uma impressão física de parte fragmentada.

## Riscos e regras

- Um corte através de furos, cascas múltiplas ou malha não-manifold pode produzir caps incorretos: não declarar conclusão até testar.
- Sem encaixes, as partes exigem processo externo de colagem/alinhamento.
- Não sobrescrever automaticamente `peca.stl`; usar nomes sequenciais e verificar colisões de arquivos.
- A fragmentação deve ser opcional e acionada pelo usuário, mesmo quando o programa detectar tamanho excedente; alertas e prévia devem ser informativos.
- Este documento não significa que a fragmentação ou exportação STL das partes esteja implementada.

## Implementação inicial — 17/10/2026

- [x] `multislicer/src/core/multislicer_fragment.pas`: primeiro algoritmo de corte de triângulos por plano ortogonal, tentativa de fechamento de contornos e escrita de STL binário.
- [x] `multislicer/src/app/multislicer_main.pas`: botão **Fragmentar e exportar STL...** na etapa Modelo, diálogo de eixo X/Y/Z e coordenada de corte, seleção de diretório e arquivos `_parte01.stl`/`_parte02.stl`, inclusão de duas partes editáveis na cena, preservação da peça original.
- [ ] Validar montagem de faces recortadas em malhas complexas, laços com furos, bordas não-manifold e verificações topológicas antes de rotular o STL como imprimível.
- [ ] Compilar com FPC/Lazarus e executar testes reais de STL importado/exportado.
- [ ] Prover prévia de corte antes da confirmação.
- [ ] Implementar divisão automática em mais de duas partes segundo volume útil e margens.
- [ ] Integrar undo/redo estrutural da inclusão/exclusão de partes; por ora, criação de fragmentos limpa o histórico de undo de transformações anterior.
- [ ] Preservar transformações relativas em manifesto e integrar plenamente à gravação `.mslice`.

**Limite funcional:** esta entrega inicial cria duas partes por um plano escolhido e mantém o modelo original. Não é a implementação completa de FRAG-001 a FRAG-010 e não deve ser usada em produção antes dos testes de malha fechada e fatiamento.
