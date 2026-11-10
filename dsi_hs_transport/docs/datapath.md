# Datapath de dsi_hs_transport

Derivado del flujo aprobado, conservado como primera página del único editable
[DSI_HS_TRANSPORT.drawio](DSI_HS_TRANSPORT.drawio). Se sigue la convención de
`dsi_lane_packer`: bloques sin relleno, anchos explícitos, MUX y operadores
identificados, controles discontinuos y frontera con la unidad de control.

Vistas: [almacenamiento y lectura](datapath_almacenamiento.svg),
[contadores y condiciones](datapath_control.svg), [PDF de ambas](DATAPATH.pdf).
La especificación es de transporte lógico; no fija tiempos eléctricos D-PHY.

## Memoria necesaria

Sean W = BUFFER_WORDS y A = max(1, ceil(log2(W))). W debe ser positivo.

| Elemento | Bits | Reset | Motivo |
|---|---:|---|---|
| RAM | W × 18 | No | Conservar un paquete completo antes de reservar HS; 16 bits de datos y dos de máscara por posición |
| Q | 18 | No | Registro de lectura de RAM que conserva la palabra publicada hasta iniciar su consumo |
| COUNT | A+1 | 0 | Recordar longitud completa, incluida W, y dirección de escritura durante recepción |
| INDEX | A | 0 | Contar las palabras consumidas y determinar dirección siguiente |

Con W=2048 y A=11: RAM=36 864 bits, Q=18, COUNT=12 e INDEX=11;
**36 905 bits lógicos de datapath**. Q representa el registro de salida de la
lectura síncrona; no se añade un segundo registro después de la RAM. Este es
un recuento lógico, no un resultado de asignación de bloques físicos Gowin.

STATE[3], DONE[1] y ERROR_CODE[2] están en UC según el RTL actual y no se
vuelven a dibujar como registros de datapath. No se guarda last por posición:
COUNT conserva la longitud e INDEX determina cuál palabra es la última.

## RAM y selección de lectura

```text
WR_DATA[17:0] = {tx_word_keep[1:0], tx_word_data[15:0]}
WR_ADDR[A-1:0] = COUNT[A-1:0]
WE = WRITE_EN

Σ1 = INDEX + 1                   (A bits)
M0 entrada 0 = Σ1
M0 entrada 1 = 0                 (A bits)
SEL_M0 = PRIME
RD_ADDR = PRIME ? 0 : Σ1
Q ← RAM[RD_ADDR]                 solo con READ_EN, en posedge

hs_word_data = Q[15:0]
hs_word_keep = Q[17:16]
hs_word_last = FINAL_WORD
```

La escritura sucede solo durante recepción. Tras aceptar last se bloquea la
entrada; PRIME lee dirección cero. Q conserva la primera palabra durante
reserva y espera de grant. Durante envío, el flanco que consume Q carga la
siguiente dirección si aún quedan palabras. Así no se sobrescribe la primera
antes de consumirla ni se introduce una burbuja entre palabras.

M0 es el único MUX explícito de selección de datos/dirección. La retención
pertenece a los enables; no se añaden MUX externos de realimentación. Un
keep=01 conserva el significado del packer: solo byte bajo válido. No se
transmite el byte alto como relleno.

## Contadores y comparadores

```text
RST_DP = rst | CLEAR_COUNT
Σ0 = COUNT + 1                  (A+1 bits)
COUNT ← Σ0                      con WRITE_EN
INDEX ← Σ1                      con ADVANCE
Σ2 = COUNT - 1                  (A+1 bits)

C0: FULL = (COUNT == W-1)
C1: OCCUPIED = (COUNT != 0)
C2: FINAL_WORD = ({1'b0, INDEX} == Σ2)
L0: MASK_OK = (keep == 2'b11) | ((keep == 2'b01) & last)
```

COUNT e INDEX capturan en **posedge**, con reset síncrono activo alto y
prioritario sobre enable. Sin enable conservan Q. RST_DP no limpia RAM ni Q;
la fase de UC y los contadores invalidan cualquier contenido anterior.

FULL se comprueba **antes de escribir**, durante recepción: COUNT=W−1 indica
que la aceptación actual ocuparía la última posición disponible. Si esa palabra
no tiene last, la operación falla inmediatamente. Una última palabra válida
puede ocupar exactamente esa posición. COUNT puede llegar a W; por eso se
conserva un bit más que el índice de dirección. No hay acceso posterior a la
posición W. A=1 permite W=1 sin vectores de anchura cero.

FINAL_WORD solo se interpreta en envío. Con COUNT=0 su valor no representa una
transferencia; no es necesario añadir otro registro ni un indicador de vacío
distinto de OCCUPIED.

## Frontera con la UC

| Control desde UC | Efecto |
|---|---|
| WRITE_EN | Escribir RAM e incrementar COUNT en la aceptación válida |
| READ_EN | Actualizar Q con una lectura síncrona |
| PRIME | Seleccionar dirección cero en M0 |
| ADVANCE | Incrementar INDEX después de consumir una palabra no final |
| CLEAR_COUNT | Limpiar COUNT e INDEX al recibir hs_complete |

UC recibe MASK_OK, FULL, OCCUPIED y FINAL_WORD, además de los handshakes y
confirmaciones externos. El bus de cuatro condiciones de la segunda página
agrupa conexiones nombradas; no añade almacenamiento.

```text
EN = !rst & !phy_abort
WRITE_EN = tx_word_valid & tx_word_ready & MASK_OK
tx_word_ready = EN & fase_recepción
READ_EN = EN & (PRIME | (hs_word_valid & !FINAL_WORD))
ADVANCE = hs_word_valid & !FINAL_WORD
CLEAR_COUNT = EN & fase_espera_liberación & hs_complete
```

Los controles son combinacionales antes del mismo posedge que realiza la
operación. No se introduce una acción retenida para negedge. UC genera valid,
solicitudes, done y errores; estos no son nuevos registros de datos. RAM/Q
pueden conservar valores anteriores tras reset, pero valid y las solicitudes
están bloqueados y no permiten observarlos como una entrega.

## Correspondencia con el flujo

| Operación | Acción del datapath |
|---|---|
| Aceptar palabra válida | RAM[COUNT] ← {keep,data}; COUNT ← COUNT+1 |
| Detectar máscara inválida | No escribir; UC registra fallo |
| Última posición sin last | Puede almacenarse la palabra; UC invalida la operación y no solicita HS |
| Paquete completo | Precargar Q desde RAM[0]; conservar COUNT |
| Esperar reserva/grant | Conservar RAM, Q, COUNT e INDEX |
| Consumir palabra no final | Leer RAM[INDEX+1] y avanzar INDEX en el mismo flanco |
| Consumir última | No leer otra posición; UC emite done |
| Confirmar liberación | Limpiar COUNT e INDEX, habilitar recepción |
| Reset/aborto | Invalidar operación mediante UC; reset limpia contadores |

No se añaden FIFO asíncrona, ECC/CRC, serializadores ni temporizadores físicos.
La fuente de este contrato es el plan aprobado del proyecto (2026-11-08).
El RTL implementa los bloques dibujados mediante instancias separadas. Las
pruebas de simulación y netlist se recogen en el [README](../README.md);
no constituyen STA ni implementación física.
