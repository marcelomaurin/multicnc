# TAREFA: MultiPhysics 0.2: simulação física da montagem, utilizável de ponta a ponta

- **Aberta em:** 18/10/2026.
- **Estado:** plano detalhado escrito; implementação ainda não começou (ver **Progresso**).
- **Solicitação do usuário:** "com base nos documentos apresentados, crie uma versão deste projeto para atender tudo o que foi apresentado". Escopo confirmado pelo usuário: **interface completa**, **solver FEM próprio**, **integração CalculiX**, **completar os modelos que hoje são esqueleto** e "o que achar necessário para as simulações pretendidas".
- **Documentos-base (especificação):** [README.md](../README.md), [AI_GUIDE.md](AI_GUIDE.md), [RUNTIME.md](RUNTIME.md), [INTEGRATION_ROADMAP.md](INTEGRATION_ROADMAP.md).
- **Base conferida:** branch `fila`, commit `f836f89` (release 0.13 preparada).
- **Padrão de documento:** [MultiAssembly TAREFA](../../multiassembly/docs/TAREFA.md), [MultiCAD TAREFA](../../multicad/docs/TAREFA.md).
- **Padrão visual:** [multisuite_controls](../../multisuite/src/core/multisuite_controls.pas), [multisuite_icons](../../multisuite/src/core/multisuite_icons.pas) e a tela do [MultiAssembly](../../multiassembly/src/app/multiassembly_main.pas).

> **Para quem continuar:** leia a seção **Como continuar** no fim deste arquivo antes de mexer no código. Cada tarefa tem um ID (`MP-f.n`), os arquivos envolvidos, o que fazer e o critério de aceite. Ao terminar uma tarefa, marque-a como feita na tabela **Progresso** com a data e o commit. Não marque como feita uma tarefa sem teste passando.

---

## 1. Objetivo

O MultiPhysics deve receber uma montagem do MultiAssembly, completar o que falta para simular (materiais, cargas, fixações, contatos, ambiente, circuitos e controle) e devolver resultados com **rótulo de fidelidade** (ESTIMATIVA, ENGENHARIA ou VALIDADO).

Simulações pretendidas, tiradas dos documentos-base:

| # | Simulação | Exemplo de uso | Fidelidade-alvo nesta versão |
|---|---|---|---|
| S1 | Estrutural estática linear | Deflexão e tensão de von Mises de um pórtico de CNC sob a força de corte | ENGENHARIA (FEM com malha e convergência) |
| S2 | Térmica em regime permanente | Temperatura de um suporte de motor que dissipa 20 W, com convecção | ENGENHARIA |
| S3 | Termomecânica | Dilatação e tensão térmica do mesmo suporte | ENGENHARIA |
| S4 | Modal (frequências naturais) | Primeiras 6 frequências de um eixo Z em balanço | ENGENHARIA |
| S5 | Contato colado entre peças | Base + motor parafusados tratados como colados | ENGENHARIA (com aviso de que é colado, sem atrito) |
| S6 | Sistema eletromecânico no tempo | Fonte → driver → motor → carga → sensor → controle (runtime) | ESTIMATIVA |
| S7 | Máquina CNC virtual XYZ + spindle | Comando X=100, Y=50, Z=20; perda de passo; fim de curso; falhas | ESTIMATIVA |
| S8 | Circuitos | MNA DC, transitório RC/RL, diodo/MOSFET por Newton | ENGENHARIA para os casos com solução analítica conferida |
| S9 | Ambiente e fluido | Arrasto, pressão dinâmica, empuxo, flutuação | ESTIMATIVA (com aviso "não é CFD") |
| S10 | Embarcação simples | Centro de empuxo e altura metacêntrica de casco em caixa | ESTIMATIVA |
| S11 | Atmosfera e alta velocidade | Atmosfera ISA por altitude, número de Mach e aviso de compressibilidade | ESTIMATIVA |
| S12 | Degradação e falhas | Corrosão, oxidação, curto persistente, fusível I²t | ESTIMATIVA |
| S13 | Comparação com CalculiX | Mesmo caso S1/S2/S4 resolvido pelo `ccx` quando instalado | ENGENHARIA (externo) |

Fora do escopo desta versão (manter como "evolução" nos documentos): CFD/FSI real, contato com atrito e separação, plasticidade, grandes deslocamentos, co-simulação SPICE completa, 6-DOF com massa variável de foguete, superfície livre e ondas.

## 2. Regras que valem para todas as tarefas

Copiadas de [AI_GUIDE.md](AI_GUIDE.md) e reforçadas:

1. **Fidelidade sempre visível.** Todo resultado (tela, CSV, relatório) mostra ESTIMATIVA, ENGENHARIA ou VALIDADO. FEM próprio = ENGENHARIA só quando a malha passou na verificação de qualidade e o estudo de convergência (MP-4.9) foi feito; senão ESTIMATIVA.
2. **Não inventar resultado.** Sem malha válida, sem material ou sem fixação suficiente, o botão Resolver fica desabilitado e a tela diz o que falta.
3. **Determinismo.** Mesma entrada, mesmo resultado, bit a bit, em toda execução (sem `Random` sem semente fixa, sem depender de ordem de `TList` de ponteiros).
4. **Toda fórmula nova tem teste contra caso analítico** (lista de benchmarks na seção 6).
5. **Unidades SI no núcleo** (m, N, Pa, K ou °C indicado, s, kg). A interface aceita mm e converte; a conversão fica em um só lugar (`multiphysics_units.pas`, MP-1.6).
6. **Textos da interface em português sem acento** nos `.pas` (padrão da suíte), formato numérico com `InvariantFS` em arquivos e `multisuite_numfmt` na tela.
7. **MultiCNC continua dono da máquina real.** O MultiPhysics nunca abre porta serial nem envia G-code.
8. **Código no estilo dos arquivos novos da suíte** (uma instrução por linha, comentários curtos em português). Os arquivos antigos compactados em uma linha podem ser reformatados quando forem tocados de verdade, nunca só por estética em massa.

