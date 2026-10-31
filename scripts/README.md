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
