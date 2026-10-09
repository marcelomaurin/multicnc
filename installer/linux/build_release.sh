#!/usr/bin/env bash
# Gera o pacote Linux do MultiSuite para a arquitetura escolhida:
#   dist/linux-<arch>/multisuite_<versao>_<arch>.deb
#   dist/linux-<arch>/MultiSuite-<versao>-linux-<cpu>.tar.xz
#
# Uso: installer/linux/build_release.sh [amd64|arm64|armhf]   (padrao: amd64)
#
# Requisitos (Debian/Ubuntu): sudo apt install lazarus lcl-gtk2 dpkg-dev
# Para arm64/armhf em maquina x86_64 e preciso um Free Pascal cruzado para o
# alvo e binutils do alvo (veja installer/linux/README.md). Em uma maquina ARM
# (ex.: Raspberry Pi) basta rodar sem argumento de cruzamento: o script detecta.
set -euo pipefail

VERSION="${VERSION:-0.1.1-dev}"
[[ "$VERSION" =~ ^[0-9][A-Za-z0-9.+~-]*$ ]] || { echo "ERRO: versao invalida." >&2; exit 1; }
HOSTARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
ARCH="${1:-$HOSTARCH}"
case "$ARCH" in
  amd64) CPU=x86_64;  TRIPLE=x86_64-linux-gnu ;;
  arm64) CPU=aarch64; TRIPLE=aarch64-linux-gnu ;;
  armhf) CPU=arm;     TRIPLE=arm-linux-gnueabihf ;;
  *) echo "ERRO: arquitetura nao suportada: $ARCH (use amd64, arm64 ou armhf)" >&2; exit 1 ;;
esac
TARNAME="$CPU"; [ "$ARCH" = armhf ] && TARNAME=armhf
LAZOPTS=(--build-mode=Default --ws=gtk2)
STRIP=strip
if [ "$ARCH" != "$HOSTARCH" ]; then
  LAZOPTS+=(--os=linux --cpu="$CPU")
  STRIP="$TRIPLE-strip"
  command -v "$STRIP" >/dev/null || { echo "ERRO: $STRIP nao encontrado (instale binutils-$TRIPLE)." >&2; exit 1; }
fi
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/dist/linux-$ARCH"
STAGE="$OUT/stage"
APPDIR=/opt/multisuite

cd "$ROOT"
command -v lazbuild >/dev/null || { echo "ERRO: lazbuild nao encontrado no PATH." >&2; exit 1; }

# id | projeto | executavel gerado | nome exibido | descricao
APPS=(
  "multisuite|multisuite/src/app/multisuite.lpi|multisuite/src/app/multisuite|MultiSuite|Central de engenharia MultiSuite"
  "multicad|multicad/src/app/multicad.lpi|multicad/src/app/multicad|MultiCAD|Modelagem CAD mecanica"
  "multipcb|multipcb/src/app/multipcb.lpi|multipcb/src/app/multipcb|MultiPCB|Esquematico e PCB"
  "multiassembly|multiassembly/src/app/multiassembly.lpi|multiassembly/src/app/multiassembly|MultiAssembly|Montagem eletromecanica"
  "multiphysics|multiphysics/src/app/multiphysics.lpi|multiphysics/src/app/multiphysics|MultiPhysics|Simulacao estrutural, termica e dinamica"
  "multicam|multicam/src/app/multicam.lpi|multicam/src/app/multicam|MultiCAM|CAM e simulacao CNC Router"
  "multislicer|multislicer/src/app/multislicer.lpi|multislicer/src/app/multislicer|MultiSlicer|Fatiamento para impressao 3D"
  "makepcb|makepcb/src/app/makepcb.lpi|makepcb/src/app/makepcb|MakePCB|Projeto de placas do zero"
  "makerouter|makerouter/src/app/makerouter.lpi|makerouter/src/app/makerouter|MakeRouter|Projeto e usinagem de madeira"
  "routerpcb|routerpcb/src/app/routerpcb.lpi|routerpcb/src/app/routerpcb|RouterPCB|Fresagem de PCB na CNC Router"
  "laserpcb|laserpcb/src/app/laserpcb.lpi|laserpcb/src/app/laserpcb|LaserPCB|Preparacao de PCB para laser"
  "laserart|laserart/src/app/laserart.lpi|laserart/src/app/laserart|LaserArt|Imagem, vetor e arte para laser"
  "multicnc|src/app/multicnc.lpi|src/app/multicnc|MultiCNC|Controle e execucao da maquina"
  "multisuite_test_center|multisuite/src/testing/multisuite_test_center.lpi|multisuite/src/testing/multisuite_test_center|MultiSuite Central de Testes|Central de testes do MultiSuite"
)

