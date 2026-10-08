# Clipper2 (Delphi/Pascal)

Biblioteca de recorte e deslocamento (*offset*) de poligonos de Angus Johnson, licenca
Boost Software License 1.0 (ver `LICENSE`). Copia sem alteracoes de
`Delphi/Clipper2Lib` do repositorio https://github.com/AngusJohnson/Clipper2
(commit f9c5eb6e14a59f6f5d65fbfb3564519a561cf4fd Mon Apr 20 11:18:06 2026 +1000). Compila no FPC 3.2 em modo Delphi (o `Clipper.inc` trata o FPC).

Usada pelo MakeRouter (`makerouter/src/geom/makerouter_clip.pas`) para offset de perfis e
bolsoes e para soldar/subtrair vetores. Para atualizar: copiar os arquivos da mesma pasta
do repositorio e rodar `makerouter/tests/test_makerouter`.
