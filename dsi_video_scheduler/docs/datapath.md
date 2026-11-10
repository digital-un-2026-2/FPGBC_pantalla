# Datapath del planificador DSI

**Especificación implementada en `../src/`.** Deriva del [flujo](flujo.md).
La [integración de pantalla](../../dsi_display/README.md) añade CSR, mailbox
entre relojes y pruebas con los módulos reales. El perfil del panel sigue pendiente.
El [editable único](DSI_VIDEO_SCHEDULER.drawio) contiene flujo en páginas 1–2
y datapath en páginas 3–6. [PDF del datapath](DATAPATH.pdf).

Vistas: [configuración](datapath_config.svg), [calendario](datapath_calendario.svg),
[payload](datapath_payload.svg) y [supervisión](datapath_estado.svg).
Registros rectangulares, MUX con entradas numeradas, operadores separados,
buses con ancho y controles discontinuos. Las redes con igual nombre se
conectan entre páginas; las ecuaciones explicitan los operandos y enables.
Las cajas externas contienen módulos existentes, no nueva lógica interna.

## 1. Configuración y reloj

La primera versión selecciona un **perfil constante de elaboración** mediante
`profile_id[7:0]` y `vc[1:0]`. Un perfil reúne dimensiones, calendario y
compatibilidad con la PHY. La fuente `dsi_test_pattern` ya elaborada debe
tener exactamente esas dimensiones. Esto concreta la configuración genérica
del flujo: no se convierte el WIDTH/HEIGHT del generador en registros de CPU.
No se añade un cargador de programas de eventos ni un framebuffer.

Un único `clk` para CSR, planificador, fuente y cadena lógica, registros en
posedge, `rst` síncrono activo alto con prioridad sobre LD. El target futuro
debe elegir su frecuencia a partir de la implementación física; 40 MHz es
solo el reloj de las pruebas existentes. Si CPU/CSR y vídeo usan dominios
distintos, será necesario un puente que transfiera coherentemente órdenes,
configuración y respuestas. Un sincronizador por bit no basta para ese bus.
Los cruces y flancos internos de la PHY existente conservan sus contratos.

`cfg_write` solo actualiza R_SHADOW con `stopped=1`. Toda escritura aceptada
invalida `config_ok` en UC. APPLY no copia registros: valida la selección.
Una escritura y APPLY/START simultáneos no aceptan APPLY/START; el software
debe volver a solicitarlo. START solo se acepta con configuración validada,
panel autorizado, fuente y cadena disponibles. Captura R_ACTIVE y abre una
ejecución; cuadros repetidos usan el mismo R_ACTIVE. Escrituras durante
ejecución se rechazan y no modifican los registros. STOP queda pendiente
hasta fin de cuadro y enlace libre.

ROM_META tiene lectura combinacional por perfil y contiene WIDTH[16],
HEIGHT[16], N_EVENTS[16], T_FRAME[32] y banderas constantes de certificación
temporal/destino. C_CFG consulta esos mismos metadatos con el ID candidato
de R_SHADOW; la ruta de ejecución consulta con R_ACTIVE. No se necesita un
registro de metadatos adicional. La validación exige:

- `1 ≤ N_PROFILES ≤ 256`; comparar el ID extendido a 9 bits para admitir 256.
- WIDTH coincide con la fuente, es ≥8 y múltiplo de 8; HEIGHT coincide y es ≥1.
- `WC_EXT = zero_extend_18(WIDTH) + (zero_extend_18(WIDTH) << 1)`.
  Exigir WC_EXT≤65535 y WC_EXT+6≤2×BUFFER_WORDS antes de truncar WC a 16 bits;
  hacer la suma de capacidad al menos en 19 bits. Paquete total par.
- `1 ≤ N_EVENTS ≤ 65535`; todos los accesos IP están dentro de ese rango.
- Calendario certificado para el reloj, costes de UC/preparación, transporte
  y PHY del destino. Un perfil solo sintético no autoriza hardware físico.

La tabla se comprueba al elaborar/generar y al verificar el diseño, no mediante
un nuevo procesador de validación en hardware. APPLY consulta sus condiciones
y banderas constantes. No hay actualmente un perfil real certificado.
La autorización del firmware no anula `PROFILE_OK=0` del wrapper Gowin.

