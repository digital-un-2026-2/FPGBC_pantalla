# FSM del planificador DSI

**Especificación implementada en `../src/`.** Completa el [flujo](flujo.md) y el [datapath](datapath.md).
El [editable único](DSI_VIDEO_SCHEDULER.drawio) contiene las transiciones en
página 7 y los controles en página 8. [PDF](FSM.pdf) · [Transiciones SVG](fsm.svg) ·
[Controles SVG](fsm_controles.svg).

## Estado, reloj y prioridades

STATE[3:0] usa codificación binaria explícita. Registros en posedge de clk,
reset síncrono activo alto. No se añade next_state registrado ni un registro
de acciones. Los enables se calculan antes del flanco y el datapath ejecuta
la operación en ese mismo flanco.

Prioridad: **rst → fallo → transición normal**. Reset pone STATE=IDLE y
limpia UC y datapath con el reset coordinado de toda la cadena. FAULT solo
sale mediante ese reset; CLEAR_ERROR aislado no recupera un paquete parcial.
Los códigos 10–15 se detectan como ilegales y llevan a FAULT con causa 5.
No se promete detección física de X/Z ni protección de todos los fallos de bits.

| Código | Estado | Transición normal y acción en el flanco |
|---|---|---|
| 0000 | IDLE | START_ACCEPT copia R_SHADOW→R_ACTIVE y pasa a ARM |
| 0001 | ARM | SF inicia fuente y cuadro; FRAME_BEGIN; pasa a LOAD |
| 0010 | LOAD | Si IP_OK, EVENT_LOAD captura ROM_EVENT; pasa a RELEASE |
| 0011 | RELEASE | Con released: WAIT→ADVANCE, RGB→CMD, END_OK→FINISH |
| 0100 | CMD | DF acepta descriptor; limpia contador/banderas de paquete; pasa a PAYLOAD |
| 0101 | PAYLOAD | LAST_BF acepta último byte de payload; pasa a TX_WAIT |
| 0110 | TX_WAIT | PKT_OK emite RGB_COMPLETE una vez; pasa a ADVANCE |
| 0111 | ADVANCE | Si NEXT_IP_OK, EVENT_ADVANCE incrementa IP; pasa a LOAD |
| 1000 | FINISH | STOP_NEXT→IDLE; de lo contrario ARM para otro cuadro |
| 1001 | FAULT | Conservar hasta rst; bloquear nuevos inicios |

Sin guard habilitado se conserva STATE. LOAD y ADVANCE con índice inválido
van a FAULT (causa 5). RELEASE con KIND=3 va a FAULT incluso antes de RELEASE.
El calendario solo permite END en el último índice; END en otra posición
es causa 5. Un evento RGB con LINE≥HEIGHT es causa 6.

En RELEASE/END, LINE debe llegar a HEIGHT; FRAME_SEEN_NEXT y fuente/enlace
libres completan END_OK. Si todavía falta una condición, conservar estado
hasta cumplirla o perder su plazo. FRAME_COMPLETE se emite en RELEASE al
aceptar END, **antes** de entrar en FINISH: no se retrasa el éxito a un ciclo
posterior que pudiera quedar fuera del plazo. FINISH no vuelve a contar el cuadro.

## Handshakes y salidas

```text
SF      = source_start_valid && source.start_ready
DF      = cmd_valid && packet.cmd_ready
BF      = payload_valid && packet.payload_ready
LAST_BF = BF && (BCNT == WC-1)
IP_OK   = IP < N_EVENTS
NEXT_IP_OK = (zero_extend_17(IP)+1) < N_EVENTS

PKT_OK = (PKT_NEXT == 3'b111) && !transport.busy && !packet.busy &&
         (BCNT == WC) && (LINE < HEIGHT)
END_OK = released && (KIND == END) && (IP == N_EVENTS-1) &&
         (LINE == HEIGHT) && FRAME_NEXT && chain_free
```

PKT_NEXT y FRAME_NEXT incorporan tanto memoria retenida como pulsos actuales.
`chain_free` exige fuente, preparador, transporte y árbitro lógicamente libres.
El fin físico de cada paquete se confirma por hs_complete del árbitro antes
de RGB_COMPLETE. Los errores externos y FAULT_REQ siempre invalidan el éxito.

```text
running       = STATE en ARM/LOAD/RELEASE/CMD/PAYLOAD/TX_WAIT/ADVANCE/FINISH
stopped       = (STATE == IDLE) && chain_free && !R_ERROR.valid && !rst
frame_active  = STATE en LOAD/RELEASE/CMD/PAYLOAD/TX_WAIT/ADVANCE
event_valid   = STATE en RELEASE/CMD/PAYLOAD/TX_WAIT
pkt_window    = DF || STATE en PAYLOAD/TX_WAIT
frame_window  = FRAME_BEGIN || frame_active
stop_window   = START_ACCEPT || running

source_start_valid = (STATE == ARM) && !HARD_BLOCK
cmd_valid          = (STATE == CMD) && !HARD_BLOCK
G = (STATE == PAYLOAD) && (BCNT < WC) && !HARD_BLOCK
```

FRAME_BEGIN=SF reinicia IP, TICK, LINE y la bandera de fuente. En LOAD,
EVENT_LOAD captura el evento combinacional. EVENT_ADVANCE se emite solo
en ADVANCE, con NEXT_IP_OK; RGB_COMPLETE ya incrementó LINE en TX_WAIT.
No se mantienen ventanas de actividad en registros adicionales.

