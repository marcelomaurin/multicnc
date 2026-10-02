#!/usr/bin/env bash
# Entrada compativel: tests/run_all.sh [modulo ...].
# O mesmo compilador de testes atende ao Linux, Windows e empacotamento.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/tools/verify_suite.py" console "$@"