rm -rf "$OUT"
mkdir -p "$STAGE$APPDIR" "$STAGE/usr/bin" "$STAGE/usr/share/applications" "$STAGE/usr/share/mime/packages" "$STAGE/DEBIAN"

if [ "$ARCH" = armhf ]; then
  # Debian's native FPC can default to EABI soft-float despite the armhf host.
  # A compiler wrapper works with older lazbuild versions without ExtraOpts.
  FPC_REAL="$(command -v "${FPC:-fpc}")"
  GCC_TARGET="$TRIPLE-gcc"
  if ! command -v "$GCC_TARGET" >/dev/null; then
    [ "$ARCH" = "$HOSTARCH" ] || { echo "ERRO: instale gcc-$TRIPLE para os objetos de inicializacao C." >&2; exit 1; }
    GCC_TARGET=gcc
  fi
  CRT_BEGIN="$("$GCC_TARGET" -print-file-name=crtbegin.o)"
  [ -f "$CRT_BEGIN" ] || { echo "ERRO: crtbegin.o do alvo ARM nao encontrado." >&2; exit 1; }
  GCC_LIBDIR="$(dirname "$CRT_BEGIN")"
  FPC_WRAP_DIR="$(mktemp -d)"
  trap 'rm -rf "$FPC_WRAP_DIR"' EXIT
  python3 - "$FPC_REAL" "$FPC_WRAP_DIR/fpc-armhf" "$GCC_LIBDIR" <<'PY'
import pathlib, shlex, sys
p = pathlib.Path(sys.argv[2])
p.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.argv[1]) +
             ' "$@" -Parm -Tlinux -Aas -CaEABIHF -CfVFPV3_D16 -CpARMV7A ' +
             shlex.quote('-Fl' + sys.argv[3]) + '\n')
p.chmod(0o755)
PY
  export FPC="$FPC_WRAP_DIR/fpc-armhf"
  LAZOPTS+=(--compiler="$FPC" --build-all)
  # Check the actual linker output before the expensive LCL/application build.
  cat > "$FPC_WRAP_DIR/abi_probe.pas" <<'PAS'
program abi_probe;
uses SysUtils, Math;
begin
  if Abs(Sqrt(StrToFloat('2.25')) - 1.5) > 0.00001 then Halt(1);
  Writeln('ARM floating point: OK');
end.
PAS
  "$FPC" -FE"$FPC_WRAP_DIR" -FU"$FPC_WRAP_DIR" "$FPC_WRAP_DIR/abi_probe.pas"
  readelf -h "$FPC_WRAP_DIR/abi_probe"
  readelf -A "$FPC_WRAP_DIR/abi_probe"
  python3 - "$FPC_WRAP_DIR/abi_probe" <<'PY'
import pathlib, struct, sys
head = pathlib.Path(sys.argv[1]).read_bytes()[:52]
if len(head) < 52 or head[:6] != b'\x7fELF\x01\x01':
    raise SystemExit('O compilador ARM nao gerou ELF32 little-endian.')
flags = struct.unpack_from('<I', head, 36)[0]
if flags & 0xff000600 != 0x05000400:
    raise SystemExit(f'O compilador ARM nao gerou EABI5 hard-float: 0x{flags:x}')
print(f'ARM compiler ABI: OK (e_flags=0x{flags:x})')
PY
  [ "$ARCH" != "$HOSTARCH" ] || "$FPC_WRAP_DIR/abi_probe"
fi

check_armhf() {
  python3 - "$1" <<'PY'
import pathlib, struct, sys
head = pathlib.Path(sys.argv[1]).read_bytes()[:52]
flags = struct.unpack_from('<I', head, 36)[0]
if head[:6] != b'\x7fELF\x01\x01' or flags & 0xff000600 != 0x05000400:
    raise SystemExit(f'ABI ARM incorreta antes/depois de strip: {sys.argv[1]} e_flags=0x{flags:x}')
PY
}

strip_executable() {
  if [ "$ARCH" = armhf ]; then
    check_armhf "$1"
    cp -p "$1" "$FPC_WRAP_DIR/unstripped"
    "$STRIP" -s "$1"
    if ! check_armhf "$1"; then
      cp -p "$FPC_WRAP_DIR/unstripped" "$1"
      echo "Strip alterou a ABI; preservando o executavel original: $1"
    fi
    rm -f "$FPC_WRAP_DIR/unstripped"
  else
    "$STRIP" -s "$1"
  fi
}

