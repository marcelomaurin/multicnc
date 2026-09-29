# Pacote Linux MultiSuite

Arquiteturas: **amd64** (PC x86_64), **arm64** (Raspberry Pi 3/4/5 com sistema 64 bits, placas ARM64) e **armhf** (Raspberry Pi OS 32 bits, inclusive Pi Zero/1).

Requer glibc 2.34 ou mais nova: Raspberry Pi OS Bookworm, Debian 12, Ubuntu 22.04+ ou equivalente. Raspberry Pi OS Bullseye (glibc 2.31) nao e suportado.

## Instalar
```
sudo apt install ./multisuite_0.1.0_arm64.deb     # ou _amd64 / _armhf
```
Ou, sem instalar, extrair o `.tar.xz` e executar `./multisuite` (manter todos os executaveis na mesma pasta: o MultiSuite abre as ferramentas a partir da pasta do proprio executavel).

## Gerar os pacotes
```
installer/linux/build_release.sh            # arquitetura da propria maquina
installer/linux/build_release.sh arm64      # cruzado a partir de x86_64
installer/linux/build_release.sh armhf
```
Saida em `dist/linux-<arch>/`: `multisuite_<versao>_<arch>.deb` e `MultiSuite-<versao>-linux-<cpu>.tar.xz`. A versao pode ser definida com `VERSION=0.2.0`.

### Build nativo (inclusive no proprio Raspberry Pi)
```
sudo apt install lazarus lcl-gtk2 dpkg-dev
installer/linux/build_release.sh
```

### Build cruzado x86_64 -> ARM
1. Ferramentas do alvo: `sudo apt install binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu libc6-dev-arm64-cross` (armhf: troque por `arm-linux-gnueabihf` / `armhf-cross`).
2. Free Pascal cruzado 3.2.2 a partir do codigo-fonte:
   - arm64: `make crossall crossinstall OS_TARGET=linux CPU_TARGET=aarch64 BINUTILSPREFIX=aarch64-linux-gnu- INSTALL_PREFIX=/usr`
   - armhf: `make crossall crossinstall OS_TARGET=linux CPU_TARGET=arm BINUTILSPREFIX=arm-linux-gnueabihf- OPT="-dFPC_ARMHF" CROSSOPT="-CpARMV6 -CfVFPV2 -CaEABIHF" INSTALL_PREFIX=/usr`
   - No FPC 3.2.2 original, `rtl/linux/aarch64/cprt0.as` referencia `__libc_csu_init/__libc_csu_fini`, removidos na glibc 2.34. Troque as quatro linhas que carregam esses simbolos em `x3`/`x4` por `mov x3,#0` e `mov x4,#0` antes de compilar (os pacotes FPC do Debian/Ubuntu ja trazem essa correcao para o proprio host).
3. Bibliotecas GTK2 do alvo para o link. Se as bibliotecas ARM nao estiverem disponiveis (sem acesso ao repositorio ARM), gere stubs de link a partir das bibliotecas do host:
   ```
   python3 installer/linux/gen_stubs.py aarch64-linux-gnu-gcc /opt/stubs/aarch64 \
     libgtk-x11-2.0.so.0 libgdk-x11-2.0.so.0 libgdk_pixbuf-2.0.so.0 libglib-2.0.so.0 \
     libgobject-2.0.so.0 libgmodule-2.0.so.0 libgthread-2.0.so.0 libpango-1.0.so.0 \
     libcairo.so.2 libatk-1.0.so.0 libX11.so.6
   ```
   Os stubs tem o mesmo SONAME e os mesmos simbolos; servem so para o link e nao sao distribuidos. No alvo, o sistema carrega o GTK2 real.
4. No `/etc/fpc.cfg`:
   ```
   #ifdef cpuaarch64
   -XPaarch64-linux-gnu-
   -Fl/usr/aarch64-linux-gnu/lib
   -Fl/opt/stubs/aarch64
   #endif
   ```
   (armhf: `#ifdef cpuarm` com `-XParm-linux-gnueabihf-`, `-Fl/usr/arm-linux-gnueabihf/lib`, `-Fl/opt/stubs/armhf`, `-CpARMV6 -CfVFPV2 -CaEABIHF`.)
