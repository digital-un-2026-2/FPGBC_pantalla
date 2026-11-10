# Datapath de dphy_gowin_tx

**RTL implementado, 2026-11-09. Perfil físico pendiente.** [Único Draw.io](DPHY_GOWIN_TX.drawio), páginas 5–7;
[PDF del datapath](DATAPATH.pdf). [Interfaces y parámetros](interfaces.md).

Se usa la convención de `dsi_lane_packer` y `dsi_hs_transport`: registros con
LD/reset/flanco, símbolos de MUX, buses con ancho, operadores separados y
controles discontinuos. La UC_SUP supervisa arranque y recuperación; las fases
HS y sus contadores permanecen en `dphy_hs_tx`.

## 1. Registro de tramas y tres serializadores

R_FRAME captura los 16 bits de `hs_frame_data` en posedge con LD_CMD. Se
separan Q[7:0] para D0 y Q[15:8] para D1. No necesita reset de datos: V_P y
SAFE impiden conducir una trama anterior. S0/S1 emiten ocho bits por lane.

M1 selecciona 00 para CLK-Zero/Trail o AA para oscilación. Selección:
R_CTRL0.CLK_TOGGLE, de la primera etapa, no del control ya retardado. S2
recorre el mismo calendario de carga de los serializadores de datos. No se
hace gating combinacional de FCLK ni se reinterpreta la retirada de grant.
El adaptador de SER8 mapea los puertos de la primitiva para emitir bit 0
primero; no hay un contador de bits RTL funcionando a 40 MHz.

La abstracción SER8 recibe D[7:0], PCLK, FCLK y RESET, y emite Q. OSER8 es el
candidato, no una primitiva ya configurada. En la declaración instalada de
Yosys tiene D0–D7, TX0–TX3, PCLK/FCLK/RESET, Q0/Q1 y **no tiene DONE**. El
adaptador debe resolver TX/Q1, orden de bits y latencia usando el dispositivo
concreto; la declaración vacía no aporta un modelo temporal.

Sync y Trail ya están en FRAME: no se vuelven a generar ni se añade otro
registro del último bit, last, keep, PENDING o ACTIVE. kind viaja como etiqueta
para observación. La restricción keep=11 la mantiene el secuenciador existente.

## 2. Control capturado y retardo común

M0 selecciona lp_d0 del secuenciador o estado_D0 del puente según lp_grant.
Se captura también ese grant como OWNER, evitando que el estado LP y su
propietario recorran rutas de distinta longitud. Otros catorce bits vienen
del secuenciador; el bit OWNER completa CTRL_IN[16:0].

| Campo | Bits de CTRL_IN y CTRL_P |
|---|---|
| kind | [1:0] |
| hs_data_on, hs_clk_on, clk_toggle | [2], [3], [4] |
| D0 seleccionado por M0 | [6:5] |
| lp_d1, lp_clk | [8:7], [10:9] |
| lp_grant capturado | [11] |
| clk_prepared_s, data_prepared_s | [12], [13] |
| data_stopped_s, clk_stopped_s | [14], [15] |
| local_stop_s | [16] |

R_CTRL0 captura {1,CTRL_IN}; el bit 17 es validez. R_CTRL1…R_CTRL(L−1)
reciben el valor anterior de su predecesor. LD_CMD es común a R_FRAME y todas
las etapas: no hay stalls, ready ni habilitación por grant. La captura sigue
activa con HS apagado para que el retorno LP y sus ACK lleguen a la salida.

```text
RST_PIPE = rst_byte | phy_abort | !RUN_B
LD_CMD = RUN_B & !RST_PIPE

En posedge, prioridad para cada R_CTRL:
  RST_PIPE: Q <- 0
  LD_CMD:   Q <- D
  resto:    conservar Q

R_CTRL0.D = {1'b1, CTRL_IN[16:0]}
R_CTRLi.D = R_CTRL(i-1).Q, i=1…L-1
V_P = R_CTRL(L-1)[17]
CTRL_P = R_CTRL(L-1)[16:0]
```

