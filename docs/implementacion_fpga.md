# Implementación en la FPGBC

Para mostrar una imagen, usar el **target autónomo `display_image`**:
`pixi run --locked build-display-image`. El bitstream
`build/display_image/gateware/display_image.fs` inicializa el panel y habilita
HS automáticamente. [Carga y prueba de barras](imagen_en_pantalla.md).
Los modos de `display_board` descritos aquí se conservan para depuración.

Target de placa: `gateware/targets/display_board.py`. FPGA
`GW2AR-LV18EQ144PC8/I7`, reloj externo de 40 MHz. No añade pines de reset,
alimentación o backlight: esas conexiones no están disponibles en este diseño.

## Pines y estándares

Los números corresponden al encapsulado de la FPGA. El orden de los vectores
del RTL es D0, D1, CLK, índices 0, 1, 2.

| Conductor | GPIO LP | Estándar LP | Pin HS | Estándar HS |
|---|---:|---|---:|---|
| D0_P | 122 | LVCMOS12, 4 mA | 117 | LVDS25 |
| D0_N | 123 | LVCMOS12, 4 mA | 116 | LVDS25 |
| D1_P | 124 | LVCMOS12, 4 mA | 115 | LVDS25 |
| D1_N | 125 | LVCMOS12, 4 mA | 114 | LVDS25 |
| CLK_P | 126 | LVCMOS12, 4 mA | 113 | LVDS25 |
| CLK_N | 128 | LVCMOS12, 4 mA | 112 | LVDS25 |
| Referencia de 40 MHz | 11 | LVCMOS33 | — | — |
| UART RX de FPGA | 28 | LVCMOS33 | — | — |
| UART TX de FPGA | 27 | LVCMOS33 | — | — |

Los doce pines del panel tienen `PULL_MODE=NONE`. La rama LP atraviesa la
resistencia de 100 Ω existente; la rama HS llega directamente al conductor.
Bancos medidos: LP 1,21 V y HS 2,52 V. El mapa procede de la continuidad
confirmada en [hardware.md](hardware.md), no de numeración del conector LCD.

