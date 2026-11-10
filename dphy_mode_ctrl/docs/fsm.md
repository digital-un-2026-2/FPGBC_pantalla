# FSM de dphy_mode_ctrl

Propuesta derivada del flujo y del [datapath](datapath.md). El
[Draw.io](DPHY_MODE_CTRL.drawio) incorpora las transiciones en la página 7
y las prioridades/controles en la página 8. El [PDF de FSM](FSM.pdf) reúne
ambas vistas y el contrato temporal de la página 9. El RTL sigue estas
transiciones con UC en posedge, salidas combinacionales y datapath en negedge.

## Estado y memoria

Se proponen diez estados con registro de fase `state[3:0]`, actualizado en
`posedge`, reloj de control de 40 MHz. La codificación binaria coincide con
los nombres de [mode_control.v](../src/mode_control.v).
La síntesis podría recodificar la máquina.

El registro de fase conserva propiedad y progreso. ACTION [4], también en
posedge, conserva la decisión hasta negedge. Los siete bits del datapath
conservan rearme, preferencia, causa y pulsos. Son quince bits lógicos con
esta codificación, no una medición de recursos físicos tras implementación.

Las transiciones están dentro de `always @(posedge clk)`; no hay bloque
`next_state` combinacional. Las salidas de UC se asignan exclusivamente en
`always @(*)`, decodificando fase y acción. Declararlas `output reg` en
Verilog permite esa asignación procedural; no crea flip-flops en esas salidas.

## Transiciones normales

Esta tabla se evalúa después de descartar reset y fallo HS. Toda condición se
muestrea en el flanco ascendente. Una entrada `done` o confirmación ajena al
estado actual se ignora.

| Código | Estado | Condición de avance | Destino | Acción de arco |
|---:|---|---|---|---|
| 0 | `IDLE` | `LP_FIRE` | `LP_OWNED` | Guardar `A_TAKE_LP` |
| 0 | `IDLE` | `HS_FIRE` | `HS_CLK_PREPARE` | Guardar `A_TAKE_HS` |
| 1 | `LP_OWNED` | `lp_done` | `LP_RETURN` | Retirar permiso LP al registrar el nuevo estado |
| 2 | `LP_RETURN` | `stop_ready` | `IDLE` | Guardar `A_FIN_LP` |
| 3 | `HS_CLK_PREPARE` | `clk_prepared` | `HS_DATA_PREPARE` | Empezar preparación de datos |
| 4 | `HS_DATA_PREPARE` | `data_prepared && hs_data_ready` | `HS_TRANSFER` | Autorizar transferencia HS |
| 5 | `HS_TRANSFER` | `hs_done` | `HS_DATA_STOP` | Retirar grant HS y pedir parada de datos |
| 6 | `HS_DATA_STOP` | `data_stopped` | `HS_CLK_STOP` | Pedir parada de reloj |
| 7 | `HS_CLK_STOP` | `clk_stopped` | `HS_RETURN` | Esperar reposo completo |
| 8 | `HS_RETURN` | `stop_ready` | `IDLE` | Guardar `A_FIN_HS` |
| 9 | `FAULT` | `clear_error && stop_ready` | `IDLE` | Guardar `A_CLEAR` |

Si no se satisface la condición correspondiente, se conserva el estado.
En `IDLE`, sin ningún `FIRE` se permanece en `IDLE`. `LP_FIRE` y `HS_FIRE`
son excluyentes por las ecuaciones de arbitraje del datapath.

## Prioridades globales

| Prioridad | Condición | Próximo estado | Efecto sobre el datapath |
|---:|---|---|---|
| 1 | `rst=1` | `IDLE` | ACTION a NONE; datapath se resetea en negedge |
| 2 | `HS_FAULT=1`, sin reset | `FAULT` | Guardar `A_PLL_ERROR` o `A_HS_ERROR`; sin acción de éxito |
| 3 | Código 10–15, sin reset | `FAULT` | Guardar `A_INVALID`; sin acción de éxito |
| 4 | Ninguna anterior | Según tabla normal | Controles normales |

`HS_FAULT = HS_ACTIVE && (!pll_locked || hs_error)`. Se considera activa la
operación HS en todos los estados 3–8, incluida la espera final de reposo.
Por ello, perder PLL en `HS_RETURN` tiene prioridad sobre terminar con éxito
aunque `stop_ready=1`.

En `FAULT`, los estímulos de fallo no vuelven a capturar la causa porque
`HS_ACTIVE=0`. El fallo permanece hasta limpieza autorizada o reset.
No se necesita recuperar PLL para permitir nuevamente LP; la elegibilidad
del datapath sigue impidiendo reservar HS mientras no esté disponible.

Los códigos 10–15 son codificaciones binarias no usadas. Se asignan cero a
sus intenciones de salida y se registra causa `11` al entrar en `FAULT`.

## Decodificaciones y salidas