Memoria ordinaria: R_FRAME[16] + L×R_CTRL[18] = **16+18L bits**; con L=2,
**52 bits**. Se excluyen UC, supervisor/reset/CDC y memoria interna de IOLOGIC.
No se suma otro R_PAD ni cuatro registros ACK. La retención está en los enables,
sin MUX externos de realimentación redundantes.

### Instantes y prueba requerida del perfil

C[k] nombra el comando de la ventana k, estable antes de la captura en E(k+1).
Para la ruta HS el secuenciador publica C[k] después de E(k). En E(k+1),
R_FRAME toma C[k]; en E(k+2), SER8 carga ese R_FRAME anterior. Con J etapas
adicionales de la primitiva, el comando alcanza el pin en E(k+2+J).
Por tanto L=2+J, y el control debe tener L registros desde su captura lógica:
CTRL_P[k]=CTRL_IN[k−L] bajo la misma indexación de ventanas.

El modelo de dibujo usa J=0, L=2. La latencia física incluye carga interna,
ruteo y fases; no se presupone que OSER8 tenga J=0. La fase de FCLK_C debe
centrar CLK respecto a los bits de D0/D1. OE y LP deben coincidir con las
fronteras físicas programadas, sin truncar bits ni alargar Trail. La igualdad
de retardo entero no sustituye esa comprobación subciclo hasta los pads.

En LPDT la fuente cambia en negedge y se captura en el siguiente posedge.
Añade una fracción fija de ciclo respecto a su fuente, conservando las
longitudes de sus estados cuando se cumple ese camino temporal. El retorno
se cualifica con OWNER retardado, LP_DAT/EN y el estado actual del motor;
`tx_done` lógico por sí solo no prueba retorno físico.

Un desplazamiento común conserva los intervalos y su orden: si Trail termina
en n y POST dura P, sus eventos físicos son n+L y n+P+L, separados por P.
Por eso el wrapper no añade contadores TIME/POST. Retardar solo ACK o solo
FRAME rompe este argumento y queda expresamente prohibido. La prueba debe
abarcar también los puntos de espera de grant/órdenes con el árbitro real.

## 3. MUX y buffers LP; conducción HS

| Bloque | Entradas numeradas | Selección / función |
|---|---|---|
| M0, 2:1 [2] | 0 lp_d0; 1 estado_D0 | lp_grant |
| M1, 2:1 [8] | 0 00; 1 AA | R_CTRL0.CLK_TOGGLE |
| M2, 2:1 [6] | 0 P_LP_BLOCK_DATA; 1 LP_P | SAFE |
| M3, 2:1 [6] | 0 P_LP_BLOCK_EN; 1 P_LP_RUN_EN | SAFE |
| G0, AND vectorial [3] | HS_REQ, SAFE replicado | Habilitación final HS |
| G1, AND vectorial [4] | ACK_P, SAFE replicado | ACK al árbitro |

```text
SAFE = RUN_B & V_P & !rst_byte & !phy_abort & LOCK_RAW & !INHIBIT & !UC_BLOCK & !EV_RAW
LP_DAT = SAFE ? LP_P : P_LP_BLOCK_DATA
LP_EN  = SAFE ? P_LP_RUN_EN : P_LP_BLOCK_EN
HS_REQ = {CLK_ON_P, DATA_ON_P, DATA_ON_P}
HS_OE  = HS_REQ & {3{SAFE}}
ACK_OUT = ACK_P & {4{SAFE}}
```

B_LP son seis TBUF: I=LP_DAT, OEN=~LP_EN. B_HS son tres buffers diferenciales:
I={SER_CLK,SER_D1,SER_D0}, OEN=~HS_OE; O/OB forman los seis pines HS. La
primitiva y las restricciones de banco/encapsulado se validan en el perfil.

