# Scripts del PC y del entorno

[Inicio](../README.md) · [Flujo completo](../docs/flujo_de_trabajo.md)

## `test_lpdt_hw.py`: prueba lógica dentro de la FPGA

Necesita un bitstream `debug` ya cargado, sus `csr.csv`/`analyzer.csv` y
`litex_server` activo. **No sintetiza, no programa y no accede al panel.**
Escribe registros por UARTWishbone, captura con LiteScope, reconstruye los bytes
LPDT y verifica datos, estados y tiempos muestreados.

Desde la raíz, dentro de `pixi shell`:

```sh
python scripts/test_lpdt_hw.py --help
python scripts/test_lpdt_hw.py --output build/debug/captures/patron_01.vcd
```

El patrón actual tiene siete bytes; su destino predeterminado conserva el nombre
histórico `tres_bytes.vcd`. Elegir un destino explícito y nuevo: no sobrescribe.
`--dcs-sequence` prueba tres paquetes DCS cortos, calcula ECC en el PC y produce
capturas y resumen JSON; requiere especificar ambas esperas. Ejemplo y límites
en el [flujo de trabajo](../docs/flujo_de_trabajo.md#7-capturar-y-verificar-el-motor-en-fpga).

Los nombres LiteScope están fijados en `SIGNALS`: un cambio de elaboración
puede exigir compararlos con el CSV real y adaptar el script. Las comprobaciones
dependen de la codificación y tiempos del motor actual, no son un receptor general.

## `display_control.py`: cadena DSI integrada

Controla el target `gateware.targets.display` mediante su banco CSR y un
`litex_server` activo. Incluye estado, reset coordinado, configuración,
inicialización LPDT desde un JSON explícito, START y STOP al final de cuadro.
No programa hardware ni contiene una secuencia supuesta para el LCD.
[Mapa, formato JSON y límites](../dsi_display/README.md).
Para el bitstream físico LPDT, usar `--csr-csv build/display_board_lpdt/csr.csv`.
`check_display_board.py` contrasta pines y opciones con la tabla de continuidad;
`--implemented` verifica también el hash, la inhibición HS y el timing del
bitstream LPDT. [Procedimiento de placa](../docs/implementacion_fpga.md).

```sh
pixi run --locked python scripts/display_control.py --help
```

## `probe_fpgbc_firmware.py`: análisis estático del firmware original

Ensaya checksums, compresión y un conjunto acotado de hipótesis de cifrado;
escribe informes en `build/reverse_v1_4/probes/`. Requiere un Python con
`numpy` y `cryptography` (incluido `hazmat.decrepit`), dependencias opcionales
que no forman parte del entorno FPGA de Pixi.

```sh
python3 scripts/probe_fpgbc_firmware.py --input build/reverse_v1_4/original/update.bin
```

El binario se obtiene por separado. La procedencia, el SHA-256 y los límites
del análisis están en el [informe de firmware](../docs/analisis_firmware_v1_4.md).
El script no accede al hardware; los resultados actuales no recuperan
contenido descifrado verificado.

## `setup_env.sh`: preparación con efectos adicionales

La tarea `pixi run setup-env` ejecuta este script. Hace tres cosas:

1. Crea o reemplaza el enlace local al nombre de nextpnr esperado por LiteX.
2. Descarga y extrae un compilador RISC-V en `.toolchain/`, sin verificar checksum.
3. Usa `sudo` para escribir `/etc/udev/rules.d/70-ft232-fpga.rules` y recargar reglas.

udev gestiona dispositivos y permisos de acceso en Linux. La regla incluida
selecciona USB `0403:6001`; no necesariamente corresponde a todos los adaptadores.
No ejecutar como preparación automática ni como prueba inocua. El target actual
no necesita el compilador RISC-V. El manual explica cómo resolver únicamente el
nombre de nextpnr sin ejecutar las otras acciones. Este cambio documental no
modifica el comportamiento del script.