## 3. Estado atual (conferido em 18/10/2026)

Os documentos descrevem muito mais do que o código entrega. A maioria das unidades tem de 8 a 36 linhas: tipos e fórmulas de uma linha, sem validação nem testes de borda. Os testes são programas de 5 linhas sem `.lpi` (a Central de Testes compila pelo catálogo).

| Área | Arquivo(s) | Linhas | Situação real |
|---|---|---|---|
| Interface | `src/app/multiphysics_main.pas` | 25 | Formulário com ~12 `TButton` empilhados, `TTreeView` e `TMemo`. Não usa `multisuite_controls`. Sem salvar/abrir. |
| Projeto | `src/core/multiphysics_project.pas` | 25 | Peças, CCs e contatos em memória. Sem persistência, sem geometria, sem casos de carga. |
| Tipos | `src/core/multiphysics_types.pas` | 17 | Material, CC, contato, ambiente, configurações, resultado escalar. |
| Materiais | `src/core/multiphysics_materials.pas` | 52 | ~25 materiais; ok como base. Falta lista indexável e busca por nome. |
| Ambiente / cenário | `multiphysics_environment.pas`, `multiphysics_scenario.pas` | 26 + 16 | Ar/Água/Vácuo, estimativa de arrasto/empuxo. |
| Solver FEM | `src/solver/multiphysics_solver.pas` | 17 | Escreve deck CalculiX só com materiais; solve bloqueado. **Não existe malha nem FEM.** |
| Acoplamento / não linear | `multiphysics_coupling.pas`, `multiphysics_nonlinear.pas` | 9 + 11 | Esqueleto. |
| Circuitos | `multiphysics_mna.pas` (30), `multiphysics_circuit_newton.pas` (616) | | MNA linear ok; Newton com diodo/NMOS é a unidade mais completa. |
| ODE | `multiphysics_ode.pas` | 192 | RK4, Dormand-Prince, Verlet, Euler simplético. Ok. |
| Dinâmica | `multiphysics_vector`, `rigidbody`, `mechanics`, `buoyancy` | 14 a 35 | Fórmulas básicas. |
| Runtime | `multiphysics_runtime*.pas`, `graph*.pas`, `scheduler.pas`, `components*.pas` | 12 a 142 | Ciclo fonte→motor→carga→sensor→PID funciona de forma reduzida. |
| Máquina CNC | `machine_runtime`, `axis_control`, `stepper_physics`, `machine_faults` | 9 a 25 | Eixos X/Y/Z, spindle, trip. Reduzido. |
| Eletrônica | `common_electronics`, `digital_power`, `circuit_models`, `electrical_faults` | 14 a 35 | Uma função por componente. |
| MCU | `multiphysics_mcu.pas`, `mcu_program.pas` | 29 + 16 | Perfis e GPIO/PWM/ADC básicos. |
| Física diversa | `electromagnetics`, `physical_devices`, `energy_chemistry`, `degradation` | 18 a 37 | Fórmulas de uma linha. |
| Instrumentos | `instruments`, `machine_instruments` | 14 + 8 | Amostragem e CSV mínimos. |
| Importação | `multiphysics_unified_import.pas` | 10 | Adivinha o tipo pelo nome; ignora posição e geometria. |
| Testes | `tests/*.lpr` | 5 cada (exceto newton_ode 174, unified_merge 30) | Um caso feliz por arquivo. Sem `.lpi`. |

Entradas que o MultiPhysics vai consumir:
- **MultiAssembly:** projeto JSON (`multiassembly/src/core/multiassembly_project.pas`, `SaveToFile`), componentes com posição/rotação e bloco `geometry` de primitivas (`box`, `cyl`, `prism`, `disk`), descrito em [models/components/README.md](../../models/components/README.md); exportador `ExportAssemblyToUnified` em `multiassembly/src/core/multiassembly_physics_export.pas`.
- **Contrato unificado:** `src/shared/multisuite_component_contract.pas` (`TUnifiedMachine`, `TUnifiedComponent`, `TUnifiedLink`).
- **MultiCAD:** exporta `.stl` (malha de superfície). Importar STL como geometria é P1 (MP-3.8).

## 4. Arquitetura proposta

```
multiphysics/src/
  core/      tipos, unidades, projeto (.mphys), materiais, ambiente, casos de carga
  geometry/  primitivas, transformação da montagem, seleção de faces            (novo)
  mesh/      malha tetraédrica, qualidade, conjuntos de nós/faces             (novo)
  fem/       matrizes esparsas, PCG, elementos, estático, térmico, modal       (novo)
  ccx/       escrita do deck .inp, execução do ccx, leitura do .frd           (novo)
  solver/    MNA, Newton, ODE, acoplamento (existente)
  dynamics/  corpo rígido, mecânica, empuxo (existente)
  runtime/   grafo, scheduler, máquina, MCU, falhas (existente, a completar)
  instruments/ gravador e séries temporais
  ui/        vista 3D com mapa de cores, gráficos, painéis                     (novo)
  app/       formulário principal e .lpr
```