M_STATUS selecciona palabras de estado de 32 bits mediante la dirección CSR:
0 estado UC; 1 R_FRAMES; 2 R_ERROR; 3 R_ACTIVE; 4 WIDTH; 5 HEIGHT. Extender
con ceros los campos cortos y devolver cero para entradas no asignadas.
Es una selección lógica propuesta; el futuro banco CSR puede distribuir
estas palabras en registros separados sin cambiar el datapath funcional.

## 2. Memoria y operadores

Todos los registros del planificador resetean a cero. LD=0 conserva Q.
R_SHADOW pertenece al banco CSR; el resto de esta tabla pertenece al datapath.

| Registro | Bits | Carga / función |
|---|---:|---|
| R_SHADOW | 10 | Escritura CSR aceptada: ID[8] y VC[2] |
| R_ACTIVE | 10 | START_ACCEPT copia R_SHADOW |
| R_TICK | 32 | FRAME_BEGIN pone 0; TICK_EN incrementa |
| R_IP | 16 | FRAME_BEGIN pone 0; EVENT_ADVANCE incrementa |
| R_EVT | 66 | EVENT_LOAD copia KIND[2], RELEASE[32], DEADLINE[32] |
| R_BCNT | 16 | DF pone 0; BF incrementa bytes de payload |
| R_LINE | 16 | FRAME_BEGIN pone 0; RGB_COMPLETE incrementa líneas terminadas |
| R_PKT_SEEN | 3 | Retiene {hs_complete, hs_done, packet_done} por paquete |
| R_FRAME_SEEN | 1 | Retiene source.frame_done por cuadro |
| R_STOP | 1 | Retiene solicitud STOP por ejecución |
| R_ERROR | 5 | Primera causa: valid[1] y cause[4] |
| R_FRAMES | 32 | FRAME_COMPLETE incrementa, módulo 2³² |

**198 bits de datapath**, más 10 bits de R_SHADOW en CSR. No incluye estado
de UC, config_ok, panel_initialized, ventanas de captura, decodificación CSR
ni memoria interna de bloques externos. Es un presupuesto lógico propuesto,
no un resultado de síntesis.

A0/A1/A2/A3/A4 son sumadores +1 de TICK/IP/BCNT/LINE/FRAMES respectivamente.
M0/M1/M2/M3 son MUX 2:1 del mismo ancho que su registro, entrada 0=0,
entrada 1=Q+1. SEL es el inverso del evento de inicialización. La retención
la expresa LD, sin otro MUX de realimentación externo.

```text
R_TICK: LD = FRAME_BEGIN | TICK_EN;       SEL_M0 = !FRAME_BEGIN
R_IP:   LD = FRAME_BEGIN | EVENT_ADVANCE; SEL_M1 = !FRAME_BEGIN
R_BCNT: LD = DF | BF;                    SEL_M2 = !DF
R_LINE: LD = FRAME_BEGIN | RGB_COMPLETE; SEL_M3 = !FRAME_BEGIN
R_FRAMES: D = A4; LD = FRAME_COMPLETE
```

FRAME_BEGIN coincide con el handshake de inicio de la fuente; UC lo emite
una vez por cuadro. DF solo se acepta cuando el preparador está libre; el
preparador actual no acepta payload en ese mismo flanco. RGB_COMPLETE es un
evento único de UC por paquete RGB, después de verificar su finalización;
no es un alias combinacional permanente de las banderas retenidas.

## 3. Calendario

ROM_EVENT es una tabla lógica combinacional, constante al elaborar. Cada
perfil contiene hasta E_MAX eventos, expandiendo las líneas del cuadro.
Cada entrada tiene **66 bits**: KIND[2], RELEASE[32], DEADLINE[32]. Memoria
lógica `N_PROFILES × E_MAX × 66` bits, más metadatos. La implementación física
y posibles optimizaciones quedan para síntesis. Cambiarla por BRAM síncrona
exige añadir una fase de lectura y revisar sus costes temporales.

| KIND | Evento | Acción |
|---|---|---|
| 0 | WAIT | Terminar cuando TICK alcanza RELEASE |
| 1 | RGB | Descriptor y payload de una línea; completar antes de DEADLINE |
| 2 | END | Fin de cuadro, tras RELEASE y con todas las operaciones completas |
| 3 | Inválido | Fallo; también se devuelve para una dirección no válida |

