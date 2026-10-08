# TAREFA: MakeRouter (projeto e usinagem de madeira na CNC Router)

- **Aberta em:** 08/10/2026
- **Estado:** em análise. É preciso decidir D1 a D6 antes de começar a fase 0.
- **Visão:** [../README.md](../README.md)
- **Arquitetura:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Contrato de G-code:** [../../docs/CONTRATO_GCODE.md](../../docs/CONTRATO_GCODE.md)

## Comparação com o padrão do PCB

| | PCB | Madeira |
|---|---|---|
| Programas | MakePCB (projeto) → RouterPCB (CAM) → MultiCNC | MakeRouter (projeto + CAM) → MultiCNC |
| Troca entre programas | pasta Gerber + Excellon (padrão da indústria) | não há etapa intermediária: o desenho e os percursos ficam no mesmo arquivo `.mrouter` |
| Zero | canto inferior esquerdo da placa, Z no cobre | 9 pontos do material, Z no topo ou na mesa |
| Quem posiciona na máquina | MultiCNC (Zero Workpiece + Frame) | MultiCNC (Zero Workpiece + Frame) |
| Saída | G-code GRBL, um arquivo por ferramenta | G-code GRBL, um arquivo por ferramenta ou único com M0 |

**Conclusão:** segue o padrão nos pontos que importam: zero virtual, MultiCNC como único dono
da máquina, G-code GRBL validado e cabeçalho reconhecido. A diferença, desenho e CAM juntos, é
intencional. No PCB o Gerber já é a fronteira natural. Na madeira o usuário ajusta desenho e
percurso juntos o tempo todo, como no Aspire, e separar em dois programas só criaria idas e
vindas.

## Decisões para o Marcelo

| # | Pergunta | Proposta |
|---|---|---|
| **D1** | Papel do MultiCAM depois do MakeRouter | MultiCAM fica com simulação da máquina e CAM de peças mecânicas do MultiCAD. Madeira, letreiros e móveis ficam no MakeRouter. |
| **D2** | Nome e lugar na suíte | `makerouter/` na raiz e `stiMakeRouter` no fim do enum, no grupo **Projetar** ao lado do MakePCB. Os percursos também o colocariam em Preparar, mas o usuário começa pelo desenho. |
| **D3** | Biblioteca de polígonos (offset e booleanas) | Usar a **Clipper** (Angus Johnson, licença Boost, versão Delphi/Pascal), que precisa ser conferida no FPC 3.2. A alternativa é escrever o offset próprio: mais tempo e mais risco. |
| **D4** | Emissor de G-code comum | Tirar o emissor e o verificador do RouterPCB para `src/shared/multisuite_gcode_writer.pas` e fazer RouterPCB e MakeRouter usarem o mesmo. |
| **D5** | Vista 3D | Começar com renderização por *software* (mapa de alturas sombreado, como a prévia do LaserPCB), que funciona no Wine e sem drivers. OpenGL (`TOpenGLControl`) entra depois, se ficar lento. |
| **D6** | Escopo da primeira entrega | Fases 0 a 4: material, desenho, perfil, bolsão, furação, simulação 2,5D e G-code. V-Carve e relevo 3D ficam nas fases 5 e 6. |

## Fases (depois das decisões)

Cada fase termina com testes rodando no Linux e no Win64, commit e push na `fila`, e o
andamento registrado neste arquivo. Mesmo procedimento do RouterPCB.

### Fase 0: base (≈ 1 h)
- [ ] Árvore `makerouter/src/{core,geom,relief,cam,sim,export,ui,app}` e `tests`.
- [ ] D3: trazer a biblioteca de polígonos e escrever um teste de offset e booleana.
- [ ] D4: emissor comum em `src/shared`, com os testes do RouterPCB passando sem mudança.
- [ ] Contrato: cabeçalho `MS-...` no emissor comum (o RouterPCB ganha as linhas sem mudar o
      resto).

### Fase 1: material, zero e projeto (≈ 2 h)
- [ ] `makerouter_types`, `makerouter_project` (JSON `.mrouter`) e `makerouter_datum`, com
      os 9 pontos e Z no topo ou na mesa.
