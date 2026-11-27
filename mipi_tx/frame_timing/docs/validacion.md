# Validación del componente de encuadre

Ejecutada el 2026-11-26 desde `origin/main` `37dcd6e` (PR #21), en la
rama propia `feature/frame-timing`. No se modifica el target ni se
programa la FPGA.

## Simulación unitaria

```sh
pixi run --locked make -C mipi_tx/frame_timing test
pixi run --locked make -C mipi_tx/frame_timing sim GTKWAVE=true
```

Ambos perfiles pasan:

- Perfil 0: admisiones separadas un ciclo, dos cuadros consecutivos.
- Perfil 1: admisiones separadas 1168 ciclos, dos cuadros consecutivos.
- Por cuadro: 743 admisiones, 3 VSS, 20 HSS, 720 RGB, en el orden aprobado.
- Cada tipo corresponde al índice **previo** al avance en ↓.
- Índice y descriptor se conservan sin admisión, incluso entre cuadros.
- Publicar inicio después de ↑ no cambia registros hasta ↓.
- Reset prioritario con inicio simultáneo, en periodos pendientes
  0, 3, 11, 371, 731 y 742, y después de consumir el periodo 742.
- Tras reset, la primera admisión vuelve al periodo 0.
- Inicio alto durante tres ↓ representa tres admisiones: no se pierde
  ninguna por una detección de flanco no prevista en el contrato.

El banco comprueba registros antes y después de ↓ y tras cada ↑.
`test` no genera ondas. El segundo comando prueba el mismo banco con
`+waves`, escribe `build/frame_timing/frame_timing_TB.fst` y sustituye
GTKWave por `true` para no abrir una GUI durante la validación.

## Comprobación estructural

```sh
pixi run --locked yosys -Q -T -l build/frame_timing/synth_check.log -p \
  'read_verilog mipi_tx/frame_timing/src/*.v; hierarchy -check -top frame_timing; proc; opt; check -assert; stat'
```

Resultado: cero problemas. Dos bancos de registros de flanco negativo:
contador de 10 bits y descriptor de 2 bits, con reset síncrono y
habilitación. No se infieren latches, memorias ni FSM.

Se exportó `docs/FRAME_TIMING.drawio` a PNG dentro de
`build/frame_timing/` usando Draw.io y se revisó visualmente la página.
La fuente editable es el único artefacto gráfico versionado.

## Regresión existente

```sh
pixi run --locked make -C mipi_tx test
```

Pasan los dos perfiles existentes: 18 paquetes LP y 204 bytes DSI,
dos líneas RGB consecutivas de 1080 lecturas con CRC `EE/7E`, drenaje
de CRC y reset/reinicio desde LP y primer píxel. Sus esperas se escalan
según el banco existente; no son la prueba de esperas físicas completas.
Esta regresión todavía usa el transmisor sin FRAME_TIMING conectado.

## Pendiente de integración

Esta entrega **no** valida:

- Dos cuadros reconstruidos desde pads, paquetes VSS/HSS o Blanking.
- Cero lecturas durante las ráfagas de sincronismo integradas.
- El desplazamiento de `READY` a `d1167` con el prefijo añadido.
- Enrutado, empaquetado mixto, lectura de un `.fs` nuevo o E/S de placa.
- Recepción por el LCD ni imagen estable.

Todo ello pertenece a la integración posterior. Se mantienen el diseño
aprobado de 1168 ciclos, el cierre físico existente, las precauciones de
E/S y la autorización de carga separada.
