# FSM de dsi_hs_transport

Derivada del flujo aprobado y del [datapath](datapath.md). El editable único
[DSI_HS_TRANSPORT.drawio](DSI_HS_TRANSPORT.drawio) incorpora las páginas
**FSM · Transiciones** y **FSM · Controles y temporización**.
Vistas: [transiciones](fsm.svg), [controles](fsm_control.svg),
[PDF de ambas páginas](FSM.pdf).

## Estados, memoria y flancos

| Código binario | Estado | Función |
|---|---|---|
| 000 | FILL | Recibir un paquete completo |
| 001 | PRIME | Leer la primera palabra de RAM |
| 010 | REQUEST | Reservar el enlace HS |
| 011 | WAIT_GRANT | Esperar permiso de transferencia |
| 100 | SEND | Entregar una palabra por ciclo |
| 101 | WAIT_COMPLETE | Esperar liberación del enlace |
| 110 | FAULT | Conservar fallo hasta reset coordinado |
| 111 | No usado | Entrar en FAULT, causa 11 |

STATE[2:0], DONE[0] y ERROR_CODE[1:0] constituyen **seis bits de UC**.
La codificación coincide con el RTL inspeccionado en
[hs_transport_control.v](../src/hs_transport_control.v); síntesis puede
recodificarla. No se añaden registros ACTION ni otro estado para el pulso done.

La memoria de UC y el datapath cambian en **posedge clk**, con reset síncrono
activo alto. Los controles se decodifican combinacionalmente del estado y
entradas vigentes **antes** del mismo flanco que acepta datos o cambia la fase.
No se registran enables para aplicarlos un ciclo después. Las transiciones
están dentro del bloque secuencial; no se añade un registro de próximo estado.
El RTL expresa las salidas de UC en `always @(*)`, con valores por defecto
para evitar latches; los registros internos solo cambian en `posedge`.

## Condiciones y transiciones normales

```text
E = !rst & !phy_abort
V = tx_word_valid       K = MASK_OK
L = tx_word_last        F = FULL
R = hs_req_ready        G = hs_grant
T = FINAL_WORD          C = hs_complete
```

La tabla se interpreta con E=1, salvo FAULT, que solo sale por reset.
F se calcula **antes** de aceptar la palabra: COUNT=W−1. Una última palabra
válida puede ocupar la última posición; una palabra no final en esa posición
provoca fallo inmediato. K solo permite keep=11, o keep=01 con last=1.

| Origen | Condición | Destino | Acción en ese flanco |
|---|---|---|---|
| FILL | !V | FILL | Conservar |
| FILL | V y !K | FAULT | CAUSA←10; no escribir RAM |
| FILL | V y K y F y !L | FAULT | CAUSA←01; se escribe la palabra pero el paquete queda invalidado |
| FILL | V y K y L | PRIME | Escribir última palabra e incrementar COUNT |
| FILL | V y K y !F y !L | FILL | Escribir palabra e incrementar COUNT |
| PRIME | Siempre | REQUEST | Q←RAM[0] |
| REQUEST | !R | REQUEST | Mantener req y data_ready |
| REQUEST | R | WAIT_GRANT | Retirar req al cambiar la fase |
| WAIT_GRANT | !G | WAIT_GRANT | Conservar Q; mantener data_ready |
| WAIT_GRANT | G | SEND | Publicar Q sin sobrescribirla |
| SEND | !G | FAULT | CAUSA←11; no entregar ni leer |
| SEND | G y !T | SEND | Consumir Q; leer siguiente; INDEX←INDEX+1 |
| SEND | G y T | WAIT_COMPLETE | Consumir última; DONE←1; no leer otra dirección |
| WAIT_COMPLETE | !C | WAIT_COMPLETE | Entrada cerrada; sin nuevas entregas |
| WAIT_COMPLETE | C | FILL | Limpiar COUNT/INDEX; permitir siguiente paquete |
| FAULT | !rst | FAULT | Conservar primera causa; DONE←0 |
| 111 | Sin reset ni aborto | FAULT | CAUSA←11 |

R solo se interpreta en REQUEST; G permite avanzar en WAIT_GRANT y consumir
en SEND; C solo libera en WAIT_COMPLETE. last sin entrada aceptada no cierra
un paquete. Un grant temprano no permite saltarse la reserva. No se rearma
una nueva petición mientras falta complete. No hay timeout.

## Salidas y controles

Con E=1, las salidas son:

| Estado | ready | hs_req | hs_data_ready | hs_word_valid | busy | error/hs_error |
|---|---:|---:|---:|---:|---|---:|
| FILL | 1 | 0 | 0 | 0 | OCCUPIED | 0 |
| PRIME | 0 | 0 | 0 | 0 | 1 | 0 |
| REQUEST | 0 | 1 | 1 | 0 | 1 | 0 |
| WAIT_GRANT | 0 | 0 | 1 | 0 | 1 | 0 |
| SEND | 0 | 0 | 1 | G | 1 | 0 |
| WAIT_COMPLETE | 0 | 0 | 0 | 0 | 1 | 0 |
| FAULT | 0 | 0 | 0 | 0 | 1 | 1 |
| 111 | 0 | 0 | 0 | 0 | 1 | 0 hasta registrar FAULT |

`ready` corresponde a tx_word_ready. Los controles hacia el datapath son:

