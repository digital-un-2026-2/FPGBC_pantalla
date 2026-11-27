# Validación offline del cuadro — 2026-11-26

RTL e integración: commit `197e887`, sobre `main` `ee0593e`.
PR de integración separado del componente FRAME_TIMING (#22).
No se carga la FPGA ni se escribe flash.

## Artefactos nuevos y enrutado

Directorio definitivo: `build/fpgbc_frame_1168/`, separado de
`build/fpgbc_white/` y de los ensayos intermedios `build/fpgbc_frame/`.
No se reutilizan bitstreams viejos. Los productos no se versionan.

| Patrón | Archivo | SHA-256 |
|---|---|---|
| Barras | `bars/fpgbc_white.fs` | `aded5b0a5665cefcb234c7c01be9fce80b6029edff7009f222934019b9ea028b` |
| Blanco | `white/fpgbc_white.fs` | `99ad5fc0b8b73979965055ade3c1fa8991fa4b97a509629d46190b01702abf18` |

Ambos tienen 4 618 782 bytes. Cada directorio incluye JSON enrutado,
`route.log`, `timing.json`, `.fs.review.json` y revisión de fusibles.
`source_manifest.json` en la raíz de productos enlaza hashes de fuentes
activas, ROM y artefactos. El nombre histórico `fpgbc_white` del TOP no
significa que el archivo de `bars/` emita blanco.

| Patrón | Byte: frecuencia estimada máxima / objetivo | Referencia | Watchdog |
|---|---|---|---|
| Barras | 81,06 / 55 MHz | 73,10 / 40 MHz | 95,88 / 31 MHz |
| Blanco | 83,31 / 55 MHz | 71,26 / 40 MHz | 92,94 / 31 MHz |

Resultados del estimador de nextpnr, no frecuencias medidas en placa.
Las rutas de CLK_HS/110 MHz no tienen caminos interiores reportados:
esta tabla no valida por sí sola fase ni setup/hold de pads.
La auditoría confirma rutas dedicadas GCLK/HCLK/IOLOGIC, serializadores
locales, OEN dinámicos dominados por ISO, doce pads DSI, OBUF de
backlight y fusibles de BANK0=1,2 V, BANK1=2,5 V y BANK5=3,3 V.
Son configuraciones seleccionadas, **no medidas eléctricas**.

En ambos `.fs.review.json`:

```text
errors = []
bitstream_written = true
serialized_bitmap_roundtrip = true
hardware_accessed = false
electrical_validation = NOT_MEASURED
```

El adaptador mixto está limitado por versión/hash a Apicula 0.32.
Se serializa el mismo mapa auditado, no una segunda ejecución de
place/pack. Se relee y compara todo el bitmap antes de publicar el
archivo; se rechaza sobrescribir el `.fs` o su revisión.

## Comandos reproducibles

Desde la raíz:

```sh
pixi run --locked make -C gateware -j2 test
pixi run --locked make -C gateware fs VARIANT=bars
pixi run --locked make -C gateware fs VARIANT=white
```

Los dos últimos ya se ejecutaron para los artefactos anteriores. Para
repetir sin sobrescribirlos, usar otro BUILD:

```sh
pixi run --locked make -C gateware fs VARIANT=bars \
  BUILD="$PWD/build/fpgbc_frame_repeticion"
```

## Simulación y regresiones

La prueba abreviada previa reconstruyó dos cuadros desde pads para
ambos patrones, con 720 RGB por cuadro y CRC EE/7E y 25/34; preservó
los 7 ms finales. Su escenario de fallos reveló una suposición del
banco: exigir PWM alto justo al abortar una ráfaga. Se corrigió a
exigir EN alto; la prueba independiente de PWM mantiene periodo/duty
de 1 kHz/50 %. No se cambió el circuito de backlight para acomodarla.

**Prueba final con todas las esperas LP completas: en ejecución.**
El resultado definitivo se registrará aquí al terminar; no confundir
la reconstrucción abreviada previa con ese cierre.
El log definitivo es `build/fpgbc_frame_1168/test_full.log`.

Regresiones ya completadas:

- `pixi run --locked test`, `test-init`, `test-phy`: PASS de las tres
  suites LP heredadas, sin modificar su RTL.
- `make -C mipi_tx test`: PASS, ambos perfiles del modo anterior.
- `make -C mipi_tx/hs_packer test`: PASS del datapath RGB original.
- `make -C mipi_tx/link_fsm test`: PASS de admisión, prioridad LP,
  drenaje/trail, periodo y reset del modo anterior.
- `make -C video_source test`: PASS, ambos perfiles.
- `make -C mipi_tx/frame_timing test`: PASS, dos perfiles y reset.
- 30 pruebas Python (`test_frame_pack`, `test_lp_target`,
  `test_review_io`, `test_review_fuses`): PASS. Incluyen rechazo de
  bitmap alterado, forma distinta, BSRAM y archivos preexistentes.
- Siete pruebas de capturas sintéticas: PASS, sin cambiar capturas.
- Fuentes Draw.io de flujo, datapath y TOP exportadas a PNG y
  revisadas visualmente. Exportaciones solo en productos locales.

## Prueba física

**No ejecutada; hito no cumplido todavía.**
Ver [revisión de E/S](revision_io_frame.md): confirmar VCCIO5 y
polaridades, estado del LCD al empezar LP y condiciones de configuración.
Solo después corresponde solicitar autorización separada de carga
SRAM con FT232RL. No hay evidencia física de barras, solo backlight
ni ausencia de respuesta obtenida en esta entrega.
