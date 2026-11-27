# FPGBC: barras y blanco con encuadre experimental

[Diagrama editable del TOP](fpgbc_white.drawio). `fpgbc_white` exporta la
cadena de la sonda supervisada para `GW2AR-LV18EQ144PC8/I7`. La fuente puede
entregar barras fijas (predeterminado, `--bars`) o blanco (`--white`); ambas conservan el
handshake y el índice de palabra. `MIPI_TX` conserva SoT, cabecera fija y CRC
calculado sobre los píxeles. No hay framebuffer. El encuadre aprobado usa
`FRAME_TIMING` dentro de `LINK_FSM + TIMER` y el prefijo/sincronismos de
`HS_PACKER`; no añade puertos externos a `MIPI_TX`.

[Diseño de cuadro](fpgbc_frame.drawio) · [Flancos y presupuesto](fpgbc_frame.md)
· [Revisión de E/S previa a carga](revision_io_frame.md).

El perfil de la [sonda](../../phy/README.md) se conserva: `CLK_REF=40 MHz`,
`CLK_BYTE=55 MHz`, `CLK_HS=220 MHz`, DDR a 440 Mbit/s por carril,
`LP_DIV=6`, `T_CLK_START=27`, `T_LPX/PREP/ZERO/TRAIL=4/3/7/4` y
`C_LINE=1168`, `FRAME_MODE=1`. El reloj reenviado no es continuo. La variante directa es
la predeterminada; `--delay` conserva la alternativa de 32 taps para
comparación offline.

## Arranque y cortes

| Condición | Enlace | EN/PWM |
|---|---|---|
| Arranque / pulsador activo | Aserción asíncrona, dos ↓ de sincronización al liberar el botón y 16 ↓ adicionales de `CLK_REF` en reset. | `0/0`. |
| Calificación por el supervisor | El watchdog observa `CLK_REF` y `CLK_BYTE`. `RESET` va solo a la rPLL; `RST_BYTE` se libera después del par ↑/↓ de calificación. | `0/0`. |
| LP disponible | INIT empieza en dir. 0; 18 paquetes y 18 WAIT. El último dura 385 000 ciclos de byte (7 ms) antes de END. | `0/0` hasta después de END. |
| `INIT_DONE` | Se ofrece una línea completa; `READY` arbitra el enlace entre transacciones. El cuadro empieza por el periodo 0 VSS. | Permanece encendido entre ráfagas. |
| Pérdida de referencia, byte, lock o reset | `RST_BYTE` y `ISO` aíslan los doce pads aun sin flancos. Al recuperar reloj y lock, se repite la ROM desde 0. | Corte asíncrono y rearme solo tras el nuevo END. |
| Fallo de protocolo interno del PHY | `ISO` mantiene los pads aislados hasta reset. | `ISO` apaga ambas salidas. |

El control de placa registra `INIT_DONE` en ↓ de byte y lo sincroniza con
dos FF en ↑ de referencia. `RST_SUP | RST_BYTE | ISO` corta directamente
las dos salidas y aserta el reset local; dos ↓ de referencia sincronizan
la liberación. Los registros EN/PWM y el contador de 16 bits se actualizan
en ↓, parten de cero y se borran en reset. EN precede al PWM un ciclo; el
contador recorre 40 000 ciclos con el PWM alto durante 20 000 (1 kHz, 50 %).
`READY` no participa en ese camino.

Pines FPGA: reloj 11; botón 120, activo bajo con pull-up; EN 46 y PWM 47.
El botón usa **LVCMOS25** en este target: comparte el banco 1 con las
salidas HS y sigue la sonda y el adaptador mixto. Es el reset de la FPGA.
La plataforma del target LP conserva LVCMOS33 en ese pin. Verificar en
placa el nivel de la entrada y su pull-up. Los doce pines DSI y su red
externa se describen en [hardware](../../docs/hardware.md). Para EN/PWM,
LVCMOS33 y activo alto son candidatos: quedan por confirmar VCCIO5,
umbrales, polaridades y estado mientras se configura la FPGA.

