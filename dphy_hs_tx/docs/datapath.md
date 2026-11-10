# Datapath propuesto de dphy_hs_tx

**PROPUESTO · 2026-11-08.** Derivado del [flujo](flujo.md) y del
[contrato temporal S320](contrato_temporal.md). Diseño del modelo funcional
restringido a paquetes pares; implementado en RTL, sin primitivas de E/S.
[Resultados de verificación](../README.md).

Editable único: [DPHY_HS_TX.drawio](DPHY_HS_TX.drawio), páginas 3 y 4.
Vistas: [datos y salida](datapath_datos.svg),
[temporizadores y UC](datapath_control.svg), [PDF](DATAPATH.pdf).

Las decisiones de arquitectura siguientes son deducciones de esos contratos,
no requisitos atribuidos a MIPI. Las fuentes técnicas G1–G4, L1/L2 y T1/T2
siguen identificadas en los documentos anteriores. Continúan pendientes el
cotejo normativo de Zero/Sync/Trail, la lane parcial y el wrapper físico.

## Memoria y relojes

| Elemento | Bits en S320 | Actualización / reset | Justificación |
|---|---:|---|---|
| P_DATA | 16 | CAPTURE; sin reset de datos | Palabra pendiente durante Sync y emisión de la anterior |
| P_LAST | 1 | CAPTURE; reset a 0 | Marca final de la palabra pendiente |
| P_VALID | 1 | CAPTURE/MOVE/CLEAR_PIPE; reset a 0 | Ocupación de PENDING |
| A_DATA | 16 | MOVE; sin reset de datos | Palabra estable durante sus ocho bits |
| A_LAST | 1 | MOVE; reset a 0 | Reconocer el fin serial del paquete |
| A_VALID | 1 | MOVE/RETIRE/CLEAR_PIPE; reset a 0 | Ocupación de ACTIVE |
| TIME_LEFT | 12 | TIME_LOAD/TIME_STEP; reset a 0 | Temporizador compartido: hasta 4000 intervalos de INIT |
| POST_LEFT | 4 | POST_LOAD/POST_STEP; reset a 0 | Nueve intervalos POST, en paralelo a Exit de datos |

**52 bits lógicos de datapath**, excluidos UC y el generador conductual serial.
PENDING y ACTIVE suman 36; temporizadores, 16. No hay RAM, FIFO, contador de
paquetes, registro de keep, copia de Sync ni registro adicional de último bit.
El cálculo no predice recursos físicos ni incluye memoria de un simulador.

Todos estos registros capturan en **posedge clk**, con reset síncrono activo
alto y prioritario sobre cargas/enables. Los datos sin reset solo se usan
con validez o fase apropiada; en reset se enmascaran salidas seriales y ACK.
No se añade datapath en negedge: el árbitro existente conserva sus propios
registros en ese flanco. El reset coordinado cubre ambos flancos del árbitro.

STATE y causa de fallo pertenecen a UC; no se cuentan dos veces en datapath.
La [FSM propuesta](fsm.md) usa cinco bits de estado y tres de causa; decodifica
las confirmaciones sin añadir registros ACK. Total propuesto: 60 bits lógicos.

## Captura y movimiento de palabras

```text
K0: MASK_OK = (hs_word_keep == 2'b11)
CAPTURE = UC_RX_OPEN & hs_word_valid & hs_grant & MASK_OK & !rst & !phy_abort

P_DATA ← hs_word_data                       con CAPTURE
P_LAST ← hs_word_last                       con CAPTURE
A_DATA ← P_DATA anterior                    con MOVE
A_LAST ← P_LAST anterior                    con MOVE
```

MOVE requiere P_VALID. Puede coincidir con CAPTURE en el mismo posedge:
ACTIVE recibe el PENDING **anterior**, y PENDING recibe la entrada nueva.
No existe paso combinacional de entrada a ACTIVE. La retención se representa
con enables del registro, sin MUX externos de realimentación redundantes.

Prioridades de validez después de reset:

```text
P_VALID': CLEAR_PIPE ? 0 : CAPTURE ? 1 : MOVE ? 0 : P_VALID
A_VALID': CLEAR_PIPE ? 0 : MOVE ? 1 : RETIRE ? 0 : A_VALID
```

En ambas ecuaciones las condiciones se evalúan **antes** del flanco. MOVE y
RETIRE simultáneos retiran la palabra anterior y cargan la nueva. UC no puede
activar CAPTURE/MOVE junto con CLEAR_PIPE. Un aborto enmascara los controles
y fuerza invalidación síncrona; los valores de datos pueden conservarse.

