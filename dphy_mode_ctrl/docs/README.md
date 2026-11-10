# Diagramas de dphy_mode_ctrl

Se documentan el flujo, el datapath, la FSM y su implementación RTL.
En las páginas de flujo una caja representa
una operación, no necesariamente un estado ni un ciclo.

Abrir [DPHY_MODE_CTRL.drawio](DPHY_MODE_CTRL.drawio) en Draw.io para editar.
El [PDF](DPHY_MODE_CTRL.pdf) reúne las nueve páginas:

| Página | Vista | Contenido |
|---|---|---|
| 1 | [Arbitraje general](flujo_general.svg) | Reset, reposo, elegibilidad, preferencia y reserva del enlace |
| 2 | [Recorrido LPDT](flujo_lpdt.svg) | Concesión de LP, espera de fin y liberación tras reposo |
| 3 | [Recorrido HS](flujo_hs.svg) | Preparar reloj/datos, transferir, detener datos/reloj y confirmar reposo |
| 4 | [Reset y fallos](flujo_recuperacion.svg) | Prioridades, aborto, causa de fallo y recuperación |
| 5 | [Datapath: arbitraje](datapath_arbitraje.svg) | Elegibilidad, reserva, registros de rearme y preferencia, frontera con UC |
| 6 | [Datapath: salidas](datapath_salidas.svg) | Causa, pulsos de fin, detección de fallo y protección de salidas |
| 7 | [FSM: transiciones](fsm.svg) | Estados normales, avances, permanencias y eventos de fin |
| 8 | [FSM: prioridades](fsm_control.svg) | Reset, FAULT, códigos inválidos y controles por estado |
| 9 | [Contrato temporal](temporizacion.svg) | UC en posedge, salidas combinacionales, acción retenida y datapath en negedge |

El [PDF de datapath](DATAPATH.pdf) contiene únicamente las páginas 5–6.
Su [justificación](datapath.md) explica la memoria de siete bits y las reglas
de actualización.

El [PDF de FSM](FSM.pdf) contiene las páginas 7–9. La
[especificación FSM](fsm.md) detalla codificación, transiciones, prioridades y
relación con el datapath. El [contrato temporal](contrato_temporal.md)
explica el ajuste de flancos solicitado por el usuario y está disponible
también como [PDF independiente](CONTRATO_TEMPORAL.pdf).

Los conectores **L**, **H**, **F** y **R** enlazan los recorridos entre páginas.
Los rombos contienen condiciones y cada salida está marcada Sí/No. Los bucles
conservan la petición o espera; no crean otra operación. `←` indica asignación
y `↑clk` el flanco ascendente.

Se muestran tres reglas globales para mantener legible el flujo:

- Reset tiene prioridad desde cualquier punto y no genera éxito.
- PLL perdido o `hs_error` durante HS retira órdenes y grants y lleva a F.
- Una solicitud consumida se rearma al observar su `req=0` en negedge.

Las confirmaciones `clk_prepared`, `data_prepared`, `data_stopped`,
`clk_stopped` y `stop_ready` pertenecen a un modelo de PHY. El diagrama no fija
Prepare/Zero/Trail/Exit eléctricos, tiempos del LCD ni polaridades de pads.
Esos contratos requieren una especificación posterior.

Base funcional contrastada: [contrato del módulo](../README.md),
[RTL estructural](../src/dphy_mode_ctrl.v) y
[puente LPDT](../../dsi_lpdt_bridge/README.md). Los diagramas se actualizaron
para reflejar FSM en posedge, datapath en negedge y retención de acciones.

Orden de trabajo: revisar este flujo → justificar datapath → definir FSM →
acordar verificación → implementar o corregir RTL.
