# FSM de dsi_test_pattern

**Implementada en RTL y verificada en simulación.** Derivada del [flujo](flujo.md) y del
[datapath](datapath.md), sin cambiar puertos ni añadir almacenamiento de imagen.
Página 4 del [editable único](DSI_TEST_PATTERN.drawio).
[SVG](fsm.svg) · [PDF](FSM.pdf).

## Estados, memoria y flanco

Dos estados con codificación binaria de un bit: **IDLE=0**, **STREAM=1**.
STATE se actualiza en posedge de clk; el datapath comparte ese flanco.
No se usan estados por componente, píxel, línea o fin de cuadro: los registros
X/Y/C ya contienen la posición y el componente; frame_done tiene su registro.

UC contiene **dos bits**: STATE[1] y R_DONE[1]. busy y ACTIVE se decodifican
de STATE, no se almacenan de nuevo. Con los 22 bits del datapath, el perfil
720 × 720 usa **24 bits lógicos** antes de síntesis. No quedan códigos
binarios sin usar en STATE; esta elección no detecta cambios accidentales
de un estado válido al otro ni promete recuperación de X/Z o fallos de C.

La implementación actualiza STATE directamente en el bloque
secuencial. Los controles del datapath y handshakes son combinacionales,
con valores por defecto para evitar latches. No se añade un registro de
acciones, retardo a negedge ni fase extra de preparación o entrega.

## Condiciones y salidas

```text
ACTIVE       = (STATE == STREAM)
start_ready  = !rst & (STATE == IDLE)
tx_byte_valid= !rst & (STATE == STREAM)
busy         = ACTIVE
frame_done   = R_DONE

START_FIRE = start_valid & start_ready
BYTE_FIRE  = tx_byte_valid & tx_byte_ready

INIT       = START_FIRE
STEP_COMP  = BYTE_FIRE & !IS_B
STEP_PIXEL = BYTE_FIRE & IS_B & !X_END
STEP_LINE  = BYTE_FIRE & IS_B & X_END & !Y_END
FINISH     = BYTE_FIRE & IS_B & X_END & Y_END
```

Todas las condiciones son de un bit. IS_B, X_END e Y_END son salidas de los
comparadores CC, CX y CY del datapath. Se evalúan sobre el byte ofrecido
**antes del flanco** que lo acepta; no sobre los contadores ya incrementados.
INIT y los tres STEP llegan a LD/SEL del datapath antes de ese mismo flanco.

start_ready y tx_byte_valid son salidas de estado enmascaradas por reset.
INIT/STEP/FINISH son Mealy: dependen también de la aceptación. frame_done es
la salida del registro R_DONE y no una decodificación del estado IDLE.

| Estado, con rst=0 | start_ready | tx_byte_valid | busy | INIT | STEP / FINISH |
|---|---:|---:|---:|---|---|
| IDLE | 1 | 0 | 0 | start_valid | Todos 0 |
| STREAM | 0 | 1 | 1 | 0 | Según BYTE_FIRE y condiciones |

Con rst=1: start_ready=tx_byte_valid=INIT=STEP_COMP=STEP_PIXEL=STEP_LINE=FINISH=0.
busy y frame_done conservan la decodificación de la memoria previa hasta
el posedge que aplica reset. No se les añade máscara asíncrona. El byte y
las marcas se anulan inmediatamente mediante tx_byte_valid, como exige
el datapath; el reset debe cubrir un posedge para descartar la operación.

## Tabla de transiciones y operaciones

Las filas normales presuponen rst=0. En STREAM, tx_byte_valid=1 y
BYTE_FIRE equivale a tx_byte_ready. start_valid se ignora durante STREAM;
tx_byte_ready y los tres comparadores no afectan las decisiones de IDLE.

