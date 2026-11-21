# MultiPhysics 0.2 — manual do usuário

O MultiPhysics simula fisicamente uma montagem antes de fabricar: deformação e tensão (estrutural), temperatura (térmica), dilatação (termomecânica), frequências naturais (modal), o comportamento de um sistema eletromecânico no tempo, uma CNC virtual, circuitos e flutuação. Ele **não comanda a máquina real**: isso é do MultiCNC.

Todo resultado mostra a **fidelidade**:

| Rótulo | Quando aparece |
|---|---|
| **ENGENHARIA** | Análise por elementos finitos (FEM) com malha sem elementos invertidos e estudo de convergência com variação menor que 5% entre a malha pedida e uma 1,5 vez mais grossa. |
| **ESTIMATIVA** | Convergência não verificada ou acima de 5%, ou modelos reduzidos (sistema, CNC, fluido, flutuação). |
| **VALIDADO** | Nunca é atribuído pelo programa: exige comparação com ensaio ou referência. |

Os exemplos citados abaixo ficam em `documentation/models/multiphysics` na instalação (no código-fonte, `models/multiphysics`).

## 1. A janela

- **Cabeçalho:** nome do programa e, à direita, o selo do último resultado (análise e fidelidade).
- **Lateral esquerda:** as 10 etapas, os botões Novo, Abrir, Salvar, Demo e a árvore do projeto (peças, condições, contatos, resultado).
- **Centro:** a vista 3D (ou o gráfico, nas etapas Sistema, Máquina CNC e Circuito) e o registro embaixo.
- **Direita:** o painel da etapa atual.
- **Rodapé:** situação, arquivo do projeto e o botão **Resolver** (durante o cálculo ele vira **Cancelar**).

Na vista 3D: arraste com o botão esquerdo para girar, com o direito para deslocar, use a roda para aproximar, clique numa face para selecioná-la. Os botões Ajustar, Iso, Frente, Topo e Lado reposicionam a câmera.

Unidades na tela: mm, MPa, °C, N, W. No arquivo do projeto (`.mphys`, JSON) tudo é SI (m, Pa, N).

## 2. Fluxo de uma análise FEM

1. **Montagem** — adicione peças (caixa, cilindro, tubo, perfil L) ou **Importar montagem (.massembly)** do MultiAssembly. Posição e rotação em mm e graus. Peças que se tocam viram **contatos colados** (botão Detectar contatos).
2. **Materiais** — escolha o material da biblioteca (25 materiais) e ajuste E, Poisson, densidade, condutividade, dilatação e escoamento.
3. **Cargas e fixações** — escolha o tipo, a peça e a face (ou clique na face na vista 3D) e informe o valor:
   - Fixação (graus X, Y, Z), Deslocamento prescrito (mm), Força total (N, repartida pela área), Pressão (MPa, positiva empurra para dentro), Gravidade (m/s²);
   - Temperatura (°C), Fluxo de calor (W/m²), Convecção (h em W/m²K e temperatura ambiente), Potência dissipada na peça inteira (W).
   A face pode ser só o nome (`xmin`, `lateral`, `lado0` — vale em todas as primitivas da peça) ou o nome completo `PECA/primitiva/face`.
4. **Malha** — tamanho dos elementos em mm, TET10 (recomendado) e estudo de convergência. Gerar malha mostra nós, elementos e qualidade.
5. **Resolver** — análise (estática, térmica, termomecânica, modal), número de modos e solver: **FEM próprio** ou **CalculiX (ccx)** se instalado.
6. **Resultados** — campo (deslocamento, von Mises, fator de segurança, temperatura, modos), deformada com escala automática ou manual, animação dos modos, resumo com máximos, reações, frequências e massa efetiva. Exporta CSV, relatório HTML (com imagem) e VTK para o ParaView.

## 3. Simulações passo a passo

### S1 — Viga em balanço (estrutural estática)
Exemplo `viga_balanco.mphys` (ou botão **Demo**): viga de aço 200 × 10 × 20 mm, engastada na face `xmin`, 100 N para baixo na face `xmax`.
1. Abra o projeto e vá a **Resolver** → Estática linear → Resolver.
2. Resultado esperado: flecha máxima ≈ 0,201 mm (teoria de vigas com cisalhamento: 0,2016 mm), von Mises ≈ 15 MPa no meio do vão (pico de ≈ 32 MPa no engaste, concentração da fixação rígida), fidelidade ENGENHARIA (variação entre malhas ≈ 0,1%).

### S2 / S3 — Suporte de motor (térmica e termomecânica)
Exemplo `suporte_motor_termico.mphys`: perfil L de alumínio com um motor de aço colado que dissipa 20 W, base a 25 °C, convecção de 10 W/m²K com o ar a 25 °C.
1. Resolver → Térmica permanente: mapa de temperatura do motor ao suporte.
2. Resolver → Termomecânica: a mesma temperatura entra como carga de dilatação na análise estrutural (com a base parafusada).

### S4 — Frequências naturais (modal)
No projeto da viga: Resolver → Modal, 4 modos. Esperado: 1º modo ≈ 204,6 Hz (flexão na direção fina; teoria 203,8 Hz), 2º ≈ 406 Hz (flexão na direção alta, 2 × o 1º), massa efetiva do 1º modo ≈ 61% em Y. Marque **Animar** para ver o modo.

### S5 — Peças coladas
Duas peças que se tocam (ou se sobrepõem) com um contato na etapa Montagem se movem juntas: as faces encostadas e os volumes sobrepostos são amarrados, sem atrito e sem separação. Primitivas da mesma peça (corpo e eixo de um motor, por exemplo) são sempre coladas. Sem contato, uma peça sem fixação própria fica solta e o cálculo é recusado com a mensagem "estrutura sem fixação suficiente".

