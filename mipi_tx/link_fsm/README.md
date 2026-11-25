# LINK_FSM + TIMER — control lógico de MIPI_TX

[Diagrama editable: Flujo, Datapath y FSM](docs/LINK_FSM.drawio).
[`link_fsm`](src/link_fsm.v) arbitra paquetes LPDT y líneas HS e
instancia un solo [`link_fsm_timer`](src/link_fsm_timer.v). No está
conectado al TOP ni habilita drivers físicos. Las referencias son
`MIPI_TX_componentes.pdf`, las dos páginas de `MIPI_TX_bloques.pdf` y
`MIPI_TX_adopcion.md` de `digital_UN/MIPI_LCD/Docs`. Los flancos de los
vecinos siguen [LP_TX](../lp_tx/README.md#flancos-acordados-del-primer-paquete),
[HS_PACKER](../hs_packer/src/hs_packer.v) y
[PHY_IF](../phy_if/README.md#flancos-acordados).

## Interfaz y admisión

`CLK_BYTE` es común; `RST_BYTE` es síncrono, activo en 1, y debe cubrir
un ↑ y el ↓ siguiente. `CLK_BYTE` tiene que estar disponible para estos
flancos aunque `CLK_REQ=0`. Se enmascaran combinacionalmente los controles
a reposo durante reset. En ↑ se aborta la transacción y se vuelve a
`LINE_WAIT`; en ↓ el contador vuelve a cero. No se emite un fin por
reset ni se reanuda una transacción abortada.

- **LP:** `INIT_READY` es un **nivel de disponibilidad para un paquete**:
  vale 1 solo en `LINE_WAIT`, con `READY && LOCK` y sin reset. Se acepta
  `INIT_REQ` en el ↑ en que ambos están a 1. El secuenciador presenta
  un primer BYTE válido con la petición, mantiene la petición hasta
  el ↑ de aceptación y luego la retira. `LINK_FSM` no lee el BYTE ni
  `INIT_LAST`. `LP_START` dura un ciclo, de ↑ a ↑; `LP_TX` lo lee en el
  último de esos dos flancos. `SEL_OUT=01` se sostiene hasta leer
  `LP_DONE` en ↑. Entonces `INIT_DONE_TX` sube durante un ciclo para
  indicar **fin de ese paquete**, no de toda la inicialización. El
  secuenciador lo lee en el ↑ siguiente, con `INIT_READY` aún bajo en
  ese flanco. `INIT_NEXT` va directamente de `LP_TX` a
  `INIT_SEQUENCER` y solo confirma la captura de un BYTE. Los WAIT de
  7/9/65 ms, y la habilitación de vídeo después del WAIT final, quedan
  fuera de este módulo.
- **HS:** en `LINE_WAIT` se acepta una línea en ↑ solo con `VID_REQ &&
  VID_LINE_RDY && READY && LOCK` y sin reset; si además hay `INIT_REQ`,
  gana LP. No se encolan pulsos. Mientras no haya línea lista se
  conserva LP11 y no hay `PK_START`. Tras la aceptación, la fuente
  garantiza las 1080 palabras de píxeles sin pausas; los cambios de
  `VID_REQ` o `VID_LINE_RDY` no interrumpen la ráfaga. La fuente consume
  palabras por `VID_RD` de `HS_PACKER`; no se añade un acuse de línea.
- **PHY, por acordar:** para probar aisladamente, `LOCK` indica reloj
  válido, y `READY` indica que se puede iniciar desde reposo en LP o
  reservar una ráfaga HS completa. Ambos deben estar ya en el dominio
  de `CLK_BYTE` al llegar a `LINK_FSM`. No se presupone un `READY` que
  dependa de haber activado `HS_REQ`/`CLK_REQ`, ni se usa como `VALID`
  por byte: cualquiera de esos significados requeriría revisar esta
  propuesta. Una pérdida de `LOCK` o de disponibilidad en plena
  ráfaga no se resuelve pausando el enlace; la protección del PHY y
  el aborto por reset común se acuerdan en la integración.

## Control por estado

Las transiciones se deciden dentro del bloque de ↑, como en
[`phy_control.v`](../../motor_phy/src/phy_control.v); no hay bloque
combinacional de `next_state`. Las salidas son combinacionales, con
valores por defecto: `SEL_OUT=00`, `LP_FORCE=11`, y los demás controles
en 0. Un estado inválido conserva esos valores y vuelve a `LINE_WAIT`
en el siguiente ↑. Se muestran abajo las excepciones; `LP_FORCE` solo
afecta a D0 y D1 con `SEL_OUT=10` y está en orden `{P,N}`.

| Estado | `SEL_OUT` | `LP_FORCE` | `HS_REQ` / `CLK_REQ` propuestos | Control y avance |
|---|:---:|:---:|:---:|---|
| `LINE_WAIT` | `00` | — | `0 / 0` | `INIT_READY=READY && LOCK`; arbitra en ↑ o sigue en reposo. |
| `LP_BEGIN` → `LP_RUN` | `01` | — | `0 / 0` | `LP_START=1` solo en `LP_BEGIN`; `LP_RUN` espera `LP_DONE`. |
| `LP_ACK` | `00` | — | `0 / 0` | `INIT_DONE_TX=1`; al siguiente ↑ vuelve a `LINE_WAIT`. |
| `LP01` | `10` | `01` | `0 / 1` | Carga `T_LPX`. |
| `LP00_PREP` | `10` | `00` | `0 / 1` | Carga `T_PREP` dentro de LP00. |
| `LP00_ZERO` | `10` | `00` | `1 / 1` | Carga `T_ZERO` dentro de LP00; se pide al PHY el cero HS, no bytes. |
| `SOT` | `11` | — | `1 / 1` | `SOT_EN=1` para un ↓, `PK_START=0`. |
| `DATA0` → `DATA` | `11` | — | `1 / 1` | `SOT_EN=0`; `PK_START=1` solo en `DATA0`. `DATA` espera `PK_DONE`. |
| `EOT` | `10` | `00` | `0 / 1` | Quita la selección de palabras tras leer `PK_DONE`. Carga `N_EOT`. |
| `LP11` | `00` | — | `0 / 0` | Carga `T_GAP`, luego un ↑ lleva a `LINE_WAIT`. |

`SEL_OUT`: `00` reposo, `01` LPDT, `10` LP forzado, `11` HS. Es una
selección lógica, no una habilitación física de pines. Como propuesta,
`CLK_REQ` pide reloj reenviado desde `LP01` hasta el final de `EOT`;
no inicia ni detiene `CLK_BYTE`. El PHY tendría que asegurar que el
reloj reenviado preceda al SoT y respete el tiempo de salida después
del enlace de datos. El adelanto, la retención al retirar `CLK_REQ` y
el modo continuo o por ráfaga quedan pendientes de acuerdo.

**Propuesta de cierre para el modelo:** el PHY consume en ↓ lo que ya
estaba registrado en `PHY_IF` antes del flanco. Si `z` es el primer ↓
de `LP00_ZERO`, muestrea allí el ascenso de `HS_REQ`; genera el nivel
HS de entrada e inicia los bytes en `z + T_ZERO + 1` (el ↓ posterior
a la captura de SoT por `PHY_IF`). `T_ZERO` mide aquí la fase de
control; el cero físico también depende de la latencia de ese traspaso.
Al muestrear el descenso de `HS_REQ` en `↓1083`, el PHY aún toma el
CRC registrado por `PHY_IF` en `↓1082` y lo serializa durante ese
ciclo. No toma más palabras:
ni el `00/00` que aparece al salir de la selección HS ni el W0 que
reaparece al volver el packer a reposo. El modelo pasa a trail al
terminar el CRC, en `↓1084`, no al leer `PK_DONE`. Esto exige una
latencia de consumo acordada y que la caída de `HS_REQ` **no** apague
de inmediato los drivers HS. No se añade `VALID` ni otro puerto.
Quedan pendientes el flanco real de carga del serializador, la
duración del drenaje y el patrón y tiempos físicos de zero, trail
y retorno a LP11. EoT aquí es cierre del enlace, no un paquete EoTp.

## Un solo temporizador

`STATE[3:0]` y el bit interno `ENTER_T` se actualizan en ↑. Al entrar
en un estado temporizado, `ENTER_T=1`; si no se entra en otro estado
temporizado en el próximo ↑, baja. El decodificador presenta `LOAD_T`
desde ese bit y selecciona el límite `N`. Dos cargas en fases
consecutivas pueden dejar `LOAD_T=1` en dos ↓ seguidos: cada ↓ carga
el límite de su propia fase. No se recarga mientras se permanece
en la misma fase.

El único contador `CNT[W-1:0]` carga `N-1` en el primer ↓ de la
fase, decrementa en los siguientes ↓ si `CNT_EN=1` y `CNT!=0`, y
se satura en cero. `CNT_EN=1` solo en las fases temporizadas. Reset
tiene prioridad sobre la carga y la carga sobre el decremento.
`TIMER_DONE=(CNT==0)` es combinacional; la FSM
lo lee solo en ↑ de un estado temporizado, después del primer ↓ de
ese estado. Para `N=1`, ese primer ↓ registra la fase en `PHY_IF`
y carga 0. El ↑ siguiente avanza y el próximo ↓ ya registra la
siguiente fase: **un ciclo completo**, no cero ni dos.

Los parámetros `T_LPX`, `T_PREP`, `T_ZERO`, `T_TRAIL` y `C_LINE` se
expresan en ciclos enteros de `CLK_BYTE`, no en tiempos físicos
aprobados. Los cuatro límites `T_*` valen 1 por defecto y
`C_LINE=1091`, solo para simulación. El ancho `W` basta para representar el
mayor límite, incluido `N_EOT` (`W = max(1, ceil(log2(N_max + 1)))`).
La carga se reutiliza para `T_LPX`, `T_PREP`, `T_ZERO`,
`N_EOT = N_DRAIN + T_TRAIL` y `T_GAP`. `N_DRAIN=1` en la propuesta
de cierre anterior: el primer ciclo de EoT todavía contiene el CRC
en el serializador y los `T_TRAIL` ciclos restantes son de trail.
No se necesita otro contador ni convertir `PK_DONE` en un fin físico.

**Espera residual:** desde la primera captura de LP01 por `PHY_IF`,
`C_ACTIVE = T_LPX + T_PREP + T_ZERO + 1 + 1083 + N_EOT` ciclos hasta
entrar en LP11. Para un período objetivo `C_LINE`, se usa
`T_GAP = C_LINE - C_ACTIVE - 1`, con `T_GAP >= 1`. El `−1` reserva el
primer ciclo en `LINE_WAIT` (su primer ↑ entra desde `LP11`, el
siguiente ya puede aceptar). La simulación rechaza fases menores
que uno y presupuestos con menos de dos ciclos libres. Si todo
está listo, LP01 a LP01 suma exactamente `C_LINE`: no se espera otra
línea completa después de la ráfaga. Si no, `LINE_WAIT` prolonga
LP11 hasta una petición admitida, sin volver a cargar el período.
Como referencia de presupuesto, `21,20 µs` medidos y `55 MHz`
**candidatos** dan 1166 ciclos; 1084 son SoT y paquete, y los otros
82 deben cubrir toda la entrada, el cierre y la espera. No son
porches ni tiempos físicos medidos.

## Tabla de flancos LP

`↑n` está entre `↓n` y `↓(n+1)`. `D=LP_DIV`, `↓0` es la primera
publicación de LP10 por `LP_TX`. Para anclar el cierre se usa el
primer paquete de la ROM, de ocho BYTE tras el selector `87`.

| Flanco | `LINK_FSM` | `INIT_SEQUENCER`, `LP_TX` y `PHY_IF` |
|---|---|---|
| Antes de `↑−2` | `LINE_WAIT`, `SEL_OUT=00`, `INIT_READY=1` si `READY && LOCK`. | `INIT_REQ=1`, primer BYTE `29`, `INIT_LAST=0`, ya estables. |
| `↑−2` | Lee `INIT_REQ && INIT_READY`; entra en `LP_BEGIN`, presenta `LP_START=1`, `SEL_OUT=01`, `INIT_READY=0`. | El secuenciador puede retirar `INIT_REQ`; no retira el BYTE. `LP_TX` aún no lee el nuevo `LP_START`. |
| `↑−1` | Entra en `LP_RUN`; baja `LP_START`, mantiene `SEL_OUT=01`. | `LP_TX` lee el 1 previo de `LP_START` y comienza `ENTRY`. |
| `↓0`, `↓D`, `↓2D`, `↓3D` | Sostiene `SEL_OUT=01`. | `LP_TX` publica `10→00→01→00`; `PHY_IF` registra cada valor en el ↓ siguiente. En `↓0` aún captura LP11. |
| `↓4D`; luego `↓L` / `↑L` por BYTE | No interviene en el avance de la ROM. | `LP_TX` carga `87` en `↓4D` sin `INIT_NEXT`. Por cada BYTE DSI carga y publica en `↓L`, sube `INIT_NEXT`; el secuenciador lo lee en `↑L` y avanza una sola vez. `PHY_IF` captura la primera marca en `↓(L+1)`. |
| `↓132D` / `↑132D`; `↑(148D−1)` | Sigue en `LP_RUN`. | Carga el último BYTE `CA`; `INIT_NEXT` lleva la ROM al WAIT de 9 ms. `LP_TX` lee `INIT_LAST=1` en la frontera siguiente y cierra sin emitir el argumento de WAIT. |
| `↓148D`, `↓149D`, `↓(149D+1)` | Sigue seleccionado LPDT. | `LP_TX` publica el `10` de salida y después `11`; `PHY_IF` captura `10` en `↓(148D+1)` y LP11 en `↓(149D+1)`. |
| `↓150D` | No cambia la selección ni registra un fin en ↓. | `LP_TX` publica `LP_DONE=1` tras el resguardo; `PHY_IF` ya tiene LP11, o lo captura en ese mismo ↓ si `D=1`. |
| `↑150D`, luego `↓(150D+1)` | Lee `LP_DONE`; entra en `LP_ACK`, presenta `INIT_DONE_TX=1` y vuelve a `SEL_OUT=00`. | `LP_TX` vuelve a `IDLE` en ↑ y baja `LP_DONE` en el siguiente ↓. `PHY_IF` sigue capturando LP11. |
| `↑(150D+1)` | Vuelve a `LINE_WAIT`; baja `INIT_DONE_TX` y puede volver a anunciar `INIT_READY`. | El secuenciador lee el 1 previo de `INIT_DONE_TX` e inicia su WAIT; aún no presenta el BYTE del paquete siguiente. |

## Tabla de flancos HS

Se usa la numeración de `PHY_IF`: `↓0` captura W0 y `↑n` está
entre `↓n` y `↓(n+1)`. El control presentado en ↑ llega estable
al ↓ siguiente. Las capturas de SoT/W0/CRC son las del contrato lógico.
La última columna describe el **modelo propuesto** de consumo, no
un PHY validado.

| Flanco | `LINK_FSM` y carga de `TIMER` | Captura lógica por `PHY_IF` / `HS_PACKER` | Consumo en el PHY (propuesta) |
|---|---|---|---|
| ↑ en `LINE_WAIT`, si falta alguna condición de HS y no hay LP admisible | Espera con `SEL_OUT=00`, sin SoT ni `PK_START`. | El siguiente ↓ sigue en LP11; el packer no avanza. | Sin ráfaga. |
| ↑ de admisión y primer ↓ de `LP01` | Con `VID_REQ && VID_LINE_RDY && READY && LOCK`, sin `INIT_REQ`, pone `SEL_OUT=10`, `LP_FORCE=01`, `CLK_REQ=1`. Carga `T_LPX−1` en ↓. | Primer LP01 registrado en D0/D1. | Preparación del reloj reenviado, por acordar. |
| ↑ al terminar `T_LPX`, luego ↓ | `LP00_PREP`: `LP_FORCE=00`, `HS_REQ=0`; carga `T_PREP−1`. | Primer LP00 registrado en D0/D1. | Aún no consume HS. |
| ↑ al terminar `T_PREP`, luego `↓z` | `LP00_ZERO`: mantiene `SEL_OUT=10`, `LP_FORCE=00`, eleva `HS_REQ`; carga `T_ZERO−1`. | Salidas lógicas LP00, sin palabra HS. | Muestrea la petición; prepara cero HS. |
| `↑−2` / `↓−1` (`z + T_ZERO`) | Al terminar `T_ZERO`, `SOT`: `SEL_OUT=11`, `SOT_EN=1`, `PK_START=0`. | Captura `B8 / B8`; W0 ya está preparada y el packer no avanza. | Aún no toma el nuevo registro de SoT. |
| `↑−1` / `↓0` | `DATA0`: retira `SOT_EN` y presenta `PK_START=1`, sin salir de `SEL_OUT=11`. | Captura W0 `3E / 70` justo después de SoT, sin hueco; el packer lee `PK_START` y pasa a W1. | Consume el SoT ya registrado. |
| `↑0` / `↓1`, luego `↓2…↓1081` | `DATA`: baja `PK_START`, sigue `SEL_OUT=11`. | W1 `08 / 13`, luego 1080 palabras de píxeles, una por ↓. | Consume en cada ↓ la palabra registrada en el anterior. |
| `↓1082` | Todavía `DATA`, mantiene HS. | Captura W1082 `CRC_L / CRC_H`; el packer publica `PK_DONE=1` después de ↓. | Consume W1081. |
| `↑1082` / `↓1083` | Lee `PK_DONE` en ↑. Entra en `EOT`: `SEL_OUT=10`, `LP_FORCE=00`, retira `HS_REQ`, mantiene `CLK_REQ`; carga `N_EOT−1` en ↓. | Captura `00 / 00` **sin dato** fuera de HS; el packer vuelve a preparar W0, no lo transmite. | Toma el CRC que aún estaba registrado antes de `↓1083` y lo serializa completo durante este ciclo. |
| `↓1084` hasta el último ↓ de `EOT` | Continúa EoT, sin seleccionar otra palabra; `TIMER` recorre los `T_TRAIL` ciclos restantes. | Ninguna palabra adicional. | Trail tras el último bit del CRC; no serializa `00 / 00`. |
| ↑ tras `EOT`, luego ↓ | `LP11`: `SEL_OUT=00`, retira `CLK_REQ`, carga `T_GAP−1`. | Registra LP11; el packer está en reposo. | Salida a LP y tiempos del reloj por acordar. |
| ↑ tras `T_GAP`, luego ↓ | Vuelve a `LINE_WAIT`; la siguiente admisión puede ser en el próximo ↑. | Un ↓ más de LP11 como mínimo. | Sin ráfaga hasta una nueva admisión. |

## Pruebas aisladas

```sh
pixi run --locked make -C mipi_tx/link_fsm test
pixi run --locked make -C mipi_tx/link_fsm sim
pixi run --locked make -C mipi_tx/link_fsm wave
```

`test` ejecuta el mismo banco en dos perfiles, sin generar ondas:

- **p0:** `T_LPX/T_PREP/T_ZERO/T_TRAIL=1/1/1/1`, `T_GAP=1`,
  `C_LINE=1091`, `LP_DIV=1` en el modelo LP_TX.
- **p1:** `5/3/7/4`, `T_GAP=61`, `C_LINE=1166`, `LP_DIV=3` en el
  modelo. Son valores de prueba, no una propuesta de ajuste físico.

El banco instancia solo `link_fsm` con su temporizador. Los vecinos
son modelos de los flancos: comprueba el paquete LP, el retardo de
`PHY_IF` y los pulsos de admisión y de fin; el reposo sin línea lista;
SoT y W0 consecutivos; las 1083 palabras y el cierre con un CRC
de prueba; y el período entre dos inicios de línea. Comprueba el
aborto por reset durante datos HS, con `LP_DONE` pendiente y con
temporizador activo, y que se puedan volver a enviar LP y HS.
No verifica la serialización de bits ni los tiempos de los drivers.

`sim` utiliza p1 por defecto (`SIM_PROFILE=0` selecciona p0), guarda
`build/link_fsm/link_fsm_TB.fst` y lo abre en GTKWave. `wave` lo reabre
sin recompilar.

## Pendientes para integración

- Conectar la admisión LP por paquete y su fin con `INIT_SEQUENCER`;
  mantener `INIT_NEXT` directo de `LP_TX` al secuenciador y el WAIT
  final antes de habilitar vídeo. Confirmar que la fuente reserva
  la línea completa al aceptar `VID_REQ && VID_LINE_RDY`.
- Acordar qué garantizan `READY` y `LOCK`, su sincronización a
  `CLK_BYTE`, y el comportamiento ante pérdida de disponibilidad.
  Coordinar el adelanto y la retención del reloj reenviado con `CLK_REQ`.
- Acordar el flanco en que el PHY consume los bytes registrados, el
  efecto diferido de la caída de `HS_REQ`, la latencia real del CRC
  y el inicio de trail sin truncar ni añadir bytes. Validar los
  límites físicos de las fases LP/HS y los caminos de medio ciclo
  antes de usar el enlace en placa.
