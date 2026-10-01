#!/usr/bin/env bash
# Compila e executa todos os testes de console da suite MultiCNC.
#
# Uso:  tests/run_all.sh [modulo ...]
#   sem argumentos: todos (. multisuite multiphysics multicam multipcb
#   laserpcb multislicer multiassembly multicad)
#
# Os executaveis ficam ao lado de cada .lpr (ex.: multicam/tests/test_hsm),
# que e onde a Central de Testes do MultiSuite os procura. Units compiladas
# vao para $MULTICNC_BUILD (padrao: /tmp/multicnc-build).
# Testes que dependem da LCL (uses Interfaces) sao compilados pelo lazbuild
# no CI e ignorados aqui.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="${MULTICNC_BUILD:-/tmp/multicnc-build}"
mkdir -p "$BUILD"
MODULES="${*:-. multisuite multiphysics multicam multipcb laserpcb multislicer multiassembly multicad}"
ALL=$(find */src src -type d ! -name app | sed 's/^/-Fu/' | tr '\n' ' ')
pass=0; fail=0; cfail=0; failed=""
for m in $MODULES; do
  if [ "$m" = "." ]; then
    own="-Fusrc/app $(find src -type d | sed 's/^/-Fu/' | tr '\n' ' ')"
    tag="multicnc"
  else
    own=$(find "$m/src" -type d ! -name app | sed 's/^/-Fu/' | tr '\n' ' ')
    tag="$m"
  fi
  mkdir -p "$BUILD/$tag"
  for t in "$m"/tests/*.lpr; do
    [ -f "$t" ] || continue
    grep -qE '\bInterfaces *[,;]' "$t" && continue
    name=$(basename "$t" .lpr)
    dir=$(dirname "$t")
    log="$BUILD/$tag/$name.log"
    # shellcheck disable=SC2086
    if fpc -Mobjfpc -Sh -O1 -vw0 $own $ALL -FU"$BUILD/$tag" -FE"$dir" "$t" > "$log" 2>&1; then
      if out=$(cd "$dir" && timeout 300 "./$name" 2>&1); then
        pass=$((pass + 1))
        echo "PASS  $tag/$name  $(echo "$out" | tail -1)"
      else
        fail=$((fail + 1)); failed="$failed $tag/$name"
        echo "FAIL  $tag/$name"; echo "$out" | tail -5 | sed 's/^/      /'
      fi
    else
      cfail=$((cfail + 1)); failed="$failed $tag/$name(compile)"
      echo "BUILD $tag/$name"; grep -E 'Error|Fatal' "$log" | head -5 | sed 's/^/      /'
    fi
  done
done
echo "----"
echo "aprovados=$pass falhas=$fail erros_de_compilacao=$cfail"
[ -n "$failed" ] && echo "falharam:$failed"
[ $fail -eq 0 ] && [ $cfail -eq 0 ]
