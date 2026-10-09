# Orientações para agentes — MultiCNC

Leia `OBJETIVO_CONTROLADOR.md` antes de trabalhar. Ele é o documento vivo do produto, com requisitos, parâmetros, comportamento implementado e limitações.

- O controlador usa Lazarus/Object Pascal. Não substituir a stack sem solicitação do usuário.
- Equipamentos se conectam apenas por serial. Cada sessão tem uma thread proprietária da porta.
- Atualize `OBJETIVO_CONTROLADOR.md` no mesmo conjunto de mudanças de cada implementação, incluindo parâmetros novos, defaults, testes e pendências.
- Compatibilidade comercial pesquisada não é homologação. Nunca afirmar operação física com base apenas no simulador.
- Diferencie posição reportada, posição projetada e posição medida. Não inferir movimento real de um `ok`.
- Testes comuns não devem abrir portas de máquinas reais ou enviar comandos físicos.
- Use `apps/control/build.ps1 -Test` para a compilação/testes Win64, ajustando `-LazarusDir` quando necessário.
- Não versionar `bin/`, `lib/`, cadastro local, logs, `.lps` ou configuração pessoal do Lazarus.
- A proposta da suíte está em `docs/`; recursos planejados só mudam para implementados quando houver código e validação correspondentes.