La documentación da por estable la alimentación del LCD y no identifica
quién libera su reset físico; `PANEL_RST` no es accesible. El TOP supone
que el LCD ya está listo antes del primer comando. En placa se debe
confirmar esa condición y la aceptación de una reinicialización sin reset
físico tras el retorno del reloj.

## Reproducción

Desde la raíz:

```sh
pixi run --locked make -C gateware -j2 test-final-wait
pixi run --locked make -C gateware -j2 test
pixi run --locked make -C gateware audit
pixi run --locked make -C gateware fs
pixi run --locked make -C gateware fs VARIANT=white
pixi run --locked test-gateware
pixi run --locked python -m unittest gateware.tests.test_frame_pack -v
```

Ambas pruebas usan el TOP exportado y los modelos de primitivas. `test`
ejecuta las esperas reales completas. `test-final-wait` abrevia los ticks
de las 17 esperas LP intermedias en el banco y conserva intactos los
385 000 ciclos (7 ms) de la espera final. Ambas reconstruyen los paquetes
LP y comprueban **dos cuadros completos** desde los pads para cada patrón:
743 periodos, un SoT `B8/B8` por ráfaga, sincronismos y 720 paquetes RGB
por cuadro con cabecera `3E 70 08 13`, 1080 lecturas por línea, 2160 bytes
de píxeles y CRC `25/34` en D0/D1 para blanco (`EE/7E` para barras).
El Blanking activo contiene seis ceros y CRC `70/08`. No hay lecturas
durante los 23 periodos de sincronismo ni durante los prefijos.
Comprueba PWM y, en blanco, corta `CLK_REF` y `CLK_BYTE` por separado con `LOCK_RAW`
alto; en ambos casos comprueba aislamiento, backlight apagado y
reinicialización completa. `sim` genera ondas y `wave` abre el último
volcado.

`audit` sintetiza y enruta el TOP real con ROM en lógica (`-nobram`).
Comprueba pines, rutas dedicadas, serializadores locales y OEN; reaplica
la auditoría de los doce pads DSI y bancos 0/1 del PR #19 al JSON final
con el adaptador mixto. Añade los dos OBUF de backlight y BANK5 a la
auditoría de fusibles. Los informes nuevos quedan en
`build/fpgbc_frame_1168/{bars,white}/`, con `route.log`, `timing.json` y
`fuse_review.json`; no se reutiliza `build/fpgbc_white/`.

`fs` ejecuta el mismo cierre, serializa **ese mismo mapa auditado** y
relee el bitmap completo del archivo para compararlo bit a bit.
Genera `fpgbc_white.fs` y `fpgbc_white.fs.review.json` dentro de la
variante elegida; el nombre del TOP se conserva por compatibilidad.
Rechaza sobrescribir un `.fs` o su revisión anterior. Para una
reconstrucción nueva, indicar otro directorio, por ejemplo:

```sh
pixi run --locked make -C gateware fs \
  BUILD="$PWD/build/fpgbc_frame_nueva_revision" VARIANT=bars
```

La CLI del target solo exporta fuentes/scripts; usar el objetivo `fs`
para el empaquetado mixto auditado, no el `gowin_pack` directo ni el
wrapper LP. `audit` no escribe bitstream; `fs` no programa hardware.

## Pendiente para el LCD

El TOP repite el cuadro de ensayo aprobado: 3 VSS → 8 HSS → 720 activos
→ 12 HSS, sin VSE ni EoTp. Las líneas activas emiten HSS → Blanking de
seis ceros → RGB, dentro de la misma ráfaga. Los 743 periodos medidos a
21,20 µs (~63,486 Hz) no prueban esa receta. La
[extracción de captura](../../../digital_UN/basic_circuits/test_peripherals/rtl/cores/MIPI_LCD/Docs/extraccion_025/README.md)
no identifica VSS/VSE, HSS/HSE, porches, blanking, EoTp ni el modo de
reloj original. La receta es una hipótesis, no una medida. A 55 MHz,
1168 ciclos producen 21,23636 µs por línea y ~63,3769 Hz; la desviación
aprobada es +0,1715 % en periodo para conservar el cierre físico.
La prueba en el LCD todavía depende de
confirmar el arranque del panel, niveles y polaridades, y medir fase,
setup/hold y márgenes eléctricos del PHY.
