# Pacote Linux MultiSuite

## Requisitos de build (Debian/Ubuntu)
```
sudo apt install lazarus lcl-gtk2 dpkg-dev
```

## Gerar pacotes
```
installer/linux/build_release.sh
```

Compila as onze aplicacoes com o widgetset GTK2, remove simbolos dos executaveis e gera em `dist/linux/`:

- `multisuite_<versao>_amd64.deb` — instala em `/opt/multisuite`, cria comandos em `/usr/bin`, atalhos no menu e associa `.msuite` ao MultiSuite.
- `MultiSuite-<versao>-linux-x86_64.tar.xz` — mesmos executaveis, para rodar sem instalar (manter todos na mesma pasta: o MultiSuite abre as ferramentas a partir da pasta do proprio executavel).

A versao pode ser definida com `VERSION=0.2.0 installer/linux/build_release.sh`.

## Instalar
```
sudo apt install ./multisuite_0.1.0_amd64.deb
```