Dependências: `ui` → `fem`/`ccx`/`runtime` → `mesh` → `geometry` → `core`. O núcleo (tudo menos `ui` e `app`) não usa LCL visual, para os testes rodarem como console.

Adicionar as pastas novas em `OtherUnitFiles` de `src/app/multiphysics.lpi` e no `.lpi` de cada teste.

---

## 5. Fases e tarefas

Prioridade: **P0** = obrigatório na versão 0.2 · **P1** = desejável na 0.2 · **P2** = evolução.

### Fase 0: base de testes e build (P0)

**MP-0.1 Projeto `.lpi` para cada teste.**
Arquivos: `multiphysics/tests/*.lpi` (novos).
Fazer: um `.lpi` por `.lpr`, no modelo de `laserart/tests/test_laserart_box.lpi`, com `OtherUnitFiles` = `../src/core;../src/solver;../src/dynamics;../src/runtime;../src/instruments;../src/examples;../src/geometry;../src/mesh;../src/fem;../src/ccx;../../src/shared;../../multisuite/src/core`, saída em `lib/$(TargetCPU)-$(TargetOS)`, console.
Aceite: `lazbuild` compila todos; cada executável retorna 0 e imprime `PASS`.

**MP-0.2 Script `tests/run_all.ps1`.**
Compila e roda todos os testes do MultiPhysics, mostra uma linha por teste e sai com código ≠ 0 se algum falhar.
Aceite: rodar o script na árvore atual lista os 25 testes existentes, todos `PASS`.

**MP-0.3 Unidade de verificação comum `tests/mp_check.pas`.**
`Check(Cond, Msg)`, `CheckNear(Got, Expected, RelTol, Msg)`, contador de falhas e `Finish` (Halt(1) se falhou), no estilo de `laserart/tests/test_laserart_box.lpr`. Testes novos usam esta unidade.

**MP-0.4 Catálogo da Central de Testes.**
Arquivo: `multisuite/src/testing/multisuite_test_catalog.pas`. Registrar cada teste novo criado nas fases seguintes (linha `Add(Result,'MultiPhysics', ...)`).

### Fase 1: núcleo de dados e projeto persistente (P0)

**MP-1.1 Casos de carga e CCs com alvo geométrico.**
Arquivo: `src/core/multiphysics_types.pas`.
Fazer: `TBoundaryCondition` ganha `TargetKind` (peça inteira, face, aresta, nó) e `TargetFace` (ID estável da face, ver MP-3.3); `TLoadCase` (nome, lista de CCs, tipo de análise). `TPhysicsResult` passa a ter `Fidelity`, `MeshNodes`, `MeshElements`, `SolverName`, `Warnings`.
Aceite: compila; testes antigos continuam passando.

**MP-1.2 Projeto `.mphys` (JSON).**
Arquivo: `src/core/multiphysics_project.pas` (+ `multiphysics_project_io.pas` se ficar grande).
Fazer: `SaveToFile`/`LoadFromFile` com `fpjson`, versão de formato `"format": 1`, números com `InvariantFS`. Guardar: nome, arquivo da montagem de origem, peças (ID, nome, material por nome + overrides, geometria, transformação), CCs, contatos, ambiente, configurações de malha e análise, casos de carga, cenário de fluido, grafo do runtime (componentes, parâmetros, ligações) e caminho do último resultado.
Aceite: teste `test_project_io` salva, recarrega e compara campo a campo (incluindo geometria e grafo); arquivo de versão desconhecida é recusado com mensagem.

**MP-1.3 Biblioteca de materiais indexável.**
Arquivo: `src/core/multiphysics_materials.pas`.
Fazer: `MaterialCount`, `MaterialByIndex`, `FindMaterial(Name)`; completar `YieldStrength`, `Emissivity`, `MaxServiceTemperature`, `MeltingTemperature` onde faltam, com fonte em comentário.
Aceite: `test_materials` confere que todo material tem E>0, ν∈(0,0.5), ρ>0, k>0, c>0, e que `FindMaterial` acha todos pelo nome.

**MP-1.4 Material personalizado no projeto.**
Peça pode sobrescrever qualquer propriedade; o `.mphys` guarda só o que difere.

**MP-1.5 Validação do projeto.**
`TPhysicsProject.Validate(Log): Boolean` lista o que falta para cada análise: peça sem material, nenhuma fixação (estrutural/modal), nenhuma CC térmica (térmica), malha ausente ou ruim, contato apontando para peça inexistente.
Aceite: `test_project_validate` cobre cada mensagem.

**MP-1.6 Unidades.**
`src/core/multiphysics_units.pas`: mm↔m, MPa↔Pa, °C↔K, rpm↔rad/s, formatação com unidade. A interface só converte por aqui.

### Fase 2: geometria da montagem (P0)

