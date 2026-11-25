# PHY_IF — adaptador lógico de MIPI_TX

[Datapath editable](docs/PHY_IF.drawio). `OUT_SEL`, `LP_MUX` y `HS_MUX`
son combinacionales. Las salidas usan dos instancias de
[`reg_0`](../../motor_lpdt/src/reg_0.v) con carga en cada `negedge CLK_BYTE`.
No hay FSM, control de drivers ni lógica del PHY físico.

## Selección y reset

El contrato de `MIPI_LCD` no fija la codificación de `SEL_OUT`, el índice LP de
cada par ni los valores de reset. Estas son las convenciones adoptadas para
`PHY_IF`; los bloques vecinos deben respetarlas al integrar.

| `SEL_OUT[1:0]` | LP D0 | LP D1 | LP CLK | HS D0 / D1 |
|---|---|---|---|---|
| `00` Reposo | LP11 | LP11 | LP11 | `00 / 00` (sin dato) |
| `01` LPDT | `LP_D0` | LP11 | LP11 | `00 / 00` (sin dato) |
| `10` Forzado | `LP_FORCE` | `LP_FORCE` | LP11 | `00 / 00` (sin dato) |
| `11` HS | LP00 | LP00 | LP11 | `B8 / B8` si `SOT_EN=1`, si no `WORD[7:0] / WORD[15:8]` |

`LP_D0` y `LP_FORCE` están en orden `{P,N}`; `LP_P[2:0]` y `LP_N[2:0]`,
en orden `{CLK,D1,D0}`. Para la entrada a HS, `LINK_FSM` selecciona
forzado con LP01 → LP00. `RST_BYTE` es síncrono y activo en 1; tiene
prioridad en `negedge` y carga `LP_P = LP_N = 3'b111` y los dos bytes
HS en `8'h00`. Son niveles lógicos, no habilitaciones de drivers.

## Flancos acordados

`↓0` es el `negedge` en que `HS_PACKER` acepta `PK_START`. `LINK_FSM`
presenta sus controles desde el `posedge` anterior. `PHY_IF` captura
lo que estaba estable **antes** de cada `negedge`, no el nuevo `WORD`
publicado por el packer después de ese flanco.

| Flanco | Control estable antes de ↓ | `HS_PACKER`: antes → después de ↓ | HS registrado D0 / D1 |
|---|---|---|---|
| ↓−1 | HS, `SOT_EN=1`, `PK_START=0` | W0 preparada (`0x703E`); no avanza | `B8 / B8` |
| ↓0 | HS, `SOT_EN=0`, `PK_START=1` | W0 (`0x703E`) → W1; acepta el inicio | `3E / 70` |
| ↓1 | HS, `SOT_EN=0`, `PK_START=0` | W1 (`0x1308`) → W2 | `08 / 13` |
| ↓2…↓1081 | HS, `SOT_EN=0` | Una palabra de píxeles por ↓ | Byte bajo / alto |
| ↓1082 | HS, `SOT_EN=0` | W1082 (CRC) → `PK_DONE=1` | CRC bajo / alto |
| ↓1083 | Fuera de HS en el modelo | Sin palabra → vuelve a presentar W0 | `00 / 00` (sin dato) |

`PK_START` y `PK_DONE` solo enlazan `LINK_FSM` con `HS_PACKER`.
Para integrar:

- `LINK_FSM` debe retirar `SOT_EN` y activar `PK_START` en el ↑ entre
  ↓−1 y ↓0, y leer `PK_DONE` en el ↑ entre ↓1082 y ↓1083.
- Si `LP_TX` cambia `LP_D0` en ↓, el nuevo símbolo llega a las salidas
  en el ↓ siguiente. Alinear `SEL_OUT` con el primer y último símbolo
  que debe llegar a D0; el reset común debe cubrir ambos flancos.
- Falta acordar cuándo consume el PHY los bytes ya registrados, cómo
  coordina las habilitaciones y la rama CLK, y cómo realiza EoT/T_TRAIL
  después de consumir el CRC. `00 / 00` fuera de HS no es un byte del paquete.

## Pruebas aisladas

```sh
pixi run --locked make -C mipi_tx/phy_if test
pixi run --locked make -C mipi_tx/phy_if sim
pixi run --locked make -C mipi_tx/phy_if wave
```

El banco modela los controles en `posedge` y los productores LP y HS en
`negedge`. Verifica reposo, LPDT, LP forzado, las salidas solo en `negedge`,
SoT seguido de W0/W1, el orden de los bytes durante toda la línea y reset
en plena ráfaga. El CRC es un patrón de prueba: solo se verifica su paso
por los dos carriles. `test` no genera ondas; `sim` genera un FST en
`build/phy_if/` y lo abre en GTKWave; `wave` reabre el último volcado.
