# Setup 017 — MultiSuite 0.17

Edição de **31/10/2026**, para **Windows x64**. MultiCAD 0.0.9.0.

[Instalador](../setup/setup_multcnc_0.17.exe) · [Cópia em bin](../bin/setup_multcnc_0.17.exe) · [SHA-256](../setup/SHA256SUMS)

## MultiCAD 0.0.9.0: rosca, engrenagens, revolução e variáveis

- **Rosca real em hélice** (aba Operações ou Inserir > Rosca): externa num pino, interna
  num furo, perfil ISO de 60°. Medida automática pela face (diâmetro do pino ou broca do
  furo: 6,75 vira M8), tabela M2 a M24 com passo normal ou fino, ou personalizada.
  Rosca esquerda, comprimento e início. **Folga radial para impressão 3D** (FDM: 0,1 a
  0,2 mm). Termina antes de ombros e de fundos de furo cego.
- **Engrenagens** (Inserir > Engrenagem): cilíndrica externa, interna (anel) e
  cremalheira, com dentes retos, helicoidais ou espinha de peixe. Perfil evolvente,
  correção do perfil, folga, furo com rasgo de chaveta e posição por plano, ponto, giro e
  afastamento. O painel mostra os diâmetros e a distância entre centros do par. A
  engrenagem nasce como corpo separado; "Mesclar resultado" a une ao eixo.
- **Revolução**: ícone próprio e eixo escolhido com o clique na vista (linha do esboço,
  inclusive de centro e de construção, aresta reta, eixo de referência ou face cilíndrica).
- **Medidas com conta e variáveis**: qualquer cota ou campo aceita `35-10mm`. Uma cota
  digitada como `aresta=25` passa a se chamar "aresta" e pode ser usada em outros lugares
  como `Esboço1.aresta`, `Cubo.aresta` (pelo nome da operação), `[Ressalto-Extrusão1].aresta`
  ou só `aresta` quando o nome é único. Mudar a variável recalcula esboços, profundidades e
  campos das operações que a usam; a expressão fica gravada no `.mcad`.
- Detalhes e limites: [README do MultiCAD](../multicad/README.md).

## OpenCascade

`mcad_occt.dll` recompilada (OpenCascade 7.6.3 estático, MinGW) com a ponte versão 2:
booleana sem unificar faces, usada pela rosca. O instalador traz a DLL nova ao lado do
`multicad.exe`; com a DLL antiga a rosca dá erro em vez de travar. No OpenCascade cada
rosca leva alguns segundos; no núcleo Pascal (sem a DLL) cerca de 20 s, podendo recusar
roscas longas sem estragar o modelo.

## Verificação e rastreabilidade

- Os 14 aplicativos foram compilados para Win64 (Lazarus 3.0 / FPC 3.2.2 com compilação
  cruzada no Linux) e o instalador gerado com Inno Setup 6.4.3 no Wine.
- **120 testes de console aprovados, nenhuma falha** (121 programas compilados), rodando
  os executáveis Win64 no Wine.
- MultiCAD: 679 verificações do núcleo com OpenCascade (Linux e Wine) e 660 no núcleo
  Pascal; `test_thread_gear_ui` aprovado no Linux e no Wine.
- Instalação silenciosa de teste no Wine: 765 arquivos, os 14 aplicativos, a DLL nova,
  documentação e modelos; desinstalação limpa.
- `tools/verify_suite.py`: o `test_multicad` ganhou limite de tempo próprio (cortes de rosca).
- Não inclui ensaios em máquinas reais nem verificação interativa no Windows nativo.
- [Manifesto de compilação](../setup/build-manifest-017.json): fontes `7d22596`, árvore limpa na geração.
- [Resultados de console](../setup/qa-tests-017.json).

SHA-256 do instalador:

```text
2d4d72b91c0faa6258b641f843fbef1285a7d48dc4958ce3cfd8e3471143ebd4  setup_multcnc_0.17.exe
```