**MP-2.1 Leitura da montagem do MultiAssembly.**
Arquivos: `src/geometry/multiphysics_assembly_import.pas` (novo).
Fazer: ler o JSON do projeto do MultiAssembly (mesmo formato de `TAssemblyProject.SaveToFile`) **sem depender das units de UI do MultiAssembly**; para cada componente: ID, nome, modelo, tipo, posição, rotação, tamanho, `source_ref` e bloco `geometry`. Se faltar `geometry`, carregar do arquivo de origem em `models/components/mec` (mesma regra do MultiAssembly) ou gerar caixa pelo `size`. Material sugerido pelo tipo (perfil → alumínio, parafuso → aço, motor → aço/alumínio etc.), sempre editável.
Aceite: `test_assembly_import` importa a CNC de demonstração do MultiAssembly (gerar o JSON pelo próprio `multiassembly_demo` num teste ou usar um arquivo de exemplo em `multiphysics/tests/data/`) e confere contagem de peças, posições e primitivas.

**MP-2.2 Primitivas e transformação.**
`src/geometry/multiphysics_geometry.pas`: tipos `box`, `cyl` (com `ri`, `r2`, `arc`), `prism`, conforme o README de componentes; matriz de transformação da peça (posição + rotação do MultiAssembly, mm → m); envolvente, volume e centro de massa analíticos por primitiva.
Aceite: `test_geometry` confere volume e centroide de caixa, cilindro, tubo, cone e prisma contra fórmula fechada (erro < 1e-9 relativo).

**MP-2.3 Faces nomeadas.**
Cada primitiva expõe faces com ID estável: caixa `xmin,xmax,ymin,ymax,zmin,zmax`; cilindro `base,topo,lateral` (+ `interna` para tubo); prisma `base,topo,lado_N`. ID global da face = `IDpeca/IDprimitiva/face`. É o alvo das CCs (MP-1.1).

**MP-2.4 Propriedades de massa da montagem.**
Massa, centro de massa e tensor de inércia por peça e total, usando o material. Alimenta o runtime (inércia de carga) e o empuxo (MP-8).
Aceite: inércia de cilindro e caixa contra fórmula.

### Fase 3: malha (P0)

**MP-3.1 Estrutura de malha.**
`src/mesh/multiphysics_mesh.pas`: nós (x,y,z), elementos tetraédricos de 4 nós (TET4) e opcionais de 10 (TET10), peça de origem de cada elemento, faces de contorno com ID de face geométrica (MP-2.3), conjuntos de nós por face.

**MP-3.2 Malhador por primitiva (estruturado).**
- Caixa: grade nx×ny×nz pelo tamanho alvo, cada hexaedro dividido em 6 tetraedros com padrão consistente entre vizinhos (sem faces não conformes).
- Cilindro/tubo/cone/setor: malha estruturada em (r, θ, z); núcleo do cilindro maciço por O-grid ou fatias triangulares; dividir prismas em 3 tetraedros com regra de diagonal consistente.
- Prisma extrudado: triangulação do polígono (ear clipping; furos não suportados na 0.2) e extrusão em camadas → prismas → 3 tetraedros.
Aceite: `test_mesh_primitives`: volume da malha = volume analítico (caixa e prisma exato; cilindro converge com o refinamento, erro < 1% com 32 segmentos); nenhum tetraedro com volume ≤ 0; toda face interna compartilhada por exatamente 2 elementos.

**MP-3.3 Peças múltiplas e contato colado.**
Malhas independentes por peça. Contato colado ("bonded") entre faces que se tocam: amarrar por **restrição de penalidade** ou **MPC** de cada nó da face escrava à face mestre (interpolação no triângulo mais próximo). Detecção automática de faces coincidentes dentro de uma tolerância (padrão 0,01 mm) e lista editável na interface.
Aceite: `test_mesh_tie`: duas caixas empilhadas coladas sob compressão dão o mesmo deslocamento do topo que uma caixa única da mesma altura (erro < 2%).

**MP-3.4 Qualidade da malha.**
Razão de aspecto, ângulo diedro mínimo, razão raio inscrito/circunscrito; contagem de elementos ruins; bloqueio do Resolver se houver elemento invertido.

**MP-3.5 TET10 (quadrático).**
Gerar nós de meio de aresta compartilhados (dicionário por par de nós). Usado por padrão no estrutural porque TET4 é rígido demais em flexão.

**MP-3.6 Tamanho de malha e refino local.**
Tamanho global + tamanho por peça. Preparar para o estudo de convergência (MP-4.9).

**MP-3.7 Exportar malha.**
Escrever a malha em formato Abaqus/CalculiX `.inp` (usado por MP-5) e em VTK legado `.vtk` (para abrir no ParaView).

**MP-3.8 (P1) Importar STL do MultiCAD.**
STL fechado → malha volumétrica exige malhador não estruturado (Delaunay 3D com recuperação de fronteira). Na 0.2: aceitar STL só para visualização e para volume/massa; avisar que FEM em STL fica para 0.3, ou usar o CalculiX/cgx se disponível.

### Fase 4: solver FEM próprio (P0)

**MP-4.1 Matriz esparsa.**
`src/fem/multiphysics_sparse.pas`: montagem em triplas (COO) → CSR com soma de duplicados; produto matriz-vetor; aplicação de condições de Dirichlet por eliminação simétrica.
Aceite: `test_sparse` contra matriz densa pequena.

