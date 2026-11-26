# Targets FPGBC con LiteX/Migen

El [target `fpgbc_white`](docs/fpgbc_white.md) integra LP y HS para
verificar offline líneas RGB888 blancas. El target LP se describe abajo.

## Integración LP

Esta integración conecta los RTL existentes sin CPU, CSR, UART ni LiteScope:

```text
clk40 → reset de arranque → secuenciador_init ↔ motor_lpdt
                                  ↕               │
                              motor_phy ← estado_D0
                                  │
                            GowinLPPads → LP / HS
```

## Archivos

- `platforms/fpgbc.py`: dispositivo, reloj y mapa de doce pines DSI.
  LP usa `LVCMOS12`, `DRIVE=8`, `SLEW_RATE=FAST`; las ramas HS usan
  GPIO `LVCMOS25` con salida permanentemente deshabilitada.
  Todos los pads DSI tienen `PULL_MODE=NONE`. Se fija la familia Yosys `gw2a`.
- `cores/phy_pads.py`: seis `TBUF` LP con `OEN=~lp_oe` y seis
  `IOBUF` sobre las ramas HS con `OEN=1` constante. No hay transmisor
  diferencial HS ni lógica de recepción; las entradas de IOBUF se ignoran.
  No se conducen 2,5 V sobre el panel. Sin registros ni reloj.
- `cores/lp_init.py`: instancia y conecta los tres tops RTL; incluye
  los bloques compartidos una sola vez.
- `targets/fpgbc_lp_init.py`: reloj de 40 MHz, reset inicial de 16 ciclos y
  exportación del diseño. El reset del PHY es global, no `rst_motor`.
  El pulsador central de volumen (`global_rst_n`, pin FPGA 120, activo bajo,
  LVCMOS33 con pull-up, como en `FPGBC_digital_UN`) reinicia toda la cadena.
  Se sincroniza con dos registros y mantiene reset al menos 16 ciclos tras
  detectar la liberación; no implementa un antirrebote de milisegundos.
  No resetea físicamente el LCD.

## Exportación y pruebas

Desde la raíz:

```sh
# Exporta Verilog, CST y scripts, SIN ejecutar herramientas de implementación.
# Por defecto conserva reset permanente y no habilita ningún driver.
pixi run python -m gateware.targets.fpgbc_lp_init

# Variante activa exclusivamente para revisión y simulación.
pixi run python -m gateware.targets.fpgbc_lp_init --enable-lp

pixi run python -m unittest gateware.tests.test_lp_target -v
```

Las pruebas usan el top generado y modelos funcionales de los buffers:
reconstruyen 18 paquetes / 204 bytes desde los pads, comprueban las pausas
completas de 9/65 ms, LP-11 final, reset/fallo durante transmisión y la variante
aislada por defecto. Solo se acorta la espera inicial de alimentación de 20 ms.
Los modelos no son bibliotecas eléctricas del fabricante.

Tras sintetizar el JSON de revisión, se puede comprobar su estructura con:

```sh
pixi run python -m gateware.tests.check_netlist build/fpgbc_lp_init/fpgbc_lp_init.json
```

Se ha comprobado síntesis GW2A y place-and-route con nextpnr a **40 MHz**.
En la ejecución de revisión, el reloj interno pasa con Fmax informada de
85,05 MHz; no equivale a cierre temporal externo ni a validación D-PHY.
El JSON enrutado se puede comprobar con la misma utilidad y `--routed`.
La auditoría de fusibles pasa: las seis ramas HS tienen salida estáticamente
apagada (`ODMUX_1=0`) y todos los pads DSI conservan pulls desactivados.
Se generó un candidato **no medido eléctricamente** y se verificó que al
releerlo reproduce exactamente el mapa de fusibles comprobado.