Las intenciones de UC son Moore: dependen del estado. La matriz completa está
en la página 8. Se usan estos indicadores:

```text
ARB_LIBRE = (state == IDLE)
HS_ACTIVE = state pertenece a {3, 4, 5, 6, 7, 8}
FAULT_ACTIVE = (state == FAULT)
BUSY_CTRL = (state != IDLE)
```

El vector R se conecta al enmascaramiento del datapath:

```text
R = {LP_OWNER, HS_TRANSFER_ACTIVE, CLK_START, DATA_START, DATA_STOP, CLK_STOP}
Y = R & {6{!rst & !HS_FAULT}}
Y = {lp_grant, hs_grant, clk_start_req, data_start_req, data_stop_req, clk_stop_req}
```

Los valores de R son `000000` en `IDLE`, `LP_RETURN`, `HS_RETURN`, `FAULT`
y códigos no usados; `100000` en `LP_OWNED`; `001000` en `HS_CLK_PREPARE`;
`001100` en `HS_DATA_PREPARE`; `011100` en `HS_TRANSFER`; `001010` en
`HS_DATA_STOP`; `000001` en `HS_CLK_STOP`.

Los controles de carga/eventos y el enmascaramiento también dependen de
entradas; por eso no todas las salidas del módulo son Moore.

## Acción retenida y controles del datapath

ACTION se actualiza en el mismo posedge que STATE. Por defecto pasa a
`A_NONE` en cada posedge, salvo un evento de la tabla. La decodificación
combinacional mantiene los controles hasta la siguiente decisión:

| ACTION | Código | Salidas combinacionales con `rst=0` |
|---|---:|---|
| `A_NONE` | 0 | Todos los controles de acción en cero |
| `A_TAKE_LP` | 1 | `TAKE_LP=1` |
| `A_TAKE_HS` | 2 | `TAKE_HS=1` |
| `A_PLL_ERROR` | 3 | `LD_ERR=1`, `SEL_ERR=1`, `PLL_CAUSE=1` |
| `A_HS_ERROR` | 4 | `LD_ERR=1`, `SEL_ERR=1`, `PLL_CAUSE=0` |
| `A_INVALID` | 5 | `LD_ERR=1`, `SEL_ERR=2` |
| `A_CLEAR` | 6 | `LD_ERR=1`, `SEL_ERR=0` |
| `A_FIN_LP` | 7 | `FIN_LP_EVT=1` |
| `A_FIN_HS` | 8 | `FIN_HS_EVT=1` |

Los controles no indicados son cero. Durante reset todos los controles de
acción están bloqueados. Las intenciones de propiedad y órdenes siguen
dependiendo de STATE y del enmascaramiento de seguridad del datapath.

Las condiciones de fin de la tabla se deciden en posedge; las señales D son:

```text
FIN_LP_EVT = !rst & (ACTION == A_FIN_LP)
FIN_HS_EVT = !rst & (ACTION == A_FIN_HS)
```

Son entradas D de los dos registros de fin, con carga en cada negedge. El
pulso aparece en el negedge posterior al posedge que retorna a IDLE. La
siguiente aceptación puede ocurrir en el posedge posterior.

Por ejemplo, si `lp_done=1` en el flanco N, el estado pasa de `LP_OWNED` a
`LP_RETURN`. Si `stop_ready=1` en N+1, pasa a IDLE y guarda `A_FIN_LP`.
En el negedge siguiente `lp_complete` queda alto hasta el próximo negedge.
Un productor nuevo puede aceptarse en el posedge N+2. El fin local no confirma
recepción por el LCD.

La captura de causa utiliza M3/M4 del datapath. `SEL_ERR=1` elige causa HS,
con prioridad a PLL; `SEL_ERR=2` elige `11`; `SEL_ERR=0` limpia a `00`.
`SEL_ERR=3` no se emite. Rearme y preferencia siguen las ecuaciones del
datapath en todos los estados y no requieren estados adicionales.

## Reset y protección inmediata

Reset del almacenamiento es síncrono a cada flanco. Debe mantenerse durante
un ciclo completo para cubrir ambos. Antes del siguiente flanco, el
enmascaramiento combinacional ya bloquea grants/órdenes y reservas y pide
aborto. En posedge se registran IDLE y A_NONE; busy cae entonces. En negedge
se resetean los siete bits del datapath. Reset antes de ese negedge también
anula una acción pendiente, sin emitir éxito.

Un fallo HS también retira grants/órdenes y activa aborto combinacionalmente;
FAULT y la acción que identifica la causa se registran en posedge; el código
se captura en negedge. El modelo PHY debe
procesar aborto/recuperación y confirmar reposo antes de limpiar el fallo.

La FSM representa coordinación funcional con una PHY modelada. Las esperas
no tienen timeout ni definen tiempos eléctricos. La transferencia HS no se
pausa cuando baja `hs_data_ready`; el productor mantiene continuidad o
señala `hs_error`.