- [ ] Biblioteca de ferramentas (`makerouter_tools`): reta, esférica, V, broca e gravação, com
      avanço, mergulho, RPM, *stepdown* e *stepover* por ferramenta. Sem valores "universais":
      os padrões aparecem como exemplo para ajustar.
- [ ] Testes: conversão projeto → saída nos 9 pontos, Z na mesa somando a espessura, JSON
      ida e volta.

### Fase 2: desenho 2D (≈ 4 h)
- [ ] Primitivas, texto em contorno, DXF e SVG.
- [ ] Transformações, alinhar, soldar, subtrair, *offset* e camadas.
- [ ] Vista 2D com grade, réguas, *snap*, seleção múltipla, alças e desfazer, no padrão do
      editor do MakePCB.
- [ ] Testes de geometria e de importação.

### Fase 3: percursos 2,5D (≈ 4 h)
- [ ] Perfil (fora, dentro ou na linha) com pontes, rampa e sobremetal.
- [ ] Bolsão (offset e zigue-zague) com ilhas.
- [ ] Furação e gravação em linha.
- [ ] Lista de percursos com recálculo e indicação de "desatualizado".
- [ ] Testes:
  - distância do percurso ao vetor igual a R;
  - bolsão sem sobra maior que o *stepover*;
  - pontes na altura certa;
  - G-code aceito por `multicnc_safety` e pelo analisador do MultiCNC.

### Fase 4: simulação, saída e suíte (≈ 3 h)
- [ ] Material como mapa de alturas, remoção pela forma da ferramenta, vista 3D e tempo
      estimado.
- [ ] Saída: um arquivo por ferramenta ou único com M0, e "Abrir no MultiCNC".
- [ ] MultiCNC: reconhecer `; MakeRouter -> MultiCNC (CNC Router)` e ler `MS-DATUM`,
      `MS-STOCK` e `MS-BOUNDS` (Frame e curso).
- [ ] Suíte: registro, ícone, bandeja, MultiSuite, Central de Testes, CI, instalador e
      documentação.
- [ ] **Primeira entrega:** placa com texto gravado, bolsão e recorte com pontes.

### Fase 5: V-Carve (≈ 3 h)
- [ ] Campo de distâncias por região, profundidade `r / tan(A/2)`, topo plano e limpeza com
      fresa reta.
- [ ] Teste: profundidade no eixo medial de um retângulo de largura L igual a `L/2 / tan(A/2)`.

### Fase 6: relevo e 3D (≈ 5 h)
- [ ] Mapa de alturas com domo, rampa, extrusão, revolução, imagem → relevo e STL.
- [ ] Desbaste 3D em níveis e acabamento raster (drop-cutter) com fresa esférica.
- [ ] Simulação 3D com fresa esférica.
- [ ] Exemplo: bandeja com divisórias, como a captura de referência.

## Critério de pronto (primeira entrega, fases 0 a 4)
1. Desenhar uma placa 300 × 200 × 18 mm com texto, um bolsão e o contorno, gerar os percursos,
   simular e gerar G-code sem erro.
2. O G-code abre no MultiCNC em CNC Router, mostra o ponto de zero do cabeçalho e o Frame
   percorre `MS-BOUNDS`.
3. Mudar o zero de BL para C e gerar de novo desloca o G-code exatamente
   `(-W/2, -H/2)`. Teste automatizado.
4. Testes do MakeRouter passam no Linux e no Win64; o RouterPCB segue passando com o
   emissor comum.

## Riscos
- **Offset robusto** (D3): é o coração do CAM 2D. Sem uma biblioteca confiável, os bolsões
  com ilhas e os textos pequenos dão problema.
- **Texto:** converter fontes TrueType em contorno no Windows e no Linux. A alternativa
  inicial é uma fonte de traço própria, como a do MakePCB, para gravação, e TrueType depois.
- **Desempenho do 3D:** uma chapa inteira em 0,1 mm dá 500 M células. Na simulação, a
  resolução tem que se adaptar ao tamanho, com aviso ao usuário.
- **Parâmetros de corte:** avanço e RPM dependem de máquina, fresa e madeira. Valores padrão
  só como ponto de partida, com teste em material.
