# Diseños y reloj/reset

`display_image.py` genera el bitstream autónomo de imagen 720×720 RGB888:
inicialización JDI por LPDT y barras a 60 Hz mediante dos lanes de 480 Mbit/s.
Conecta los pines físicos y arranca automáticamente. Construir con
`pixi run --locked build-display-image`.
[Carga, pruebas y límites de validación](../../docs/imagen_en_pantalla.md).

[Gateware](../README.md) · [Flujo de trabajo](../../docs/flujo_de_trabajo.md)

`debug.py` reúne SoCMini, UARTWishbone, registros, supervisor LPDT y LiteScope.
Usa el núcleo `dphy_lpdt_tx` directamente; D0 permanece interno, sin drivers del panel.
`crg.py` conecta el reloj de 40 MHz y genera el reset de arranque con un contador.
Ese reset no es el RESET físico de la pantalla.

`display.py` integra la cadena de pantalla completa con control CSR por
UARTWishbone. Conserva los pads internos y los perfiles deshabilitados por
defecto. Generar con `pixi run --locked generate-display`; resultados en
`build/display/`. [Interfaz, pruebas y límites](../../dsi_display/README.md).

`display_board.py` reserva los doce pines LP/HS, añade CST/SDC y genera
bitstream con timing estricto. Modos parked, LPDT a 40 MHz y HS mediante perfil
JSON. Admite Apicula/YoWASP y generación de proyecto Gowin EDA.
[Comandos y pinout](../../docs/implementacion_fpga.md).

Dentro de `pixi shell`:

```sh
python -m gateware.targets.debug
python -m gateware.targets.debug --build
```

La primera orden genera archivos; la segunda añade síntesis e implementación.
Ambas escriben `build/debug/` y ninguna programa la FPGA.
La captura LiteScope tiene 2048 muestras a 40 MHz.
