# Exercício do MultiCAM

O MultiCAM não abre arquivos: os parâmetros são digitados e ele gera o G-code.

## E1 — Perfil retangular

1. No MultiCAM, preencha: **Largura (mm)** 40, **Altura (mm)** 40,
   **Diametro ferramenta** 3, **Profundidade final negativa** -3, **Step-down** 1,
   **Safe Z** 5, e configure Feed, Plunge e Spindle RPM.
2. **Gerar perfil retangular**: o painel mostra o número de movimentos do percurso.
3. **Validar e exportar G-code** e salve como `perfil_40x40.nc`.
4. Abra no MultiCNC e compare com `../cnc_router/02_quadrado_40x40.nc` (mesmo quadrado,
   gerado à mão).

Esperado: 3 passadas de 1 mm, com a ferramenta por fora do quadrado (raio 1,5 mm).
