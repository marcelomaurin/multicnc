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

VERSION="${VERSION:-0.1.0}"
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

for entry in "${APPS[@]}"; do
  IFS='|' read -r id lpi exe name desc <<<"$entry"
  echo "=== Compilando $lpi ==="
  rm -f "$exe"
  lazbuild "${LAZOPTS[@]}" "$lpi"
  [ -x "$exe" ] || { echo "ERRO: executavel nao encontrado: $exe" >&2; exit 1; }
  install -m 0755 "$exe" "$STAGE$APPDIR/$id"
  "$STRIP" -s "$STAGE$APPDIR/$id"

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

cp -r docs "$STAGE$APPDIR/docs"

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
Depends: libgtk2.0-0 | libgtk2.0-0t64, libc6
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

echo
echo "Pacotes gerados em $OUT:"
ls -la "$OUT"
