# Setup 0.16: inclusao obrigatoria do SimuCNC

- Fonte do empacotamento: `cbb8f0e`; executaveis Win64 da compilacao anterior, sem alteracoes.
- Causa: componente `tools\simucnc` nao pertencia ao tipo `compact` e era opcional.
- Correcao: `Types: full compact custom; Flags: fixed`.
- 11 testes Python de empacotamento aprovados (incluem ausencia do simulador e selecao obrigatoria).
- Inno Setup 6.3.3 compilou o pacote completo com sucesso.
- Prova isolada em TEMP: mesmas secoes Types/Components e mesmo binario SimuCNC; sem registro, atalhos, autostart ou desinstalador. Aprovados full, compact e custom (custom solicitando apenas MultiCNC); SimuCNC extraido com hash identico nos tres.
- Manifesto do staging e hashes dos binarios conferidos.
- Nao foi executada instalacao completa no sistema do usuario.
- Os dois nomes de arquivo sao identicos: `setup_multcnc_0.16.exe` e `setup_multcnc_016.exe`.
- SHA-256: `9a5004172f0ac0d3ec524cd927e2461f6540ebb0e97aba367412794040fec532`.
- Tamanho: 39720672 bytes.
