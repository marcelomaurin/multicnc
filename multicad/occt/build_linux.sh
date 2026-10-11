#!/bin/sh
# Compila libmcad_occt.so (Linux) com o OpenCascade do sistema (apt: libocct-*-dev).
set -e
cd "$(dirname "$0")"
OUT=${1:-../../bin/libmcad_occt.so}
g++ -std=gnu++17 -O2 -fPIC -shared -fvisibility=hidden -I/usr/include/opencascade mcad_occt.cpp -o "$OUT" \
  -lTKSTEP -lTKSTEP209 -lTKSTEPAttr -lTKSTEPBase -lTKXSBase -lTKOffset -lTKFillet -lTKBool -lTKBO \
  -lTKPrim -lTKMesh -lTKShHealing -lTKTopAlgo -lTKGeomAlgo -lTKBRep -lTKGeomBase -lTKG3d -lTKG2d \
  -lTKMath -lTKernel
echo "ok: $OUT"