| Frontera del contrato | Controles | Resultado durante el siguiente intervalo |
|---|---|---|
| C0 | CAPTURE | P=W0; M1 selecciona Sync; ACTIVE inválido |
| C1 | MOVE; CAPTURE si existe W1 | A=W0; P=W1 o vacío; M1 selecciona payload |
| Ci, 1<i<N | RETIRE+MOVE+CAPTURE | A=W(i−1); P=Wi; payload sin hueco |
| CN | RETIRE si había palabra activa, MOVE | A=última; P vacío; grant puede bajar después del flanco |
| C(N+1) | RETIRE | ACTIVE inválido; datos retenidos para generar Trail |

N=1: C1 solo MOVE, sin RETIRE de un payload anterior; C2 RETIRE. A_VALID
no habilita Trail: UC selecciona explícitamente esa fase tras retirar la
última palabra. A_DATA queda intacto durante todo Trail.

UC cierra RX al capturar last y no lo abre hasta la nueva transacción. Para
decidirlo usa hs_word_last en CAPTURE y después las marcas P_LAST/A_LAST.
No necesita un tercer registro end_seen: el cierre queda en su fase.
Retirar grant tras last no invalida las palabras ya almacenadas.

## Selección de palabra y generador serial

M1 es un MUX de cuatro entradas, de 16 bits; cada byte corresponde a una lane:

| SEL_WORD[1:0] | Entrada M1 | Uso |
|---|---|---|
| 00 | 16'h0000 | HS-Zero |
| 01 | 16'hB8B8 | Sync, un intervalo T |
| 10 | A_DATA[15:0] | Payload, solo con A_VALID |
| 11 | {{8{~A_DATA[15]}},{8{~A_DATA[7]}}} | Trail por lane |

El último bit serial propuesto de D0 es A_DATA[7], y el de D1, A_DATA[15].
Invertir y replicar cada bit evita añadir un registro TAIL: ACTIVE conserva
la última palabra hasta acabar Trail. UC impide MOVE durante Trail y solo
selecciona esa entrada después de haber emitido un payload completo.

El generador conductual recibe FRAME[15:0] al comienzo del intervalo y lo
conserva durante ocho UI; selecciona D0=FRAME[i], D1=FRAME[8+i], i=0…7.
El índice de tres bits y los eventos UI pertenecen al **modelo de simulación**,
no a un contador RTL que avance ocho veces por cada posedge de 40 MHz.
En la frontera de palabra se actualiza primero el datapath; el generador toma
el nuevo FRAME después de esas actualizaciones, sin carrera de deltas.

El generador produce también el reloj ideal centrado en los bits conforme al
contrato temporal. UC entrega las órdenes lógicas HS_DATA_ON y HS_CLK_ON y
los estados LP de CLK/D0/D1. Los enables de salida no dependen de A_VALID:
Zero, Sync y Trail también requieren señalización HS con ACTIVE inválido.
No conectar estas órdenes directamente a OEN físico. La FSM añade CLK_TOGGLE:
HS_CLK_ON=1 con CLK_TOGGLE=0 mantiene CLK en HS-0 durante Zero/Trail;
CLK_TOGGLE=1 genera la oscilación ideal. Es un control del modelo, sin registro
nuevo de datapath.

## Temporizador compartido y contador POST

M0 selecciona N−1 desde constantes del perfil. Anchura general
W_TIME=max(1,ceil(log2(max(N_fase)))); en S320, W_TIME=12.

| TIME_SEL | Intervalo | N−1, S320 |
|---|---|---:|
| 0 | INIT | 3999 |
| 1 | LPX de reloj o datos | 1 |
| 2 | CLK-PREPARE | 1 |
| 3 | CLK-ZERO | 9 |
| 4 | CLK-PRE | 0 |
| 5 | HS-PREPARE | 2 |
| 6 | HS-ZERO | 4 |
| 7 | HS-TRAIL | 2 |
| 8 | Exit de datos o reloj | 3 |
| 9 | CLK-TRAIL | 2 |

TIME_SEL tiene cuatro bits; códigos 10…15 son inválidos y UC debe registrar
fallo si se solicita TIME_LOAD con ellos. El MUX entrega 0 por defecto para
evitar un valor indeterminado, pero ese valor no valida el selector.

En RTL, UC comprueba su selector nominal antes de aplicar la selección Exit
de la recuperación. TIME_SEL_OK del datapath es diagnóstico interno; usarlo
para decidir la misma sustitución del selector crearía dependencia circular.