R_ACTIVE se carga solo al aceptar START en IDLE. FRAME_BEGIN no lo modifica;
repetir cuadros vuelve FINISH→ARM sin nuevas escrituras CSR. Un único START
produce cuadros hasta STOP o fallo. source_start_valid y cmd_valid permanecen
activos mientras esperan ready, salvo reset/fallo urgente que aborte la cadena.
STOP no cancela un handshake, un evento ni un cuadro.

## Plazos y fallos sin lazos combinacionales

HARD_BLOCK es una condición **independiente de BF y DF**: rst, código de
estado ilegal, STATE=FAULT, R_ERROR.valid o fallo urgente. Durante ejecución,
fallos urgentes son PHY/phy_abort, transporte, overflow y plazos vencidos.
No entrar en FAULT por simple falta de disponibilidad de la PHY mientras
se está en IDLE: START queda rechazado hasta que esté disponible.

Los errores locales de marcas o conteo pueden depender del handshake que
acaba de ocurrir. No deben volver a enmascarar combinacionalmente G ni BF.
El byte aceptado se contabiliza; se registra el fallo y se entra en FAULT en
ese flanco. No emitir RGB_COMPLETE, FRAME_COMPLETE, EVENT_LOAD/ADVANCE ni
FRAME_BEGIN como éxito cuando FAULT_REQ=1. Si un fallo local apareciera junto
a otro handshake válido independiente, ese handshake tampoco se borra
retroactivamente; recuperar exige reset coordinado.

Esto precisa la máscara genérica fault_block del datapath y evita el lazo
`G → BF → mark_error → G`. La FSM no conduce pads directamente ni sustituye
el aborto que ya implementan árbitro y PHY.

El plazo de evento se comprueba **solo mientras event_valid**. En ADVANCE
el evento anterior ya terminó; no volver a comprobar su DEADLINE. En LOAD
todavía no está vigente el nuevo R_EVT. Sí se comprueba T_FRAME en todos los
estados frame_active, incluidos LOAD y ADVANCE. FINISH queda fuera del tiempo
del cuadro que ya terminó. Completar con TICK==DEADLINE está permitido;
TICK>DEADLINE causa fallo antes del éxito. TICK continúa bajo backpressure.
ARM espera ready sin timeout de cuadro porque FRAME_BEGIN aún no ha ocurrido.

P_ERR conserva la prioridad definida en el datapath: PHY/aborto (1), transporte
(2), overflow (3), plazo (4), evento/índice/STATE ilegal (5), contador (6), marcas
(7), fuente (8). Fuente inconsistente incluye frame_done durante su ventana
cuando no se han aceptado todos los bytes de la última línea. Para esa señal
registrada se comprueba BCNT==WC y LINE==HEIGHT−1, o LINE==HEIGHT si el paquete
ya terminó; no se exige coincidencia con el último BF.

LD_ERROR=FAULT_REQ && !R_ERROR.valid. Un código ilegal se detecta incluso fuera
de ejecución; errores de la cadena se convierten en fallo del planificador
solo mientras running. En FAULT se conserva la primera causa y se invalidan
config_ok y panel_initialized.

## CSR y memoria de UC

UC agrega **6 bits**: STATE[4], config_ok[1], panel_initialized[1]. Los registros
de retención de eventos y primera causa ya pertenecen al datapath. Presupuesto
propuesto: 198 bits datapath + 10 R_SHADOW CSR + 6 UC = **214 bits**, excluyendo
ROM, CPU, bus y módulos externos. No es resultado de síntesis.

Solo IDLE con stopped permite escribir configuración, APPLY o autorización.
Si llegan varios comandos detenidos: `cfg_write > APPLY > escritura de
panel_initialized > START`. La escritura de configuración invalida config_ok;
APPLY lo carga con cfg_match. En escritura de autorización, clear domina set.
START_ACCEPT exige config_ok, panel_initialized, chain_free, PHY disponible,
ausencia de fallos y ausencia de comandos con mayor prioridad.

START/APPLY se interpretan como strobes de escritura CSR, no niveles que se
reintenten automáticamente. Solicitudes durante ejecución se rechazan sin
cola. STOP puede coincidir con START; el set dominante de R_STOP hará que la
ejecución se detenga después de su primer cuadro. Un STOP en FINISH también
se incluye en STOP_NEXT para evitar iniciar otro cuadro. STOP en IDLE sin
START no abre ejecución ni queda pendiente para un futuro inicio.

config_ok y autorización se limpian por reset/fallo. `running` y `stopped`
se decodifican; en FAULT ambos son cero y software consulta error. Ventanas,
event_valid y pulsos de operación también se decodifican; no añaden memoria.

## Verificación y límites

`python dsi_video_scheduler/docs/verificar_fsm.py` comprueba el modelo simbólico
de guards, códigos y enables empleado como especificación. Cubre prioridad
de reset/fallo, códigos ilegales, pausas, ventanas, límites de índice,
operaciones únicas y recorridos WAIT/RGB/END con STOP y repetición.
El generador usa la misma lista de estados para las vistas.

Esta comprobación simbólica no ejecuta RTL ni certifica tiempos del panel.
`pixi run --locked test-dsi-display` ejecuta la FSM con la cadena real, verifica
ECC/CRC desde pads simulados, STOP, reset, fallos, plazos y control CSR.
No se cambia la limitación del perfil WAIT/RGB/END: un
modo real del panel puede necesitar eventos y preparadores adicionales.
