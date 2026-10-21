# Setup 015 — MultiSuite 0.15

Edição de **21/10/2026**, para **Windows x64**.

[Instalador](../setup/setup_multcnc_015.exe) · [Cópia em bin](../bin/setup_multcnc_015.exe) · [SHA-256](../setup/SHA256SUMS)

## Novidades do Setup 015: MultiProject (primeira versão)

### 1. Projeto por objetivo
- Um **objetivo** ("construir um motor DC") dividido em **tarefas** com EAP: peça mecânica,
  eletrônica, montagem, validação, fabricação (impressão 3D, router, corte e arte laser,
  torno, placa), montagem física, teste funcional, compra, resumo e marco.
- Cada tarefa tem nome, ID, descrição curta e longa, **especificação técnica** (chave, valor,
  unidade e texto) e **especificação funcional** (critérios de aceite com estado).
- Arquivo `.mproj` em JSON, com gravação atômica, desfazer/refazer e preservação de campos
  desconhecidos.

### 2. Grafo de tarefas
- Vínculos **TI, II, TT e IT** (FS, SS, FF, SF) com latência útil, decorrida ou em %,
  digitados como no Project (`T-0003TI+2h`).
- Ciclos recusados com o caminho completo; tarefas em cadeia ou em paralelo; lista de
  **cadeias** na lateral para filtrar.

### 3. Cronograma pelo caminho crítico
- Calendário padrão (seg–sex, 08–12 e 13–17) com os **feriados do Brasil** e calendário 24 h
  para máquinas.
- Restrições ASAP/ALAP/SNET/SNLT/FNET/FNLT/MSO/MFO, data limite, tarefa manual, margens total
  e livre, caminho crítico e avisos com a tarefa, o problema e a correção.

### 4. Tela no padrão da suíte
- Sete etapas (Objetivo, Tarefas, Relações, Recursos, Cronograma, Acompanhar, Relatórios),
  vistas **Gantt**, **Rede** e **Quadro**, filtros, agrupamento e realce das críticas.
- Exemplo **Demo**: motor DC didático com 17 tarefas e 17 vínculos.
- Registrado na **MultiSuite Bandeja** no novo grupo **PLANEJAR**.

As próximas etapas (abrir a tarefa na ferramenta e vincular o arquivo, gerar tarefas,
recursos e superalocação, linha de base e relatórios) estão em
`documentation/multiproject/docs/TAREFA.md`.

## Rastreabilidade
- [Manifesto de compilação](../setup/build-manifest-015.json)
- [Resultados de testes QA](../setup/qa-tests-015.json)
- Gerado no Linux por compilação cruzada win64 (`installer/windows/build_release_wine.sh`):
  testes de console win64 executados no Wine e instalador do Inno Setup 6.3.1.
