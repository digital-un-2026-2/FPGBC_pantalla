# MIPI_TX — integración lógica LP/HS

[Datapath editable](docs/MIPI_TX.drawio). [`mipi_tx`](src/mipi_tx.v) solo
cablea los cuatro bloques del contrato `MIPI_LCD`. No añade lógica de control,
registros ni retardos. No es un TOP de placa.

| Conexión | Señales |
|---|---|
| `INIT_SEQUENCER` ↔ [`LINK_FSM + TIMER`](link_fsm/README.md) | `INIT_REQ` hacia el enlace; `INIT_READY` (disponibilidad por paquete) e `INIT_DONE_TX` (fin de paquete) de vuelta al secuenciador. |
| `INIT_SEQUENCER` ↔ [`LP_TX`](lp_tx/README.md) | `INIT_BYTE[7:0]` e `INIT_LAST` hacia `LP_TX`; `INIT_NEXT` de vuelta por BYTE capturado, no por `87` ni por WAIT. |
| `VIDEO_SOURCE` → `LINK_FSM` | `VID_REQ` y `VID_LINE_RDY` ofrecen una línea completa. |
| `VIDEO_SOURCE` ↔ [`HS_PACKER`](hs_packer/src/hs_packer.v) | `VID_WORD[15:0]` hacia el packer; `VID_RD` de vuelta, muestreado en cada `↓` de píxeles. No hay `VID_HDR`. |
| `LINK_FSM` ↔ PHY | `HS_REQ` y `CLK_REQ` hacia el PHY; `READY` y `LOCK` hacia el enlace. `CLK_REQ` no gobierna `CLK_BYTE`. |
| [`PHY_IF`](phy_if/README.md) → PHY | `LP_P[2:0]` / `LP_N[2:0]` en orden `{CLK,D1,D0}` y `HS_BYTE0[7:0]` / `HS_BYTE1[7:0]` (D0 bajo, D1 alto de `WORD`). |

`INIT_DONE` (fin de toda la inicialización) va directamente del
[secuenciador](../init_sequencer/README.md) a la
[fuente de vídeo](../video_source/README.md) fuera de `MIPI_TX`.
`CLK_BYTE` sigue activo en reposo y durante reset. El `RST_BYTE` común
es síncrono activo en 1: debe cubrir un `↑` y el `↓` siguiente.
`LP_DIV` se pasa a `LP_TX`; `T_LPX`, `T_PREP`, `T_ZERO`, `T_TRAIL` y `C_LINE`
se pasan a `LINK_FSM`. Los valores por defecto son los de los bloques;
no son ajustes de placa. `T_CLK_START` (por defecto `0`) también se pasa
a `LINK_FSM`: reserva el par CLK mediante `CLK_REQ` antes del LP01 de
datos y se cuenta dentro de `C_LINE`. La
[integración Gowin](../phy/README.md) ensaya `T_CLK_START=27` sin añadir
puertos a `MIPI_TX`.

## Contrato de consumo del PHY simulado

En LP, `PHY_IF` registra cada símbolo de `LP_TX` un `↓` después de que se
publica. `LINK_FSM` espera `LP_DONE` antes de soltar LPDT, de modo que
LP11 ya está registrado al confirmar el fin al secuenciador.

En HS, el modelo no usa `PK_START`, `PK_DONE`, `SOT_EN` ni el contenido
de los bytes para decidir qué consumir. Muestrea la subida de `HS_REQ`
en `↓z` y empieza a tomar palabras en `z + T_ZERO + 1`. Cada `↓` consume
el registro **anterior** de `PHY_IF`:

| Flanco | Registro publicado por `PHY_IF` | Palabra consumida |
|---|---|---|
| `↓−1` | SoT `B8/B8` | Ninguna |
| `↓0` (`PK_START=1`, `SOT_EN=0`) | W0 `3E/70` | SoT |
| `↓1` | W1 `08/13` | W0 |
| `↓2`…`↓1081` | 1080 palabras de píxeles | W1…penúltima palabra de píxeles |
| `↓1082` | CRC bajo/alto; el packer publica `PK_DONE` | Última palabra de píxeles |
| `↓1083` (`HS_REQ` ya bajo) | `00/00`, sin dato | CRC, último consumo |

