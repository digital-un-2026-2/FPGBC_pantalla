# HS_PACKER — RGB y prefijo de cuadro opcional

El modo por defecto `FRAME_MODE=0` conserva el paquete RGB original:
cabecera `3E 70 08 13`, 1080 palabras de píxeles y CRC calculado sobre
2160 bytes. El SoT sigue fuera, en `PHY_IF`.

El TOP de cuadro selecciona `FRAME_MODE=1`. El descriptor interno
`BURST_KIND[1:0]`, capturado antes de `PK_START` y estable durante toda
la ráfaga, elige:

- `00`: VSS candidato, dos palabras, ninguna lectura RGB.
- `01`: HSS, dos palabras, ninguna lectura RGB.
- `10`: HSS (dos palabras), Blanking (seis palabras), paquete RGB
  original (1083 palabras). Exactamente 1080 lecturas RGB.
- `11`: reservado, no lo produce FRAME_TIMING.

El TOP solo conecta los componentes y ecuaciones de habilitación.
Reutiliza `hs_packer_word_cnt` con ancho 4 para el prefijo y ancho 11
para RGB. El contador de prefijo parte de 0, avanza con `PK_START` o
durante el prefijo, llega a 9 y retiene hasta fin de ráfaga. `PK_DONE`
reinicia **la transacción** del prefijo en el ↓ siguiente; `RST_BYTE`
reinicia ambos contadores y CRC por reset **del módulo**.
El descriptor de cuadro se conserva fuera del packer.

`RGB_START` se publica combinacionalmente con índice de prefijo 8,
durante un único ciclo. La cabecera RGB consume ese ↓ y borra su CRC;
los ocho ciclos anteriores no arrancan el contador RGB ni leen píxeles.
El multiplexor existente añade la selección del prefijo sin alterar
la selección RGB ni los componentes de su CRC.

El último dato RGB se consume antes del ↓ de CRC. Después de ese ↓,
`PK_DONE` se publica combinacionalmente; LINK_FSM lo lee en ↑. No se
confunde ese fin lógico con la salida física del último bit por OSER8.

[Diseño del camino RGB](docs/HS_PACKER.drawio), correspondiente al modo
base, y [flujo/datapath ampliados de cuadro](../../gateware/docs/fpgbc_frame.drawio).
[Tabla de flancos y receta](../../gateware/docs/fpgbc_frame.md).

```sh
pixi run --locked make -C mipi_tx/hs_packer test
pixi run --locked make -C gateware -j2 test
```

El primer banco conserva las regresiones RGB. El segundo verifica el
prefijo, sincronismos, dos cuadros y CRC de barras/blanco desde los
pads modelados del TOP real.
