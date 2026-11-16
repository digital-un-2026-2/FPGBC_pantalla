# Integración LP con LiteX/Migen

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
  LP usa `LVCMOS12`; HS usa `LVDS25`; ambos con `PULL_MODE=NONE`.
  En Apicula se fija la familia Yosys `gw2a` y se añaden restricciones
  individuales de los seis pines HS para evitar la resolución incompleta
  de pares vectoriales del nextpnr instalado.
- `cores/phy_pads.py`: seis `TBUF` LP con `OEN=~lp_oe` y tres
  `TLVDS_TBUF` HS con `OEN=1` constante. Sin registros ni reloj.
- `cores/lp_init.py`: instancia y conecta los tres tops RTL; incluye
  los bloques compartidos una sola vez.
- `targets/fpgbc_lp_init.py`: reloj de 40 MHz, reset inicial de 16 ciclos y
  exportación del diseño. El reset del PHY es global, no `rst_motor`.

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
73,30 MHz; no equivale a cierre temporal externo ni a validación D-PHY.
El JSON enrutado se puede comprobar con la misma utilidad y `--routed`.
No se ha ejecutado el empaquetador ni generado un bitstream de este top.

**Nota de Apicula:** los seis `OBUF` HS del JSON sintetizado son marcadores de
pad que nextpnr fusiona con los tres `TLVDS_TBUF`. No usar `-noiopads`:
nextpnr necesita esos marcadores para ubicar las ramas P/N y aplicar OEN.

## Antes de la placa

La configuración de E/S es una **candidata**, no una validación eléctrica:
revisar corriente, slew, niveles, pulls durante configuración y tiempos hasta
los pads. `PULL_MODE=NONE` no controla el período previo a configuración.
El reset de arranque no detecta alimentación ni reinicia el panel.
No se cambia ninguna resistencia ni alimentación.

El exportador no ofrece opciones de carga ni ejecuta la generación de bitstream.
**El script shell que LiteX deja en `build/` sí contiene una llamada al
empaquetador:** no ejecutarlo sin la revisión anterior. Los scripts se generan
sin permitir fallos de timing; nextpnr puede usarse por separado para revisión.
No se ha programado la FPGA. Hace falta revisión y autorización separadas.
Ver [hardware](../docs/hardware.md).

No sintetizar ni programar bitstreams antiguos de `build/` como si
correspondieran a esta arquitectura.
