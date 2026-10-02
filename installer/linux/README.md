# Pacotes Linux MultiSuite

## Arquiteturas e compatibilidade

- **amd64**: PC x86_64.
- **arm64**: sistema ARM de 64 bits, incluindo Raspberry Pi compatível com sistema 64 bits.
- **armhf**: ABI ARM hard-float; a distribuição usa ARMv7/VFPv3-D16. Pi Zero original e Pi 1 (ARMv6) não são alvos deste pacote.

Os arquivos históricos de `releases/0.1.0` exigem glibc 2.34 ou superior. Cada novo build calcula a versão mínima a partir dos símbolos ELF e grava uma dependência versionada de `libc6` no DEB. Não deduza compatibilidade apenas pelo nome da arquitetura; confira a dependência e o sistema do alvo.

## Instalar e verificar

```bash
sha256sum -c SHA256SUMS
sudo apt install ./multisuite_0.1.1-dev_amd64.deb
```

O tar pode ser extraído e executado por `./multisuite`. Preserve a estrutura completa: os aplicativos ficam lado a lado e os testes ficam em `tests/` e `<módulo>/tests/`. GTK2 e as bibliotecas do sistema são necessárias.

`build-manifest.json` registra versão, commit, árvore Git, compiladores, alvo e SHA256 de cada arquivo incluído. `qa-tests.json` registra os testes executados; `not-run` indica compilação sem execução. A Central executa os testes em pastas temporárias e salva relatórios na configuração do usuário.

## Gerar

Requisitos: Git, Python 3.9+, Free Pascal/FCL, Lazarus/LCL GTK2, binutils e dpkg-dev.

```bash
sudo apt install git python3 lazarus lcl-gtk2 fp-units-misc binutils dpkg-dev
VERSION=0.1.1-dev installer/linux/build_release.sh
```

A árvore Git deve estar limpa. O padrão é `0.1.1-dev`; não sobrescreve os arquivos históricos de `releases/0.1.0`. Um build local em desenvolvimento pode usar `RELEASE_REQUIRE_CLEAN=0`; seu manifesto registra `source_dirty=true` e não deve ser publicado como release definitiva.

O script compila aplicativos, executa testes nativos, inclui os testes, verifica arquiteturas, gera DEB/tar e cria/confere `SHA256SUMS`. A saída fica em `dist/linux-<arch>/`.

## CI

`Linux Packages` gera amd64 e arm64 em runners nativos. armhf usa Debian Bookworm ARMv7 dentro de QEMU; testes são executados nesse userspace. Emulação não valida uma placa física, dispositivo serial, display ou periféricos.

## Build cruzado

`build_release.sh arm64` / `armhf` também aceitam alvo diferente do host. Isso exige FPC cruzado, RTL/FCL/LCL e bibliotecas GTK2 reais do alvo, além de binutils do alvo. armhf usa `-CpARMV7A -CfVFPV3_D16 -CaEABIHF` no toolchain.

Em build cruzado, testes são compilados com `-P<cpu> -Tlinux` e registrados como `not-run`. Não confunda esse resultado com os testes nativos ou emulados do CI. Não use stubs de bibliotecas como evidência de runtime; valide o pacote no sistema alvo antes de uma release.
