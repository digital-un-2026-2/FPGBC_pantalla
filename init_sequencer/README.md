# INIT_SEQUENCER — inicialización desde ROM

[Diagrama editable: Flujo, Datapath y FSM](docs/INIT_SEQUENCER.drawio).
El módulo agrupa `CTRL`, `A_COUNT`, `D_COUNT` e `INIT_MEM` como bloques
separados, fuera de `MIPI_TX`. El diseño de inicio anterior sirve de
referencia visual; el handshake sigue los flancos acordados en
[LINK_FSM](../mipi_tx/link_fsm/README.md#tabla-de-flancos-lp) y
[LP_TX](../mipi_tx/lp_tx/README.md#flancos-acordados-del-primer-paquete).
No se conecta el TOP ni se define aquí el reset físico del panel.

## Interfaz

| Señal | Dirección | Contrato |
|---|---|---|
| `CLK_BYTE` / `RST_BYTE` | Entradas comunes | Reloj activo también durante reset y las pausas. Reset lógico síncrono activo en 1: cubrir un ↑ y el ↓ siguiente. |
| `INIT_REQ` | A `LINK_FSM` | Nivel con el primer BYTE estable; se mantiene hasta el ↑ que acepta `INIT_REQ && INIT_READY`. No se reemite por byte. |
| `INIT_READY` | De `LINK_FSM` | Disponibilidad para un paquete. No avanza la ROM. |
| `INIT_BYTE[7:0]` / `INIT_LAST` | A `LP_TX` | Lectura combinacional: `INIT_BYTE=ARG`, `INIT_LAST=LAST`. Los BYTE tienen LAST=0; WAIT tiene LAST=1. Aunque ARG de WAIT esté en el bus, LP_TX lo ignora y cierra después del último BYTE. Fuera de la transacción o durante reset no hay consumo. |
| `INIT_NEXT` | De `LP_TX` | Un pulso tras cada ↓ que carga un BYTE DSI, válido en el ↑ intermedio. No pulsa por el selector `87` ni por WAIT. |
| `INIT_DONE_TX` | De `LINK_FSM` | Pulso leído en ↑ tras el cierre de un paquete. Autoriza comenzar su WAIT. |
| `INIT_DONE` | Hacia `VIDEO_TIMING` (integración posterior) | Nivel que habilita el vídeo solo tras leer END; se mantiene hasta reset. No es `INIT_DONE_TX`. |

## Datapath y control

- **CTRL (↑):** `STATE[2:0]` va a `READ` y `ADV_BYTE` (1 bit) a 0 con
  `RST_BYTE`. Se evalúan en cada ↑; no hay una habilitación global ni
  un bloque de `next_state` separado. Las salidas de CTRL son
  combinacionales, a 0 por defecto y durante reset. `READ` verifica
  el primer BYTE y pasa a `REQUEST`. La admisión lleva a `TX` y baja
  `INIT_REQ` sin mover la dirección.
- **A_COUNT (↓):** `ADDR[7:0]` se reinicia a 0 con `RST_ALL=RST_BYTE`,
  y solo avanza con `INC_A` (tope 222). En `TX`, CTRL carga `ADV_BYTE`
  en cada ↑ con la condición `BYTE && INIT_NEXT`; fuera de `TX` lo
  limpia. `INC_A` se decodifica de `ADV_BYTE` en `TX`, no del `INIT_NEXT`
  vivo, que puede bajar en el mismo ↓ del avance. En el próximo ↑ sin
  pulso de BYTE se limpia la orden, antes de otro ↓. La nueva lectura
  combinacional queda disponible desde el ↓ de avance, antes del ↑
  en que LP_TX decide la próxima frontera, y estable hasta su ↓ de carga.
- **INIT_MEM (combinacional):** 223 palabras de 11 bits con
  `{OP[1:0], LAST, ARG[7:0]}` (`OP=00` BYTE, `01` WAIT, `10` END,
  `11` reservado). Fuera de 0…222 la salida por defecto es `600`
  (reservado), sin añadir palabras a la imagen. `LAST` no marca el
  último BYTE: la dirección de WAIT se sostiene desde el avance que
  sigue a ese BYTE hasta el fin de la pausa. En `TX`, solo al leer
  `INIT_DONE_TX` con WAIT presente se entra en `LOAD_DELAY`. No hay
  petición LP durante el cierre ni durante el conteo.
- **D_COUNT (↓):** `LOAD_DELAY` presenta `START_DELAY` para un solo ↓;
  si queda tiempo por contar en el ↑ posterior, `DELAY` habilita el
  conteo con `COUNT_DELAY`. Al leer `DONE_DELAY` en ↑ desde `LOAD_DELAY`
  o `DELAY`, CTRL entra en `ADV_WAIT`, que aplica un `INC_A` en el ↓
  siguiente. Tras ese ↓, CTRL lee OP en ↑: BYTE vuelve a `REQUEST`; END
  (LAST=0) pasa a `DONE` sin otra petición. Un OP inesperado lleva a
  `READ`, que no solicita nada sin BYTE válido.

Reset aborta sin emitir un fin ni reanudar lo interrumpido: en ↑ limpia
el estado y la orden de avance; en ↓ limpia la dirección y ambos contadores
de tiempo. Al liberarlo se vuelve a leer dirección 0. Cada `START_DELAY`
reinicia la fase de una pausa sin reiniciar la dirección ni usar el reset
global. Los caminos de medio ciclo se deben comprobar al integrar.

### Tick de 1 ms

`CLK_BYTE_HZ` vale `1000` por defecto solo para el banco. La integración
debe fijarlo al reloj suministrado. Para un tick exacto de ciclos se
requiere un múltiplo entero de 1000 no menor que 1000; la simulación
rechaza otros valores. No se presupone una frecuencia física.
`P = CLK_BYTE_HZ / 1000` es el número de ciclos por tick. `TICK_MS`
es una habilitación combinacional, no un reloj derivado.

| Registro | Reset en ↓ (`RST_ALL=1`) | Carga o habilitación en ↓ |
|---|---|---|
| `PHASE[W-1:0]`, `W=max(1, ceil(log2(P)))` | 0 | Con `START_DELAY` comienza una fase nueva. Ese primer ↓ ya cuenta como ciclo 1: deja `PHASE=1` si `P>1`. Con `COUNT_DELAY` y `MS_LEFT>0`, incrementa hasta `P−1`; al aplicar el tick vuelve a 0. Con `P=1` permanece en 0. |
| `MS_LEFT[7:0]` | 0 | Carga `DELAY_MS=ARG` con `START_DELAY` y resta uno por tick hasta saturar en 0. Con `P=1`, carga `ARG−1` (saturado) porque ese ↓ de carga también es el primer tick. Sin carga ni tick conserva su valor. |

En conteo, `TICK_MS` se aplica con `COUNT_DELAY`, `MS_LEFT>0` y
`PHASE=P−1`. `DONE_DELAY=(MS_LEFT==0)` se lee solo en `LOAD_DELAY`/`DELAY`,
tras el ↓ de carga. Si el fin de paquete se lee en `↑a`, el tick `k` se aplica
en `↓(a+kP)` y una pausa de `M` ms vence en `↑(a+MP)`: exactamente
`MP` ciclos entre esos ↑. El avance ocurre medio ciclo después y se
decodifica la nueva palabra en el ↑ siguiente. Esa latencia de lectura,
la admisión del siguiente paquete y un `INIT_READY` tardío no forman
parte del conteo.

### Incorporación de la ROM

[`src/init_mem.hex`](src/init_mem.hex) es una copia **byte por byte**
del `init_mem.hex` de `digital_UN/MIPI_LCD` en `13947bf1`. SHA-256:
`e68a62c8b9499de10a6034a9701137fc5b76478890022f9f310abd36689ea7b4`.
`make -C init_sequencer rom` verifica el archivo y genera
`build/init_sequencer/init_mem_table.vh`, con las mismas 223 palabras
y un caso por dirección. Tanto simulación como síntesis deben incluir
ese directorio al compilar los `.v` de `src/`. No hay `$readmemh` en
ejecución ni dependencia del repositorio vecino, de una ruta absoluta
fija o del directorio desde el que se ejecute el simulador.

El mapa y la imagen de origen coinciden: **204 BYTE, 18 WAIT**
(15 de 9 ms, 2 de 65 ms, 1 de 7 ms) **y 1 END**. La tabla no recalcula
ECC/CRC ni añade el selector `87` de LP_TX; conserva `087` en la
dirección 19 como BYTE DSI.

## Flancos para revisión

`↑n` está entre `↓n` y `↓(n+1)`. Los cambios indicados son los
publicados *después* del flanco; los receptores muestrean el valor
que ya estaba estable *antes*.

### Primer paquete: `29 02 00 00 B0 00 D6 CA`

`D=LP_DIV` y `↓0` publica el primer LP10 de `LP_TX`, como en el
diagrama del vecino. Las direcciones son decimales; las palabras
y los bytes se escriben en hex.

| Flanco | LINK_FSM / LP_TX | INIT_SEQUENCER |
|---|---|---|
| ↑ en `READ`, tras reset | Puede no estar disponible. | Lee dir. 0 (`029`) y pasa a `REQUEST`: `INIT_REQ=1`, `INIT_BYTE=29`, `INIT_LAST=0`. |
| Cualquier ↑ de `REQUEST` con `INIT_READY=0` | No admite. | Mantiene petición, dir. 0 y BYTE `29`. |
| `↑−2` | Acepta `INIT_REQ && INIT_READY`; publica `LP_START`. | Pasa a `TX` y baja `INIT_REQ`. No avanza `ADDR`. |
| `↑−1` y `↓4D` | LP_TX lee `LP_START`; tras la entrada carga su selector `87` en `↓4D` sin `INIT_NEXT`. | Dir. 0 y BYTE `29` siguen estables. |
| `↓20D` → `↑20D` → `↓(20D+1)` | Carga `29` en `↓20D` y publica `INIT_NEXT`, que cae en `↓(20D+1)`. | Lee `INIT_NEXT` en `↑20D`, arma `INC_A`; solo en `↓(20D+1)` avanza 0→1 y publica `02`. |
| `↓L` → `↑L` → `↓(L+1)`, con `L=(36,52,68,84,100,116)D` | Carga los BYTE `02 00 00 B0 00 D6`, uno por frontera, y pulsa tras cada carga. | Lee cada pulso y avanza una dirección por ↓, de 1 hasta 7. No interviene `INIT_READY`. |
| `↓132D` → `↑132D` → `↓(132D+1)` | Carga `CA` (dir. 7, LAST=0) y publica su último `INIT_NEXT`. | Lee el pulso y avanza 7→8. `309` indica WAIT de 9 ms: `INIT_LAST=1`, sin iniciar aún D_COUNT. |
| `↑(148D−1)`, luego cierre en ↓ | LP_TX toma la decisión de salida con `INIT_LAST=1`, estable desde `↓(132D+1)`. No carga `09`. | Dir. 8 retenida; `INIT_REQ=0`, `START_DELAY=0`. |
| `↑150D`, luego `↑a=↑(150D+1)` | LINK_FSM lee `LP_DONE` en `↑150D`; presenta `INIT_DONE_TX` hasta `↑a`. | Lee el pulso en `↑a` y presenta `START_DELAY=1`. |
| `↓(a+1)`; ticks `↓(a+kP)`, `k=1…9` | Ya no consume ni confirma BYTE. | Carga el WAIT, cuenta los 9 ticks y conserva dir. 8. Con `P=1`, carga y primer tick coinciden. |
| `↑(a+9P)` → `↓(a+9P+1)` → `↑(a+9P+1)` | No puede aceptar el siguiente paquete antes de `↑(a+9P+2)`. | Lee `DONE_DELAY`; avanza 8→9 en ↓. En el último ↑ decodifica `029` y presenta la nueva petición con `29` estable. |

### WAIT final y END

Aquí `↓L` carga el último BYTE del paquete 18 y `↑f` es el ↑
que lee su `INIT_DONE_TX`.

| Flanco | Resultado |
|---|---|
| `↓L` → `↑L` → `↓(L+1)` | LP_TX carga `F8` de dir. 220 (LAST=0) y publica `INIT_NEXT`. CTRL lee el pulso en ↑ y `A_COUNT` pasa 220→221 en el ↓ siguiente. `307` presenta WAIT de 7 ms y `INIT_LAST=1`. |
| Hasta `↑f` | LP_TX completa `F8`, ve LAST en la siguiente frontera y vuelve a LP11 sin consumir `07`. Se retiene dir. 221 sin `START_DELAY` ni `INIT_REQ`. |
| `↑f` → `↓(f+1)` | CTRL lee `INIT_DONE_TX` y presenta `START_DELAY`; D_COUNT carga y comienza la pausa en el ↓. `INIT_DONE=0`. |
| `↓(f+kP)`, `k=1…7` | Un tick por ms; el séptimo deja `MS_LEFT=0`. Dir. 221 sigue intacta. Para `P=1` el primer tick coincide con la carga. |
| `↑(f+7P)` → `↓(f+7P+1)` | CTRL lee `DONE_DELAY` a los `7P` ciclos exactos, entra en `ADV_WAIT` y avanza 221→222 en ↓. La ROM publica `400` (END). |
| `↑(f+7P+1)` y siguientes | Lee END, entra en `DONE` y activa `INIT_DONE=1`. Dir. 222 queda fija y `INIT_REQ=0` hasta reset. No se admite un paquete 19. |

## Pruebas aisladas

```sh
pixi run --locked make -C init_sequencer test
pixi run --locked make -C init_sequencer sim
pixi run --locked make -C init_sequencer wave
```

`test` ejecuta el mismo [banco](TB/init_sequencer_TB.v) sin ondas en
dos perfiles: p0 (`P=1`, `LP_DIV=1`) y p1 (`P=5`, `LP_DIV=3`).
`LP_DIV` solo configura el modelo de LP_TX. Los relojes de prueba de
1 kHz y 5 kHz permiten comprobar ciclos y milisegundos simulados; no
son ajustes de placa. El banco instancia solo `init_sequencer`; modela
la admisión, las fronteras de byte y el cierre de `LINK_FSM` / `LP_TX`
en sus flancos acordados, sin serializar bits.

Compara los 18 paquetes y sus 204 bytes DSI con el mapa de referencia.
Verifica un único avance en ↓ por BYTE, que no se toman WAIT ni END
como datos, y las 18 pausas exactas desde el ↑ que lee `INIT_DONE_TX`.
También comprueba `INIT_READY` tardío, `INIT_DONE` solo tras el WAIT
final y END, y reinicio desde dirección 0 con un avance pendiente,
durante una pausa y después de END.

`sim` usa p1 por defecto (`SIM_PROFILE=0` selecciona p0), guarda
`build/init_sequencer/init_sequencer_TB.fst` y lo abre en GTKWave.
`wave` reabre el último FST sin recompilar.