El modelo usa LP_RUN_EN=3F, LP_BLOCK_EN=00, LP_BLOCK_DATA=00. En HS, los estados
LP del secuenciador son cero, por lo que las ramas resistivas conducen cero;
no se convierten automáticamente en alta impedancia. En bloqueo se deshabilitan
las ramas LP del modelo, sin forzar LP-11 contra un motor activo. Estos valores
no constituyen aprobación eléctrica para la placa.

## 4. Comparadores y salidas al árbitro

```text
C1 = (LP_DAT == 6'h3f)
C2 = (LP_EN  == 6'h3f)
C3 = (HS_REQ == 3'b000)
G3 = !(OWNER_P | lp_grant)
C4 = (estado_D0 == 2'b11)
COND[4:0] = {C4,G3,C3,C2,C1}
C_STOP = SAFE & LOCAL_STOP_P & (&COND)
stop_ready = C_STOP

clk_prepared_p  = ACK_OUT[0]
data_prepared_p = ACK_OUT[1]
data_stopped_p  = ACK_OUT[2]
clk_stopped_p   = ACK_OUT[3]
```

G2 es una AND de siete entradas: SAFE, LOCAL_STOP_P y cinco condiciones.
C1/C2 evitan afirmar LP-11 si solo hay un valor lógico almacenado pero el
perfil tiene los buffers deshabilitados. OWNER retardado bloquea reutilización
antes de vaciar una operación LP anterior. El grant actual bloquea una nueva
concesión LP. No se usa busy del puente: incluye espera de permiso y causaría
un bloqueo circular. No se mide tensión ni se confirma recepción del panel.

## 5. Reloj, resets y frontera con UC_SUP

PLL0 produce PCLK/byte_clk, FCLK_D y FCLK_C desde ref_clk. Toda la cadena
funcional se integra en byte_clk común; el target actual todavía usa clk40
directo. Dos relojes nominalmente de 40 MHz no justifican cruzar FRAME sin
restricciones ni un diseño de CDC. No se usa sincronización de bits sueltos
para un bus de tramas.

R_LOCK0/R_LOCK1 sincronizan LOCK en ref_clk. R_INHIBIT se activa de forma
asíncrona por rst, phy_abort, !LOCK_RAW, UC_BLOCK o EV_RAW, con prioridad sobre RELEASE_SAFE.
Esta inhibición llega a G0 sin depender de un FCLK que puede haberse detenido.
R_RUN0/R_RUN1 sincronizan su liberación a byte_clk. Los resets de SER8 se
liberan por dominio con dos FF; SER_READY_B reúne las liberaciones sincronizadas
a byte_clk. RUN_B=R_RUN1 & SER_READY_B: no se llena la tubería antes de SER8 listo.
Los resets de SER8 dependen de INHIBIT, **no de RUN_B**, para evitar un lazo de
arranque entre SER_READY y RUN_B.

`rst_byte` se aserta por rst o !LOCK_RAW y se libera en byte_clk; no se activa
por phy_abort, que debe conservar el estado de fallo del árbitro hasta reset
coordinado. El sistema mantiene rst el tiempo necesario para cubrir ref_clk,
los dos flancos del árbitro y los dominios derivados. No usar una pérdida de
PLL como autorización para reintentar automáticamente la ráfaga.

UC_SUP no es una segunda UC de ráfagas. Tras rst: BOOT_ALLOWED=1,
RUN_STARTED=0, ABORT_SEEN=0, CLOCK_FAULT=0; INHIBIT sigue alto. Con rst=0, phy_abort=0,
LOCK_SYNC=1 y PROFILE_OK=1, emite un único RELEASE_SAFE, consume BOOT_ALLOWED
y marca RUN_STARTED=1. Cualquier aborto/fallo posterior impide otro RELEASE
hasta un nuevo rst. La pérdida de LOCK tras RUN_STARTED se conserva como
CLOCK_FAULT aunque LOCK se recupere; su captura debe retener eventos breves.
El mapeo de esa captura asíncrona a recursos Gowin requiere verificación física.

