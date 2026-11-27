# Integración del cuadro aprobado

Base: `origin/main` `ee0593e`, con PR #21 y el módulo FRAME_TIMING
del PR #22 ya integrados. Rama propia `feature/fpgbc-frame-integration`.
No se modifica el repositorio vecino.

[Flujo y datapath editables](fpgbc_frame.drawio).

## Arquitectura y receta

Se conservan los cuatro bloques del contrato `MIPI_LCD` y los puertos
`VID_WORD[15:0]`, `VID_RD`, `VID_REQ` y `VID_LINE_RDY`. El parámetro
`FRAME_MODE=0` conserva el modo anterior de líneas RGB sin encuadre
para sus regresiones. El TOP de placa selecciona explícitamente `1`.

- `VIDEO_SOURCE` permanece intacto: barras existentes de ocho tramos
  de 90 píxeles, o blanco por parámetro. Cuenta solo al consumir `VID_RD`.
- `LINK_FSM` admite solo desde `LINE_WAIT`, con `READY && LOCK` y
  `VID_REQ && VID_LINE_RDY`; `INIT_REQ` conserva prioridad.
- El primer ↓ de `CLK_PRE` captura el descriptor de FRAME_TIMING y
  avanza el índice del periodo. El descriptor permanece estable hasta
  la próxima admisión, aunque no se lean píxeles en un sincronismo.
- `BURST_KIND[1:0]` es interno a MIPI_TX: 00 VSS, 01 HSS, 10 activo.
- `HS_PACKER` añade un contador de prefijo de cuatro bits en ↓ y un
  multiplexor combinacional. Arranca el datapath RGB original solo
  después de las ocho palabras del prefijo activo. No cambia sus
  contadores, cabecera, selector de píxeles ni cálculo CRC.
- `PHY_IF` añade un único SoT por carril y ráfaga. El PHY y sus tiempos
  de CRC/trail/post/reloj no cambian.

| Periodos | Tipo | Bytes DSI después del SoT |
|---|---|---|
| 0…2 | VSS candidato | `01 00 00 07` |
| 3…10 | HSS | `21 00 00 12` |
| 11…730 | Activo | HSS, Blanking, RGB888 de 720 píxeles |
| 731…742 | HSS | `21 00 00 12` |

Prefijo activo: `21 00 00 12`, seguido por
`19 06 00 25 00 00 00 00 00 00 70 08`.
El CRC de Blanking es constante sobre sus seis ceros; el CRC RGB se
borra al empezar su propia cabecera y cubre exclusivamente 2160 bytes.
No se añade VSE ni EoTp.

**Medición:** 743 periodos de 21,20 µs; 720 intervalos asociados a RGB
y 23 verticales, con ráfagas breves. **Reconstrucción:** Blanking de
seis ceros con CRC válido; HSS calibrado, no evidencia independiente.
**Decisión de ensayo aprobada:** receta vertical anterior, omisión de
VSE/EoTp y prefijo activo. No se presenta como protocolo original probado.

## Flancos y presupuesto

`d0` es el primer ↓ que captura `CLK_REQ`, después del ↑ de admisión.
Datapath en ↓; estados FSM en ↑; controles y selección de palabras
combinacionales. `RST_BYTE` es activo alto y debe cubrir ambos flancos.

| ↓ / evento | Acción del periodo activo |
|---|---|
| d0 | Captura tipo; avanza índice módulo 743. |
| d27…d40 | Entrada de datos LP01/PREP/ZERO original. |
| d41 | PHY_IF publica SoT B8/B8; serializador aún ZERO. |
| d42/d43 | PHY_IF consume las dos palabras HSS; serializador toma primero SoT. |
| d44…d49 | Consume seis palabras Blanking. Sin lectura RGB. |
| d50/d51 | Consume cabecera RGB 3E/70 y 08/13; borra CRC en d50. |
| d52 | Primera palabra RGB presentada antes del flanco: PHY_IF y CRC la consumen; después la fuente avanza. |
| d53…d1130 | Lecturas RGB consecutivas. |
| d1131 | Última lectura, palabra 1079. Fuente vuelve al índice/fase cero. |
| d1132 | PHY_IF consume CRC; serializador toma último píxel. PK_DONE se publica después de ↓. |
| ↑ siguiente | LINK_FSM entra en EOT, cae HS_REQ. |
| d1133 | Serializador aún toma el CRC registrado. |
| d1134…d1140 | Trail, conservando la latencia OSER8 presupuestada. |
| d1141/1142/1143 | Corte HS de datos / aislamiento / LP11. |
| d1152…d1155 | Retirar alternancia CLK; último pulso natural y HS-0. |
| d1159/1160/1161 | Corte OE CLK / aislamiento / LP11. |
| d1167 | READY disponible después del ↓. |
| ↑ siguiente / d1168 | Admisión y primer ↓ de la siguiente reserva. |

Un sincronismo solo consume dos palabras en d42/d43; publica fin
después de d43 y el serializador consume la última en d44. El cierre
físico se desplaza 1081 ciclos respecto a la línea RGB anterior al
prefijo: READY vuelve en d78. El resto del periodo conserva LP11.

| Presupuesto | Activo | Sincronismo |
|---|---:|---:|
| Palabras DSI (sin SoT) | 1091 | 2 |
| Reserva lógica con drenaje/trail | 1138 | 49 |
| GAP lógico | 29 | 1118 |
| LINE_WAIT | 1 | 1 |
| Total | **1168** | **1168** |

El temporizador necesita 11 bits por el GAP de sincronismos. El GAP
contiene parte del cierre físico: no es un porch conocido. READY de
la base era d1159; los ocho ciclos del prefijo lo llevan a d1167,
demasiado tarde para C_LINE=1166. No se oculta el retraso con una
readmisión variable: se usa el ajuste aprobado a 1168.

Periodo resultante a 55 MHz: 21,23636 µs; cuadro 15,77862 ms,
~63,3769 Hz, +0,1715 % de periodo respecto a lo medido. No se recortan
CRC, trail, CLK-POST, HS-0 de CLK ni guarda LP11.

Reset común reinicia secuenciador desde ROM 0, dirección/fase RGB,
contador/descriptor de cuadro y prefijo; no se reanuda un cuadro parcial.
El camino ↑→↓ de control dispone de medio ciclo de byte; los registros
del descriptor están disponibles desde d0 antes de generar paquetes.
