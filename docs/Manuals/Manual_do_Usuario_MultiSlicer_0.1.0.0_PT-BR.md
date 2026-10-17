# MultiSlicer 0.1.0.0 — Manual do Usuário

Manual técnico oficial do fatiador 3D para manufatura aditiva FDM/FFF do ecossistema **MultiSuite**.

- **Versão do Aplicativo:** 0.1.0.0 (Windows x64)
- **Edição da Documentação:** 17 de outubro de 2026 (adendo do degrau inicial Z)
- **Desenvolvedor:** MaurinSoft / MultiSuite
- **Nota:** o PDF 0.1.0.0 permanece na edição anterior; as instruções do degrau inicial Z estão atualizadas nesta versão em texto.
- **Documento PDF Oficial:** [`Manual_do_Usuario_MultiSlicer_0.1.0.0_PT-BR.pdf`](Manual_do_Usuario_MultiSlicer_0.1.0.0_PT-BR.pdf) (A4, 30 páginas, sumário, marcadores e capturas de tela)

---

## Sumário dos Capítulos

1. [Fluxo de Trabalho e Fatiamento 3D](#01-fluxo-de-trabalho-e-fatiamento-3d)
2. [Conheça a Interface e Navegação na Mesa](#02-conheça-a-interface-e-navegação-na-mesa)
3. [Importação de Modelos (STL, 3MF) e MultiCAD](#03-importação-de-modelos-stl-3mf-e-multicad)
4. [Conferência e Reparo Automático de Malhas](#04-conferência-e-reparo-automático-de-malhas)
5. [Manipulação de Peças: Posição, Escala e Giro](#05-manipulação-de-peças-posição-escala-e-giro)
6. [Arranjo Automático e Cena com Múltiplas Peças](#06-arranjo-automático-e-cena-com-múltiplas-peças)
7. [Equipamentos e Perfis de Impressoras 3D — Degrau inicial Z](#07-equipamentos-e-perfis-de-impressoras-3d--degrau-inicial-z)
8. [Configuração de Filamentos e Materiais](#08-configuração-de-filamentos-e-materiais)
9. [Gestão Térmica e Refrigeração](#09-gestão-térmica-e-refrigeração)
10. [Qualidade e Alturas de Camada](#10-qualidade-e-alturas-de-camada)
11. [Perímetros, Paredes e Costura (Seam)](#11-perímetros-paredes-e-costura-seam)
12. [Superfícies Sólidas de Topo e Base](#12-superfícies-sólidas-de-topo-e-base)
13. [Padrões e Densidade de Preenchimento](#13-padrões-e-densidade-de-preenchimento)
14. [Estratégias de Suportes e Aderência](#14-estratégias-de-suportes-e-aderência)
15. [Hastes Manuais e Bloqueadores de Suporte](#15-hastes-manuais-e-bloqueadores-de-suporte)
16. [Saia (Skirt), Aba (Brim) e Jangada (Raft)](#16-saia-skirt-aba-brim-e-jangada-raft)
17. [Velocidades de Impressão e Acelerações](#17-velocidades-de-impressão-e-acelerações)
18. [Retração, Z-Hop e Prevenção de Fios](#18-retração-z-hop-e-prevenção-de-fios)
19. [Motor de Fatiamento e Segundo Plano](#19-motor-de-fatiamento-e-segundo-plano)
20. [Inspeção da Prévia 3D por Camada](#20-inspeção-da-prévia-3d-por-camada)
21. [Estimativa de Tempo e Consumo de Filamento](#21-estimativa-de-tempo-e-consumo-de-filamento)
22. [Projeto MultiSlicer (.mslice) e Arquivos](#22-projeto-multislicer-mslice-e-arquivos)
23. [Pós-Processamento e Firmwares (Marlin/Klipper)](#23-pós-processamento-e-firmwares-marlinklipper)
24. [Contrato MultiSuite e Envio ao MultiCNC](#24-contrato-multisuite-e-envio-ao-multicnc)
25. [Calibração de Fluxo e Precisão Dimensional](#25-calibração-de-fluxo-e-precisão-dimensional)
26. [Exercício Guiado: Da Malha à Impressão](#26-exercício-guiado-da-malha-à-impressão)
27. [Diagnóstico e Resolução de Problemas](#27-diagnóstico-e-resolução-de-problemas)
28. [Teclas de Atalho e Especificações Técnicas](#28-teclas-de-atalho-e-especificações-técnicas)

---

## 01. Fluxo de Trabalho e Fatiamento 3D

O **MultiSlicer** transforma malhas tridimensionais (polígonos de triângulos) em instruções de código G para manufatura aditiva FDM/FFF. 
A esteira digital da MultiSuite divide o trabalho em:
1. **Modelagem:** Concepção sólida paramétrica no MultiCAD ou softwares CAD externos;
2. **Fatiamento (MultiSlicer):** Orientação da peça, fatiamento em camadas, infill, suportes e geração de código G;
3. **Execução (MultiCNC):** Transmissão serial USB ou TCP para a impressora 3D com supervisão térmica e conferência de volume físico.

---

## 02. Conheça a Interface e Navegação na Mesa

A interface do MultiSlicer é organizada em um fluxo de abas lineares:
- **Topo:** Equipamento (Impressora cadastrada no MultiCNC ou Ajuste Manual);
- **Modelo:** Transformações geométricas (Posição, Escala, Rotação, Espelho, Arranjo);
- **Material:** Seleção do polímero (PLA, ABS, PETG, TPU), temperaturas de bico/mesa, ventilação e fluxo;
- **Qualidade:** Alturas de camada (fixas e adaptativas), paredes, superfícies sólidas, infill e velocidades;
- **Suporte:** Suportes automáticos e manuais (hastes), bloqueadores, saia (skirt), aba (brim) e jangada (raft);
- **Prévia 3D:** Deslizante camada por camada, legenda de trajetórias e métricas de tempo/consumo;
- **Saída:** Projeto `.mslice`, exportação de G-code e botão de envio direto *'Abrir no MultiCNC'*.

**Navegação 3D:**
- **Botão Direito do Mouse:** Rotação orbital;
- **Shift + Botão Direito:** Panorâmica (Pan);
- **Roda do Mouse (Scroll):** Zoom dinâmico.

---

## 07. Equipamentos e Perfis de Impressoras 3D — Degrau inicial Z

Na **etapa 1 — Impressora**, configure **Degrau inicial Z (mm)** para equipamentos em que a superfície de impressão se encontre acima do zero físico, ou nos quais o início do trabalho requeira um deslocamento vertical positivo conhecido. O parâmetro é específico do **perfil da impressora**, separado da altura de camada, e tem valor padrão **0,00 mm**.

### Configuração passo a passo

1. Selecione a marca/modelo ou perfil manual da impressora.
2. Confira as dimensões **Mesa X**, **Mesa Y** e **Altura máxima Z**.
3. Preencha **Degrau inicial Z (mm)** com o valor físico requerido, por exemplo **3,00**.
4. Salve o perfil em **Salvar...**. O valor é persistido como `print_start_z`; perfis antigos sem esse campo assumem zero.
5. Fatie novamente e confira na prévia e no G-code o Z da primeira camada; só envie ao MultiCNC após verificar o referencial do equipamento e a superfície real.

**Exemplo:** modelo com altura da primeira camada de **0,20 mm** e degrau de **3,00 mm**. Sem raft, a primeira camada de deposição começa em **Z=3,20 mm**. As alturas subsequentes são deslocadas por +3,00 mm, sem alterar distância entre camadas, geometria fatiada ou quantidade de extrusão. Com raft, o mesmo deslocamento é aplicado ao conjunto de camadas, incluindo sua base.

O G-code recebe o metadado `; MS-PRINT-START-Z: 3.00`; os comandos de Z da impressão e os comentários de camadas já incluem o deslocamento. A altura disponível é reduzida pelo degrau: uma peça de 100 mm, com degrau de 3 mm, exige pelo menos 103 mm de curso útil de impressão.

### Cuidados e limitações

- **Não confunda com Z-offset de calibração do bico.** O degrau não altera homing, malha de nivelamento nem configuração do firmware.
- Se a mesa real estiver em Z=0 e não houver plataforma correspondente em Z=3, imprimir em Z=3 mm depositará material no ar.
- Revise G-code inicial personalizado: comandos de purga, `G92 Z...`, outros offsets ou movimentos absolutos anteriores às camadas **não são corrigidos automaticamente** por este parâmetro.
- Faça um teste supervisionado com movimento sem extrusão, seguido de primeira camada, antes de produzir peças completas.
- A implementação foi publicada no código-fonte; o processo de compilação e testes físicos deste recurso ainda necessita validação.

---

## 08. Configuração de Filamentos e Materiais

Tabela de parâmetros recomendados por polímero:

| Polímero | Bico (1ª Camada / Demais) | Mesa Aquecida | Ventoinha de Peça |
|---|---|---|---|
| **PLA** | 210 °C / 200 °C | 60 °C / 55 °C | 100% (camada 2+) |
| **PETG** | 235 °C / 230 °C | 80 °C / 75 °C | 30% a 50% |
| **ABS / ASA** | 245 °C / 240 °C | 100 °C / 95 °C | 0% (desligada) |
| **TPU (95A)** | 220 °C / 215 °C | 50 °C / 45 °C | 50% a 80% (baixa vel.) |

---

## 13. Padrões e Densidade de Preenchimento

O MultiSlicer implementa o padrão moderno **Gyroid (Giroide)**:
- Distribuição homogênea de rigidez tridimensional sem cruzamento de cordões na mesma camada;
- Elimina batidas do bico aquecido e reduz drasticamente vibrações e ruídos;
- Densidade recomendada: 15% a 25% para peças de uso geral; 40% a 50% para peças sujeitas a esforços mecânicos severos.

---

## 24. Contrato MultiSuite e Envio ao MultiCNC

O MultiSlicer anexa ao início de cada G-code gerado o contrato de metadados:
```gcode
; MultiSlicer -> MultiCNC (Impressora 3D)
; MS-Machine: printer3d
; MS-Bounds: X10.0 Y15.0 X190.0 Y180.0 Z0.0 Z120.0
; MS-Filament: PLA (1.75 mm) - Massa: 45.2 g
; MS-Temperatures: Bed 60C, Nozzle 205C
```

Ao acionar **Abrir no MultiCNC**, o painel MultiCNC confere se as coordenadas `MS-Bounds` cabem na mesa da máquina. Se extrapolarem o limite, um alarme impede a partida acidental.

---

## 28. Teclas de Atalho de Referência Rápida

| Atalho | Função |
|---|---|
| `Ctrl + O` | Abrir modelo (STL, 3MF, .mslice) |
| `Ctrl + S` | Salvar projeto MultiSlicer (.mslice) |
| `Ctrl + R` | Fatiar a cena atual |
| `Esc` | Cancelar fatiamento em andamento |
| `Delete` | Remover peça selecionada da cena |
| `Ctrl + D` | Duplicar peça selecionada |