| Estado | WRITE_EN | READ_EN | PRIME/SEL_M0 | ADVANCE | CLEAR_COUNT |
|---|---|---|---:|---|---|
| FILL | V & K | 0 | 0 | 0 | 0 |
| PRIME | 0 | 1 | 1 | 0 | 0 |
| REQUEST | 0 | 0 | 0 | 0 | 0 |
| WAIT_GRANT | 0 | 0 | 0 | 0 | 0 |
| SEND | 0 | G & !T | 0 | G & !T | 0 |
| WAIT_COMPLETE | 0 | 0 | 0 | 0 | C |
| FAULT / 111 | 0 | 0 | 0 | 0 | 0 |

```text
tx_word_ready = E & (STATE == FILL)
hs_req = E & (STATE == REQUEST)
hs_data_ready = E & (STATE ∈ {REQUEST, WAIT_GRANT, SEND})
hs_word_valid = E & (STATE == SEND) & hs_grant
WRITE_EN = tx_word_valid & tx_word_ready & MASK_OK
READ_EN = E & (PRIME | (hs_word_valid & !FINAL_WORD))
ADVANCE = hs_word_valid & !FINAL_WORD
CLEAR_COUNT = E & (STATE == WAIT_COMPLETE) & hs_complete
PRIME = (STATE == PRIME)
busy = (STATE != FILL) | OCCUPIED
error = hs_error = (STATE == FAULT)
hs_done = E & DONE
error_code = ERROR_CODE
```

Con rst o phy_abort se bloquean de inmediato ready, req, data_ready, valid,
WRITE_EN, READ_EN, ADVANCE, CLEAR_COUNT y done. **PRIME es un selector**, no un
enable: puede seguir alto mientras STATE=PRIME, pero READ_EN=0 impide captura.
`busy`, `error` y el código reflejan la memoria anterior hasta el flanco de
reset; no se les atribuye un borrado asíncrono inexistente.

Los datos y la máscara provienen de Q; last proviene de FINAL_WORD. Solo
representan entrega con hs_word_valid=1. No son registros nuevos en UC.

## Prioridades, pulso de fin y recuperación

En cada posedge, reset tiene prioridad absoluta. Sin reset se borra DONE por
defecto y se aplica, en este orden:

1. Si ya está en FAULT, conservar fase y causa aunque cambien los estímulos.
2. Si phy_abort=1, entrar en FAULT con causa 11, sin éxito.
3. Aplicar errores y transiciones de la fase vigente. En FILL, máscara inválida
   tiene prioridad sobre capacidad. En SEND, perder grant tiene prioridad
   sobre FINAL_WORD. El código 111 entra en FAULT con causa 11.

ERROR_CODE=00 tras reset, 01 por capacidad, 10 por máscara, 11 por aborto,
pérdida de grant durante envío o código no usado. El código local 11 no es el
código de diagnóstico del árbitro: son interfaces independientes.

DONE se pone a uno únicamente al consumir una palabra final en SEND. Permanece
alto durante el primer ciclo de WAIT_COMPLETE y se borra en el siguiente
posedge. El árbitro puede observar hs_done en ese siguiente flanco. Si ocurre
aborto o reset, el enmascaramiento retira el pulso inmediatamente.

No existe clear_error local. Recuperar un fallo requiere reset coordinado del
productor, packer, transporte y árbitro; no se busca last después del descarte.
El hecho de que el árbitro no acepte HS mientras hs_error está alto no limpia
el error local ni solicita un reintento. Un fallo local mientras LP posee el
enlace queda retenido aunque el árbitro no lo interprete durante LP.

## Ejemplo temporal: paquete de dos palabras

| Flanco | Fase previa | Operación | Fase posterior |
|---|---|---|---|
| N | FILL | Aceptar segunda palabra con last; COUNT←2 | PRIME |
| N+1 | PRIME | Q←RAM[0] | REQUEST |
| H | REQUEST | hs_req && hs_req_ready | WAIT_GRANT |
| G | WAIT_GRANT | Observar hs_grant; no leer otra palabra | SEND |
| G+1 | SEND | Consumir palabra 0; Q←RAM[1]; INDEX←1 | SEND |
| G+2 | SEND | Consumir palabra final; DONE←1 | WAIT_COMPLETE |
| G+3 | WAIT_COMPLETE | Árbitro observa done; DONE←0 | WAIT_COMPLETE |
| C | WAIT_COMPLETE | hs_complete; COUNT/INDEX←0 | FILL |

H y G pueden demorarse; en sus esperas Q permanece estable. Durante SEND no
hay ready de salida: la entrega es obligatoria en cada posedge con valid=1.
Una sola palabra sigue el mismo recorrido, con T=1 en el primer consumo y sin
leer la dirección uno. done no significa que el panel recibió el paquete ni
que la PHY ya volvió al reposo; ese último evento corresponde a complete.

## Verificación de esta entrega

Se contrastaron códigos, guardas, prioridades, controles y pulsos con el RTL
actual, el flujo y el datapath, y se validaron las referencias del editable.
Las exportaciones incluyen las dos páginas de FSM. El RTL implementa esta
máquina y las pruebas verifican sus controles y transiciones. No se afirma
validación física. El plan de pruebas
[verificacion.md](verificacion.md) conserva los escenarios de simulación.