Esta versión concreta únicamente el recorrido RGB existente. Los modos de
panel que necesiten sincronismos, blanking en paquetes o comandos de memoria
requieren ampliar el formato y los preparadores. No se declara compatible
con Video Mode ni Command Mode del LCD sin esa definición. Un perfil
sintético puede verificar la arquitectura sin constituir un modo real.

Cada perfil legal contiene exactamente HEIGHT eventos RGB, termina en END
y cumple `0 ≤ RELEASE ≤ DEADLINE ≤ T_FRAME ≤ 0xFFFFFFFE`. La certificación
comprueba orden y ventanas con los ciclos de carga/avance, preparación de
paquetes y finalización del enlace. El transporte no admite cargar el
siguiente paquete mientras envía el actual; esa limitación entra en el
presupuesto temporal. No basta comprobar el número de píxeles por segundo.

R_EVT se carga una vez y permanece estable hasta EVENT_ADVANCE. UC conserva
event_valid, decodifica KIND y no envía un descriptor antes de `released`.

```text
released   = R_TICK >= R_EVT.RELEASE
late       = event_valid && (R_TICK > R_EVT.DEADLINE)
frame_late = frame_active && (R_TICK > T_FRAME)
overflow   = frame_active && (R_TICK == 0xFFFFFFFF)
TICK_EN    = frame_active && !overflow
```

La comparación usa Q antes del flanco; completar en DEADLINE está permitido.
El tiempo continúa bajo backpressure. Overflow detiene el contador y registra
fallo, sin envolver. Un plazo vencido tiene prioridad sobre completar con éxito.
Al avanzar IP se calcula IP+1 en **17 bits** y se exige `< N_EVENTS`; nunca
se depende del desbordamiento de R_IP. END no avanza IP.

## 4. Payload y líneas

Descriptor RGB combinacional desde configuración activa:
`cmd_vc=VC`, `cmd_dt=6'h3E`, `cmd_wc=WC_EXT[15:0]`. R_ACTIVE no cambia
durante la ejecución, de modo que estos campos permanecen estables bajo
backpressure. UC conserva cmd_valid hasta DF y no lo reemite para el mismo
evento. Cada cuadro inicia la fuente una sola vez, no una vez por línea.

```text
DF = cmd_valid && cmd_ready
G = rgb_payload_window && !rst && !fault_block
payload_data  = source.tx_byte_data
payload_valid = source.tx_byte_valid && G
source.tx_byte_ready = packet.payload_ready && G
BF = payload_valid && packet.payload_ready
```

rgb_payload_window abre después de aceptar el descriptor y cierra al consumir
WC bytes; la fuente conserva el siguiente byte entre líneas. Byte[8] no tiene
registro adicional en el planificador. Los registros del generador y del
preparador existentes garantizan su estabilidad cuando no hay handshake.

La [FSM](fsm.md) concreta fault_block como HARD_BLOCK, independiente de BF/DF.
Un fallo local de marcas derivado de BF registra el error en ese flanco sin
cancelar retroactivamente el handshake ni crear un lazo combinacional.

```text
expect_line_last  = (R_BCNT == WC-1)
expect_frame_last = expect_line_last && (R_LINE == HEIGHT-1)
mark_error = BF && ((source.tx_line_last != expect_line_last) ||
                   (source.tx_frame_last != expect_frame_last))
count_error = (BF && R_BCNT >= WC) ||
              (packet_done && R_BCNT != WC) ||
              (RGB_COMPLETE && R_LINE >= HEIGHT)
```

Comparaciones y sumas usan valores antes del flanco. R_BCNT cuenta de 0 a WC
inclusive, R_LINE de 0 a HEIGHT inclusive; ambos caben en 16 bits con los
límites elegidos. BCNT incrementa con BF, LINE con RGB_COMPLETE, y no avanzan
fuera de sus límites en una operación legal. Las marcas solo se comprueban
con BF. `source.tx_line_last` no se conecta a la salida `packet.tx_byte_last`.

El recorrido externo conserva byte[8] con valid/ready/last hasta el packer;
después palabra[16], keep[2] y valid/ready/last al transporte. Las flechas del
diagrama indican el avance de datos; ready retorna al productor en cada enlace.
ECC, CRC, RAM y serialización pertenecen a sus módulos actuales.

