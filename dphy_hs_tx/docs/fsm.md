# FSM propuesta de dphy_hs_tx

**PROPUESTO · 2026-11-08.** Derivada de [flujo](flujo.md),
[datapath](datapath.md) y [contrato temporal S320](contrato_temporal.md).
El RTL implementa este modelo funcional de paquetes pares; ver
[resultados y límites](../README.md). El generador serial es de testbench.

Editable único: [DPHY_HS_TX.drawio](DPHY_HS_TX.drawio), páginas 5–7.
Vistas: [preparación](fsm_preparacion.svg), [transferencia y retorno](fsm.svg),
[controles y fallos](fsm_control.svg); [PDF de tres páginas](FSM.pdf).

## Memoria, flancos y notación

STATE[4:0] contiene 25 estados con códigos 0…24. CAUSE[2:0] conserva la primera
causa local; phy_error=(CAUSE!=0). **Ocho bits de UC** y 52 de datapath: 60 bits
lógicos, excluidos el generador conductual serial. Los ACK se decodifican del
estado; no se añaden registros ACK, DONE, ACTION ni end_seen.

La memoria de UC y datapath cambia en **posedge clk**. Las salidas y enables
son combinacionales, con valores por defecto. Se calculan antes del mismo
flanco que mueve palabras, carga tiempos o cambia de fase; no se retienen
acciones para negedge ni se requiere un registro next_state.

Las salidas de fase cambian después del flanco; el modelo serial toma el
FRAME resultante después de las actualizaciones de los registros. Cada estado
SYNC o payload ocupa un intervalo completo T=25 ns. El árbitro conserva sus
flancos existentes y es el único que genera grant/complete.

Notación de tablas, siempre con entradas anteriores al posedge:

- Z: TIME_LAST_INTERVAL; J: POST_LAST_INTERVAL; V: hs_word_valid;
  L: hs_word_last; G: hs_grant; K: MASK_OK.
- P/Pf: P_VALID/P_LAST; A/Af: A_VALID/A_LAST.
- CS/DS/DT/CT: clk_start_req/data_start_req/data_stop_req/clk_stop_req.
- `T(k)` significa TIME_SEL=k, TIME_LOAD=1 en ese flanco.
- `PS` significa POST_STEP=1; `PL` significa POST_LOAD=1.
- CAP/MOV/RET/CLR: CAPTURE/MOVE/RETIRE/CLEAR_PIPE.

Salvo donde se indica, condiciones de espera conservan estado y memoria.
TIME_STEP=1 en los estados temporizados (INIT, LPX, Prepare, Zero mínimo,
PRE, Trail, Exit), incluso en el flanco de salida; TIME_LOAD tiene prioridad.
POST_STEP=1 en DATA_EXIT y WAIT_CLK_STOP. No se comparte TIME entre fases
simultáneas: solo POST transcurre en paralelo.

## Estados y transiciones normales

Toda transición está subordinada a las prioridades de fallo/reset descritas
más abajo. Las solicitudes ajenas no provocan saltos a otra fase.

| Código / estado | Condición de avance | Destino y acción en ese flanco |
|---|---|---|
| 0 BOOT | Siempre | INIT; T(0), CLR |
| 1 INIT | Z | IDLE |
| 2 IDLE | CS | CLK_LPX; T(1), CLR |
| 3 CLK_LPX | Z | CLK_PREP; T(2) |
| 4 CLK_PREP | Z | CLK_ZERO; T(3) |
| 5 CLK_ZERO | Z | CLK_PRE; T(4) |
| 6 CLK_PRE | Z | WAIT_DATA |
| 7 WAIT_DATA | DS | DATA_LPX; T(1) |
| 8 DATA_LPX | Z | DATA_PREP; T(5) |
| 9 DATA_PREP | Z | DATA_ZERO; T(6) |
| 10 DATA_ZERO | Z | WAIT_WORD |
| 11 WAIT_WORD | !V | Mantener HS-0, sin Sync ni timeout |
| 11 WAIT_WORD | V y G y K | CAP; L=0→SYNC_OPEN, L=1→SYNC_CLOSED |
| 12 SYNC_OPEN | P y !Pf; V y G y K | MOV+CAP; L=0→STREAM_OPEN, L=1→DRAIN_PENDING |
| 13 SYNC_CLOSED | P y Pf; !V | MOV; FINAL |
| 14 STREAM_OPEN | A y !Af; P y !Pf; V y G y K | RET+MOV+CAP; L=0→STREAM_OPEN, L=1→DRAIN_PENDING |
| 15 DRAIN_PENDING | A y !Af; P y Pf; !V | RET+MOV; FINAL |
| 16 FINAL | A y Af; !P; !V; DT | RET; DATA_TRAIL; T(7) |
| 17 DATA_TRAIL | Z | DATA_EXIT; T(8), PL |
| 18 DATA_EXIT | Z | WAIT_CLK_STOP; PS |
| 19 WAIT_CLK_STOP | CT y J | CLK_TRAIL; T(9), PS |
| 20 CLK_TRAIL | Z | CLK_EXIT; T(8) |
| 21 CLK_EXIT | Z | RETURN |
| 22 RETURN | !CS y !DS y !DT y !CT y !G | IDLE |
| 23 ABORT_EXIT | Z | HALTED |
| 24 HALTED | Sin reset | Permanecer, aunque desaparezca phy_abort |