M2 selecciona la carga M0 frente al decremento Σ0; M3 selecciona N_POST−1
frente al decremento Σ1. Ambos tienen dos entradas, de 12 y cuatro bits
respectivamente. La retención pertenece al enable del registro.

```text
Σ0 = TIME_LEFT - 1                        (W_TIME bits)
M2 = TIME_LOAD ? M0 : Σ0
EN_TIME = TIME_LOAD | (TIME_STEP & (TIME_LEFT != 0))
TIME_LEFT ← M2                            con EN_TIME
C0: TIME_LAST_INTERVAL = (TIME_LEFT == 0)

Σ1 = POST_LEFT - 1                        (W_POST bits)
M3 = POST_LOAD ? (N_POST-1) : Σ1
EN_POST = POST_LOAD | (POST_STEP & (POST_LEFT != 0))
POST_LEFT ← M3                            con EN_POST
C1: POST_LAST_INTERVAL = (POST_LEFT == 0)
W_POST=max(1,ceil(log2(N_POST)))=4          para N_POST=9
```

Carga tiene prioridad sobre decremento. No hay wrap ni underflow. Solo se
admiten N≥1. Los valores N y sus límites se comprueban al validar el perfil;
no se añade una unidad aritmética que calcule tiempos normativos en hardware.

**Convención de intervalo:** en la frontera E se carga N−1 y empieza la fase.
En E+1…E+N−1 se decrementa. Un cero señala que el intervalo **actual** es el
último: UC lo evalúa en el siguiente posedge E+N para cambiar de fase. No es
un permiso combinacional para cambiar la salida inmediatamente al llegar a 0.
Para N=1, se carga cero en E y se cambia de fase en E+1, nunca en E.

TIME_LEFT se comparte porque preparación/parada de reloj y datos ocurren
secuencialmente. Sync y payload no necesitan este temporizador: duran un
intervalo de bytes cada uno, por transición de UC y movimiento de palabras.
Durante espera de grant se conserva HS-0, con TIME_STEP=0.

POST_LEFT se carga en la frontera del final de Trail de datos, simultáneamente
con TIME_LOAD para Exit de datos. POST_STEP avanza desde el siguiente posedge
y continúa durante la espera de clk_stop_req. Cuando el POST llega a cero,
se mantiene cero; UC puede terminar su espera en la siguiente frontera que
cumpla también la orden de parada. No hace falta otro flag post_running:
la fase de UC habilita la interpretación de C1 después de POST_LOAD.

## Condiciones hacia UC y controles desde UC

| Condiciones hacia UC | Uso |
|---|---|
| MASK_OK | Rechazar keep distinto de 11, antes de capturar |
| P_VALID, P_LAST, A_VALID, A_LAST | Ocupación, última entrada y último payload |
| TIME_LAST_INTERVAL, POST_LAST_INTERVAL | Terminar fase en la siguiente frontera habilitada |
| TIME_SEL_OK = TIME_SEL≤9 | Validar carga del perfil |

UC recibe además los puertos públicos valid/last/grant, órdenes del árbitro,
reset y phy_abort; esas entradas no atraviesan un registro nuevo del datapath.
UC detecta hueco antes de last, palabra adicional tras cierre RX, pérdida de
grant antes de last y parada prematura/ausente. No enmascarar una entrada
ilegal sin registrar su causa. El código de fallo pertenece a la futura UC.

| Control desde UC | Destino / significado |
|---|---|
| UC_RX_OPEN | Ventana de captura; CAPTURE se cualifica con valid/grant/máscara |
| MOVE, RETIRE, CLEAR_PIPE | Movimiento e invalidación de palabras |
| SEL_WORD[1:0] | M1: Zero/Sync/payload/Trail |
| TIME_SEL[3:0], TIME_LOAD, TIME_STEP | M0 y temporizador principal |
| POST_LOAD, POST_STEP | Temporizador concurrente de POST |
| HS_DATA_ON, HS_CLK_ON, CLK_TOGGLE; estados LP | Generador conductual, fuera de la memoria del datapath |

UC publica ACK y errores; la composición externa combina reposo con motor y
puente LPDT. Ningún bloque aquí genera ECC/CRC, arbitraje, hs_complete o pads.

## Verificación de diseño

La comprobación de especificación [verificar_datapath.py](verificar_datapath.py)
contrasta la carga N−1 en N=1/2/3/4/5/9/10/4000, POST concurrente con Exit,
pipeline simultáneo en seis longitudes, Sync y Trail a partir de bits extremos.
Es evidencia de coherencia del diseño propuesto; no sustituye a pruebas RTL.
No se modifica el RTL de los bloques existentes.
