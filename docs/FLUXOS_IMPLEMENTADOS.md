# Fluxos implementados e validação

## Projeto integrado

1. No MultiSuite, crie um `.msuite` numa pasta de trabalho gravável.
2. Adicione arquivos reais e selecione a ferramenta responsável.
3. Salve. A reabertura restaura arquivos e estados do workflow; internos usam caminhos relativos.
4. Dê duplo clique num artefato. O launcher transmite `--project` e `--file` com caminho absoluto.
5. Depois de exportar um resultado numa ferramenta, adicione esse novo arquivo ao projeto. As etapas são marcadas manualmente.

A demonstração cria uma pasta `cnc-demo`, um projeto e um G-code de quadrado para análise/simulação. Não inventa documentos CAD/PCB ausentes.

## Preparar G-code

No MultiCNC, abertura por launcher, diálogo e drag/drop compartilham o mesmo fluxo. A análise e a prévia usam o mesmo interpretador. Confira as projeções, configure limites e exporte o relatório. Erros bloqueiam o início no simulador local; análise parcial fica explícita. A conexão real também verifica compatibilidade de protocolo e condições da sessão, mas a análise não substitui a conferência física.

A interface MultiCNC 0.1.0.3 conecta Serial ou TCP e também oferece Simulador local. Identifica GRBL, consulta estado/posição, trata inicialização Marlin, acompanha confirmações e oferece equipamentos salvos, Frame/Outline, controle térmico e joystick. A prévia não verifica colisões nem remoção de material. Consulte o [manual ilustrado](Manuals/Manual_do_Usuario_MultiCNC_0.1.0.3_PT-BR.pdf) e o [guia do painel](../src/app/README.md).

## STL para impressão

No MultiSlicer 0.0.7.0, selecione a impressora cadastrada no MultiCNC ou use Ajuste manual. Abra um STL/3MF, configure o perfil e clique em Fatiar. Acompanhe o progresso no rodapé; Cancelar interrompe o cálculo em segundo plano. Selecione a camada na prévia 3D para ver paredes, preenchimento e suportes. A exportação usa exatamente o resultado do pipeline da prévia. Alterar altura, temperatura, mesa ou qualquer configuração invalida o programa; exportar regenera o resultado.

O motor mantém limitações geométricas: não oferece suporte completo a suportes/bridges nem resolve toda geometria autointersectante. A tela não transforma esses recursos em disponíveis.

## Testes e pacotes

Os testes de console são descobertos e compilados por `tools/verify_suite.py`, usado no Linux, Windows e instaladores. O catálogo inclui todos os testes de console. Testes GUI são executados pelo Suite CI em Xvfb. A Central trata MISSING, FAIL e ERROR separadamente de PASS, limita o tempo e captura stderr.

Cada distribuição contém o commit de origem, alvo, compiladores, hashes e resultados. Os builds requerem árvore limpa e não atualizam `releases/0.1.0`. arm64 tem runner nativo; armhf é compilado/testado em userspace emulado. Teste em placa ARM e validação de instalação/hardware permanecem verificações próprias.

## Próximas prioridades

- Validação física dos fluxos de operação e evolução da persistência de receitas/ferramentas; conexão serial/TCP e equipamentos salvos já estão na interface MultiCNC.
- Expor HSM, raster, Gerber X2, restrições CAD e cenários editáveis de MultiPhysics nas respectivas telas.
- Instalação/desinstalação automatizadas e smoke test em hardware ARM.
- Publicação por tag imutável, com manifesto/checksums e aprovação das verificações da versão.
