# Flujo de dsi_test_pattern

Estado: **IMPLEMENTADO EN RTL**. [Editable](DSI_TEST_PATTERN.drawio) ·
[SVG](flujo.svg) · [PDF](FLUJO.pdf).

Se conservan las convenciones de los flujos de `dsi_long_packet_tx` y
`dphy_gowin_tx`: inicio redondeado, operaciones azules, decisiones amarillas,
flechas ortogonales, ramas Sí/No, bucles de espera y reset global prioritario.
Una caja expresa una operación; no necesariamente un estado o un ciclo.
Este documento describe el flujo. El [datapath](datapath.md) lo concreta en
las páginas 2–3 del mismo editable; la [FSM](fsm.md) está en la página 4.
El [RTL y sus pruebas](../README.md) siguen este contrato.

## Parámetros y patrón

Constantes de elaboración: `WIDTH=720`, `HEIGHT=720`. Para esta primera versión,
WIDTH debe ser >= 8 y múltiplo de 8; HEIGHT >= 1. Una configuración inválida
se rechaza al elaborar, antes de simular o sintetizar. No hay configuración por bus.

Cada franja mide B=WIDTH/8 píxeles. De izquierda a derecha:

| Índice | Color | RGB hexadecimal |
|---|---|---|
| 0 | Blanco | FFFFFF |
| 1 | Amarillo | FFFF00 |
| 2 | Cian | 00FFFF |
| 3 | Verde | 00FF00 |
| 4 | Magenta | FF00FF |
| 5 | Rojo | FF0000 |
| 6 | Azul | 0000FF |
| 7 | Negro | 000000 |

Seleccionar color por el intervalo `i*B <= x < (i+1)*B`; esta expresión
describe el patrón, no exige un divisor en hardware. El orden lógico de bytes
es R → G → B, recorriendo filas de izquierda a derecha y de arriba abajo.
Todas las filas son iguales. En el perfil de prueba: 90 píxeles/franja,
2160 bytes/línea y 1 555 200 bytes/cuadro.

## Interfaz

Un único dominio `clk`, inicialmente 40 MHz en simulación. Transferencias y
actualizaciones en posedge. `rst` activo alto, síncrono para la memoria;
mientras rst=1, se bloquean combinacionalmente ambos handshakes y las marcas.
Debe cubrir al menos un posedge y coordinarse con el consumidor al descartar.

| Puerto | Sentido | Bits | Semántica |
|---|---|---:|---|
| clk, rst | Entrada | 1 cada uno | Reloj y reset comunes |
| start_valid | Entrada | 1 | Solicitud de producir un cuadro |
| start_ready | Salida | 1 | Disponible para aceptar una solicitud |
| tx_byte_data | Salida | 8 | Componente R, G o B actual |
| tx_byte_valid | Salida | 1 | Byte disponible |
| tx_byte_ready | Entrada | 1 | Consumidor acepta el byte |
| tx_line_last | Salida | 1 | Byte B del último píxel de una línea |
| tx_frame_last | Salida | 1 | Byte B del último píxel del cuadro |
| busy | Salida | 1 | Cuadro aceptado y aún no entregado por completo |
| frame_done | Salida | 1 | Pulso de un ciclo al entregar el último byte |

`START_FIRE = start_valid && start_ready`; `BYTE_FIRE = tx_byte_valid &&
tx_byte_ready`. En reposo start_ready=1, busy=0 y tx_byte_valid=0. Mientras
se produce un cuadro start_ready=0, busy=1 y tx_byte_valid=1. Con valid=0,
tx_byte_data=0 y ambas marcas=0. No hay cola, timeout ni descarte por pausas.

Las marcas son niveles asociados al byte ofrecido: permanecen estables aunque
ready=0. Solo se consumen con BYTE_FIRE; no son pulsos independientes.
`tx_line_last` no se conecta a `dsi_long_packet_tx.tx_byte_last`: este último
es una salida del preparador que identifica el CRC alto, no el fin del payload.

## Algoritmo y contrato temporal