**MP-4.2 Gradiente conjugado pré-condicionado.**
PCG com pré-condicionador Jacobi (P0) e Cholesky incompleto IC(0) (P1); critério de parada relativo 1e-10; limite de iterações; relatório de iterações e resíduo.
Aceite: `test_pcg` resolve Laplaciano 1D/3D e confere com solução conhecida.

**MP-4.3 Elementos TET4 e TET10 elásticos.**
`src/fem/multiphysics_elements.pas`: funções de forma, matriz B, matriz constitutiva isotrópica D(E,ν), rigidez por quadratura (TET4: 1 ponto; TET10: 4 pontos), massa consistente e concentrada, vetor de carga de superfície (pressão) e de corpo (gravidade).
Aceite: teste de patch (deformação uniforme reproduzida exatamente em malha distorcida).

**MP-4.4 Análise estática linear.**
`src/fem/multiphysics_static.pas`: monta K, aplica fixações (face fixa, deslocamento prescrito), forças (força total distribuída na face, pressão), gravidade; resolve; calcula deslocamentos, deformações, tensões nos pontos de Gauss, média nodal, von Mises, tensões principais, reações e fator de segurança (σ_escoamento/σ_vM).
Aceite (benchmarks da seção 6): B1 barra em tração, B2 viga em balanço, B3 placa com furo (P1).

**MP-4.5 Térmica em regime permanente.**
`src/fem/multiphysics_thermal.pas`: condução com k por peça; CCs de temperatura, fluxo de calor, potência dissipada volumétrica, convecção h·(T−T∞) na face; radiação linearizada (P1).
Aceite: B4 parede plana 1D, B5 aleta com convecção.

**MP-4.6 Termomecânica.**
Carga térmica α·ΔT no estrutural usando o campo de temperatura de MP-4.5.
Aceite: B6 barra presa nas duas pontas aquecida: σ = −E·α·ΔT.

**MP-4.7 Modal.**
`src/fem/multiphysics_modal.pas`: K·φ = ω²·M·φ por iteração em subespaço (P0) ou Lanczos com reortogonalização (P1), com deslocamento espectral para modelos livres; N modos pedidos; frequência em Hz e forma modal normalizada pela massa.
Aceite: B7 viga em balanço, 1ª frequência; B8 barra livre-livre axial.

**MP-4.8 Fatores de participação e massa efetiva (P1).**

**MP-4.9 Estudo de convergência.**
Resolver com 3 tamanhos de malha (h, h/1,5, h/2,25), extrapolar (Richardson) e informar variação da grandeza principal. Resultado só recebe ENGENHARIA se a variação entre as duas malhas mais finas for < 5%.

**MP-4.10 Desempenho mínimo.**
Modelo de 50 mil nós TET10 estático deve resolver em < 60 s num PC comum; registrar tempo no relatório. Se não atingir, implementar IC(0) (MP-4.2) e reordenação RCM.

**MP-4.11 Execução em segundo plano.**
Solve em `TThread` com progresso e botão Cancelar; a interface não congela.

### Fase 5: integração CalculiX (P0)

**MP-5.1 Deck completo.**
`src/ccx/multiphysics_ccx_writer.pas`: `*NODE`, `*ELEMENT, TYPE=C3D4/C3D10`, `*ELSET` por peça, `*NSET`/`*SURFACE` por face, `*MATERIAL` (`*ELASTIC`, `*DENSITY`, `*CONDUCTIVITY`, `*SPECIFIC HEAT`, `*EXPANSION`), `*SOLID SECTION`, `*TIE` para contatos colados, `*BOUNDARY`, `*CLOAD`/`*DLOAD`/`*DFLUX`/`*FILM`, `*STEP` com `*STATIC`, `*HEAT TRANSFER, STEADY STATE`, `*COUPLED TEMPERATURE-DISPLACEMENT` ou `*FREQUENCY`, `*NODE FILE` (U, RF, NT) e `*EL FILE` (S, E). Unidades SI.
Aceite: `test_ccx_writer` gera o deck da viga B2 e confere as seções (texto), sem precisar do ccx.

**MP-5.2 Execução do ccx.**
`src/ccx/multiphysics_ccx_run.pas`: localizar `ccx` por `CALCULIX_EXE`, configuração salva ou PATH; rodar com `TProcess` em pasta temporária do projeto, sem janela, com tempo limite e cancelamento; capturar saída para o log.

**MP-5.3 Leitura do `.frd` (ASCII) e `.dat`.**
`src/ccx/multiphysics_frd.pas`: blocos de nós, elementos, DISP, STRESS, NDTEMP, autovalores; mapear para a malha interna pelo número do nó.
Aceite: `test_frd` lê um `.frd` pequeno guardado em `tests/data/` (gerado uma vez com o ccx e versionado).

**MP-5.4 Comparação automática.**
Quando o ccx existir, `test_ccx_compare` resolve B2 e B7 nos dois solvers e exige diferença < 2%. Sem ccx o teste imprime `IGNORADO: ccx nao encontrado` e sai com 0 (não conta como passou no relatório).

**MP-5.5 Instalação.**
Não distribuir o ccx no setup (licença GPL e tamanho); a interface mostra onde baixar e o campo para indicar o executável.

### Fase 6: interface no padrão da suíte (P0)

Referência visual: MultiAssembly e MakeRouter. Usar `TSuiteHeader`, `NewButton`/`TSuiteButton`, `NewPanel`, `clSuite*`, `SUITE_FONT`, ícones `sik*`.