for entry in "${APPS[@]}"; do
  IFS='|' read -r id lpi exe name desc <<<"$entry"
  echo "=== Compilando $lpi ==="
  rm -f "$exe"
  lazbuild "${LAZOPTS[@]}" "$lpi"
  [ -x "$exe" ] || { echo "ERRO: executavel nao encontrado: $exe" >&2; exit 1; }
  install -m 0755 "$exe" "$STAGE$APPDIR/$id"
  strip_executable "$STAGE$APPDIR/$id"

  # Wrapper em /usr/bin: o launcher procura as ferramentas ao lado do executavel real.
  printf '#!/bin/sh\nexec %s/%s "$@"\n' "$APPDIR" "$id" > "$STAGE/usr/bin/$id"
  chmod 0755 "$STAGE/usr/bin/$id"

  mime=""; [ "$id" = multisuite ] && mime="MimeType=application/x-multisuite-project;"
  cat > "$STAGE/usr/share/applications/$id.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$desc
Exec=$APPDIR/$id %f
Terminal=false
Categories=Engineering;Development;
$mime
EOF
done

if [ "${MULTICNC_GUI_SMOKE:-0}" = 1 ]; then
  for test in tests/test_app multisuite/tests/test_suite_app multislicer/tests/test_slicer_app; do
    lazbuild "${LAZOPTS[@]}" "$test.lpi"
    xvfb-run -a "$ROOT/$test"
  done
fi

cp -r docs "$STAGE$APPDIR/docs"

# Testes acompanham a instalacao e executam em diretorios temporarios gravaveis.
if [ "$ARCH" = "$HOSTARCH" ]; then
  python3 tools/verify_suite.py console --stage "$STAGE$APPDIR"
else
  MULTICNC_TEST_FLAGS="-P$CPU -Tlinux" python3 tools/verify_suite.py console --build-only --stage "$STAGE$APPDIR"
fi
while IFS= read -r -d '' exe; do
  strip_executable "$exe"
done < <(find "$STAGE$APPDIR/tests" -type f -name 'test_*' -print0)

# A dependência minima vem dos simbolos dos executaveis efetivamente gerados.
GLIBC_MIN=$(find "$STAGE$APPDIR" -type f -exec readelf --version-info {} \; 2>/dev/null | sed -n 's/.*Name: GLIBC_\([0-9.]*\).*/\1/p' | sort -Vu | tail -1)
[ -n "$GLIBC_MIN" ] || { echo "ERRO: nao foi possivel determinar a glibc minima." >&2; exit 1; }
MANIFEST_OPTS=()
[ "${RELEASE_REQUIRE_CLEAN:-1}" = 1 ] && MANIFEST_OPTS+=(--require-clean)
python3 tools/release_manifest.py --app-dir "$STAGE$APPDIR" --version "$VERSION" --os linux --arch "$ARCH" "${MANIFEST_OPTS[@]}"
cp "$STAGE$APPDIR/build-manifest.json" "$STAGE$APPDIR/qa-tests.json" "$OUT/"

cat > "$STAGE/usr/share/mime/packages/multisuite.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-multisuite-project">
    <comment>Projeto MultiSuite</comment>
    <glob pattern="*.msuite"/>
  </mime-type>
</mime-info>
EOF

SIZE=$(du -sk "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<EOF
Package: multisuite
Version: $VERSION
Section: science
Priority: optional
Architecture: $ARCH
Depends: libgtk2.0-0 | libgtk2.0-0t64, libc6 (>= $GLIBC_MIN)
Installed-Size: $SIZE
Maintainer: Maurinsoft <marcelomaurinmartins@gmail.com>
Homepage: https://github.com/marcelomaurin/multicnc
Description: MultiSuite - CAD, PCB, CAM, fatiamento, laser e controle CNC
 Inclui MultiSuite, MultiCAD, MultiPCB, MultiAssembly, MultiPhysics, MultiCAM,
 MultiSlicer, MakePCB, MakeRouter, RouterPCB, LaserPCB, LaserArt, MultiCNC e Central de Testes.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-mime-database >/dev/null && update-mime-database /usr/share/mime || true
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
EOF
cp "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"
chmod 0755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

dpkg-deb --root-owner-group --build "$STAGE" "$OUT/multisuite_${VERSION}_${ARCH}.deb"

TARDIR="$OUT/MultiSuite-$VERSION-linux-$TARNAME"
mkdir -p "$TARDIR"
cp -r "$STAGE$APPDIR/." "$TARDIR/"
tar -C "$OUT" -cJf "$OUT/MultiSuite-$VERSION-linux-$TARNAME.tar.xz" "$(basename "$TARDIR")"
rm -rf "$TARDIR" "$STAGE"

(cd "$OUT" && sha256sum "multisuite_${VERSION}_${ARCH}.deb" "MultiSuite-${VERSION}-linux-${TARNAME}.tar.xz" > SHA256SUMS && sha256sum -c SHA256SUMS)

echo
echo "Pacotes gerados em $OUT:"
ls -la "$OUT"
