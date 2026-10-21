#!/usr/bin/env bash
# Gera o setup Windows x64 no Linux: compilacao cruzada win64 (FPC/Lazarus),
# testes de console win64 rodando no Wine e Inno Setup (ISCC.exe) no Wine.
# Mesmos passos e saidas do build_release.ps1.
#
# Requisitos: lazbuild, fpc com as units x86_64-win64 (RTL e pacotes), wine
# (32 e 64 bits), python3 com Pillow e o Inno Setup 6.3+ (ISCC.exe).
#
#   ISCC=/caminho/ISCC.exe installer/windows/build_release_wine.sh 0.15 015 [--allow-dirty]
#
# MULTICNC_CHATGPT_DIR aponta para o repositorio CHATGPT (padrao: ../CHATGPT).
set -euo pipefail
VERSION=${1:-0.15}
SEQ=${2:-015}
ALLOW_DIRTY=${3:-}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
DIST="$ROOT/dist"; APP="$DIST/app"; BIN="$ROOT/bin"
WINE=${WINE:-wine}
ISCC=${ISCC:?defina ISCC com o caminho do ISCC.exe}
LAZBUILD=${LAZBUILD:-lazbuild}
FPC_BIN=${FPC:-fpc}
CHATGPT=${MULTICNC_CHATGPT_DIR:-$(dirname "$ROOT")/CHATGPT}
[[ "$SEQ" =~ ^[0-9]{3}$ ]] || { echo "SetupSeq invalido: $SEQ"; exit 1; }
if [ "$ALLOW_DIRTY" != "--allow-dirty" ] && [ -n "$(git status --porcelain)" ]; then
  echo "A release exige uma arvore Git limpa. Para build local use --allow-dirty."; exit 1
fi
rm -rf "$APP"
mkdir -p "$APP" "$BIN" "$DIST/build-logs"
# dependencias do CHATGPT, como no build_release.ps1
CONFIG="$DIST/compiler-dependencies.cfg"
: > "$CONFIG"
for folder in "pacote/AI" "pacote/AI Input/AISerial" "pacote/AI Simulation/Marlin" "pacote/AI Input/AISockets" "pacote/AI Input/AIVirtualSerial"; do
  [ -d "$CHATGPT/$folder" ] && echo "-Fu$CHATGPT/$folder" >> "$CONFIG"
done
# o lazbuild 3.0 nao tem --opt: um compilador "embrulhado" le o mesmo arquivo
WRAP="$DIST/fpc-win64.sh"
printf '#!/bin/sh\nexec %s @%s "$@"\n' "$(command -v "$FPC_BIN")" "$CONFIG" > "$WRAP"
chmod +x "$WRAP"
TARGETS=(
  "multiproject/src/app/multiproject|multiproject"
  "multicad/src/app/multicad|multicad"
  "multiassembly/src/app/multiassembly|multiassembly"
  "multiphysics/src/app/multiphysics|multiphysics"
  "multicam/src/app/multicam|multicam"
  "multislicer/src/app/multislicer|multislicer"
  "makepcb/src/app/makepcb|makepcb"
  "makerouter/src/app/makerouter|makerouter"
  "routerpcb/src/app/routerpcb|routerpcb"
  "laserpcb/src/app/laserpcb|laserpcb"
  "laserart/src/app/laserart|laserart"
  "src/app/multicnc|multicnc"
  "multisuite/src/tray/multisuite_tray|multisuite_tray"
  "src/simucnc/simucnc|SimuCNC"
)
for t in "${TARGETS[@]}"; do
  project=${t%%|*}; name=${t##*|}
  echo "Compilando $name..."
  log="$DIST/build-logs/$name.log"
  if ! "$LAZBUILD" -B --cpu=x86_64 --os=win64 --ws=win32 --compiler="$WRAP" --build-mode=Default "$project.lpi" > "$log" 2>&1; then
    tail -35 "$log"; echo "Falha ao compilar $name"; exit 1
  fi
  # no Windows o nome nao diferencia maiusculas (simucnc.lpi gera SimuCNC.exe)
  out="$project.exe"; [ -f "$out" ] || out="$(dirname "$project")/$name.exe"
  cp "$out" "$APP/$name.exe"
done
[ -f "$BIN/mcad_occt.dll" ] || { echo "DLL obrigatoria ausente: bin/mcad_occt.dll"; exit 1; }
cp "$BIN/mcad_occt.dll" "$APP/"
[ -d models/components/mec ] || { echo "Biblioteca ausente: models/components/mec"; exit 1; }
mkdir -p "$APP/models/components"
cp -r models/components/mec "$APP/models/components/"
for exe in "$APP"/*.exe; do strip --strip-debug "$exe"; done
# o Wine nao tem Times New Roman: test_sketch_text compara duas fontes diferentes
"$WINE" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' \
  /v "Times New Roman" /d "DejaVu Serif" /f > /dev/null
MULTICNC_TEST_FLAGS="-Px86_64 -Twin64" MULTICNC_TEST_RUNNER="$WINE" FPC="$FPC_BIN" \
  MULTICNC_CHATGPT_DIR="$CHATGPT" python3 -u tools/verify_suite.py console --stage "$APP"
python3 tools/stage_documentation.py --app-dir "$APP" --version "$VERSION"
CLEAN=--require-clean; [ "$ALLOW_DIRTY" = "--allow-dirty" ] && CLEAN=
FPC="$FPC_BIN" python3 tools/release_manifest.py --app-dir "$APP" --version "$VERSION" --os windows --arch amd64 \
  --version-include "$DIST/version.iss" $CLEAN
python3 installer/windows/prepare_images.py --version "$VERSION" --out "$DIST/installer-images"
NAME="setup_multcnc_$SEQ"
"$WINE" "$ISCC" /Q "/dSetupSeq=$SEQ" "/dOutputExeName=$NAME" "$(winepath -w "$ROOT/installer/windows/multisuite.iss")"
mkdir -p setup
cp "$DIST/$NAME.exe" "$BIN/"
cp "$DIST/$NAME.exe" setup/
for t in "${TARGETS[@]}"; do cp "$APP/${t##*|}.exe" "$BIN/"; done
HASH=$(sha256sum "$DIST/$NAME.exe" | cut -d' ' -f1)
echo "$HASH  $NAME.exe" > "$DIST/SHA256SUMS"
{ [ -f setup/SHA256SUMS ] && grep -v "  $NAME.exe\$" setup/SHA256SUMS | grep '\S' || true; echo "$HASH  $NAME.exe"; } > setup/SHA256SUMS.new
mv setup/SHA256SUMS.new setup/SHA256SUMS
cp "$APP/build-manifest.json" "setup/build-manifest-$SEQ.json"
cp "$APP/qa-tests.json" "setup/qa-tests-$SEQ.json"
echo "Setup gerado: bin/$NAME.exe"