En WAIT_WORD, V=0 permite que G demore sin iniciar Sync. Una vez capturada la
primera palabra, SYNC_OPEN y STREAM_OPEN **exigen** V=1 en la siguiente
frontera: su ausencia es underflow. No existe ready ni pausa entre palabras.
UC_RX_OPEN=1 solo en WAIT_WORD, SYNC_OPEN y STREAM_OPEN, sin fallo ni aborto.
El guardado de máscara y CAP siguen las ecuaciones del datapath.

SYNC_CLOSED y DRAIN_PENDING codifican que ya se aceptó last; en ellos no se
exige G ni se admite otra palabra. FINAL tampoco exige G ni DS: en este
intervalo el árbitro retira el permiso y solicita parada. DT puede llegar en
cualquier momento posterior a la aceptación de last, pero debe estar presente
antes del flanco que termina FINAL. No se añade una espera que prolongue un
bit ni se invalida ACTIVE al retirar G.

Las invariantes de P/A se comprueban **antes** de activar MOV o RET. En
SYNC_OPEN/SYNC_CLOSED se exige A=0; en WAIT_WORD P=A=0. La captura inicial no
mueve un valor antiguo hacia ACTIVE. La palabra final sigue en A_DATA después
de RET; M1 la usa para Trail aunque A_VALID ya sea 0.

## Salidas por fase y composición

Selección M1: Zero=00, Sync=01, payload=10, Trail=11. El valor por defecto es
Zero; cuando HS_DATA_ON=0, FRAME no representa bits sobre la salida lógica.

| Estados | Datos HS / M1 | CLK HS / CLK_TOGGLE | Intención LP cuando HS no está activo |
|---|---|---|---|
| BOOT, INIT, IDLE, RETURN | 0 / 00 | 0 / 0 | CLK/D0/D1=11 |
| CLK_LPX | 0 / 00 | 0 / 0 | CLK=01; datos=11 |
| CLK_PREP | 0 / 00 | 0 / 0 | CLK=00; datos=11 |
| CLK_ZERO | 0 / 00 | 1 / 0 | Datos=11 |
| CLK_PRE, WAIT_DATA | 0 / 00 | 1 / 1 | Datos=11 |
| DATA_LPX | 0 / 00 | 1 / 1 | D0/D1=01 |
| DATA_PREP | 0 / 00 | 1 / 1 | D0/D1=00 |
| DATA_ZERO, WAIT_WORD | 1 / 00 | 1 / 1 | — |
| SYNC_OPEN, SYNC_CLOSED | 1 / 01 | 1 / 1 | — |
| STREAM_OPEN, DRAIN_PENDING, FINAL | 1 / 10 | 1 / 1 | — |
| DATA_TRAIL | 1 / 11 | 1 / 1 | — |
| DATA_EXIT, WAIT_CLK_STOP | 0 / 00 | 1 / 1 | Datos=11 |
| CLK_TRAIL | 0 / 00 | 1 / 0 | Datos=11 |
| CLK_EXIT, ABORT_EXIT, HALTED | 0 / 00 | 0 / 0 | CLK/D0/D1=11 |

**Refinamiento de interfaz:** se añade CLK_TOGGLE al contrato UC→generador.
HS_CLK_ON habilita el estado HS; CLK_TOGGLE habilita oscilación ideal. Con
HS_CLK_ON=1 y CLK_TOGGLE=0 el modelo emite HS-0, necesario en Zero y Trail.
No se traduce esto a OEN, GPIO o una tabla eléctrica real. Los estados LP
son intenciones del modelo P/N, no una aprobación de conducción simultánea.

| Salida | Estados donde es 1, sin reset ni aborto |
|---|---|
| clk_prepared | WAIT_DATA hasta WAIT_CLK_STOP inclusive (códigos 7…19) |
| data_prepared | WAIT_WORD hasta FINAL inclusive (11…16) |
| data_stopped | WAIT_CLK_STOP, CLK_TRAIL, CLK_EXIT, RETURN (19…22) |
| clk_stopped | RETURN |
| reposo_HS_local | IDLE, RETURN, HALTED |

clk_prepared no depende de CS: el reloj debe mantenerse durante POST aunque
el árbitro retire CS al solicitar CT. RETURN conserva los ACK hasta que el
árbitro haya observado el fin. Solo después de retirar sus órdenes vuelve a
IDLE; no se duplica la transacción por una petición sostenida.