## 5. Eventos, fallos y separación de UC

M4/M5/M6 seleccionan Q o cero para los registros PKT/FRAME/STOP; una OR
separada G0/G1/G2 incorpora las entradas nuevas, con set dominante sobre clear:

```text
PKT_NEXT   = (DF           ? 0 : R_PKT_SEEN)   | pkt_events
FRAME_NEXT = (FRAME_BEGIN  ? 0 : R_FRAME_SEEN) | source.frame_done
STOP_NEXT  = (START_ACCEPT ? 0 : R_STOP)       | CSR_STOP
```

Capturar pkt_events solo en la ventana desde DF hasta RGB_COMPLETE, incluyendo
ambos extremos. Capturar frame_done desde FRAME_BEGIN hasta FRAME_COMPLETE.
Fuera de esas ventanas y sin clear se conserva Q; no se capturan eventos
ajenos a la operación. STOP se acepta durante ejecución o START_ACCEPT.
Reset domina todos los sets. Las ventanas de captura pertenecen a UC.

`packet_complete = (PKT_NEXT == 3'b111) && !transport.busy`. Los eventos
son los de los módulos reales: packet_done del preparador, hs_done del
transporte y hs_complete del árbitro. PHY/transport errors invalidan el éxito.
RGB_COMPLETE requiere además BCNT==WC y evento RGB vigente; UC lo emite
una vez. Las banderas se vuelven a limpiar con el siguiente DF.

END requiere LINE==HEIGHT, FRAME_NEXT=1, transporte libre y ningún paquete
pendiente, además de su ventana temporal. UC espera hasta esa condición o
el plazo; al cumplirse emite FRAME_COMPLETE una vez. `source.frame_done`
solo expresa entrega local y no incrementa R_FRAMES por sí solo. STOP se
atiende después de FRAME_COMPLETE; sin STOP se prepara otro cuadro, sin
recapturar la configuración activa. Los tiempos entre cuadros deben entrar
en la certificación del perfil; no se promete una frecuencia con este dibujo.

P_ERR selecciona la causa por prioridad: 1 PHY/aborto; 2 transporte; 3 overflow;
4 plazo; 5 evento/índice ilegal; 6 contador; 7 marcas; 8 fuente inconsistente.
Cero significa sin causa. `LD_ERROR=FAULT_REQ && !R_ERROR.valid`; D={1,cause}.
Si ya hay causa, no se sobrescribe. El error de validación de configuración
rechaza APPLY/START mediante config_ok y no fabrica un cuadro ni un fallo
de transmisión. Reset coordinado limpia el diagnóstico del planificador;
los diagnósticos propios de la PHY conservan su mecanismo de recuperación.

La [FSM propuesta](fsm.md), páginas 7–8 del editable, usa STATE[4], config_ok[1]
y autorización[1]. event_valid, ventanas y niveles de valid se decodifican de
STATE. El datapath devuelve comparaciones y banderas. No duplicar running/stopped
en registros adicionales. DF/BF son cables combinacionales de handshake.
La FSM limita event_valid a RELEASE/CMD/PAYLOAD/TX_WAIT: no comprueba el plazo
de un evento ya terminado en ADVANCE ni el R_EVT previo durante LOAD.

## Verificación prevista al implementar

- APPLY, escritura simultánea, ID fuera de rango, fuente incompatible,
  capacidad exacta y exceso; cambio activo rechazado.
- Eventos WAIT/RGB/END, release y deadline exactos, índice agotado,
  overflow, saturación y pausas que hacen vencer un plazo.
- Estabilidad de descriptor/bytes bajo pausas; WC y marcas de última línea.
- Finals en ciclos separados, clear y set coincidentes, señales fuera de
  ventana, un único RGB_COMPLETE/FRAME_COMPLETE y primera causa estable.
- STOP coincidente con START o fin de cuadro; cuadros consecutivos;
  reset durante descriptor, payload, envío, espera y error.
- Integración con módulos reales y comprobación del presupuesto temporal
  antes de certificar cualquier perfil para el panel.

Estas son condiciones de aceptación futuras. Las comprobaciones realizadas
ahora son de diagramas y ecuaciones; no equivalen a simulación RTL.
