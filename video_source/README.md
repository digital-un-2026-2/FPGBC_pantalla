# VIDEO_SOURCE — barras RGB888

[Diagrama editable: Flujo y Datapath](docs/VIDEO_SOURCE.drawio).
[`video_source`](src/video_source.v) conecta
[`VIDEO_TIMING`](src/video_timing.v), [`V_COUNT`](src/v_count.v) y
[`VIDEO_MEM`](src/video_mem.v). Entrega solo los 2160 bytes de píxeles de
una línea, no la cabecera, el SoT ni el CRC. No está conectado al TOP ni al PHY.

## Interfaz

| Señal | Dirección y flanco |
|---|---|
| `CLK_BYTE` | Reloj común, disponible también en reposo y reset. |
| `RST_BYTE` | Reset común síncrono activo en 1: cubrir un ↑ y el ↓ siguiente. En la fuente, ↓ reinicia el datapath y el nivel de reset inhibe la oferta y el avance. |
| `INIT_DONE` | Entrada desde `INIT_SEQUENCER`: nivel publicado tras END (incluido el WAIT final), sostenido hasta el reset común. No es `INIT_DONE_TX`. |
| `VID_REQ`, `VID_LINE_RDY` | Salidas hacia `LINK_FSM`, que las lee en ↑. Solicitud y garantía de disponer de la línea completa, sin acuse de admisión. |
| `VID_RD` | Entrada desde `HS_PACKER`: nivel alto en cada uno de los 1080 ↓ de carga; no se cuentan transiciones de la señal. |
| `VID_WORD[15:0]` | Salida hacia `HS_PACKER`: con `VID_RD=1`, se consume la palabra ya estable antes de ↓. `[7:0]` es el primer byte (D0), `[15:8]` el segundo (D1). |

`VIDEO_TIMING` es combinacional, sin FSM ni temporizador. Con
`INIT_DONE && !RST_BYTE && ADDR==0` sostiene `VID_REQ` y `VID_LINE_RDY`
altas, con la palabra inicial `P0` disponible. El patrón inmutable
reserva toda la línea sin un buffer ni una escritura que pueda alterarla.
El enlace admite solo en `LINE_WAIT`, con `READY && LOCK` y sin
`INIT_REQ` prioritario. Aunque ya se haya admitido, la oferta persiste
durante la entrada HS y la cabecera. La primera lectura es la evidencia
de inicio; solo ella retira la oferta al mover la dirección.

`ADV = INIT_DONE && !RST_BYTE && VID_RD`: no depende de la oferta y no
interrumpe la carga una vez iniciada. `V_COUNT` actualiza en ↓ con `ADV`:
`ADDR[10:0]` recorre las palabras 0…1079 y `RGB_PHASE[1:0]` recorre 0…2
para empacar dos píxeles cada tres palabras. Ambos vuelven a 0 con el
último consumo, sin usar reset. Sin `ADV` conservan su valor. Con el
reset común se descarta toda línea parcial; la fuente no deduce abortos
ni hace reintentos si el enlace no llega a leer.

Los comparadores de `VIDEO_MEM` seleccionan una de ocho barras de
90 píxeles (135 palabras) a partir de `ADDR`; no hay memoria de cuadro,
PSRAM ni registro de salida. El raster `R0 G0 B0 R1 G1 B1 …` se reagrupa
en `(D0,D1) = (R0,G0), (B0,R1), (G1,B1), …`. Las líneas repiten el
mismo patrón y no se fija una cuenta, sincronismo ni receta vertical.

## Flancos acordados

