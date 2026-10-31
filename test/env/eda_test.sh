#!/usr/bin/env bash
set -uo pipefail

BUILD_DIR="build_test"
LOG_FILE="eda_test.log"
BITSTREAM_FILE="${BUILD_DIR}/gateware/sipeed_tang_nano_9k.fs"

echo "=========================================================="
echo " Ejecutando prueba del toolchain EDA                      "
echo "=========================================================="

rm -rf "$BUILD_DIR" "$LOG_FILE"

python -m litex_boards.targets.sipeed_tang_nano_9k \
    --toolchain apicula \
    --output-dir "$BUILD_DIR" \
    --build-log "./${LOG_FILE}" \
    --build \
    --load

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================================="
echo " Evaluando resultado de la prueba..."
echo "=========================================================="

if [ -f "$BITSTREAM_FILE" ] && grep -qi "openFPGALoader" "$LOG_FILE"; then
    echo -e "\033[0;32m[TEST EXITOSO]\033[0m"
    echo "- Síntesis (Yosys): OK"
    echo "- Place & Route (nextpnr-himbaechel-gowin): OK"
    echo "- Empaquetado (Apycula): OK -> $BITSTREAM_FILE generado."
    echo "- Invocación del programador: OK (openFPGALoader intentó cargar el bitstream)."
    echo ""
    echo "El entorno EDA y LiteX están correctamente integrados."
    rm -rf "$BUILD_DIR" "$LOG_FILE"
    exit 0
else
    echo -e "\033[0;31m[TEST FALLIDO]\033[0m"
    echo "El flujo falló antes de llegar a la etapa de programación."
    echo "Revisa el log detallado en: $LOG_FILE"
    rm -rf "$BUILD_DIR"
    exit 1
fi