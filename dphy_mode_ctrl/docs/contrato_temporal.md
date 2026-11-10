# Contrato temporal del RTL

Contrato solicitado por el usuario: FSM en `posedge`, señales de FSM
combinacionales y registros del datapath en `negedge`. Está representado en
la página 9 del [Draw.io](DPHY_MODE_CTRL.drawio) y en su
[PDF independiente](CONTRATO_TEMPORAL.pdf).

## Distribución de registros

| Bloque | Memoria | Flanco | Lógica de salida |
|---|---|---|---|
| `mode_control` | STATE [4], ACTION [4] | Posedge | `always @(*)`, valores por defecto completos |
| `mode_datapath` mediante `mode_register` | Rearme [2], preferencia [1], causa [2], fin [2] | Negedge | Arbitraje y protección combinacionales |
| `dphy_mode_ctrl` | Ninguna adicional | — | Conexión estructural |

La FSM conserva sus diez estados y prioridades. No hay `next_state`
combinacional. STATE y ACTION solo se escriben dentro de su bloque
secuencial; las señales de UC solo se escriben en el bloque combinacional.

## Por qué se retiene la acción

Si se cargara el datapath directamente desde `LP_FIRE` vivo, el posedge que
acepta LP cambiaría STATE a LP_OWNED. Eso desactiva ARB_LIBRE y FIRE antes
del negedge: se perderían consumo y preferencia. Lo mismo ocurriría con
un fin condicionado a LP_RETURN al regresar a IDLE, o con la causa al pasar
de HS a FAULT.

ACTION [4] conserva la decisión del posedge durante ese ciclo. Su
decodificación es combinacional y el negedge siguiente aplica la operación.
Las nueve acciones y sus controles están en la [especificación FSM](fsm.md).
No es otro registro de bytes ni añade estados de transporte.

La acción PLL/HS conserva cuál de las dos causas se decidió en posedge.
M3 usa PLL_CAUSE decodificado desde ACTION; no vuelve a leer la PLL en negedge.
Así la causa permanece correcta aunque la entrada se recupere entre flancos.

## Instantes observables

- `req && req_ready` acepta una reserva en posedge.
- Las intenciones de propiedad y órdenes reflejan la nueva fase tras ese
  posedge mediante lógica combinacional.
- Consumo, preferencia, código de causa y pulsos se registran en el negedge
  posterior. `error_code` es válido desde ese negedge después de entrar en FAULT.
- El pulso de fin dura de negedge a negedge. Un consumidor en posedge lo lee
  durante ese intervalo; puede aceptar otra reserva en ese mismo posedge.
- Una solicitud se rearma si se observa baja en negedge. Si baja después de
  la aceptación y antes de ese negedge, también se rearma: M0/M1 dan prioridad
  a esa baja frente al consumo retenido. Una solicitud mantenida alta se consume.

Una orden combinacional de la UC no espera al flanco del datapath para cambiar.
Reset o fallo retiran inmediatamente grants/órdenes y piden aborto; las
actualizaciones de almacenamiento esperan a sus respectivos flancos.

Reset debe cubrir un ciclo completo. En posedge borra STATE/ACTION; en
negedge borra el datapath. Si se activa después de decidir una acción y antes
de negedge, esa acción se anula sin emitir éxito ni capturar una causa vieja.

## Recursos lógicos y temporización

Con la codificación elegida hay ocho bits de UC y siete de datapath: quince
bits lógicos. La cifra anterior de once bits correspondía al diseño que
actualizaba todo en posedge y no incluía ACTION.

A 40 MHz, el periodo es 25 ns y cada mitad nominal es 12,5 ns. Hay caminos
posedge → lógica combinacional → negedge y negedge → arbitraje → posedge.
La simulación funcional no comprueba sus retardos; el cierre temporal debe
revisar ambos al implementar en FPGA.

## Evidencia de verificación

`pixi run --locked test-dphy-mode` ejecuta tres pruebas:

1. Unitaria: exclusión, arbitraje, 12 fallos por fase, 34 resets y observación
   de que los siete bits de datapath no cambian en posedge ni UC en negedge.
2. Integrada: ocho paquetes LPDT reconstruidos desde D0 y ocho operaciones
   HS de modelo, con cuatro latencias de PHY y sin solapamiento.
3. Entre flancos: 13 casos, incluidos entradas que cambian después de la
   aceptación, causa retenida, reset de acciones pendientes, pulso completo
   y los seis códigos no usados de STATE. Solo la inyección de esos códigos
   usa escritura jerárquica; el resto se comprueba por puertos públicos.

Yosys `proc; check -assert` pasó sin latches. La inspección de sus celdas
confirmó ocho bits de UC en flanco positivo y las celdas de registros del
datapath en flanco negativo. Es comprobación genérica, no síntesis física ni STA.
