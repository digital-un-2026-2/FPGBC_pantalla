# Datapath de dsi_lane_packer

Diseño implementado a partir de la página FLUJO del
[Draw.io editable](DSI_LANE_PACKER.drawio). La página DATAPATH muestra buses,
MUX, registros y frontera con UC. Vistas: [SVG](datapath.svg) y
[PDF independiente](DATAPATH.pdf). La [FSM](fsm.md) completa las fases y las prioridades de control.

## Memoria necesaria

| Registro | Bits | Reset | Justificación |
|---|---:|---:|---|
| WORD | 16 | 0000 | Conservar hasta dos bytes mientras el receptor espera |
| SECOND_VALID | 1 | 0 | Distinguir palabra completa de último grupo parcial |
| LAST | 1 | 0 | Conservar el fin de paquete aunque cambie la entrada |

Total: **18 bits de datapath**. WORD es un único registro lógico con cargas
independientes para sus dos bytes; no son dos almacenes de palabras. La
memoria de fase pertenece a la unidad de control y no se cuenta aquí.

Todos los registros capturan en **posedge**, como se acordó para este bloque.
`RST_DP` es síncrono, activo alto y prioritario sobre las cargas; `LD=0` conserva
Q. A 40 MHz el periodo es 25 ns. Entrada, control y datapath comparten dominio
y flanco: no se añade una acción retenida hasta negedge. Los bloques anteriores
que trabajan entre flancos tienen su propio contrato temporal.

## Datos y multiplexor

El primer byte se escribe en WORD[7:0]; simultáneamente WORD[15:8] se pone a
cero. El segundo byte se escribe únicamente en WORD[15:8], conservando abajo
el primero. M0 selecciona la entrada de la mitad alta:

| M0 | Entrada | Motivo |
|---|---|---|
| 0 | 8'h00 | Limpiar el byte alto al comenzar un grupo |
| 1 | tx_byte_data[7:0] | Añadir el segundo byte del grupo |

```text
SEL_M0 = LD_SECOND
LD_LO = LD_FIRST
LD_HI = LD_META = LD_FIRST | LD_SECOND

D_LO = tx_byte_data
D_HI = LD_SECOND ? tx_byte_data : 8'h00
D_SECOND_VALID = LD_SECOND
D_LAST = tx_byte_last

tx_word_data = WORD
tx_word_keep = {SECOND_VALID, 1'b1}
tx_word_last = LAST
```

La retención se expresa con enables de registro; no se dibujan MUX externos
de realimentación adicionales. La síntesis puede mapear esos enables a MUX
según los recursos disponibles. `SECOND_VALID` recibe directamente el evento
`LD_SECOND`: vale cero al aceptar el primero y uno al aceptar el segundo.
No necesita otro MUX de constantes.

`tx_word_keep` es concatenación combinacional, no un registro de dos bits ni
un comparador. Solo puede ser 01 o 11. Con `valid=0`, datos y metadatos pueden
conservar el grupo anterior y no representan una transferencia.

## Contrato con la unidad de control

UC recibe `tx_byte_valid`, `tx_byte_last`, `tx_word_ready`, `clk` y `rst`.
Entrega `LD_FIRST`, `LD_SECOND`, `RST_DP`, `tx_byte_ready` y `tx_word_valid`; todas son
de un bit. Los controles de carga son combinacionales y se evalúan antes del
mismo posedge que acepta el byte. No son pulsos registrados posteriores.

```text
BYTE_FIRE = tx_byte_valid & tx_byte_ready
WORD_FIRE = tx_word_valid & tx_word_ready

LD_FIRST  = BYTE_FIRE & fase_espera_primero
LD_SECOND = BYTE_FIRE & fase_espera_segundo

tx_byte_ready = !rst & (fase_espera_primero | fase_espera_segundo)
tx_word_valid = !rst & fase_salida
```

Las fases corresponden a EMPTY, HALF y OUTPUT en la [FSM](fsm.md),
implementadas en lane_control.v y verificadas en simulación. UC conserva la fase sin aceptar nuevos bytes durante la
publicación. `LD_FIRST` y `LD_SECOND` nunca coinciden; con reset son cero.
La entrada `tx_byte_last` permite decidir si, después del primero, corresponde
publicar un grupo parcial o esperar el segundo. UC no necesita leer WORD ni
comparar longitudes. Los anchos de los paquetes DSI no afectan al datapath.

| Operación del flujo | LD_FIRST | LD_SECOND | Efecto en el datapath |
|---|---:|---:|---|
| Esperar sin aceptar entrada | 0 | 0 | Conservar los 18 bits |
| Aceptar primer byte A | 1 | 0 | WORD={00,A}; SECOND_VALID=0; LAST=last de A |
| Aceptar segundo byte B | 0 | 1 | WORD={B,A}; SECOND_VALID=1; LAST=last de B |
| Publicar o entregar grupo | 0 | 0 | Conservar; la liberación pertenece a UC |
| Reset | 0 | 0 | Limpiar registros con prioridad en posedge |

La entrega no necesita limpiar WORD. El primer byte del grupo siguiente
reescribe abajo y limpia arriba; no se reutiliza un segundo byte antiguo.
No se acepta entrada en el mismo flanco de entrega de salida.

## Comprobación del diseño

- A con last=1: WORD={00,A}, keep=01, last=1.
- A sin last seguido de B: WORD={B,A}, keep=11, last=last de B.
- A B C, con C último: primero {B,A}/11/0; después {00,C}/01/1.
- Salida válida sin ready: ambas cargas en cero, conservar palabra y metadatos.
- Reset con medio grupo o salida pendiente: bloquear handshakes y borrar en
  posedge, coordinando el descarte con productor y receptor.

La revisión y las pruebas cubren conexiones, anchos y correspondencia con el
flujo. La prueba integrada pasó con 54 paquetes; la matriz de control pasó con
64 combinaciones. Yosys comprobó ausencia de latches y 20 bits de memoria en
posedge (18 de datapath y dos de UC). Ver resultados en el [README](../README.md).

En lane_datapath.v, WORD se construye con word_lo [8] y word_hi [8], dos
secciones del mismo registro lógico con enables independientes. second [1] y
last [1] conservan sus metadatos. Todas son instancias de lane_register;
M0 es una instancia de lane_mux. No se duplica la palabra de datos.

No hacen falta contador, sumador, CRC, ECC, FIFO ni MUX de salida. La agrupación
no garantiza continuidad HS: `keep=01` no autoriza transmitir el cero alto como
relleno. La política física de ráfaga y terminación corresponde al transporte.

La FSM completa la conexión de reset interno: `RST_DP = rst | (STATE == 11)`.
Así se limpian los 18 bits en el posedge de reset o de recuperación del código
no usado. En el diagrama, RST_DP alimenta los pines de reset de los registros;
no modifica la interfaz pública ni añade memoria.
