#!/usr/bin/env bash
# ==============================================================================
# MultiSuite Installer v0.01 (Build 001) - Linux
# Suporta instalacao completa ou selecao individual de ferramentas.
# ==============================================================================
set -e

VERSION="0.01"
BUILD="001"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define diretorios de instalacao
if [ "$(id -u)" -eq 0 ]; then
    INSTALL_DIR="/opt/multisuite"
    BIN_DIR="/usr/local/bin"
    DESKTOP_DIR="/usr/share/applications"
    MIME_DIR="/usr/share/mime/packages"
else
    INSTALL_DIR="${HOME}/.local/share/multisuite"
    BIN_DIR="${HOME}/.local/bin"
    DESKTOP_DIR="${HOME}/.local/share/applications"
    MIME_DIR="${HOME}/.local/share/mime/packages"
fi

mkdir -p "${INSTALL_DIR}" "${BIN_DIR}" "${DESKTOP_DIR}" "${MIME_DIR}"

declare -A TOOL_NAMES=(
    ["multisuite"]="MultiSuite - Central de Engenharia Integrada"
    ["multicnc"]="MultiCNC - Controle de Maquinas CNC (GRBL/Marlin)"
    ["multicad"]="MultiCAD - Modelagem e Desenho CAD 2D/3D"
    ["multipcb"]="MultiPCB - Design e Roteamento de Circuitos Impressos"
    ["multiassembly"]="MultiAssembly - Montagem Eletromecanica"
    ["multiphysics"]="MultiPhysics - Simulacao Fisica, Termica e Dinamica"
    ["multicam"]="MultiCAM - CAM e Simulacao CNC Router"
    ["multislicer"]="MultiSlicer - Fatiador para Impressao 3D"
    ["laserpcb"]="LaserPCB - Preparacao e Gravacao de PCB a Laser"
    ["laserart"]="LaserArt - Vetorizacao e Gravacao de Imagens a Laser"
    ["multisuite_test_center"]="Central de Testes do MultiSuite"
)

ALL_TOOLS=(
    "multisuite"
    "multicnc"
    "multicad"
    "multipcb"
    "multiassembly"
    "multiphysics"
    "multicam"
    "multislicer"
    "laserpcb"
    "laserart"
    "multisuite_test_center"
)

show_header() {
    echo "======================================================"
    echo "  MultiSuite Installer v${VERSION} (Build ${BUILD}) - Linux"
    echo "======================================================"
    echo "Destino da instalacao: ${INSTALL_DIR}"
    echo "Links de executavel:    ${BIN_DIR}"
    echo "------------------------------------------------------"
}

SELECTED_TOOLS=()

# Tratamento de argumentos por linha de comando
if [ "$1" == "--all" ] || [ "$1" == "-a" ]; then
    SELECTED_TOOLS=("${ALL_TOOLS[@]}")
elif [[ "$1" == --tools=* ]]; then
    IFS=',' read -r -a SELECTED_TOOLS <<< "${1#*=}"
else
    show_header
    echo "Selecione o modo de instalacao:"
    echo "  1) Instalar tudo (todas as 11 ferramentas)"
    echo "  2) Escolher as ferramentas que deseja instalar"
    echo "  3) Cancelar"
    echo ""
    read -rp "Opcao [1-3] (Padrao: 1): " OPTION
    OPTION=${OPTION:-1}

    if [ "$OPTION" -eq 1 ]; then
        SELECTED_TOOLS=("${ALL_TOOLS[@]}")
    elif [ "$OPTION" -eq 2 ]; then
        echo ""
        echo "Ferramentas disponiveis:"
        idx=1
        for tool in "${ALL_TOOLS[@]}"; do
            echo "  $idx) ${TOOL_NAMES[$tool]}"
            ((idx++))
        done
        echo ""
        read -rp "Digite os numeros das ferramentas separados por espaco (ex: 1 2 7) ou 'todas': " SELECTION
        if [ "$SELECTION" == "todas" ] || [ "$SELECTION" == "all" ]; then
            SELECTED_TOOLS=("${ALL_TOOLS[@]}")
        else
            for num in $SELECTION; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#ALL_TOOLS[@]}" ]; then
                    SELECTED_TOOLS+=("${ALL_TOOLS[$((num-1))]}")
                fi
            done
        fi
    else
        echo "Instalacao cancelada."
        exit 0
    fi
fi

if [ "${#SELECTED_TOOLS[@]}" -eq 0 ]; then
    echo "Nenhuma ferramenta selecionada. Cancelando."
    exit 1
fi

echo ""
echo "Instalando as seguintes ferramentas:"
for tool in "${SELECTED_TOOLS[@]}"; do
    echo " - ${TOOL_NAMES[$tool]:-$tool}"
done
echo ""

# Copia arquivos docs se existirem
if [ -d "${SCRIPT_DIR}/docs" ]; then
    cp -r "${SCRIPT_DIR}/docs" "${INSTALL_DIR}/"
fi

# Instala cada ferramenta
for tool in "${SELECTED_TOOLS[@]}"; do
    src_bin=""
    if [ -f "${SCRIPT_DIR}/${tool}" ]; then
        src_bin="${SCRIPT_DIR}/${tool}"
    elif [ -f "${SCRIPT_DIR}/bin/${tool}" ]; then
        src_bin="${SCRIPT_DIR}/bin/${tool}"
    fi

    if [ -n "$src_bin" ]; then
        install -m 0755 "$src_bin" "${INSTALL_DIR}/${tool}"
        ln -sf "${INSTALL_DIR}/${tool}" "${BIN_DIR}/${tool}"

        cat > "${DESKTOP_DIR}/${tool}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${TOOL_NAMES[$tool]:-$tool}
Comment=Ferramenta do ecossistema MultiSuite
Exec=${BIN_DIR}/${tool} %f
Terminal=false
Categories=Engineering;Development;Electronics;
EOF
        echo "  [OK] ${tool} instalado"
    else
        echo "  [AVISO] Binario '${tool}' nao encontrado no pacote"
    fi
done

# Associacao MIME
cat > "${MIME_DIR}/multisuite.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-multisuite-project">
    <comment>Projeto MultiSuite</comment>
    <glob pattern="*.msuite"/>
  </mime-type>
</mime-info>
EOF

command -v update-mime-database >/dev/null 2>&1 && update-mime-database "${MIME_DIR}/.." || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "${DESKTOP_DIR}" || true

echo ""
echo "======================================================"
echo "Instalacao concluida com sucesso!"
echo "As ferramentas selecionadas estao disponiveis em:"
echo "  ${BIN_DIR}"
echo "======================================================"