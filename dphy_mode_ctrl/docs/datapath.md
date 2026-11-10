# Datapath de dphy_mode_ctrl

Propuesta derivada de las cuatro páginas de flujo del
[Draw.io](DPHY_MODE_CTRL.drawio). Diagramas en las páginas 5–6 y en el
[PDF de datapath](DATAPATH.pdf). Esta entrega documenta los elementos de
almacenamiento y la lógica combinacional del RTL. El
[contrato temporal](contrato_temporal.md) actualiza sus flancos según la
instrucción del usuario: registros del datapath en negedge.

## Memoria y motivo de cada registro

| Registro | Bits | Reset | Motivo |
|---|---:|---:|---|
| `R_LP` | 1 | 1 | Recordar si la solicitud LP ya se consumió; impedir duplicación mientras siga alta |
| `R_HS` | 1 | 1 | La misma función para HS, incluido evitar reintento automático tras fallo |
| `PREF` | 1 | 0 | Conservar qué modo gana el próximo empate; 0 prefiere LP, 1 prefiere HS |
| `CAUSA` | 2 | 0 | Conservar la causa aunque desaparezca el estímulo que produjo el fallo |
| `FIN_LP` | 1 | 0 | Registrar el pulso `lp_complete` tras liberar el enlace |
| `FIN_HS` | 1 | 0 | Registrar el pulso `hs_complete` tras liberar el enlace |

Total: **siete bits de datapath**. La memoria de fase está dentro de la unidad
de control (UC). Así se recuerda que terminó LP y se espera reposo, por
ejemplo, sin otro registro de datos para retener `lp_done`.

Todos estos registros usan `negedge`, con reset síncrono activo en alto y
prioritario sobre carga. Con `LD=0` se conserva Q; no hace falta otro MUX de
retención externo. Reloj de control previsto: 40 MHz, periodo de 25 ns.

## Rearme, preferencia y arbitraje

M0 y M1 seleccionan el próximo bit de rearme: entrada 0 = 1, entrada 1 = 0.
La aceptación se conserva en ACTION de UC. Su decodificación combinacional
entrega `TAKE_LP` o `TAKE_HS` hasta el negedge posterior. La carga es:

```text
LD_LP = !lp_req | TAKE_LP
LD_HS = !hs_req | TAKE_HS
SEL_M0 = TAKE_LP & lp_req
SEL_M1 = TAKE_HS & hs_req
```

En negedge, una solicitud baja rearma su registro. Si permanece alta y existe
su TAKE, se consume. Así también es válida una baja de req después de aceptar
en posedge y antes del negedge posterior. Sin carga se conserva el registro.

M2 tiene las mismas constantes, seleccionado por `TAKE_HS`, y carga
`PREF` con `LD_PREF = TAKE_LP | TAKE_HS`. Aceptar LP deja preferencia HS;
aceptar HS deja preferencia LP. Sin aceptación se conserva la preferencia.

La red combinacional se define como:

```text
LP_E = lp_req & R_LP
HS_E = hs_req & R_HS & pll_locked & hs_data_ready & !hs_error
EN_ARB = !rst & ARB_LIBRE & stop_ready

lp_req_ready = EN_ARB & LP_E & (!HS_E | !PREF)
hs_req_ready = EN_ARB & HS_E & (!LP_E | PREF)
LP_FIRE = lp_req & lp_req_ready
HS_FIRE = hs_req & hs_req_ready
```

`ARB_LIBRE` es una indicación de fase de UC. Solo puede aceptar un productor
por flanco. Una solicitud no elegible no impide que se atienda la otra.
Los eventos `FIRE` reservan el enlace; los grants permiten usarlo después.

## Causa y pulsos de fin

M3 elige la causa HS: `01` si ACTION conserva pérdida de PLL, `10` si conserva
fallo del productor. Su selector es `PLL_CAUSE`, decodificado por UC desde
ACTION, no la entrada viva `pll_locked`. La causa no cambia si la PLL se
recupera después del posedge y antes de la captura en negedge.

M4 selecciona el próximo código de `CAUSA`. UC proporciona:

| Prioridad tras reset | `LD_ERR` | `SEL_ERR[1:0]` | D de `CAUSA` |
|---|---:|---:|---|
| Acción PLL/HS decidida en el posedge previo | 1 | 1 | Salida de M3 |
| Acción de condición interna inválida | 1 | 2 | `11` |
| Acción de limpieza autorizada en posedge | 1 | 0 | `00` |
| Ningún evento | 0 | Indiferente | Conservar Q |

`SEL_ERR=3` queda reservado y no debe emitirse. La causa permanece hasta
limpieza o reset. El estado de fallo activo se conserva en UC, separado del
código de causa del datapath.

Los dos registros de fin cargan en cada negedge (`LD=1`). La liberación del
enlace tras fin del productor y reposo confirmado se decide en posedge;
ACTION conserva esa decisión y UC decodifica `FIN_LP_EVT` o `FIN_HS_EVT`.
El negedge posterior captura el pulso, que dura hasta el negedge siguiente.
Reset o fallo en el flanco de decisión tienen prioridad sobre
éxito; `lp_done` y `hs_done` no se conectan directamente a sus entradas D.

## Detección de fallo y salidas combinacionales

```text
HS_FAULT = HS_ACTIVE & (!pll_locked | hs_error)
SAFE = !rst & !HS_FAULT
Y[5:0] = R[5:0] & {6{SAFE}}
```

UC entrega `HS_ACTIVE` durante preparación, transferencia, parada y espera de
reposo HS. El vector R agrupa sus intenciones, en este orden:

```text
R = {LP_OWNER, HS_TRANSFER_ACTIVE, CLK_START, DATA_START, DATA_STOP, CLK_STOP}
Y = {lp_grant, hs_grant, clk_start_req, data_start_req, data_stop_req, clk_stop_req}
```

El enmascaramiento retira órdenes y grants ante reset o fallo HS sin esperar
un flanco. UC entrega cero en R durante fallo persistente. Otras salidas son:

```text
phy_abort = rst | FAULT_ACTIVE | HS_FAULT
error = !rst & FAULT_ACTIVE
busy = BUSY_CTRL
```

`FAULT_ACTIVE` y `BUSY_CTRL` son decodificaciones de fase de UC. `error_code`
es directamente Q de `CAUSA`. No se añaden registros para estas salidas.

## Frontera con la unidad de control

UC recibe `LP_FIRE`, `HS_FIRE`, `HS_FAULT`, los dos `done`, las confirmaciones
de preparación/parada/reposo, disponibilidad de datos HS y `clear_error`.
Entrega `ARB_LIBRE`, `TAKE_LP`, `TAKE_HS`, `LD_ERR`, `SEL_ERR`, `PLL_CAUSE`,
los eventos de fin, los indicadores de fase y las seis intenciones de salida.
La [FSM](fsm.md) conserva las prioridades del flujo y añade ACTION [4] para
mantener cada decisión hasta negedge, con salidas combinacionales.

El [top RTL](../src/dphy_mode_ctrl.v) conecta `mode_control` y `mode_datapath`.
En el datapath, `R_LP/R_HS` son `r_lp/r_hs`, `PREF` es `pref`, y las salidas
de CAUSA y FIN son `error_code`, `lp_complete` y `hs_complete`.
Los cinco MUX y los seis registros parametrizables suman siete bits de datos.

El módulo coordina transacciones: no necesita almacén de bytes, sumadores,
contadores de píxeles, CRC/ECC ni FIFO. Las esperas actuales terminan mediante
confirmaciones del modelo PHY; los temporizadores eléctricos se especificarán
cuando existan los requisitos correspondientes.
