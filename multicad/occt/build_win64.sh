#!/bin/sh
# Compila mcad_occt.dll (Win64) no Linux com MinGW-w64, ligando o OpenCascade
# estatico: uma DLL so, sem dependencias alem do Windows.
#
# OpenCascade 7.6.3 compilado com MinGW (estatico), por exemplo:
#   git clone --depth 1 --branch V7_6_3 https://github.com/Open-Cascade-SAS/OCCT.git src
#   cmake ../src -DCMAKE_TOOLCHAIN_FILE=mingw64.cmake -DBUILD_LIBRARY_TYPE=Static \
#     -DBUILD_MODULE_Visualization=OFF -DBUILD_MODULE_ApplicationFramework=OFF \
#     -DBUILD_MODULE_Draw=OFF -DBUILD_MODULE_DataExchange=OFF \
#     -DBUILD_ADDITIONAL_TOOLKITS="TKXSBase;TKSTEPBase;TKSTEPAttr;TKSTEP209;TKSTEP" \
#     -DUSE_FREETYPE=OFF -DUSE_TK=OFF -DUSE_TCL=OFF -DUSE_OPENGL=OFF -DINSTALL_DIR=$OCCT_WIN
#   make -j && make install
# (mingw64.cmake: CMAKE_SYSTEM_NAME Windows, compiladores x86_64-w64-mingw32-*-posix)
set -e
cd "$(dirname "$0")"
OCCT_WIN=${OCCT_WIN:-/home/claude/occt/win}
OUT=${1:-../../bin/mcad_occt.dll}
INC=$(dirname "$(find "$OCCT_WIN" -name Standard_Version.hxx | head -1)")
LIB=$(dirname "$(find "$OCCT_WIN" -name 'libTKernel.a' | head -1)")
TK="TKSTEP TKSTEP209 TKSTEPAttr TKSTEPBase TKXSBase TKOffset TKFillet TKBool TKBO TKPrim TKMesh \
TKShHealing TKTopAlgo TKGeomAlgo TKBRep TKGeomBase TKG3d TKG2d TKMath TKernel"
LIBS=""
for t in $TK; do LIBS="$LIBS $LIB/lib$t.a"; done
x86_64-w64-mingw32-g++-posix -std=gnu++17 -O2 -shared -DOCCT_STATIC_BUILD -DOCCT_NO_PLUGINS -DNo_Exception \
  -I"$INC" mcad_occt.cpp -o "$OUT" \
  -Wl,--start-group $LIBS -Wl,--end-group \
  -static -static-libgcc -static-libstdc++ -lws2_32 -ladvapi32 -luser32 -lpsapi -lwinmm
x86_64-w64-mingw32-strip "$OUT"
echo "ok: $OUT ($(du -h "$OUT" | cut -f1))"