```text
pll_ready = RUN_B & !INHIBIT & LOCK_RAW & !rst_byte & !UC_BLOCK & !EV_RAW
```

La [FSM de UC_SUP](fsm.md), páginas 8–9 del editable, concreta STATE[3],
RUN_STARTED, ABORT_SEEN y CLOCK_FAULT: seis bits de UC. BOOT_ALLOWED es
decodificación. ABORT_SEEN retiene abortos breves; EV_RAW=ABORT_SEEN|CLOCK_FAULT
inhibe directamente, y EV_REF cruza a REF con dos FF. ABORT_REF y READY_REF
añaden otros dos FF REF cada uno. READY_REF solo observa (RUN_B & V_P & !rst_byte):
ACTIVE no se utiliza como permiso de captura. UC_BLOCK protege BLOCKED y
los códigos inválidos. Estos registros no se cuentan otra vez como datos. El set asíncrono y los resets por dominio son excepciones
físicas explícitas respecto a la lógica posedge ordinaria del datapath.

## Verificación y límites

El RTL está en `../src/`. `make -C dphy_gowin_tx test` comprueba la cadena
con el wrapper y modelos ideales explícitos de celdas, para L=2 y L=5.
Cada recorrido reconstruye siete paquetes HS y siete LPDT desde los pads
simulados. Las pruebas unitarias verifican 128 comandos consecutivos,
alineación de bits/LP/ACK, selección de propietario y máscaras de fallo.
Las pruebas de fallo inyectan pérdida de PLL con relojes detenidos, aborto
y reset en cinco fases HS, además de lane parcial y recuperación coordinada.

Yosys comprueba 52 bits ordinarios, 6 bits UC y 21 de seguridad/CDC para L=2;
no hay latches, RAM ni contadores de fases en el wrapper. `synth_gowin`
mapea la lógica para GW2A y conserva tres OSER8, seis TBUF, tres TLVDS_TBUF
y una rPLL. No se han ejecutado P&R, STA ni mediciones de placa.

### Corrección de la revisión RTL: retorno de disponibilidad

La ecuación original incluía `!phy_abort` directamente en `pll_ready`.
Al conectar el árbitro existente se obtenía el ciclo combinacional
`phy_abort → pll_ready → arbiter.hs_fault → phy_abort`.
Se elimina **solo ese factor directo de pll_ready**. SAFE conserva
`!phy_abort`, y R_INHIBIT/EV_RAW conservan el bloqueo persistente.
La prueba estructural del enlace exige cero SCC combinacionales.
No se añaden registros de ACK ni se altera L.

`rst_byte` asertado por pérdida de LOCK reinicia también el árbitro y el
transporte. Sus causas anteriores pueden desaparecer; CLOCK_FAULT del wrapper
permanece hasta `rst`. Por otra parte, `error_code=1` del árbitro indica pérdida
de disponibilidad agregada y puede aparecer después de un aborto al bajar
pll_ready por INHIBIT. Solo `clock_fault` distingue una pérdida de LOCK real.
No cambiar los módulos anteriores para fabricar conservación de sus causas.

Los adaptadores físicos son candidatos parametrizables. Los valores de PLL,
MAP_BITS, HWL, J/L, fase de CLK, red de reloj y OE deben caracterizarse en el
dispositivo concreto. PROFILE_OK=0 por defecto impide liberar el supervisor.
Los modelos ideales no constituyen prueba de la latencia de las primitivas.

Fuentes locales: puertos y RTL de dphy_hs_tx, dphy_mode_ctrl, dsi_lpdt_bridge;
[contrato lógico](../../dphy_hs_tx/docs/contrato_temporal.md),
[hardware](../../docs/hardware.md), declaración OSER8/TBUF instalada en
`/usr/share/yosys/gowin/cells_sim.v`. La declaración de OSER8 es vacía y no
justifica latencia ni funcionamiento. Para el mapeo físico consultar
[Gowin UG289](https://cdn.gowinsemi.com.cn/UG289E.pdf).
