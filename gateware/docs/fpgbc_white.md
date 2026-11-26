# FPGBC: primer blanco offline

[Diagrama editable del TOP](fpgbc_white.drawio). `fpgbc_white` exporta la
cadena de la sonda supervisada para `GW2AR-LV18EQ144PC8/I7`. La fuente puede
entregar blanco fijo (`FFFF`) o barras (`--bars`); ambas conservan el
handshake y el índice de palabra. `MIPI_TX` conserva SoT, cabecera fija y CRC
calculado sobre los píxeles. No hay framebuffer ni secuencia vertical.

El perfil de la [sonda](../../phy/README.md) se conserva: `CLK_REF=40 MHz`,
`CLK_BYTE=55 MHz`, `CLK_HS=220 MHz`, DDR a 440 Mbit/s por carril,
`LP_DIV=6`, `T_CLK_START=27`, `T_LPX/PREP/ZERO/TRAIL=4/3/7/4` y
`C_LINE=1166`. El reloj reenviado no es continuo. La variante directa es
la predeterminada; `--delay` conserva la alternativa de 32 taps para
comparación offline.

## Arranque y cortes

| Condición | Enlace | EN/PWM |
|---|---|---|
| Arranque / pulsador activo | Aserción asíncrona, dos ↓ de sincronización al liberar el botón y 16 ↓ adicionales de `CLK_REF` en reset. | `0/0`. |
| Calificación por el supervisor | El watchdog observa `CLK_REF` y `CLK_BYTE`. `RESET` va solo a la rPLL; `RST_BYTE` se libera después del par ↑/↓ de calificación. | `0/0`. |
| LP disponible | INIT empieza en dir. 0; 18 paquetes y 18 WAIT. El último dura 385 000 ciclos de byte (7 ms) antes de END. | `0/0` hasta después de END. |
| `INIT_DONE` | Se ofrece una línea completa; `READY` arbitra el enlace entre transacciones. | Permanece encendido entre ráfagas. |
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
pixi run --locked make -C gateware -j2 test
pixi run --locked make -C gateware audit
pixi run --locked make -C gateware audit VARIANT=delay
pixi run --locked test-gateware
```

`test` usa el TOP exportado y los modelos de primitivas, con las esperas
reales de la ROM. Reconstruye los paquetes LP y comprueba dos líneas
desde los pads: SoT `B8/B8`, cabecera `3E 70 08 13`, 1080 lecturas,
2160 bytes `FF` y CRC `25/34` en D0/D1. Las barras dan `EE/7E`.
Comprueba PWM y corta `CLK_REF` y `CLK_BYTE` por separado con `LOCK_RAW`
alto; en ambos casos comprueba aislamiento, backlight apagado y
reinicialización completa. `sim` genera ondas y `wave` abre el último
volcado.

`audit` sintetiza y enruta el TOP real con ROM en lógica (`-nobram`).
Comprueba pines, rutas dedicadas, serializadores locales y OEN; reaplica
la auditoría de los doce pads DSI y bancos 0/1 del PR #19 al JSON final
con el adaptador mixto. Los informes quedan en
`build/fpgbc_white/{direct,delay}/`, con `route.log`, `timing.json` y
`fuse_review.json`. El flujo termina en el mapa de fusibles en memoria.

## Pendiente para el LCD

El TOP repite líneas mientras hay enlace. Como perfil de investigación
para un cuadro, los 743 periodos medidos a 21,20 µs (~63,486 Hz) respaldan
ensayar 720 periodos RGB888 y 23 periodos de intervalo vertical. La
[extracción de captura](../../../digital_UN/basic_circuits/test_peripherals/rtl/cores/MIPI_LCD/Docs/extraccion_025/README.md)
no identifica VSS/VSE, HSS/HSE, porches, blanking, EoTp ni el modo de
reloj original. La receta de cuadro y cualquier cambio de protocolo
requieren aprobación separada. La prueba en el LCD también depende de
confirmar el arranque del panel, niveles y polaridades, y medir fase,
setup/hold y márgenes eléctricos del PHY.