**MP-6.1 Esqueleto da janela.**
Cabeçalho (nome, projeto atual, `*` se alterado), barra superior (Novo, Abrir, Salvar, Importar montagem, Desfazer, Refazer), lateral esquerda com as etapas e a árvore, área central com abas de vista, painel de propriedades à direita, barra de status com fidelidade do último resultado.
Etapas da lateral: **1 Montagem**, **2 Materiais**, **3 Contorno e cargas**, **4 Contatos**, **5 Malha**, **6 Resolver**, **7 Resultados**, **8 Sistema (runtime)**, **9 Máquina CNC**, **10 Circuito**, **11 Ambiente e fluido**, **12 Degradação**.
Aceite: abre sem erro, redimensiona, fecha encerrando o processo (`Application.CreateForm`, ver `docs/bugs.md`).

**MP-6.2 Vista 3D.**
`src/ui/multiphysics_view3d.pas`: desenhar a malha/geometria com rotação, zoom e pan pelo mouse (pode partir de `multiassembly/src/view/multiassembly_mechanical_canvas.pas`, adaptado: copiar e adaptar, não acoplar as units); seleção de face por clique (para CCs); destaque da face sob o mouse; símbolos de fixação, força, pressão e temperatura.

**MP-6.3 Mapa de cores e deformada.**
Escala de cores (azul→vermelho) para deslocamento, von Mises, temperatura, fator de segurança; legenda com mín./máx. e unidade; deformada com fator de escala automático e ajustável; animação da forma modal (seno no tempo); sonda: clique mostra o valor no nó.

**MP-6.4 Painéis de edição.**
Materiais (lista da biblioteca + override), CC (tipo, face, valor, unidade), contatos (pares detectados, tipo colado), malha (tamanho global/por peça, TET4/TET10, qualidade), análise (tipo, modos, solver próprio ou CalculiX).

**MP-6.5 Resultados e relatório.**
Tabela de máximos/mínimos por peça, reações, frequências; exportar CSV e relatório HTML com imagem da vista, fidelidade, malha, convergência, solver e avisos.

**MP-6.6 Gráficos de séries temporais.**
`src/ui/multiphysics_chart.pas` (desenho próprio em `TPaintBox`, sem TAChart para não aumentar dependências): várias séries, eixo de tempo, cursor com leitura, exportar CSV. Usado nas etapas 8 a 12.

**MP-6.7 Contexto da suíte.**
Ler `ReadSuiteContext` (como os outros apps) para abrir o projeto/montagem passado pela bandeja ou pelo MultiAssembly.

### Fase 7: runtime, máquina, circuitos e modelos esqueleto (P0)

Para cada unidade abaixo: reformatar, validar entradas (nada de divisão por zero ou NaN silencioso), documentar o modelo e as unidades no cabeçalho, e criar teste com caso analítico. Lista mínima:

| ID | Unidade | Completar | Teste/benchmark |
|---|---|---|---|
| MP-7.1 | `multiphysics_runtime.pas`, `runtime_types.pas` | Passo fixo configurável, parâmetros do motor DC (R, L, Kt, Ke, J, b), estado inicial, reset determinístico | Motor DC a vazio: velocidade final = V/Ke (1%); constante de tempo mecânica J·R/(Kt·Ke) |
| MP-7.2 | `multiphysics_graph.pas`, `graph_runtime.pas` | Validação de portas, ciclo algébrico detectado, parâmetros por componente lidos do `.mphys` | Grafo PSU→driver→motor→carga→sensor→controle converge para a referência de velocidade (erro < 2%) |
| MP-7.3 | `multiphysics_unified_import.pas` | Usar `assembly_kind` e parâmetros em vez de adivinhar por nome; posição e inércia da peça (MP-2.4) | Importar a CNC demo e conferir tipos e ligações |
| MP-7.4 | `multiphysics_scheduler.pas` | Fases documentadas em RUNTIME.md; subpassos por domínio (elétrico mais fino que térmico) | Ordem das fases registrada e igual à documentação |
| MP-7.5 | `machine_runtime`, `axis_control`, `stepper_physics` | Curva torque×velocidade do passo a passo, aceleração trapezoidal, microstep, perda de passo por torque, fim de curso, homing | Movimento X=100 mm termina em 100 mm ± 1 passo; com carga acima do torque perde passos |
| MP-7.6 | `machine_faults`, `electrical_faults`, `faults` | Circuito aberto, curto, eixo travado, sensor travado, fim de curso falso; injetar pela interface | Cada falha produz o trip ou efeito esperado |
| MP-7.7 | `multiphysics_mna.pas` | Fonte de corrente, teste de nó flutuante com mensagem clara, uso do `circuit_newton` para não lineares | Divisor, ponte de Wheatstone, RC carga (τ=RC) e RL (τ=L/R) |
| MP-7.8 | `common_electronics`, `digital_power`, `circuit_models` | Parâmetros e limites por componente; buck/boost com razão cíclica; ponte H; 555 astável | Buck ideal Vout = D·Vin; 555 f = 1,44/((R1+2R2)C) |
| MP-7.9 | `multiphysics_mcu.pas`, `mcu_program.pas` | Programa por lista de eventos/tempo; PWM com resolução do perfil; ADC com resolução e referência | ESP32 gera 200 pulsos STEP em frequência pedida |
| MP-7.10 | `electromagnetics`, `physical_devices` | Saturação do núcleo, força do solenoide pela energia, sensores com ruído determinístico (semente fixa) e faixa | Solenoide: B = μ₀·N·I/L |
| MP-7.11 | `energy_chemistry`, `degradation` | SOC de bateria por integração de corrente, curva de tensão, corrosão/oxidação com fatores documentados | Bateria 2 Ah a 1 A descarrega em 2 h |
| MP-7.12 | `multiphysics_instruments.pas`, `machine_instruments.pas` | Gravador com taxa de amostragem, várias séries, CSV com cabeçalho e unidade | CSV relido tem as mesmas amostras |
| MP-7.13 | `multiphysics_coupling.pas` | Acoplamento runtime → FEM: perdas do motor viram potência dissipada (térmico) e forças do eixo viram carga (estrutural) num instante escolhido | Potência I²R do runtime aparece como CC térmica no caso de carga |
| MP-7.14 | `multiphysics_nonlinear.pas` | Se não for usada, remover; se for, documentar e testar | — |