**Nota de Apicula:** usar `scripts/pack_lp_checked.py`, no `gowin_pack` directo.
La versión instalada no registra los pads usados antes de su bucle de pines
no utilizados. El wrapper corrige ese registro en memoria, comprueba los
atributos/fusibles y se niega a serializar si falla algún control.
No modifica la instalación ni programa hardware.

## Antes de la placa

La configuración de E/S es una **candidata**, no una validación eléctrica:
revisar corriente, slew, niveles, pulls durante configuración y tiempos hasta
los pads. `PULL_MODE=NONE` no controla el período previo a configuración.
El reset de arranque no detecta alimentación ni reinicia el panel.
No se cambia ninguna resistencia ni alimentación.

El exportador no ofrece opciones de carga ni ejecuta la generación de bitstream.
**El script shell que LiteX deja en `build/` sí contiene una llamada al
empaquetador comprobado:** no ejecutarlo sin la revisión anterior. Los scripts se generan
sin permitir fallos de timing; nextpnr puede usarse por separado para revisión.
Estos comandos no programan la FPGA; cualquier carga requiere revisión y
autorización separadas. La captura física de la iteración 2 se documenta en la
[comparación LP](../docs/comparacion_LP_ITERATION_2.md).
Ver [hardware](../docs/hardware.md).

La [revisión offline de E/S](../docs/revision_io_lp.md) añade un auditor del
JSON enrutado contra la base del encapsulado. La comprobación del packer es separada:

```sh
pixi run python -m gateware.tests.review_io build/fpgbc_lp_gpio_review/fpgbc_lp_init_routed.json
pixi run python -m gateware.tests.review_fuses build/fpgbc_lp_gpio_review/fpgbc_lp_init_routed.json
pixi run python -m unittest gateware.tests.test_review_io gateware.tests.test_review_fuses -v
```

`review_io` solo lee archivos. `review_fuses` ejecuta el packer hasta los
fusibles en memoria y no serializa salvo que se pida `-o archivo.fs`.
Ninguno certifica eléctricamente la placa ni se comunica con ella.

No sintetizar ni programar bitstreams antiguos de `build/` como si
correspondieran a esta arquitectura.

## Variante LP con backlight

`--enable-backlight` añade dos salidas activas en alto al target LP existente:
`backlight_en` (pin 46, IOB14A) y `backlight_pwm` (pin 47, IOB14B), según
`FPGBC_digital_UN/docs/identified_pins/gowin_ar_lv18e144pc.csv`.
Ambas permanecen en cero hasta `init_completa` y se apagan por reset o fallo.
El primer pulso PWM comienza un ciclo de 40 MHz después de subir EN.
El brillo es fijo: **1 kHz, 50 %**. El secuenciador y sus ROM no cambian.
El CSV no da el voltaje de VCCIO5 ni las polaridades: **LVCMOS33 y activo
en alto son supuestos del candidato**, por confirmar en placa.

Desde la raíz, generar el `.fs` con las herramientas de Pixi:

```sh
pixi run --locked python -m gateware.targets.fpgbc_lp_init \
  --enable-lp --enable-backlight --output-dir build/fpgbc_lp_backlight
pixi run --locked bash -c '
  cd build/fpgbc_lp_backlight &&
  yosys -l fpgbc_lp_init.rpt fpgbc_lp_init.ys &&
  yowasp-nextpnr-himbaechel-gowin --json fpgbc_lp_init.json \
    --write fpgbc_lp_init_routed.json --top fpgbc_lp_init \
    --device GW2AR-LV18EQ144PC8/I7 --vopt family=GW2A-18C \
    --vopt cst=fpgbc_lp_init.cst --freq 40 --seed 1 &&
  python ../../scripts/pack_lp_checked.py -d GW2A-18C \
    -o fpgbc_lp_init.fs fpgbc_lp_init_routed.json
'
```

Resultado: `build/fpgbc_lp_backlight/fpgbc_lp_init.fs`. El empaquetador
comprueba también los dos pads del backlight y no sobrescribe un `.fs` existente.