Los estándares y el ajuste LP de 4 mA están admitidos por
[Gowin DS226, tablas 2-1 y 3-10](https://cdn.gowinsemi.com.cn/DS226E.pdf).
Esto no caracteriza la red externa como D-PHY ni valida sus formas de onda.
La topología de dos ramas se describe en
[Gowin IPUG948, sección 4.2](https://cdn.gowinsemi.com.cn/IPUG948E.pdf).

## Configuraciones

| Modo | Comportamiento tras liberar reset por CSR |
|---|---|
| `parked` | Reserva los doce pines y mantiene todos sus drivers en Z |
| `lpdt` | CLK/D1 en LP-11; D0 admite DCS cortos; drivers HS siempre deshabilitados |
| `hs` | Cadena completa con perfil JSON explícito; la plantilla suministrada mantiene PHY y vídeo bloqueados |

Los tres modos arrancan con `display_reset=1`. El modo LPDT usa directamente
el reloj de 40 MHz, sin PLL ni OSER8. START y APPLY se rechazan en hardware
en este modo, incluso después de autorizar el panel. No se puede habilitar HS
por una escritura CSR accidental. Reset vuelve a poner los drivers LP en Z.

Generación y construcción local, **sin programar la FPGA**:

```sh
# Pines reservados; todas las salidas del panel deshabilitadas.
pixi run --locked generate-display-board
pixi run --locked build-display-board

# Prueba física LPDT, con HS permanentemente deshabilitado.
pixi run --locked build-display-lpdt
pixi run --locked check-display-lpdt

# Preparación de la cadena HS con la plantilla deshabilitada.
pixi run --locked python -m gateware.targets.display_board --mode hs \
  --profile profiles/display_hs.template.json --build
```

Los productos van a `build/display_board_parked/`, `build/display_board_lpdt/`
y `build/display_board_hs/`, respectivamente. En cada directorio:

- `gateware/display_board.fs`: bitstream, solo tras `--build` satisfactorio.
- `gateware/display_board.cst`: pines y opciones de E/S.
- `gateware/display_board.sdc`: restricciones para Gowin EDA.
- `gateware/display_board.report`: timing y utilización de nextpnr.
- `gateware/display_board_routed.json`: circuito físico para inspeccionar drivers.
- `csr.csv`: mapa de control correspondiente a ese circuito.
- `board_manifest.json`: modo, pines, perfil, resultado de construcción y SHA256.

Conservar juntos el bitstream, el manifiesto y `csr.csv`. Una generación sin
`--build` no actualiza un bitstream anterior; su manifiesto indica que no se ha
ejecutado implementación. No usar el CSV del target `debug` o del target interno
`display` para controlar este bitstream.

El flujo selecciona nextpnr nativo si está instalado; en este entorno usa
`yowasp-nextpnr-himbaechel-gowin` sin crear enlaces ni instalar herramientas.
La síntesis especifica la familia GW2A. Para nextpnr, las ubicaciones P y N se
emiten por separado porque se empaquetan antes de fusionarse como TLVDS. Gowin
EDA recibe su formato de ubicación por pareja.

## Relojes y resultados

Apicula usa `--freq 40` con fallo obligatorio si no se cumple timing; no se
añade `--timing-allow-fail`. En LPDT todo usa el mismo reloj y permanecen los
caminos de medio ciclo de 12,5 ns del motor/árbitro.

El SDC nativo define el reloj de referencia. Para HS añade CLKOUT/CLKOUTP
de 160 MHz y CLKOUTD de 40 MHz, fase tomada del perfil y límites de 25 ns
para los buses estables del mailbox. No corta globalmente los caminos entre
relojes ni inventa retardos de E/S del panel. Verificar que los objetos del
SDC se resuelvan en Gowin EDA: ese ejecutable no está instalado aquí.
Apicula no consume ese SDC; el ruteo no certifica el desfase CLK/datos ni los
tiempos de las primitivas frente al LCD.

Resultados obtenidos el 2026-11-10:

- LPDT: síntesis, P&R y empaquetado completos; objetivo 40 MHz cumplido,
  Fmax del modelo nextpnr 118,46 MHz. Seis TBUF conservan LVCMOS12/4 mA;
  los tres pares HS tienen OEN conectado a VCC. Sin PLL ni OSER8.
- HS con plantilla bloqueada: bitstream construido, un rPLL y tres OSER8
  colocados. Se verifican pines y recursos; no es una prueba de vídeo activo.
- `parked`: bitstream construido con los pines del panel deshabilitados.
- Simulación LPDT de placa: comandos reconstruidos desde pads, fases de cuatro
  ciclos, CLK/D1 en LP-11, HS en Z, reset y rechazo de órdenes de vídeo.
- Regresión completa de la integración y adaptador CSR: PASS.

La comprobación `check-display-lpdt` contrasta el CST con la tabla independiente
de continuidad, verifica el hash, los estándares conservados en el ruteo, la
inhibición HS y el resultado de timing.

## Proyecto para Gowin EDA

```sh
pixi run --locked python -m gateware.targets.display_board --mode hs \
  --profile profiles/display_hs.template.json --toolchain gowin
```

Genera `build/display_board_hs_gowin/gateware/run.tcl`, fuentes, CST, SDC y CSR.
Con Gowin EDA instalado se puede ejecutar `gw_sh run.tcl` desde esa carpeta,
o añadir `--build` al comando anterior. La generación se comprobó; no se ha
ejecutado el compilador propietario. Las fuentes siguen en sus rutas del repo.

## Control después de una carga manual

La tarea de construcción no carga SRAM ni escribe flash. Para la carga manual,
usar el programador y cableado ya documentados en el [flujo de trabajo](flujo_de_trabajo.md).
Una vez cargado **el bitstream LPDT correspondiente** y con `litex_server` activo:

```sh
pixi run --locked python scripts/display_control.py \
  --csr-csv build/display_board_lpdt/csr.csv reset
pixi run --locked python scripts/display_control.py \
  --csr-csv build/display_board_lpdt/csr.csv status
```

`reset` reinicia la lógica y libera los drivers LP a LP-11; no hace el reset
físico de la pantalla. `initialize archivo.json` necesita la secuencia real
del panel y sus esperas. La investigación disponible está en
[panel_lcd49754.md](panel_lcd49754.md). La secuencia pública JDI incluye DCS
largos y se ejecuta en hardware en `display_image`; no cabe en la interfaz
de comandos cortos de este target LPDT.