El modelo no corta al llegar a una longitud esperada. Drena un ciclo
al ver la caída de `HS_REQ`, pasa a `T_TRAIL` sin tomar otra palabra y
verifica que `CLK_REQ` siga alto durante el drenaje y el trail. Reset
tiene prioridad sobre el drenaje: un aborto no se trata como un fin
normal. Esto es un contrato de simulación, no una secuencia eléctrica.

## Prueba de integración

```sh
pixi run --locked make -C init_sequencer rom
pixi run --locked make -C mipi_tx test
pixi run --locked make -C mipi_tx sim
pixi run --locked make -C mipi_tx wave
```

El [banco](TB/mipi_tx_TB.v) usa RTL real de `MIPI_TX`, `INIT_SEQUENCER`
y `VIDEO_SOURCE`. El único bloque funcional modelado es el
[PHY](TB/mipi_tx_phy_model.v), que mantiene `READY` y `LOCK` altos fuera
de reset. El `Makefile` llama a `make -C init_sequencer rom` como
dependencia para generar la tabla del RTL. El comparador lee el
`init_mem.hex` original, sin versionar otra copia de sus bytes.

- Reconstruye D0 en LPDT (marcas y espacios, LSB primero) y contrasta
  los 204 bytes DSI con la ROM, aparte del selector `87` de cada paquete.
  Comprueba el retorno a LP11 sin bytes adicionales, las 18 pausas desde
  el `↑` que lee `INIT_DONE_TX` (15 de 9 ms, 2 de 65 ms, 1 de 7 ms) y
  la ausencia de vídeo hasta END.
- Reconstruye dos ráfagas consecutivas desde `TAKEN_WORD`: SoT, cabecera
  `3E 70 08 13`, las ocho barras (2160 bytes RGB en orden D0/D1) y
  CRC `EE 7E` de referencia bit a bit sobre el payload consumido.
  Comprueba exactamente 1080 `↓` con `VID_RD` por línea, un período
  `C_LINE` de LP01 a LP01 y que no haya consumo después del CRC.
- En la tercera línea aplica el reset común con 17 lecturas realizadas.
  Comprueba LP11 y la limpieza de la transacción en `↓`; verifica que
  se repite toda la inicialización y que la nueva ráfaga arranca en
  SoT/W0 y vuelve a leer desde P0, sin reanudar la parcial.

`test` no genera ondas. Ejecuta dos perfiles lógicos, no físicos:

| Perfil | `CLK_BYTE_HZ` | `LP_DIV` | `T_LPX/PREP/ZERO/TRAIL` | `C_LINE` |
|---|---:|---:|---:|---:|
| p0 | 1000 | 1 | 1/1/1/1 | 1091 |
| p1 | 5000 | 3 | 5/3/7/4 | 1166 |

`sim` usa p1 por defecto (`SIM_PROFILE=0` selecciona p0), corre las mismas
comprobaciones con `+waves` y abre `build/mipi_tx/mipi_tx_TB.fst` en
GTKWave. `wave` abre el último FST sin volver a compilar.

## Pendiente para el PHY físico

- Fijar y comprobar PLL, frecuencias, serialización DDR, orden de bits y
  fase entre ambos carriles y el reloj reenviado. Acordar su modo, adelanto
  y retención bajo `CLK_REQ`, sin detener `CLK_BYTE`.
- Acordar `READY`/`LOCK` en el dominio `CLK_BYTE` y la protección ante
  pérdida de disponibilidad o de reloj durante la ráfaga.
- Verificar el flanco de carga real, el drenaje del CRC al retirar `HS_REQ`,
  los tiempos LP/HS de entrada, zero, trail y retorno a LP11, y los
  caminos de medio ciclo.
- Revisar la red de pads y los niveles y habilitaciones antes de conectar
  o probar un panel. Esta simulación no verifica el PHY Gowin ni la
  recepción por el LCD.