1. Reset desde cualquier punto: descartar cuadro, x=0, y=0, componente=R,
   busy=0 y frame_done=0. Reset tiene prioridad sobre cualquier transferencia.
2. Esperar START_FIRE. Al aceptarlo, inicializar coordenadas y componente;
   el primer byte queda disponible después de ese flanco.
3. Ofrecer el componente del color de x. Derivar line_last de
   `(x==WIDTH-1 && componente==B)` y frame_last de esa condición más
   `y==HEIGHT-1`, cualificados por tx_byte_valid.
4. Sin BYTE_FIRE, conservar coordenadas, componente, byte, marcas y busy.
5. Con BYTE_FIRE: si no era B, avanzar R→G o G→B. Si era B y no terminaba
   la línea, avanzar x e iniciar R. Si terminaba una línea intermedia,
   x=0, y=y+1 e iniciar R.
6. Al aceptar B del último píxel del último renglón, liberar busy y emitir
   frame_done durante un ciclo. Volver a esperar solicitud.

Las decisiones de avance se refieren al byte aceptado y a los valores
anteriores al flanco. No hay ciclos de espera añadidos entre componentes,
píxeles o líneas: con ready=1 se entrega un byte por ciclo durante el cuadro.
frame_done se limpia en el siguiente posedge, incluso si se acepta otro cuadro.
No se acepta un nuevo inicio en el mismo flanco del último byte.

start_valid puede permanecer alto: cada START_FIRE inicia otro cuadro idéntico.
Esto permite repetición autónoma al atarlo a 1 en un arnés, sin CPU; no hay
rearme por flanco ni obligación de bajar la solicitud. Tras reset se puede
aceptar una solicitud nueva. frame_done solo significa entrega local del
payload, no fin de paquete, ráfaga física ni recepción del LCD.

## Integración posterior y límites

Un planificador externo presentará el descriptor de cada línea al preparador
de paquetes largos y conectará la fuente al payload cuando corresponda,
regulando tx_byte_ready entre líneas. La planificación fija VC, DT, WC,
eventos de sincronismo, blanking y ritmo de cuadro. No se asignan aquí
porches, fps, bitrate, temporizaciones D-PHY ni secuencia de inicialización.
El generador no recibe packet_done ni controla directamente HS o pads.

La fuente reutiliza `dsi_long_packet_tx`, su interfaz y su contrato de
payload, documentados en [su README](../../dsi_long_packet_tx/README.md).
Una fuente capaz de entregar un byte por ciclo no aumenta la tasa del
preparador actual (un byte de payload cada tres ciclos). El consumidor puede
pausar esta fuente; la continuidad de una ráfaga HS la garantiza otra capa.

## Criterios de verificación

- Reconstruir el cuadro 720 × 720 desde bytes aceptados y comparar cada píxel
  con una imagen de referencia; comprobar las ocho fronteras y el orden RGB.
- Contar 2160 bytes por línea, 720 marcas de línea y una de cuadro; comprobar
  frame_done solo después del último BYTE_FIRE.
- Cubrir WIDTH=8/16/720, HEIGHT=1/2/720 y rechazar dimensiones inválidas.
- Pausar en R/G/B y en los últimos bytes de línea/cuadro; comprobar estabilidad
  y ausencia de pérdidas, duplicaciones o avances sin handshake.
- Solicitud pendiente, solicitud mantenida alta y cuadros consecutivos;
  comprobar separación de inicios y entrega de exactamente un cuadro por inicio.
- Reset en reposo y durante R/G/B, incluida la coincidencia con el último byte;
  descartar sin éxito y reiniciar desde el primer píxel con una solicitud nueva.
- Integración con el preparador real: descriptor por línea, WC=3*WIDTH,
  payload exacto y ECC/CRC comprobados desde la salida del paquete.

Estos criterios se ejercitan en la [verificación RTL](verificacion.md).
La planificación por línea del enlace es un arnés de simulación; el
planificador RTL y la integración física siguen pendientes.