**MP-7.15 Telas do sistema.** Etapas 8 a 12 da interface: montar/importar o grafo, editar parâmetros, Ligar/Pausar/Desligar, gráficos (MP-6.6), injeção de falhas, painel da CNC com comando de posição e leitura dos eixos, editor simples de circuito (lista de componentes e nós, sem desenho na 0.2).

### Fase 8: ambiente, fluido e embarcação (P1)

**MP-8.1 Atmosfera ISA** por altitude (0 a 20 km): T, p, ρ, μ (Sutherland), velocidade do som. Teste contra a tabela padrão (1%).
**MP-8.2 Mach e aviso de compressibilidade:** acima de Mach 0,3 o resultado de arrasto mostra "incompressivel: nao usar como resultado final".
**MP-8.3 Volume submerso pela geometria** (malha/primitivas) cortada por um plano de linha d'água; empuxo e centro de empuxo.
**MP-8.4 Equilíbrio de flutuação:** achar o calado em que empuxo = peso (bissecção). Teste: caixa de madeira.
**MP-8.5 Altura metacêntrica** GM = KB + BM − KG para casco em caixa (BM = I/V). Teste contra fórmula.
**MP-8.6** Tudo nesta fase sai como ESTIMATIVA, com o texto "nao e CFD".

### Fase 9: integração com a suíte (P0)

**MP-9.1 MultiAssembly → MultiPhysics:** botão "Simular no MultiPhysics" no MultiAssembly que salva a montagem e abre o MultiPhysics com o arquivo (via `multisuite_launcher`). Só a chamada; nada da lógica de física no MultiAssembly.
**MP-9.2 Instalador:** conferir que o setup copia o que o MultiPhysics precisa (nenhuma DLL nova é esperada); exemplos em `documentation/models/multiphysics/` (um `.mphys` por simulação S1 a S7).
**MP-9.3 Documentação:** atualizar README.md (o que é ENGENHARIA e o que é ESTIMATIVA), AI_GUIDE.md (estrutura nova), RUNTIME.md, INTEGRATION_ROADMAP.md (mover itens para Implementado só com teste) e criar `docs/MANUAL.md` com um passo a passo por simulação S1–S7.
**MP-9.4 Versão:** `multiphysics.lpi` com versão 0.2.0.0; NEWS e notas do próximo setup.

### Fase 10: verificação final (P0)

**MP-10.1** Todos os testes (`tests/run_all.ps1`) passando; benchmarks B1–B8 dentro da tolerância.
**MP-10.2** Ensaio manual: importar a CNC demo, colar contatos, fixar a base, aplicar 200 N na ponta do eixo Z, resolver, ver mapa de von Mises, rodar modal e ver o 1º modo animado, salvar, fechar, reabrir.
**MP-10.3** Com ccx instalado: mesmo caso no CalculiX, diferença < 5% no deslocamento máximo.
**MP-10.4** Compilar com `lazbuild --cpu=x86_64 --os=win64 --ws=win32`, `strip`, copiar `multiphysics.exe` para `bin/`.

## 6. Benchmarks analíticos

| ID | Caso | Fórmula | Tolerância |
|---|---|---|---|
| B1 | Barra 100×10×10 mm, aço, força axial 1 kN | δ = F·L/(E·A); σ = F/A | 1% (TET4 e TET10) |
| B2 | Viga em balanço 200×10×20 mm, aço, força P = 100 N na ponta | δ = P·L³/(3·E·I), I = b·h³/12; σ_max = P·L·c/I | TET10: 3%; TET4: só registrar |
| B3 | (P1) Placa com furo sob tração | Kt ≈ 3 (placa larga) | 10% |
| B4 | Parede plana 1D, T1 = 100 °C, T2 = 20 °C | T linear; q = k·ΔT/L | 0,5% |
| B5 | Aleta com convecção e ponta adiabática | θ(x)/θ₀ = cosh(m(L−x))/cosh(mL), m = √(h·P/(k·A)) | 3% |
| B6 | Barra presa nas duas pontas, ΔT = 50 K | σ = −E·α·ΔT | 2% |
| B7 | Viga em balanço, 1ª frequência | f₁ = (1,875²/(2π))·√(E·I/(ρ·A·L⁴)) | 3% (TET10) |
| B8 | Barra livre-livre, 1º modo axial | f = (1/(2L))·√(E/ρ) | 2% |
| B9 | Circuito RC, degrau | v(t) = V·(1 − e^(−t/RC)) | 0,5% |
| B10 | Motor DC a vazio | ω∞ = V/Ke (com b = 0) | 1% |

