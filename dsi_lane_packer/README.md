# dsi_lane_packer

**RTL implementado desde el flujo, datapath y FSM.** Top estructural,
transiciones de UC en `posedge` y salidas combinacionales en `always @(*)`.
Los registros del datapath capturan también en `posedge`, según el contrato
aprobado para este bloque.

Empaquetador lógico de bytes DSI para dos lanes. La propuesta de arquitectura
[original](../docs/referencias/arquitectura_2026_11_08/ARQUITECTURA_OBJETIVO.md)
(§3.6) describe la agrupación de dos
octetos y una máscara para el último grupo parcial. Este bloque concreta ese
contrato interno; no define por sí solo una ráfaga física D-PHY.

## Contrato

Todos los registros usan `posedge clk`; reloj previsto 40 MHz (25 ns/ciclo).
`rst` es activo alto: bloquea combinacionalmente los handshakes y limpia los
registros en el siguiente flanco ascendente. Mantenerlo hasta ese flanco.

| Puerto | Dirección | Anchura | Significado |
|---|---|---:|---|
| `clk`, `rst` | Entrada | 1 | Reloj y reset |
| `tx_byte_data` | Entrada | 8 | Byte DSI preparado |
| `tx_byte_valid`, `tx_byte_last` | Entrada | 1 | Byte disponible / último del paquete |
| `tx_byte_ready` | Salida | 1 | Capacidad de aceptar entrada |
| `tx_word_data` | Salida | 16 | Primer byte en [7:0] (D0), segundo en [15:8] (D1) |
| `tx_word_keep` | Salida | 2 | 11: ambos bytes; 01: solo D0 |
| `tx_word_valid`, `tx_word_last` | Salida | 1 | Palabra disponible / última del paquete |
| `tx_word_ready` | Entrada | 1 | Aceptación del receptor |

Cada transferencia ocurre con `valid && ready` en el mismo posedge. El
productor mantiene `valid`, datos y `last` hasta aceptación; el empaquetador
cumple lo mismo en su salida. `last` y `keep` solo son significativos con
`valid`. No existe paquete vacío: sin bytes no se emite ninguna palabra.

Cada paquete comienza en D0. Nunca se mezclan paquetes: para bytes A B C,
se entregan `{B,A}, keep=11, last=0` y `{00,C}, keep=01, last=1`.
El cero del byte alto **no es relleno que deba transmitirse**. El futuro
transporte debe resolver la terminación física de una lane parcial y la
formación de ráfagas conforme al protocolo antes de conectar este puerto a
serializadores. Este contrato no acredita esa política física.

No hay `done`: aceptar la última palabra indica entrega al receptor, no fin
de transmisión ni recepción del panel. No hay timeout, validación DSI ni
reconstrucción de límites si falta `last`. Reset descarta la palabra parcial
o pendiente sin evento de éxito; productor y receptor deben resetearse de
forma coordinada para descartar el mismo paquete.

## Flujo, datapath y FSM

Diagramas editables, páginas FLUJO, DATAPATH y FSM: [DSI_LANE_PACKER.drawio](docs/DSI_LANE_PACKER.drawio).
Vistas: [SVG](docs/flujo.svg) y [PDF](docs/FLUJO.pdf).
Datapath: [SVG](docs/datapath.svg), [PDF](docs/DATAPATH.pdf) y
[justificación de registros, MUX y controles](docs/datapath.md).
FSM: [SVG](docs/fsm.svg), [PDF](docs/FSM.pdf) y
[transiciones, controles y contrato temporal](docs/fsm.md).

1. Aceptar el primer byte, escribirlo abajo y poner a cero el byte alto.
2. Si es último, publicar una palabra parcial; si no, esperar el segundo.
3. Aceptar el segundo byte, escribirlo arriba y copiar su marca de fin.
4. Publicar y conservar la palabra hasta aceptación; volver al paso 1.

Datapath: un registro de 16 bits con escritura por byte, un bit `second_valid`
y un bit `word_last`. La máscara es `{second_valid, 1'b1}`. FSM binaria de
tres estados, dos bits; todos los registros en posedge. El estado es la única
memoria de ocupación: no hay contador, FIFO ni otro registro de datos.

| Estado | Controles | Próximo estado |
|---|---|---|
| EMPTY | `byte_ready=1`; al aceptar, cargar byte bajo, limpiar alto y segundo válido, copiar last | last: OUTPUT; si no: HALF |
| HALF | `byte_ready=1`; al aceptar, cargar alto, marcar segundo válido y copiar last | OUTPUT |
| OUTPUT | `word_valid=1`; datos estables, `byte_ready=0` | `word_ready`: EMPTY |