### Montagem do MultiAssembly
No MultiAssembly, o botão **MultiPhysics** salva a montagem e abre o MultiPhysics com ela. Também é possível abrir `cnc_demo.massembly` em Montagem → Importar montagem. A importação traz peças, geometria, posições, material sugerido, componentes fixos, gravidade e contatos detectados. Confira materiais e fixações antes de resolver (no exemplo, fixe a face `zmin` da peça `FRAME`).

### S6 — Sistema eletromecânico no tempo
Etapa **Sistema**: Carregar máquina demonstração → Ligar. Fonte 24 V → driver PWM → motor DC (com indutância) → carga → sensor → controlador PI. O gráfico mostra tensão, corrente, velocidade, temperatura e PWM; a velocidade chega à referência (100 rad/s). **Perdas → térmica** leva a potência I²R do instante atual para a peça selecionada como potência dissipada (para resolver a térmica). Fidelidade: ESTIMATIVA.

### S7 — CNC virtual
Etapa **Máquina CNC**: Criar CNC XYZ → informe os alvos → Executar movimento. Os eixos seguem rampa trapezoidal (500 mm/s²) e o motor de passo perde torque com a velocidade: carga acima do torque disponível causa estol e passos perdidos. **Homing** procura o fim de curso mínimo. **Injetar falha**: curto e sobrecorrente desarmam, eixo travado estola, sensor com erro faz o eixo parar no lugar errado, fim de curso preso zera no lugar errado, corrosão e oxidação aquecem mais o motor.

### S8 — Circuitos
Etapa **Circuito**: escreva a netlist (estilo SPICE) e clique em Resolver circuito. Elementos: `R`, `C`, `L`, `V` (DC ou `SIN(offset amplitude frequência)`), `I`, `D` (diodo), `M` (NMOS: Vth, K); `.tran passo fim` e `.probe nós`. Sufixos f p n u m k meg g. O ponto DC vai para o registro e o transitório para o gráfico. Exemplos: `filtro_rc.cir` (carga RC, τ = 1 ms) e `retificador.cir`.

### S9 / S11 — Ambiente, fluido e atmosfera
Etapa **Ambiente**: escolha Ar, Água ou Vácuo, ou informe a altitude e clique **Atmosfera ISA** (temperatura, pressão, densidade, viscosidade e velocidade do som de 0 a 20 km). **Estimar arrasto e empuxo** calcula pressão dinâmica, arrasto com o Cd informado e empuxo; acima de Mach 0,3 o programa avisa que a hipótese incompressível não vale. ESTIMATIVA, não é CFD.

### S10 — Flutuação de um casco
Exemplo `casco_flutuacao.mphys` (caixa de madeira 1 × 0,4 × 0,3 m): gere a malha e use **Flutuação da montagem**. O programa acha o calado em que o empuxo iguala o peso, o centro de empuxo e a altura metacêntrica GM (inclinação pequena em torno de X): GM > 0 é estável.

### S12 — Degradação
Os modelos de corrosão, oxidação, curto persistente e fusível I²t estão no núcleo (`multiphysics_degradation`) e as falhas correspondentes da máquina estão na etapa Máquina CNC. ESTIMATIVA: dependem de calibração experimental.

## 4. CalculiX (opcional)

O CalculiX (ccx) é um solver FEM gratuito que serve de comparação. Ele não vem no instalador. Baixe em calculix.de (ou pelo pacote bConverged/PrePoMax no Windows), informe o executável na etapa **Resolver** (fica guardado) ou na variável `CALCULIX_EXE`, e escolha o solver CalculiX. O MultiPhysics escreve o mesmo modelo em `.inp` (malha, materiais, contatos como `*EQUATION`, cargas), executa o ccx e lê o `.frd`.

## 5. Arquivos

| Extensão | Conteúdo |
|---|---|
| `.mphys` | Projeto (JSON, SI): peças, geometria, materiais, condições, contatos, ambiente e configurações. |
| `.massembly` | Montagem do MultiAssembly (importação). |
| `.csv` | Resultado por nó ou séries temporais. |
| `.html` + `.png` | Relatório com imagem, resumo, peças, condições e registro do solver. |
| `.vtk` | Malha e campos para o ParaView. |
| `.inp` / `.frd` | Entrada e resultado do CalculiX. |

## 6. Limites desta versão

- Elementos de lados retos: cilindros são aproximados por polígonos (erro de volume de ≈ 1% com 32 segmentos).
- Contato só colado (sem atrito, sem separação); material linear elástico; pequenos deslocamentos.
- Geometria só por primitivas (caixa, cilindro/tubo/cone/setor, prisma); STL do MultiCAD ainda não vira malha.
- Fluido, sistema, CNC e flutuação são modelos reduzidos (ESTIMATIVA); não há CFD.
- Modelos muito grandes ficam lentos (o solver direto é escolhido pelo menor custo; acima do limite de memória usa gradiente conjugado).

## 7. Conferência automática

Os testes de console em `multiphysics/tests` (Central de Testes da suíte) conferem o FEM contra soluções analíticas (barra, viga, parede térmica, aleta, tensão térmica, frequências, massa efetiva), o contato colado, a importação da montagem, o projeto `.mphys`, o CalculiX (deck e leitor), circuitos, modelos de sistema e flutuação. Para rodar: `powershell -ExecutionPolicy Bypass -File multiphysics\tests\run_all.ps1`.