En HALTED, reposo_HS_local se permite incluso con phy_abort sostenido, una
vez completado ABORT_EXIT; así el árbitro puede observar stop_ready para
limpiar su fallo. Ese reposo no es un éxito. La composición externa añade
!lp_grant y lp_D0=11 al reposo local. UC no crea hs_complete.

## Órdenes inesperadas e invariantes

Para evitar ambigüedad en la implementación del modelo:

- V fuera de WAIT_WORD/SYNC_OPEN/STREAM_OPEN es fallo de protocolo; no se
  captura. En esos tres estados, una palabra con !G también es fallo.
- CT solo se admite en WAIT_CLK_STOP/CLK_TRAIL/CLK_EXIT/RETURN; antes, falla.
- DT solo se admite tras aceptar last: SYNC_CLOSED, DRAIN_PENDING, FINAL,
  DATA_TRAIL, DATA_EXIT, WAIT_CLK_STOP y RETURN. Fuera de ellos, falla.
- DS se permite desde WAIT_DATA hasta WAIT_CLK_STOP y RETURN; CS se permite
  desde IDLE hasta WAIT_CLK_STOP y RETURN. Solicitudes fuera de esas ventanas
  son fallo, salvo órdenes del propietario anterior que sigan activas en
  ABORT_EXIT/HALTED, donde se ignoran.
- CS debe seguir alto desde CLK_LPX hasta DATA_EXIT inclusive. DS debe seguir
  alto desde DATA_LPX hasta STREAM_OPEN inclusive, excluyendo SYNC_CLOSED:
  después de aceptar last puede retirarse con la parada. En DRAIN_PENDING,
  FINAL y retorno ya no es requisito. En WAIT_WORD G puede esperar, pero no
  arrancar bits sin V. En SYNC_OPEN/STREAM_OPEN, !G falla.
- G se admite en DATA_ZERO, WAIT_WORD y estados de transferencia; fuera de
  ellos, solo durante DATA_TRAIL como residuo si el árbitro aún no ha retirado
  el permiso. En la cadena existente cae al entrar FINAL. En RETURN se espera
  su retirada; allí no constituye otro fallo.

Los comandos válidos de fases posteriores no adelantan la secuencia. Las
ventanas se comprueban en los posedges; no hacen conmutar salidas asíncronamente.
No se añade timeout a WAIT_DATA/WAIT_WORD/WAIT_CLK_STOP/RETURN.

## Prioridades, causa y recuperación

Prioridad en cada posedge:

1. rst: STATE←BOOT, CAUSE←0, reset de flags/contadores; datos pueden retenerse.
2. ABORT_EXIT/HALTED ya activos: conservar CAUSE, avanzar Exit o permanecer;
   phy_abort alto no recarga el temporizador en cada ciclo.
3. phy_abort: entrar ABORT_EXIT, CLR y T(8), sin crear causa local.
4. Fallo local: registrar primera causa, entrar ABORT_EXIT con CLR y T(8).
5. Transición normal y controles de las tablas anteriores.

| CAUSE | Fallo local, en orden de prioridad si coinciden |
|---|---|
| 0 | Ninguno / aborto solicitado externamente |
| 5 | Estado codificado 25…31 |
| 6 | Selector de tiempo inválido al solicitar carga (invariante interna) |
| 4 | Invariante de PENDING/ACTIVE inválida |
| 1 | Máscara distinta de 11 en una ventana RX con V |
| 3 | Orden, valid o grant fuera de contrato; parada prematura/ausente |
| 2 | V=0 cuando SYNC_OPEN/STREAM_OPEN exige siguiente palabra |
| 7 | Reservado; no generado |

CAUSE no se borra al recibir phy_abort ni clear_error del árbitro. Un aborto
externo puede dejar HALTED con phy_error=0; su recuperación exige reset
coordinado y no declara fin correcto. No hay lazo combinacional desde
phy_abort a phy_error: CAUSE es registro. El OR hacia hs_error del árbitro
permanece una integración propuesta.

rst o phy_abort bloquean CAP/MOV/RET, ACK y habilitaciones HS inmediatamente;
en el siguiente posedge se invalida el pipeline. ABORT_EXIT usa LP-11 lógico
por cuatro intervalos y HALTED confirma reposo local; es una regla del modelo,
no una reacción eléctrica garantizada ante pérdida real de PLL/reloj.
El fallo local inhibe los controles normales del flanco que lo registra.

## Verificación de esta entrega

[verificar_fsm.py](verificar_fsm.py) es un modelo ejecutable de especificación,
no RTL. Además se contrasta ahora con el núcleo mediante vectores por
puertos públicos. Recorre la secuencia completa S320 con 1/2/3/4/1083/2048 palabras,
comprueba duraciones, ausencia de huecos entre Sync/payload/Trail y POST;
inyecta reset/aborto por estado, fallos de máscara/underflow/protocolo e
invariantes, y cubre códigos inválidos. Las comprobaciones de señales reales
entre transporte y árbitro siguen en el arnés del contrato temporal.

Ninguna de estas pruebas acredita conformidad D-PHY ni compatibilidad LCD.
