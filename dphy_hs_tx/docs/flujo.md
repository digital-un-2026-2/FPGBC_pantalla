# Flujo propuesto de una ráfaga HS

Estado: **PROPUESTO**. Es un algoritmo de responsabilidades; todavía no una
FSM ni una tabla eléctrica aprobada. [Editable](DPHY_HS_TX.drawio) ·
[SVG](flujo.svg) · [Contrato y fuentes](especificacion.md).

1. Validar perfil de prueba y confirmar reposo conjunto con la ruta LPDT.
2. Esperar clk_start_req; ejecutar entrada LP→HS del reloj, Zero e inicio de
   oscilación. Confirmar clk_prepared una vez satisfecho CLK-PRE.
3. Esperar data_start_req con reloj mantenido; ejecutar preparación de datos.
4. Cumplir Zero mínimo, confirmar data_prepared y mantener HS-0 hasta capturar
   W0. Emitir Sync durante un ciclo y luego W0 sin hueco, con registros
   PENDING/ACTIVE según el [cronograma propuesto](contrato_temporal.md).
5. Consumir una palabra por ciclo válido; serializar ambas lanes de forma
   continua. Comprobar máscara y continuidad. No emitir el byte ausente de D1.
6. Capturar last y drenar completamente la palabra final. La petición de
   parada del árbitro puede llegar durante ese drenaje: conservarla.
7. Con data_stop_req y sin bits pendientes, ejecutar Trail y retorno de datos.
   Confirmar data_stopped solo cuando ambas lanes hayan terminado.
8. Esperar clk_stop_req manteniendo el reloj necesario para CLK-POST; terminar
   reloj con Trail/retorno. Confirmar clk_stopped y cumplir Exit.
9. Confirmar stop_ready únicamente con reposo conjunto. El árbitro produce
   hs_complete; después puede empezar otra reserva.

Reset, phy_abort o fallo local desvían desde cualquier paso a descarte y
recuperación coordinada, sin completar con éxito. La forma eléctrica del aborto
queda pendiente del wrapper y no se deduce de una salida lógica a cero.

Las duraciones y límites se miden en las salidas. El perfil S320 y el calendario
concretan el modelo; el cotejo normativo de Zero/Sync/Trail y el soporte de lane
parcial siguen pendientes. El primer modelo propuesto solo completa paquetes
pares y registra fallo antes de serializar una palabra con máscara distinta de 11.