Reset tiene prioridad sobre cualquier aceptación. La codificación no usada
vuelve a EMPTY y limpia datos/metadatos; durante ese estado los handshakes
están bloqueados. No se utiliza esta recuperación como detector de fallos.

No se acepta otro byte en el flanco de entrega de una palabra. Con ambos
extremos disponibles, un grupo completo requiere tres ciclos (75 ns a
40 MHz), y uno parcial dos ciclos (50 ns). Son tasas de este adaptador,
no velocidades HS. El preparador largo actual entrega carga útil cada tres
ciclos; no se demuestra continuidad serial con esta conexión. El futuro
transporte necesita justificar almacenamiento, tasas y dominios de reloj.

## Organización RTL

| Fuente en `src/` | Elemento del diseño |
|---|---|
| `dsi_lane_packer.v` | Top estructural: conecta control y datapath |
| `lane_control.v` | STATE [2], handshakes, LD_FIRST, LD_SECOND y RST_DP |
| `lane_datapath.v` | WORD [16], SECOND_VALID [1], LAST [1], M0 y conexiones |
| `lane_register.v` | Registro parametrizable, reset síncrono prioritario y enable |
| `lane_mux.v` | MUX combinacional parametrizable; M0 selecciona cero o byte |

WORD tiene dos instancias de ocho bits con enables independientes. Son las
secciones del único registro lógico de 16 bits del diagrama; no hay segunda
palabra almacenada. Los dos metadatos usan instancias de un bit. Con STATE [2]
suman 20 bits lógicos. No hay ACTION, `next_state`, contador ni FIFO.

## Verificación

```sh
pixi run --locked check-dsi-lane-packer-rtl
pixi run --locked test-dsi-lane-packer
```

También `make -C dsi_lane_packer check test` si las herramientas están en PATH.
Productos en `build/dsi_lane_packer/`. La prueba integrada compara bytes aceptados en
entrada contra palabras aceptadas en salida, incluidos datos, máscara y fin;
comprueba además estabilidad durante pausas y ausencia de aceptación simultánea.
Prueba longitudes pares/impares, paquetes consecutivos, pausas aleatorias,
reset en los tres estados y recuperación. La integración usa los preparadores
corto y largo reales y compara también sus bytes ECC/CRC sin modificarlos;
sus regresiones independientes verifican los algoritmos ECC/CRC.
La prueba de controles añade 64 combinaciones de los cuatro códigos de fase,
reset, valid, last y ready. Comprueba carga en el mismo posedge, retención
fuera de ese flanco y recuperación del código 11. Solo esta prueba dirigida
inyecta el estado interno; el monitor de paquetes usa los puertos públicos.

Resultado local (2026-11-08):

| Comprobación | Resultado |
|---|---|
| `pixi run --locked check-rtl` | PASS, incluido el empaquetador |
| Prueba integrada del empaquetador | PASS: 54 paquetes, 34.601 palabras, 27 grupos parciales y cinco resets |
| Matriz de controles y flancos | PASS: 64 combinaciones, incluida recuperación de 11 |
| Yosys `proc; check -assert` | PASS, sin latches ni problemas de conexión |
| Inspección de netlist genérica | PASS: 20 bits en cinco bancos DFF, todos en posedge, sin reset asíncrono |
| Preparador corto | PASS: 65.815 paquetes completos y ocho abortos |
| Preparador largo | PASS: 311 paquetes completos y 22 abortos |
| Puente LPDT | PASS: 26 paquetes, siete rechazos y siete abortos |
| Árbitro LP/HS | PASS: pruebas unitaria, integrada y entre flancos |

El Makefile recompila las simulaciones para evitar reutilizar un `.vvp`
generado por otra versión de Icarus: el sistema tiene 13 y Pixi fija 12.
Las regresiones finales usan el entorno bloqueado de Pixi. El empaquetador no
emite avisos de elaboración; `check-rtl` conserva los avisos existentes de
`timescale` heredado del motor LPDT. No se ha realizado implementación física
ni STA: la comprobación de Yosys es estructural y genérica.

No se integran árbitro, PHY, LiteX ni pines. Para retirar el bloque, quitar su
directorio, tareas y enlaces; no hay cambios en los preparadores existentes.
