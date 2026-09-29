# MultiSuite 0.1.0

| Arquivo | Plataforma | Uso |
|---|---|---|
| `MultiSuite-Setup-0.1.0-win64.exe` | Windows 10/11 x64 | Instalador (menu Iniciar, atalho opcional, associa `.msuite`) |
| `multisuite_0.1.0_amd64.deb` | Debian/Ubuntu x86_64 | `sudo apt install ./multisuite_0.1.0_amd64.deb` |
| `multisuite_0.1.0_arm64.deb` | ARM 64 bits (Raspberry Pi 3/4/5 com sistema 64 bits, outras placas ARM64) | `sudo apt install ./multisuite_0.1.0_arm64.deb` |
| `multisuite_0.1.0_armhf.deb` | ARM 32 bits hard-float, ARMv7+ (Raspberry Pi 2/3/4/5 com sistema 32 bits) | `sudo apt install ./multisuite_0.1.0_armhf.deb` |
| `MultiSuite-0.1.0-linux-x86_64.tar.xz` | Linux x86_64 | Extrair e executar `./multisuite`, sem instalar |
| `MultiSuite-0.1.0-linux-aarch64.tar.xz` | Linux ARM 64 bits | Idem |
| `MultiSuite-0.1.0-linux-armhf.tar.xz` | Linux ARM 32 bits | Idem |

Inclui MultiSuite, MultiCAD, MultiPCB, MultiAssembly, MultiPhysics, MultiCAM,
MultiSlicer, LaserPCB, LaserArt, MultiCNC e Central de Testes.

Requisitos Linux: GTK2 (instalado automaticamente pelo `.deb`) e glibc 2.34 ou mais nova
(Raspberry Pi OS Bookworm, Debian 12, Ubuntu 22.04+). Raspberry Pi OS Bullseye e
Raspberry Pi Zero/1 (ARMv6) nao sao suportados por estes pacotes.

Os pacotes ARM foram compilados de forma cruzada a partir de x86_64; os testes
automatizados passaram no emulador (qemu), mas a interface grafica ainda nao foi
aberta em hardware ARM real.

Gerado a partir do commit 45f69dd (Windows e Linux x86_64) e dos scripts em
`installer/`. Conferir integridade com `sha256sum -c SHA256SUMS`.
Os executaveis Windows nao sao assinados digitalmente; o SmartScreen pode exibir aviso na primeira execucao.
