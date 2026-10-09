# 05 — MultiCNC PCB

## Finalidade

Preparar geometrias de PCB para processo a laser. A expressão “fabricação de PCB” precisa ser associada ao processo físico disponível; não assumir que qualquer laser remove cobre diretamente.

Hipótese para a primeira versão: remoção de máscara/revestimento para uma etapa posterior de corrosão, sujeita à confirmação do usuário. Exposição de material fotossensível ou remoção direta de cobre exigem perfis e validações próprios. O processo químico não é automatizado pelo software nesta proposta.

## Fluxo e telas

Importar camadas → definir face/unidades → conferir contorno e alinhamento → escolher processo e material → configurar compensação e preenchimento → visualizar áreas expostas/preservadas → gerar trabalho laser.

Tela com camadas, seleção de face, prévia positiva/negativa, dimensões, referências de alinhamento e alertas de largura/espaçamento. Toda inversão ou espelhamento deve aparecer explicitamente na prévia.

## Módulos

- Importação proposta de Gerber para camadas e Excellon para referências de furos; implementar por biblioteca avaliada ou parser com subconjunto declarado, sem anunciar suporte completo sem testes.
- Alternativa inicial controlada: SVG com escala e unidades confirmadas.
- Normalização geométrica, polaridade, união/subtração e recorte pelo contorno.
- Configuração de diâmetro efetivo do feixe, compensação, espaçamento de varredura, velocidade, potência e passes.
- Pós-processamento por perfil de laser e geração do pacote comum.
- Registro de referências de alinhamento para placas de duas faces em etapa posterior.

## Fronteiras

Não é um editor completo de esquemáticos ou roteamento eletrônico. Os arquivos vêm de uma ferramenta de projeto de PCB. Furos importados servem inicialmente à visualização/alinhamento; sua presença não significa suporte a perfuração ou fresagem. O CAM para madeira não recebe operações de PCB implicitamente.

## Validações

Exigir confirmação de escala, face, origem e polaridade antes da exportação. Sinalizar detalhes menores que o processo configurado, sem transformar o aviso em garantia de qualidade elétrica. Não aplicar espelhamento automático oculto. Parâmetros de potência dependem do perfil, material e ensaio de processo.

## Aceite

Conjunto de placas de referência com pads, trilhas, vazios, planos e recortes; comparação geométrica de importação; testes de polaridade e espelhamento; detecção de dimensões inconsistentes; pacote aceito apenas por perfil laser compatível. Produção de uma placa funcional é um marco de bancada, separado da validação de software.
