# LP_TX — transmisor lógico LPDT

[Diagrama editable: flujo, datapath y FSM](docs/LP_TX.drawio).
Transmite un paquete LPDT por D0. La arquitectura de referencia es la de
`MIPI_TX_componentes.pdf` y `MIPI_TX_bloques.pdf` de `digital_UN`; las
entradas BYTE/WAIT siguen `INIT_MEM_ROM.md`. Los flancos acordados se
describen abajo. El módulo todavía no está conectado al TOP.

## Interfaz

| Señal | Dirección respecto a LP_TX | Uso |
|---|---|---|
| `CLK_BYTE` | Entrada común | FSM en ↑, datapath en ↓. |
| `RST_BYTE` | Entrada común | Síncrono, activo en 1; debe cubrir un ↑ y el ↓ siguiente. |
| `LP_START` | Desde `LINK_FSM` | Pulso presentado después de un ↑ y leído en el siguiente ↑, solo en `IDLE` con un primer BYTE válido. |
| `LP_DONE` | Hacia `LINK_FSM` | Pulso de un ciclo tras el ↓ de resguardo de LP11; se lee en ↑. |
| `INIT_BYTE[7:0]`, `INIT_LAST` | Desde `INIT_SEQUENCER` | Durante el paquete: BYTE si `INIT_LAST=0`, WAIT si `INIT_LAST=1`. |
| `INIT_NEXT` | Hacia `INIT_SEQUENCER` | Un pulso por BYTE DSI ya capturado, no por el selector ni al terminar de serializar. |
| `LP_D0[1:0]` | Hacia `PHY_IF` | Par `{P,N}` registrado en ↓: `[1]=P`, `[0]=N`. |

El primer BYTE debe estar estable antes de aceptar `LP_START` y hasta su
carga. `INIT_NEXT` sube **después** del ↓ de carga y se mantiene hasta el
↓ siguiente. `INIT_SEQUENCER` lo lee en el ↑ intermedio y avanza una sola
dirección. La nueva pareja `INIT_BYTE`/`INIT_LAST` debe estar estable
antes del ↑ que decide la siguiente frontera de byte y hasta el ↓
siguiente; no se impone la latencia interna de la ROM. Al llegar a WAIT se
mantiene esa entrada hasta el fin del paquete: su argumento nunca se carga.
Las esperas de 7/9/65 ms quedan en `INIT_SEQUENCER`. `INIT_READY` e
`INIT_DONE_TX` no son puertos de `LP_TX`.

## Funcionamiento

- `STEP_SEQ` pasa de `IDLE` por `ENTRY → CMD → DATA → EXIT` y vuelve a
  `IDLE`. Las transiciones son secuenciales y el control se decodifica
  con valores por defecto, según [`phy_control.v`](../../motor_phy/src/phy_control.v).
- Desde LP11, `ENTRY` publica `10 → 00 → 01 → 00`. `BYTE_SEL` elige
  `0x87` solo en `CMD`; en `DATA` toma los bytes exactos de la ROM, incluido
  cualquier `0x87` que sea dato. No hay contador de bytes ni recálculo de ECC/CRC.
- `SHIFT_REG` carga el byte en el mismo ↓ que publica su primera marca.
  `SYMBOL_ENC` usa directamente el bit 0 de `BYTE_SEL` en esa carga, sin
  esperar el valor nuevo del registro. `BIT_CNT` cuenta 0…7; alterna marca
  y espacio, y desplaza a la derecha al publicar cada espacio. Se emite
  LSB primero: `1 → 10 → 00`, `0 → 01 → 00`. No hay hueco entre bytes.
- `PHASE_DIV` mantiene cada fase `D = LP_DIV` ciclos de `CLK_BYTE`, sin
  reloj derivado. El diseño lógico admite `D ≥ 1`; el valor por defecto
  (`1`) es solo para elaborar y simular, no un ajuste de placa. El valor
  para placa, el reloj real y la duración de las fases de entrada/salida
  aún requieren validación. Los ~100 ns del diagrama de referencia son
  nominales, no una medición de esta implementación. También se deben
  verificar los caminos de medio ciclo (↓ → ↑ y ↑ → ↓) al integrar.
