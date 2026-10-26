# Testbenches

[Inicio](../../README.md) · [Comandos e interfaz](../README.md)

Cada `<modulo>_TB.v` es una prueba autocontenida; las discrepancias y los
timeouts terminan con `$fatal`. Estas son pruebas lógicas, no validación eléctrica.

```sh
make -C motor_lpdt test-all
make -C motor_lpdt sim
```

## Cobertura

| Target | Qué comprueba |
|---|---|
| `count` | Tres contadores: tiempo, bit y byte; retención, reset, comparadores y aislamiento |
| `reg` | `reg_0.v`: cargas y retención independientes en 1/3/8/16 bits; 256 valores del byte |
| `mux` | Cinco configuraciones, selección y orden de entradas; selectores binarios fuera de rango producen cero |
| `motor_control` | FSM con datapath modelado; vector inicial, longitudes 1–4, permiso, avisos y reset por estado |
| `motor_lpdt` | FSM y datapath RTL reales, con almacén síncrono modelado; longitudes 1–7, longitud cero, permiso y reset por estado |

Los dos tests del motor comparan P/N ciclo a ciclo y reconstruyen
`87 05 01 00 10`, LSB primero; para ese vector comprueban 340 ciclos (8,5 µs).
También prueban patrones `00/FF/55/AA` y solicitudes adicionales durante envío.
El integrado comprueba posiciones válidas, salida en negedge y aviso final
posterior al retorno efectivo a LP-11. Tras los abortos se prueba otro envío.

Verificación local: los cinco targets finalizaron en `PASS` con `test-all`.
Icarus emitió advertencias de `timescale` heredado de los testbenches, sin
errores de compilación ni de simulación. Esto no equivale a validar la placa.

## Convenciones y límites

- Reloj de 40 MHz; control en posedge y registros/contadores en negedge.
  Los retardos `#1` permiten observar asignaciones ya actualizadas; no modelan
  retardos físicos.
- En `count`, el caso aislado mide cuatro incrementos hasta 4. En el motor,
  el temporizador recorre 0–3: la prueba integrada mide las permanencias reales.
- `reg_0` no tiene reset: su `X` inicial es una propiedad de simulación, no una
  garantía eléctrica. WC de 16 bits solo prueba almacenamiento, no paquetes largos.
- `mux` no define aquí comportamiento para selectores X/Z. Solo el caso 8:1
  de un bit explora exhaustivamente todas las combinaciones de datos.
- El test aislado de control presupone lectura anticipada; el integrado modela
  un almacén síncrono en posedge. Ninguno demuestra cierre temporal de una memoria.
- La reconstrucción LPDT usa posiciones temporales conocidas, no un receptor
  general por transiciones. Falta probar explícitamente la solicitud sostenida.
- No se verifican niveles, flancos, habilitación real HS/LP, CLK/D1, reposo inicial,
  retardos DCS ni recepción del panel. El reset probado es interno, no del panel.

## Ondas

Se generan `motor_lpdt/build/<target>_TB.vcd` y `.out`; las vistas están en
`motor_lpdt/waves/<target>_TB.gtkw`. Las del motor agrupan control, tiempo, bytes y LP.
La FSM muestra `state_name` en ASCII con `BENCH`, activado por el Makefile:
0 IDLE, 1 ESC_10, 2 ESC_00_A, 3 ESC_01, 4 ESC_00_B, 5 MARK, 6 SPACE,
7 EXIT_10, 8 DONE. Las vistas no sustituyen las comprobaciones automáticas.

