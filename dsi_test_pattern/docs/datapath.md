# Datapath de dsi_test_pattern

**Implementado en RTL.** Derivado del [flujo](flujo.md), conservando
su interfaz. [Editable único](DSI_TEST_PATTERN.drawio), páginas 2–3.
[Recorrido SVG](datapath_recorrido.svg) · [Color y salida SVG](datapath_salidas.svg) ·
[PDF de las dos páginas](DATAPATH.pdf).
La [FSM](fsm.md) completa UC en la página 4 del mismo editable.

Las convenciones siguen los datapaths de `dsi_lane_packer` y `dphy_gowin_tx`:
bloques sin relleno, MUX con entradas numeradas, operadores separados,
buses [n], controles discontinuos y frontera explícita con UC.

## Memoria, reloj y límites

`NX=max(1, ceil(log2(WIDTH)))`, `NY=max(1, ceil(log2(HEIGHT)))`.
En RTL se usa `$clog2` con un mínimo de un bit, sin logaritmos reales.
WIDTH >= 8 y múltiplo de 8; HEIGHT >= 1, constantes de elaboración.

| Registro | Bits | Reset | Función y rango legal |
|---|---:|---:|---|
| R_X | NX | 0 | Píxel de la línea, 0…WIDTH−1 |
| R_Y | NY | 0 | Línea del cuadro, 0…HEIGHT−1 |
| R_C | 2 | 0 (R) | Componente: R=0, G=1, B=2 |

Total: **NX+NY+2 bits**, **22 bits para 720 × 720**. Son registros de
posición, no almacenamiento de imagen. No se añaden registros RGB, byte,
franja, fin de línea ni fin de cuadro; tampoco un contador de bytes totales.

Todos capturan en posedge del único clk. Reset síncrono activo alto tiene
prioridad sobre LD; LD=0 conserva Q. Los controles se calculan antes del
mismo flanco que acepta inicio o byte: no se registran para otro ciclo.
El perfil de simulación inicial es 40 MHz (25 ns/ciclo), sin negedge ni CDC.

La memoria de actividad pertenece a UC; no duplicar busy en el datapath.
El pulso público frame_done necesita un registro de un bit en UC, con
`D=FINISH` en cada ciclo y reset a cero. La FSM concreta UC con STATE[1]
(IDLE/STREAM) y R_DONE[1]: dos bits, no incluidos en los 22 bits anteriores.
El total lógico para 720 × 720 es de 24 bits.

## Contadores, MUX y comparadores

La página 2 dibuja tres registros, tres incrementadores A0/A1/A2 y tres
MUX 2:1 M0/M1/M2, respectivamente para X/Y/C. Cada MUX elige 0 o Q+1.
La retención la expresa LD, sin otro MUX externo de realimentación.

```text
CX: X_END = (X == WIDTH-1)
CY: Y_END = (Y == HEIGHT-1)
CC: IS_B  = (C == 2)

LD_X   = INIT | STEP_PIXEL | STEP_LINE
SEL_M0 = STEP_PIXEL
D_X    = SEL_M0 ? X+1 : 0

LD_Y   = INIT | STEP_LINE
SEL_M1 = STEP_LINE
D_Y    = SEL_M1 ? Y+1 : 0

LD_C   = INIT | STEP_COMP | STEP_PIXEL | STEP_LINE
SEL_M2 = STEP_COMP
D_C    = SEL_M2 ? C+1 : 0
```

Los sumadores tienen el mismo ancho que su registro; el acarreo no se
almacena. La secuencia legal nunca depende del desbordamiento binario:
X se incrementa solo antes de WIDTH−1, Y solo antes de HEIGHT−1 y C solo
en R/G. Desde B se carga 0 al pasar de píxel o línea. HEIGHT=1 sigue
teniendo NY=1, pero Y no se incrementa nunca.

INIT y los tres STEP son excluyentes durante operación legal. Al terminar
el cuadro se conservan X=WIDTH−1, Y=HEIGHT−1 y C=B hasta el siguiente
inicio o reset; las salidas se enmascaran al retirar valid.

## Color y byte de salida

La página 3 muestra siete comparadores de umbral:

```text
B = WIDTH/8                         (constante entera)
C1…C7: T_i = (X >= i*B), i=1…7      (operandos NX bits)
P0: S = mayor i con T_i=1; si ninguno, S=0
```

P0 es un codificador de prioridad combinacional 7→3, no un registro de
franja. Cada umbral se calcula al elaborar; no hay división variable.
M3 (8:1 de 24 bits) selecciona las constantes de la paleta del flujo:
FFFFFF, FFFF00, 00FFFF, 00FF00, FF00FF, FF0000, 0000FF, 000000.

M4 (4:1 de 8 bits), seleccionado directamente por C[1:0], entrega:

| C / entrada M4 | Byte |
|---|---|
| 0 | RGB[23:16], R |
| 1 | RGB[15:8], G |
| 2 | RGB[7:0], B |
| 3 | 00, código no usado |

M5 (2:1 de 8 bits) selecciona 00 cuando tx_byte_valid=0 y el byte de M4
cuando vale 1. Es la máscara de reposo/reset exigida por el flujo.
La selección 3 de M4 da un valor definido, pero no es detección ni
recuperación de fallo; ese código no se alcanza desde reset con las
operaciones legales. La FSM usa todos los códigos de su estado de un bit;
no se atribuye a este circuito detección de fallos o recuperación de X/Z.

## Marcas y frontera de control

```text
G0: LINE_END     = IS_B & X_END
G1: FRAME_END    = LINE_END & Y_END
G2: tx_line_last = tx_byte_valid & LINE_END
G3: tx_frame_last= tx_byte_valid & FRAME_END

start_ready  = !rst & !ACTIVE
tx_byte_valid= !rst & ACTIVE
busy         = ACTIVE
START_FIRE   = start_valid & start_ready
BYTE_FIRE    = tx_byte_valid & tx_byte_ready

INIT       = START_FIRE
STEP_COMP  = BYTE_FIRE & !IS_B
STEP_PIXEL = BYTE_FIRE & IS_B & !X_END
STEP_LINE  = BYTE_FIRE & IS_B & X_END & !Y_END
FINISH     = BYTE_FIRE & IS_B & X_END & Y_END
```

ACTIVE equivale a STATE=STREAM en la FSM, no a otro registro del
datapath. UC la activa al aceptar
inicio y la retira al entregar el último byte; reset la limpia en posedge.
Mientras rst=1, los dos handshakes y las marcas se anulan combinacionalmente.
busy puede reflejar la actividad previa hasta ese flanco de reset.

UC recibe clk/rst, start_valid, tx_byte_ready y las condiciones X_END,
Y_END e IS_B. Entrega los cuatro eventos de carga y las salidas públicas
start_ready, tx_byte_valid, busy y frame_done. El datapath deriva byte y
marcas. START_FIRE y BYTE_FIRE son cables combinacionales, no memoria.

| Operación del flujo | INIT | STEP_COMP | STEP_PIXEL | STEP_LINE | Efecto |
|---|---:|---:|---:|---:|---|
| Esperar o pausar | 0 | 0 | 0 | 0 | Conservar X/Y/C |
| Aceptar inicio | 1 | 0 | 0 | 0 | X=0, Y=0, C=R |
| Aceptar R o G | 0 | 1 | 0 | 0 | C=C+1 |
| Aceptar B, píxel no final | 0 | 0 | 1 | 0 | X=X+1, C=R |
| Aceptar B, línea intermedia completa | 0 | 0 | 0 | 1 | X=0, Y=Y+1, C=R |
| Aceptar último B del cuadro | 0 | 0 | 0 | 0 | FINISH a UC; conservar X/Y/C |
| Reset | 0 | 0 | 0 | 0 | Reset prioritario de los registros |

frame_done se registra como FINISH en cada posedge: un pulso después de
la última entrega, limpio en el siguiente flanco incluso si se acepta otro
inicio. No se registra tx_line_last ni tx_frame_last; su alineación con
el byte procede del mismo X/Y/C. No dependen de ready: con una pausa en el
último B, ambas marcas permanecen altas hasta que se acepte ese byte.

## Correspondencia temporal y comprobación

Tras START_FIRE, el primer R queda disponible después del flanco. Cada
BYTE_FIRE cambia componente o posición para el siguiente byte sin burbujas
internas. Al entregar el último B, UC desactiva valid, activa frame_done y
ofrece start_ready; el siguiente inicio se acepta como pronto en el próximo
posedge. La lógica de datos no realimenta ready y no introduce lazos de handshake.

`python dsi_test_pattern/docs/verificar_datapath.py` comprueba conexiones
del XML, decisiones del flujo, paleta y umbrales, recorrido, marcas, pausa,
reset y repetición mediante un modelo de las ecuaciones. Contrasta los bytes
con una referencia por posición lineal del cuadro. Es verificación del
diseño documental, **no simulación ni síntesis RTL**. La implementación,
las pruebas con el preparador real y la inspección Yosys se documentan en
[verificación RTL](verificacion.md).

Comprobación ejecutada: **PASS** en las tres configuraciones (dos cuadros
por configuración, con pausas), **PASS** en reset para R/G/B y límites,
y **PASS** en estructura del editable (cuatro páginas y conexiones válidas).

Se conserva el límite de alcance del flujo: no hay ECC/CRC, descriptor DSI,
porches, ritmo de cuadro, FIFO, framebuffer ni controles físicos. Una fuente
de un byte por ciclo no elimina los límites de tasa del preparador existente.
