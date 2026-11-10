# Imagen de prueba en el LCD

## Prueba física y variante para retroiluminación

El usuario probó el primer `display_image.fs`: no apareció imagen y la
retroiluminación estaba apagada. Al apagar y encender, el firmware original
volvió a encenderla. Esto confirma que la placa puede activar la luz y que
el bitstream inicial no reproduce ese comportamiento; no identifica todavía
la causa ni demuestra que el receptor DSI reciba los comandos.

Se añadió una variante de diagnóstico sin modificar el bitstream anterior:

```sh
pixi run --locked build-display-backlight
pixi run --locked check-display-backlight
pixi run --locked openFPGALoader \
  --cable ft232RL --pins TXD:CTS:RTS:RXD --freq 1000000 --write-sram \
  --bitstream build/display_image_backlight/gateware/display_image.fs
```

Después de los once pasos originales envía `51 FF 00` (brillo) y `53 24`
(control de brillo y backlight habilitados) por LPDT, y espera 20 ms antes
del vídeo. El [driver JDI actualizado](https://github.com/will-tm/RPI-LCD-LT031MDZ4000/blob/main/panel-jdi-lt031mdz4000.c)
sí escribe brillo; el primer bitstream omitía ese paso. El valor `53 24` es
un ensayo basado en el control DCS estándar, no un ajuste confirmado del
firmware FPGBC. El driver público escribe el brillo en HS; esta variante
prueba LPDT. Datos y procedencia: `profiles/lt031mdz4000_backlight.json`.

No se asignó un GPIO de backlight desconocido. La especificación JDI también
describe una salida PWM del propio panel para CBABC; falta trazar cómo llega
al circuito de LEDs de la FPGBC. Si la luz permanece apagada, el siguiente
dato necesario es la continuidad de esa habilitación/control en la placa o
una medición comparada con el firmware original.

Con `litex_server` activo, este diagnóstico funciona también con el primer
bitstream y muestra los errores de PLL/reset aunque el reloj de byte no responda:

```sh
pixi run --locked python scripts/display_control.py \
  --csr-csv build/display_image_backlight/csr.csv diagnose
```

La variante debe completar 13 transacciones LPDT. Los flags nuevos exponen
el paso de inicialización y el estado de la fuente, además del contador de
cuadros. El resultado no confirma recepción ni retroiluminación del LCD.

### Resultado comunicado por el usuario

La variante de 13 comandos también dejó la retroiluminación apagada. El
diagnóstico UART del usuario devolvió:

| Campo | Resultado |
|---|---|
| `bridge_raw` | 9: interfaz disponible, PHY disponible |
| `reset_asserted`, `byte_reset`, `clock_fault` | false |
| `flags` | 1669333165 |
| `frames`, `frames_advanced` | 4486, avance de 19 durante la muestra |
| `observed_frame_hz` | 60,4, estimación por UART |
| `lp_completed`, `init_step` | 13, paso 12 |
| `source_state` | SEND |
| Causas de error de fuente, PHY y árbitro | 0 |

Estos datos acreditan ejecución y finalización local de transferencias.
`initialized=true` indica que terminó la secuencia de transmisión; el
circuito no recibe ACK/BTA del panel y ese flag no acredita inicialización
aceptada por el LCD. La cadencia UART tampoco mide la señal eléctrica HS.

La siguiente comprobación debe identificar el circuito de LEDs y su entrada
EN/PWM. El driver público activa además un `bl_en_gpio` en `jdi_panel_enable`;
ese GPIO pertenece a su placa de referencia, no identifica un pin de la
FPGBC. El panel también puede proporcionar PWM CBABC. Falta determinar si la
entrada del circuito de LEDs de esta FPGBC procede de la FPGA, del MCU, del
LCD o de otra red. El mapa de pines del proyecto no contiene esa conexión.

Para identificarla hace falta el marcado del circuito de LEDs y una imagen
legible de la zona del conector LCD en ambas caras, o continuidad trazada
desde su EN/PWM. Después se podrá comparar su nivel con firmware original y
con el target de prueba. No se ha deducido ni asignado un pin por posición.
No se genera otro perfil de vídeo a partir de estos contadores: todavía no
permiten separar un fallo de alimentación/habilitación de luz de un fallo
de recepción DSI.

## Target base

El target `display_image` inicializa el panel y repite ocho barras verticales
RGB888 de 720×720. Arranca automáticamente después de cargar la FPGA; no
necesita órdenes desde el PC. HS está habilitado en este target.

## Construir y cargar

Desde la raíz del proyecto:

```sh
pixi run --locked build-display-image
pixi run --locked check-display-image
```

Bitstream: `build/display_image/gateware/display_image.fs`. El pinout está
incluido en el CST y se contrasta con la continuidad documentada de la placa.
El manifiesto `build/display_image/image_manifest.json` conserva los ajustes y
el SHA256 del bitstream.

Para el FT232RL y el cableado de programación documentados en este proyecto:

```sh
pixi run --locked openFPGALoader \
  --cable ft232RL \
  --pins TXD:CTS:RTS:RXD \
  --freq 1000000 \
  --write-sram \
  --bitstream build/display_image/gateware/display_image.fs
```

La carga es temporal en SRAM. Después de unos 0,3 segundos de inicialización,
el circuito comienza a transmitir blanco, amarillo, cian, verde, magenta,
rojo, azul y negro, de izquierda a derecha. La última barra negra es parte
de la imagen. La alimentación y retroiluminación del panel deben estar activas;
este diseño no tiene pines para gobernarlas ni para el RESET físico del LCD.

## Implementación

La inicialización procede del
[driver público JDI LT031MDZ4000 de JamWu](https://github.com/jamwu/RPI-LCD-LT031MDZ4000/blob/main/panel-jdi-lt031mdz4000.c).
Los valores y esperas están en `profiles/lt031mdz4000_init.json`. El hardware
envía once comandos DCS por LPDT, incluidos paquetes largos con ECC y CRC,
software reset, sleep out y display on. Respeta las esperas de 120 ms.
No replica los pulsos GPIO de reset físico del driver porque esa conexión
no está disponible en la FPGA.

| Parámetro | Valor |
|---|---|
| Referencia / byte clock / serializador DDR | 40 / 60 / 240 MHz |
| Enlace | Dos lanes, 480 Mbit/s por lane |
| Imagen | 720×720 RGB888, ocho barras de 90 píxeles |
| Cuadro | 750 líneas: 5 VSYNC + 3 back porch + 720 activas + 22 front porch |
| Cadencia | 45.000 líneas/s, 60 cuadros/s |
| Fase nominal CLKOUTP | 90°, parámetro `0100` del PLL |

El driver público y su [fork de will-tm](https://github.com/will-tm/RPI-LCD-LT031MDZ4000/blob/main/panel-jdi-lt031mdz4000.c) proporcionan geometría, inicialización
y porches de referencia. Este transmisor utiliza ráfagas HS por línea con
HSS/HSE, VSS/VSE, blanking, RGB888 y EoTp. Es una implementación de puesta en
marcha, no una captura equivalente del enlace Raspberry Pi del driver.

Una ROM contiene los 2.326 bytes de una línea completa (1.163 palabras de
dos lanes). Las líneas de blanking sustituyen el paquete RGB por blanking de
igual longitud. El circuito entrega una palabra por ciclo, sin esperar al
preparador largo de tres ciclos por byte de la cadena general. La ROM
se genera con `python dsi_display/image/generate_assets.py`; la construcción
rechaza una ROM que no coincida con los datos fuente.

`dsi_image_top` conecta esta fuente al motor LPDT, árbitro, secuenciador HS y
primitivas Gowin existentes. Conserva el mailbox y los CSR de diagnóstico.
Un desbordamiento del plazo de línea detiene el vídeo con error; STOP termina
el cuadro en curso. La pérdida de PLL inhibe los drivers.

## Estado de verificación

Construido con Yosys/nextpnr/Apicula: objetivo de byte clock de 60 MHz cumplido
(Fmax del modelo: 80,28 MHz). El circuito ruteado conserva tres OSER8, un PLL,
seis drivers LP y habilitación dinámica de los tres pares HS. Los pines y
estándares son los de [implementacion_fpga.md](implementacion_fpga.md).

```sh
pixi run --locked test-display-image
pixi run --locked test-dsi-display
```

Las pruebas reconstruyen comandos LP y bytes HS desde los pads simulados,
comprueban ECC/CRC y píxeles, dos latencias del serializador, STOP/reinicio y
pérdida de PLL. Otra prueba recorre dos cuadros completos: 750 líneas por
cuadro, 720 filas RGB y exactamente 1.000.000 ciclos de byte entre cuadros.

El usuario leyó la etiqueta LCD-49754-001/111, coincidente con el LT031MDZ4000
documentado. La referencia completa está en `profiles/panel_identity.json`.
El usuario cargó los bitstreams base y con brillo DCS y en ambos
la retroiluminación quedó apagada; con la variante DCS se confirmó avance de
cuadros y ausencia de errores locales por UART. No hay programador USB accesible en este
entorno para cargar o medir la placa directamente. El timing de lógica superado
y los modelos ideales no comprueban la fase eléctrica real de CLK/datos ni
la recepción del panel. Esa es la validación pendiente en la placa.

También se puede generar el proyecto nativo, sin compilar ni cargar:

```sh
pixi run --locked python -m gateware.targets.display_image --toolchain gowin
```

Genera `build/display_image_gowin/gateware/run.tcl`, CST y SDC con relojes
de 40, 60 y 240 MHz. Gowin EDA no está instalado en este entorno.

## Diagnóstico por UART opcional

Con `litex_server` conectado a la UART de la placa:

```sh
pixi run --locked python scripts/display_control.py \
  --csr-csv build/display_image/csr.csv status
```

Después de la inicialización, `lp_completed` debe ser 11, `frames` debe crecer
y los flags deben mostrar running, config_ok, panel_initialized y PHY
disponible, sin error. Esos contadores confirman transmisión local.
Se admiten `status`, `reset`, `stop` y `start`; `reset` repite automáticamente
la inicialización. No ejecutar `configure` ni `initialize` en este target:
su perfil e inicialización están fijados en hardware y rechaza esas órdenes.

Las opciones `--phase`, `--latency` y `--hwl` del target permiten generar
variantes para contrastarlas con mediciones del enlace. El manifiesto
registra sus valores. Una fase aceptada por la herramienta no demuestra
por sí sola que el receptor esté muestreando correctamente.
