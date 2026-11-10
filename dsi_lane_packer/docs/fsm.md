# FSM de dsi_lane_packer

Derivada del flujo y del [datapath](datapath.md). Página FSM del
[Draw.io editable](DSI_LANE_PACKER.drawio), [SVG](fsm.svg) y
[PDF independiente](FSM.pdf). La unidad de control se implementa en [lane_control.v](../src/lane_control.v);
los resultados de simulación se recogen en el [README](../README.md).

## Estado y flancos

Tres estados con codificación binaria: `EMPTY=00`, `HALF=01`, `OUTPUT=10`.
`STATE[1:0]` conserva la fase, con reset síncrono activo alto y actualización
en `posedge clk`. UC y los 18 bits del datapath comparten ese flanco. Total:
**20 bits lógicos**, antes de cualquier recodificación u optimización de síntesis.

Las transiciones se escriben dentro de `always @(posedge clk)`, sin registro
de acción ni bloque combinacional de próximo estado. Las salidas de UC se
decodifican en `always @(*)`, con valores por defecto para evitar latches.
Los enables de carga dependen del estado vigente y del handshake antes del
flanco: el datapath captura el byte en el mismo posedge que cambia la fase.
No se deben registrar los enables y retrasar la captura al ciclo siguiente.

## Transiciones normales

Las condiciones siguientes se evalúan con `rst=0` y un estado válido:

```text
BYTE_FIRE = tx_byte_valid & tx_byte_ready
WORD_FIRE = tx_word_valid & tx_word_ready
```

| Origen | Condición en posedge | Destino | Operación del datapath en ese flanco |
|---|---|---|---|
| EMPTY | !BYTE_FIRE | EMPTY | Conservar |
| EMPTY | BYTE_FIRE y !tx_byte_last | HALF | LD_FIRST: conservar primer byte; limpiar alto |
| EMPTY | BYTE_FIRE y tx_byte_last | OUTPUT | LD_FIRST: preparar último grupo parcial |
| HALF | !BYTE_FIRE | HALF | Conservar primer byte |
| HALF | BYTE_FIRE | OUTPUT | LD_SECOND: añadir segundo byte y copiar last |
| OUTPUT | !WORD_FIRE | OUTPUT | Conservar palabra, keep y last |
| OUTPUT | WORD_FIRE | EMPTY | Conservar datos; liberar fase de salida |

`tx_byte_last` solo decide una transición cuando se acepta entrada en EMPTY.
En HALF no altera el destino: tanto un grupo intermedio como uno final pasan
a OUTPUT, con su `last` almacenado. En OUTPUT se ignoran todas las entradas
de byte. `tx_word_ready` no afecta a la captura en EMPTY ni HALF.

No hay estado de fin de paquete: `LAST` y `SECOND_VALID` ya conservan esa
información. Después de entregar cualquier grupo se espera el primer byte
del siguiente grupo; si era el último, ese grupo pertenece al paquete nuevo.

## Salidas de control

En ausencia de reset:

| STATE | tx_byte_ready | tx_word_valid | LD_FIRST | LD_SECOND |
|---|---:|---:|---|---|
| EMPTY (00) | 1 | 0 | BYTE_FIRE | 0 |
| HALF (01) | 1 | 0 | 0 | BYTE_FIRE |
| OUTPUT (10) | 0 | 1 | 0 | 0 |
| No usado (11) | 0 | 0 | 0 | 0 |

Con `rst=1`, las cuatro salidas son cero inmediatamente. Los handshakes son
decodificaciones del estado enmascaradas por reset; las cargas son Mealy,
dependen además de `tx_byte_valid`. `valid/ready` no son registros nuevos.

```text
LD_META = LD_FIRST | LD_SECOND
LD_LO = LD_FIRST
LD_HI = LD_META
SEL_M0 = LD_SECOND

tx_word_data = WORD
tx_word_keep = {SECOND_VALID, 1'b1}
tx_word_last = LAST
```

LD_FIRST y LD_SECOND son excluyentes. Sin entrada aceptada no se escribe ningún
registro de datos. Durante OUTPUT ambos son cero, incluso en WORD_FIRE.

## Reset y código no usado

Prioridades en el flanco ascendente:

1. `rst=1`: STATE vuelve a EMPTY y se limpian los 18 bits del datapath.
2. `STATE=11`, sin reset: volver a EMPTY y limpiar el datapath, sin aceptación.
3. Estado válido: aplicar la tabla normal.

Para cumplir la recuperación del código no usado descrita en el contrato se
completa la frontera interna con una señal de UC:

```text
RST_DP = rst | (STATE == 2'b11)
```

RST_DP es el reset **síncrono** de WORD, SECOND_VALID y LAST, prioritario sobre
cualquier carga. La comparación pertenece a la decodificación del registro
de fase, no exige otro estado ni memoria. Se ha actualizado su conexión en
el datapath; no cambia ningún puerto público del empaquetador. No es una
salida de diagnóstico ni una garantía de recuperación ante valores X/Z.

Reset bloquea handshakes combinacionalmente y debe cubrir un posedge para
descartar el grupo. Productor y receptor deben compartir el descarte del
paquete. No se genera pulso de éxito ni reintento automático.

## Secuencia temporal y criterios de verificación

Con fuente y receptor disponibles, para dos bytes A y B:

| Flanco | Estado antes del flanco | Transferencia | Estado después |
|---|---|---|---|
| N | EMPTY | Entrada A, last=0; LD_FIRST=1 | HALF |
| N+1 | HALF | Entrada B; LD_SECOND=1 | OUTPUT |
| N+2 | OUTPUT | Entrega {B,A}, keep=11 | EMPTY |
| N+3 | EMPTY | Primera entrada del siguiente grupo | Según last |

Un byte A con last=1 pasa de EMPTY a OUTPUT en N y puede entregarse en N+1
como {00,A}/01/1. El siguiente grupo puede aceptar su primer byte en N+2.
Los intervalos entre primeros bytes de grupos consecutivos son tres ciclos
para grupos completos (75 ns) y dos para parciales (50 ns), a 40 MHz.

La verificación comprueba todas las filas de transición,
pausas antes del segundo byte y durante salida, last sin valid, entrada
pendiente durante OUTPUT, paquetes pares/impares consecutivos, reset en cada
estado y recuperación del código binario 11. Comprueba que la entrega
y una nueva entrada nunca coinciden en un flanco, y que los controles de
carga se aplican al mismo byte aceptado. La prueba integrada pasó con 54 paquetes y la matriz de controles
con 64 combinaciones; incluye el código binario 11 y los flancos de captura.

Esta FSM organiza grupos lógicos. No añade timeout, serialización, continuidad
HS, reloj físico ni tratamiento eléctrico de una lane parcial.