- `STEP_SEQ` solo decide el cierre en el ↑ anterior a la marca que
  empezaría otro byte (`TICK` y `MARK0`). Un `INIT_LAST=1` mientras se
  emite el byte actual no altera `SHIFT_REG` ni lo trunca. Tras su último
  espacio, `EXIT` publica `10 → 11`, como en el
  [motor LPDT de referencia](../../motor_lpdt/docs/lpdt.md#transacción-inicial).
- `RST_BYTE` aborta sin emitir `INIT_NEXT` ni `LP_DONE`. Lleva la FSM a
  `IDLE` en ↑ y el par D0 a LP11 en ↓, además de limpiar los registros
  de datos y fase. Tras liberar reset se requiere un nuevo `LP_START`.

## Flancos acordados del primer paquete

`87 | 29 02 00 00 B0 00 D6 CA`. Los índices se expresan en ciclos de
`CLK_BYTE`: `↓0` publica el primer LP10; `↑n` está entre `↓n` y `↓(n+1)`.
Los valores de `LP_D0` en las tablas son los publicados **después** de ↓.
[PHY_IF](../phy_if/README.md#flancos-acordados) registra el valor que estaba
estable **antes** de ↓; con LPDT seleccionado, cada nuevo símbolo aparece
en su salida un ↓ más tarde.

| Flanco | LP_TX | LINK_FSM / INIT_SEQUENCER / PHY_IF |
|---|---|---|
| `↑−2` | `IDLE`, `LP_D0=11`. | `LINK_FSM` presenta `LP_START=1` y `SEL_OUT=01` (LPDT). ROM en dirección 0: `29`, `INIT_LAST=0`. |
| `↑−1` | Acepta `LP_START` y entra en `ENTRY`. | El primer BYTE sigue presentado; aún no se consume. |
| `↓0`, `↓D`, `↓2D`, `↓3D` | Publica `10`, `00`, `01`, `00`, respectivamente. | `PHY_IF` captura cada uno en `↓1`, `↓(D+1)`, `↓(2D+1)`, `↓(3D+1)`; en `↓0` todavía captura LP11. |
| `↑(4D−1)` / `↓4D` | Entra en `CMD`; carga `87` (b0…b7: `11100001`) y publica la marca de b0 (`10`). `INIT_NEXT=0`. | La dirección 0 no cambia. |
| `↓19D` / `↑(20D−1)` | Publica el espacio de b7 del selector; entra en `DATA` al terminar esa fase. | `29` sigue estable para el primer ↓ de carga DSI. |

En cada `↓L` de la tabla siguiente, `LP_TX` carga el byte indicado,
publica su primera marca y eleva `INIT_NEXT`. En `↑L`, `INIT_SEQUENCER`
lee el pulso, incrementa la dirección y presenta la nueva entrada al
estabilizarse la lectura. En `↓(L+1)`, `INIT_NEXT` baja y `PHY_IF` captura
esa primera marca. Los bits se transmiten en el orden mostrado.

| ↑ de decisión | ↓ de carga `L` | Dir. y BYTE consumido | b0…b7 | ↑ que lee `INIT_NEXT` | Entrada siguiente tras el avance |
|---|---|---|---|---|---|
| `↑(20D−1)` | `↓20D` | 0 · `29` | `10010100` | `↑20D` | 1 · `02`, LAST=0 |
| `↑(36D−1)` | `↓36D` | 1 · `02` | `01000000` | `↑36D` | 2 · `00`, LAST=0 |
| `↑(52D−1)` | `↓52D` | 2 · `00` | `00000000` | `↑52D` | 3 · `00`, LAST=0 |
| `↑(68D−1)` | `↓68D` | 3 · `00` | `00000000` | `↑68D` | 4 · `B0`, LAST=0 |
| `↑(84D−1)` | `↓84D` | 4 · `B0` | `00001101` | `↑84D` | 5 · `00`, LAST=0 |
| `↑(100D−1)` | `↓100D` | 5 · `00` | `00000000` | `↑100D` | 6 · `D6`, LAST=0 |
| `↑(116D−1)` | `↓116D` | 6 · `D6` | `01101011` | `↑116D` | 7 · `CA`, LAST=0 |
| `↑(132D−1)` | `↓132D` | 7 · `CA` | `01010011` | `↑132D` | 8 · WAIT `09`, **LAST=1** |

El `CA` se consume con `INIT_LAST=0`. La palabra `309` de la dirección 8
presenta `INIT_LAST=1` después del avance de `↑132D` (debe estar estable
antes de `↑(148D−1)`). `09` es el argumento de WAIT de 9 ms, no un byte
del enlace. `LP_TX` no pulsa `INIT_NEXT` por WAIT.

| Flanco | LP_TX | D0 registrado en PHY_IF / selección |
|---|---|---|
| `↓146D` / `↓147D` | Emite b7 de `CA`: `10` y después `00`. | Captura la marca y el espacio en `↓(146D+1)` y `↓(147D+1)`. |
| `↑(148D−1)` | Ya en la frontera, lee `INIT_LAST=1` y entra en `EXIT` sin cargar `09`. | Sigue en LPDT (`SEL_OUT=01`). |
| `↓148D` | Publica `10` de cierre. | Todavía captura el último `00`; captura `10` desde `↓(148D+1)`. |
| `↓149D` | Publica `11`; `LP_DONE` sigue en 0. | Todavía captura el `10` de cierre. |
| `↓(149D+1)` | Sostiene LP11. | Captura LP11 desde `LP_D0`, aún en LPDT. |
| `↓150D` | Sostiene LP11 y sube `LP_DONE` **tras** el flanco de resguardo. Con `D=1`, coincide con la primera captura de LP11. | `PHY_IF` ya registró LP11 en este ↓ o antes. |
| `↑150D` / `↓(150D+1)` | `STEP_SEQ` vuelve a `IDLE`; en el ↓ baja `LP_DONE`, `LP_D0` sigue en 11. | `LINK_FSM` lee `LP_DONE` en ↑ y puede seleccionar reposo (`SEL_OUT=00`): el siguiente ↓ conserva LP11. |

`LINK_FSM` debe mantener LPDT desde antes de la primera captura y hasta
leer `LP_DONE`. Volver a reposo conserva LP11 sin recortar el último
espacio ni el `10` de salida. Esto describe los niveles lógicos
registrados, no la recepción por el panel ni la habilitación física.

## Pruebas aisladas

```sh
pixi run --locked make -C mipi_tx/lp_tx test
pixi run --locked make -C mipi_tx/lp_tx sim
pixi run --locked make -C mipi_tx/lp_tx wave
```

`test` usa `LP_DIV=1` y `6` y no genera ondas. El banco comprueba cada
ciclo de la forma de onda y los pulsos en ambos flancos. Usa los dos
primeros paquetes de INIT_MEM, incluido el `87` de CRC bajo en
`29 06 00 23 E4 00 00 00 00 08 87 16`, y un modelo de captura en ↓ para
verificar el retardo de `PHY_IF`. También verifica que WAIT no es un
byte ni permite arrancar, que no se pierde LP11 al soltar LPDT y que
un reset en plena emisión aborta sin fin falso y permite reenviar.
No se instancian `LINK_FSM`, `INIT_SEQUENCER` ni `PHY_IF`.

`sim` ejecuta el mismo banco con `SIM_DIV=6` por defecto y abre el FST
en GTKWave. `wave` reabre `build/lp_tx/lp_tx_TB.fst` sin recompilar.