| Origen | Condición | Destino | Operación del datapath en ese posedge |
|---|---|---|---|
| IDLE | !start_valid | IDLE | Conservar X/Y/C |
| IDLE | start_valid | STREAM | INIT; X=0, Y=0, C=R |
| STREAM | !tx_byte_ready | STREAM | Conservar X/Y/C, byte y marcas |
| STREAM | BYTE_FIRE y !IS_B | STREAM | STEP_COMP; R→G o G→B |
| STREAM | BYTE_FIRE, IS_B y !X_END | STREAM | STEP_PIXEL; X=X+1, C=R |
| STREAM | BYTE_FIRE, IS_B, X_END y !Y_END | STREAM | STEP_LINE; X=0, Y=Y+1, C=R |
| STREAM | BYTE_FIRE, IS_B, X_END e Y_END | IDLE | FINISH; sin cargas de X/Y/C |

En todo posedge:

1. Si rst=1: STATE←IDLE, R_DONE←0, X←0, Y←0, C←R. Reset tiene prioridad
   sobre comienzo o último byte; no se genera éxito por el cuadro descartado.
2. Si rst=0: aplicar la tabla y actualizar **R_DONE←FINISH** cada ciclo,
   incluso en reposo y en el flanco que acepta otra solicitud.

FINISH y START_FIRE nunca coinciden, porque requieren estados distintos.
En pausas y entregas intermedias, R_DONE se pone a 0. En la última entrega
R_DONE pasa a 1 al mismo tiempo que STATE vuelve a IDLE. Un estado DONE
añadiría una espera que no necesita el contrato.

## Cronograma de referencia

| Flanco | Estado previo | Transferencia / condición | Estado posterior | Resultado posterior |
|---|---|---|---|---|
| N | IDLE | START_FIRE | STREAM | Primer R válido; busy=1; frame_done=0 |
| N+1 | STREAM | BYTE_FIRE en R | STREAM | G del mismo píxel |
| N+2 | STREAM | ready=0 | STREAM | Conservar G, posición y marcas |
| N+3 | STREAM | BYTE_FIRE en G | STREAM | B del mismo píxel |
| M | STREAM | BYTE_FIRE en último B del cuadro | IDLE | valid=0, byte=0, marcas=0; frame_done=1, start_ready=1 |
| M+1 | IDLE | start_valid=1 | STREAM | Nuevo primer R; frame_done=0 |

Si start_valid=0 en M+1, se permanece en IDLE y frame_done también se
limpia. start_valid puede mantenerse alto para repetir sin CPU: se acepta
exactamente un cuadro por START_FIRE. No hace falta bajarlo para rearmar.
La fuente avanza un byte por ciclo cuando ready=1, sin pausas entre
componentes, píxeles o líneas. Este comportamiento no fija la tasa de DSI.

## Verificación documental

`python dsi_test_pattern/docs/verificar_fsm.py` comprueba:

- Las 128 combinaciones binarias de estado, reset, solicitud, ready y los
  tres comparadores, con ambos valores previos de R_DONE: **256 casos**.
- Exclusión de controles, prioridad de reset, pulso de fin y ausencia de
  aceptación de inicio durante STREAM o en el mismo flanco del último byte.
- Todas las filas de transición, incluyendo pausas sobre el último B,
  start_valid sostenido, reposo después de fin y reset en la última entrega.
- Equivalencia con el modelo del datapath en los estados legales de X/Y/C.
- Dos cuadros por perfil 8×1, 16×2 y 720×720, con pausas y comparación
  byte a byte contra la referencia de franjas, más reset en R/G/B.
- Conexiones del editable y correspondencia de IDLE/STREAM con el diagrama.

Son comprobaciones de las ecuaciones y el diseño documental. No son
simulación RTL, síntesis, timing ni prueba del panel. La inicialización,
planificación DSI, integración física y presupuesto de tasas siguen fuera
de esta FSM.

Resultado ejecutado: **PASS** en la matriz de 256 casos, **PASS** en 960
combinaciones de equivalencia UC/datapath, **PASS** en los dos cuadros por
perfil, reset y estructura del editable. La regresión documental del
datapath también termina en **PASS**.

La [verificación RTL](verificacion.md) añade simulación de la fuente,
matriz de UC, enlace con el preparador largo y comprobación estructural Yosys.