`↓0` es W0 de cabecera en la numeración de
[LINK_FSM](../mipi_tx/link_fsm/README.md#tabla-de-flancos-hs), con `↑n`
entre `↓n` y `↓(n+1)`. `Pn` es una palabra de píxeles: `P0` corresponde
a W2, no a W0 del paquete. Se indica qué se muestrea antes del flanco y
qué se publica después.

| Flanco | Vecino: muestreo o control | VIDEO_SOURCE: dato y avance |
|---|---|---|
| Reset (↑ y ↓) | Los vecinos abortan con el mismo reset. | En reposo con `VID_REQ=VID_LINE_RDY=ADV=0`; en ↓ vuelve al índice y fase 0. |
| Antes de `↑i`, luego `↑i` | `INIT_SEQUENCER` publica `INIT_DONE` tras `↑i` al llegar a END. | Antes no solicita ni avanza. Al subir `INIT_DONE`, ofrece la línea con `P0` ya estable para una admisión posterior. |
| ↑ de espera o `↑a` de admisión | `LINK_FSM` arbitra en `LINE_WAIT`; no acusa la admisión. | Conserva ambas salidas altas, `ADDR=0` y `P0`, incluso si se demora o gana LP. No avanza por admitir. |
| `↓0`, `↓1` → `↑1` | W0 y W1 son cabecera. El packer sube `VID_RD` después de `↓1`. | `P0` ya está estable y no cambia al subir `VID_RD`. |
| `↓2` | Primera lectura: `P0` (W2). | Después publica `P1`, con índice y fase 1; bajan `VID_REQ` y `VID_LINE_RDY`. |
| `↓3…↓1080` | Lee `P1…P1078` en ↓ consecutivos. | Cada ↓ con `VID_RD=1` mueve el índice después de que se haya tomado la palabra anterior. |
| `↓1081` → `↑1081` | Lectura 1080: `P1079`. `VID_RD` baja después del ↓; el enlace sigue en `DATA` en ↑. | La última lectura vuelve al índice y fase 0. Publica `P0` y rearma la oferta para la siguiente línea. |
| `↓1082`; luego `↑a′` | CRC sin `VID_RD`; cierre y espera residual hasta la siguiente admisión. | Conserva la nueva oferta. Sin bloqueos, `↑a′` ocurre `C_LINE` ciclos después de `↑a`. |

La espera residual la gestiona solo `LINK_FSM`. La fuente no añade
otro periodo ni fija porches. Al integrar, hay que verificar los
caminos `INIT_DONE → ADV` (↑→↓) y `ADDR → VID_REQ/VID_LINE_RDY` (↓→↑),
así como `ADDR/RGB_PHASE → VID_WORD` y `VID_RD → ADV` (↓→↓).
`VID_WORD` no depende combinacionalmente de `VID_RD`.

## Pruebas aisladas

```sh
pixi run --locked make -C video_source test
pixi run --locked make -C video_source sim
pixi run --locked make -C video_source wave
```

El banco solo instancia `video_source`. Modela el nivel `INIT_DONE`,
la admisión en ↑ y el turno de `C_LINE` del enlace, y la ventana de
lectura del packer en ↓. Usa `C_LINE=1091` (margen mínimo del
modelo de `LINK_FSM`) y `1166` (perfil de prueba con otra entrada HS).
No comprueba el CRC ni los tiempos físicos. La contención con `INIT_REQ`
después de END es un estímulo sintético de prioridad, no una secuencia
normal de la ROM.

En ambos perfiles comprueba bloqueo antes de `INIT_DONE` aun con
`VID_RD` espurio, retención durante más de un periodo y ante `LOCK`
bajo o prioridad LP, y dos líneas consecutivas con 1080 lecturas
exactas separadas por un solo `C_LINE` entre admisiones. Verifica los
2160 bytes de cada línea por posición de píxel y orden de carril,
y el índice en cada flanco para detectar saltos incluso entre palabras
iguales de una barra. Prueba reset con una petición pendiente y en medio
de la carga, y el reinicio desde `P0` tras un nuevo `INIT_DONE`.

`test` no genera ondas. `sim` usa el perfil de 1166 ciclos por defecto
(`SIM_PROFILE=0` elige el de 1091), guarda
`build/video_source/video_source_TB.fst` y lo abre con GTKWave.
`wave` lo reabre sin recompilar.
