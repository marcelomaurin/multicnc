#!/bin/sh
# Compila libmcad_occt.so (Linux) com o OpenCascade do sistema (apt: libocct-*-dev).
set -e
cd "$(dirname "$0")"
OUT=${1:-../../bin/libmcad_occt.so}
# OCCT 7.8 and later group the exchange toolkits under TKDE*.
if ldconfig -p | grep -q 'libTKDESTEP[.]so'; then
  exchange="-lTKDEIGES -lTKDESTEP -lTKDE -lTKXSBase"
else
  exchange="-lTKIGES -lTKSTEP -lTKSTEP209 -lTKSTEPAttr -lTKSTEPBase -lTKXSBase"
fi
g++ -std=gnu++17 -O2 -fPIC -shared -fvisibility=hidden -I/usr/include/opencascade mcad_occt.cpp -o "$OUT" \
  $exchange -lTKOffset -lTKFillet -lTKBool -lTKBO \
  -lTKPrim -lTKMesh -lTKShHealing -lTKTopAlgo -lTKGeomAlgo -lTKBRep -lTKGeomBase -lTKG3d -lTKG2d \
  -lTKMath -lTKernel
echo "ok: $OUT"
