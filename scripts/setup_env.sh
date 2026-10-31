#!/bin/bash

BIN_DIR="$CONDA_PREFIX/bin"
ln -sf "$BIN_DIR/yowasp-nextpnr-himbaechel-gowin" "$BIN_DIR/nextpnr-himbaechel-gowin"

# Definir versión y ubicación de instalación local (carpeta oculta en el proyecto)
TOOLCHAIN_VERSION="15.2.0-1"
TOOLCHAIN_NAME="xpack-riscv-none-elf-gcc-${TOOLCHAIN_VERSION}"
TOOLCHAIN_DIR="$PIXI_PROJECT_ROOT/.toolchain/"
TOOLCHAIN_BIN="$TOOLCHAIN_DIR/$TOOLCHAIN_NAME/bin/riscv-none-elf-gcc"
URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${TOOLCHAIN_VERSION}/${TOOLCHAIN_NAME}-linux-x64.tar.gz"

# 1. Verificar si el binario ya existe y es ejecutable
if [ ! -x "$TOOLCHAIN_BIN" ]; then
    echo "⚙️  Toolchain RISC-V no encontrado. Descargando..."
    mkdir -p "$TOOLCHAIN_DIR"
    
    if curl -L "$URL" | tar -xz -C "$TOOLCHAIN_DIR"; then
        echo "✅ Toolchain instalado en $TOOLCHAIN_DIR/$TOOLCHAIN_NAME"
    else
        echo "❌ Error al descargar o extraer el toolchain."
        exit 1 
    fi
else 
    echo "✅ Toolchain instalado en $TOOLCHAIN_DIR"
fi


echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6001", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/70-ft232-fpga.rules
sudo udevadm control --reload-rules