Cada benchmark vira um teste em `multiphysics/tests/` com nome `test_bench_bN_*.lpr`.

## 7. Ordem recomendada de execução

1. Fase 0 inteira (rede de segurança).
2. MP-1.1, 1.2, 1.3, 1.5, 1.6.
3. MP-2.2, 2.3 → MP-3.1, 3.2, 3.4 → MP-4.1, 4.2, 4.3, 4.4 com B1 e B2 (primeiro marco: **viga em balanço resolvida pelo FEM próprio, em teste**).
4. MP-3.5 (TET10), MP-4.5, 4.6, 4.7 com B4–B8.
5. MP-6.1, 6.2, 6.3, 6.4 (segundo marco: **resolver a viga pela interface e ver o mapa de cores**).
6. MP-2.1, 2.4, 3.3 (montagem real com contatos colados).
7. Fase 5 (CalculiX).
8. Fase 7 e MP-7.15, MP-6.6.
9. MP-4.9, 4.10, 4.11, 6.5, 6.7.
10. Fase 8, Fase 9, Fase 10.

Cada passo termina com: compilar o app, rodar `tests/run_all.ps1`, atualizar a tabela **Progresso** e commitar.

## 8. Progresso

Atualize esta tabela a cada tarefa concluída (data, commit, teste que comprova).

| Tarefa | Estado | Data | Commit | Teste |
|---|---|---|---|---|
| Plano (este arquivo) | feito | 18/10/2026 | — | — |
| Fase 0 (MP-0.1 a 0.4) | pendente | | | |
| Fase 1 (MP-1.1 a 1.6) | pendente | | | |
| Fase 2 (MP-2.1 a 2.4) | pendente | | | |
| Fase 3 (MP-3.1 a 3.7) | pendente | | | |
| MP-3.8 (P1) | pendente | | | |
| Fase 4 (MP-4.1 a 4.11) | pendente | | | |
| Fase 5 (MP-5.1 a 5.5) | pendente | | | |
| Fase 6 (MP-6.1 a 6.7) | pendente | | | |
| Fase 7 (MP-7.1 a 7.15) | pendente | | | |
| Fase 8 (MP-8.1 a 8.6, P1) | pendente | | | |
| Fase 9 (MP-9.1 a 9.4) | pendente | | | |
| Fase 10 (MP-10.1 a 10.4) | pendente | | | |

Ao quebrar uma fase em várias sessões, detalhe as linhas por tarefa (ex.: `MP-4.4 | feito | ... | B1, B2`).

## 9. Como continuar (para outra sessão ou pessoa)

1. **Ambiente:** Windows x64, Lazarus em `C:\lazarus`, compilador `C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe`.
   Compilar o app:
   `C:\lazarus\lazbuild.exe --cpu=x86_64 --os=win64 --ws=win32 --compiler=C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe multiphysics\src\app\multiphysics.lpi`
   Executável final sem símbolos: `C:\lazarus\fpc\3.2.2\bin\x86_64-win64\strip.exe -o bin\multiphysics.exe multiphysics\src\app\multiphysics.exe`.
2. **Git:** trabalhar na branch `fila`; commits pequenos por tarefa, mensagem começando com `multiphysics:`; terminar a mensagem com a linha `Co-Authored-By` usada no repositório. Rodar `git status` antes de commitar e incluir só os arquivos da tarefa (outras sessões podem estar mexendo em outros apps).
3. **Antes de começar uma tarefa:** ler a linha dela neste arquivo, os arquivos citados e o teste correspondente; conferir na tabela **Progresso** se ninguém já fez.
4. **Ao terminar uma tarefa:** teste novo passando, testes antigos passando, app compilando, tabela **Progresso** atualizada no mesmo commit.
5. **Se algo da especificação estiver errado ou impossível na 0.2:** registrar em **Decisões** abaixo (data, decisão, motivo) em vez de mudar o objetivo em silêncio.
6. **Release:** quando a Fase 10 estiver feita, gerar o próximo setup com `installer\windows\build_release.bat -Version 0.NN -SetupSeq 0NN` (ver [installer/windows/README.md](../../installer/windows/README.md)).

## 10. Decisões

| Data | Decisão | Motivo |
|---|---|---|
| 18/10/2026 | Malhador estruturado por primitiva em vez de Delaunay 3D genérico | As peças do MultiAssembly já são primitivas (`box`, `cyl`, `prism`); dá malha válida e determinística com muito menos código. STL genérico fica para 0.3 (MP-3.8). |
| 18/10/2026 | Contato colado por amarração (tie/MPC), sem atrito | Atende S5 com solver linear; contato com atrito exige solver não linear (fora da 0.2). |
| 18/10/2026 | Solver próprio é o padrão; CalculiX é opcional e de comparação | O setup não distribui o ccx; o app precisa resolver sem dependências externas. |
| 18/10/2026 | TET10 padrão no estrutural | TET4 trava em flexão (B2 com erro grande); TET10 atinge 3% com malha moderada. |
