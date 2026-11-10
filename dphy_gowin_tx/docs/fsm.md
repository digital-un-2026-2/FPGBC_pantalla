# FSM de dphy_gowin_tx

**RTL · 2026-11-09; perfil físico pendiente.** [Editable único](DPHY_GOWIN_TX.drawio), páginas
8–9. [PDF de la FSM](FSM.pdf) · [Grafo SVG](fsm.svg) ·
[Controles y eventos](fsm_control.svg). Derivada del [flujo](flujo.md) y
del [datapath](datapath.md). Implementación: `../src/gowin_tx_control.v`.

## Memoria, flanco y responsabilidades

UC_SUP supervisa arranque y recuperación. Las fases LPX, Prepare, Zero, Sync,
payload, Trail, Exit y POST siguen en la FSM existente de `dphy_hs_tx`.
El árbitro conserva la propiedad LP/HS y los pulsos complete.

| Memoria de UC | Bits | Actualización / reset |
|---|---:|---|
| STATE | 3 | posedge ref_clk; rst síncrono prioritario → RESET |
| RUN_STARTED | 1 | En el flanco BOOT_FIRE se pone a 1; rst → 0; resto conserva |
| ABORT_SEEN | 1 | Captura asíncrona de phy_abort después de RUN_STARTED; rst → 0 |
| CLOCK_FAULT | 1 | Captura asíncrona de pérdida de LOCK después de RUN_STARTED; rst → 0 |

Total: **6 bits de UC**. BOOT_ALLOWED es decodificación del estado; no añade
memoria. R_INHIBIT pertenece al circuito físico de seguridad, no se cuenta
otra vez en STATE. Sincronizadores, resets por dominio e IOLOGIC quedan fuera
de ese recuento. El datapath ordinario mantiene sus 16+18L bits.

Las transiciones de STATE y la carga de RUN_STARTED se deciden antes del
mismo posedge de ref_clk (40 MHz). Salidas combinacionales, con valores
predeterminados; no se requiere next_state ni ACTION retenido hasta negedge.
Los registros de datos siguen en byte_clk y el árbitro en sus dos flancos.
Las excepciones asíncronas son captura de eventos e inhibición física, para
funcionar aunque se detenga FCLK. Su realización Gowin requiere validación.

## Entradas y cruces de dominio

| Señal de decisión | Origen y tratamiento |
|---|---|
| LOCK_SYNC | LOCK_RAW de PLL0 → R_LOCK0/R_LOCK1, dos FF REF existentes |
| ABORT_REF | phy_abort del árbitro → R_ABORT0/R_ABORT1, dos FF REF |
| EV_REF | ABORT_SEEN OR CLOCK_FAULT → R_EV0/R_EV1, dos FF REF |
| READY_REF | RUN_B AND V_P AND !rst_byte → R_READY0/R_READY1, dos FF REF |
| PROFILE_OK | Constante de elaboración del perfil físico |
| rst | Reset coordinado del sistema, mantenido para cubrir todos los dominios |

Los seis FF REF nuevos de ABORT/EV/READY se reinician a cero con rst.
Solo cruzan señales de un bit; FRAME, LP y ACK conservan su tubería común
en byte_clk. EV_RAW es la OR de causas capturadas antes de sincronizar:
interviene directamente en la inhibición, sin esperar a EV_REF.

```text
VALID_STATES = {000, 001, 011, 010, 110, 111}
STATE_OK = STATE pertenece a VALID_STATES
UC_BLOCK = (STATE == BLOCKED) | !STATE_OK
BOOT_ALLOWED = (STATE == RESET) | (STATE == WAIT_LOCK)

EV_RAW = ABORT_SEEN | CLOCK_FAULT
B = PROFILE_OK & LOCK_SYNC & !ABORT_REF & !EV_REF
F = EV_REF
  | (RUN_STARTED & (!LOCK_SYNC | ABORT_REF | !PROFILE_OK))
  | ((STATE == ACTIVE) & !READY_REF)
```

B es la condición normal de arranque. F tiene prioridad sobre el avance
normal; también detecta pérdida de disponibilidad después de ACTIVE.
LOCK bajo o phy_abort alto antes del primer arranque mantienen espera, sin
inventar CLOCK_FAULT ni bloquear permanentemente por el reset del árbitro.

## Estados y transiciones

Codificación Gray del recorrido normal: 000→001→011→010→110. Una transición
normal cambia un solo bit, evitando pasar por códigos inválidos que disparen
UC_BLOCK. Las transiciones de fallo ya están subordinadas a la inhibición;
reset protege el retorno de cualquier código a 000.

| Código / estado | Condición normal | Destino / acción |
|---|---|---|
| 000 RESET | !rst | WAIT_LOCK; RUN_STARTED permanece 0 |
| 001 WAIT_LOCK | !B | Conservar WAIT_LOCK, sin timeout |
| 001 WAIT_LOCK | B | RELEASE; RUN_STARTED←1 en ese mismo flanco |
| 011 RELEASE | Siempre, si !F | WAIT_READY; RELEASE dura un ciclo completo REF |
| 010 WAIT_READY | !READY_REF | Conservar; byte_clk puede estar llenando R_CTRL |
| 010 WAIT_READY | READY_REF | ACTIVE |
| 110 ACTIVE | !F | Conservar; captura continua, sin estados LPDT/HS nuevos |
| 111 BLOCKED | !rst | Conservar, aunque desaparezcan las entradas de fallo |
| 100 / 101 inválidos | !rst | BLOCKED; UC_BLOCK ya inhibe combinacionalmente |

Prioridad en cada posedge REF:

1. rst: STATE←RESET; RUN_STARTED y causas a cero.
2. Código inválido: STATE←BLOCKED.
3. F: STATE←BLOCKED.
4. Transición normal de la tabla.

No hay salida de BLOCKED por clear_error, nueva solicitud, LOCK recuperado o
phy_abort retirado. Hace falta reset coordinado de toda la cadena.

## Controles y captura de eventos

```text
BOOT_FIRE = !rst & (STATE == WAIT_LOCK) & B & !F

RUN_STARTED' = rst ? 0 : BOOT_FIRE ? 1 : RUN_STARTED

SET_ABORT = !rst & RUN_STARTED & phy_abort
SET_PLL   = !rst & RUN_STARTED & !LOCK_RAW
```

ABORT_SEEN y CLOCK_FAULT conservan sus eventos aunque las entradas se recuperen
antes de un posedge REF. Solo rst los limpia. rst tiene prioridad sobre los
sets; la implementación física debe garantizar captura y liberación correctas.
Una pérdida de LOCK simultánea con aborto conserva CLOCK_FAULT; un aborto
aislado no lo crea. clock_fault del wrapper conserva su conexión a G_ERR.

```text
G_RELEASE = !rst & PROFILE_OK & LOCK_SYNC & LOCK_RAW & !phy_abort & !EV_RAW
RELEASE_SAFE = (STATE == RELEASE) & G_RELEASE

SET_INHIBIT = rst | phy_abort | !LOCK_RAW | UC_BLOCK | EV_RAW
R_INHIBIT: SET_INHIBIT > RELEASE_SAFE (clear) > conservar
```

Después de BOOT_FIRE, STATE=RELEASE y RUN_STARTED=1 aparecen juntos. Un evento
breve durante RELEASE queda en EV_RAW y vuelve imposible limpiar INHIBIT en
el resto del ciclo, incluso si el nivel raw desaparece antes de que EV_REF
llegue a la FSM. Esta memoria cierra el caso de aborto breve en la ventana de
liberación. UC_BLOCK también protege los dos códigos inválidos sin esperar
al siguiente posedge REF.

## Relación con datapath y salidas a otros módulos

La liberación física se sincroniza en cada dominio. RUN_B, SER_READY_B y V_P
mantienen sus definiciones del datapath. No se añade ACTIVE como permiso de
salida: READY_REF es una observación retardada del arranque ya realizado en
byte_clk; usar ACTIVE para habilitarlo introduciría un lazo y alteraría L.
Por tanto SAFE puede subir durante WAIT_READY cuando la tubería está lista.

```text
RST_PIPE = rst_byte | phy_abort | !RUN_B
LD_CMD = RUN_B & !RST_PIPE

SAFE = RUN_B & V_P & !rst_byte & !phy_abort & LOCK_RAW & !INHIBIT
     & !UC_BLOCK & !EV_RAW
pll_ready = RUN_B & !rst_byte & LOCK_RAW & !INHIBIT
          & !UC_BLOCK & !EV_RAW
```

RELEASE_SAFE limpia R_INHIBIT; UC_BLOCK y EV_RAW fuerzan su set prioritario.
SAFE selecciona M2/M3 y enmascara G0/G1/C_STOP. Los cuatro ACK y stop_ready
van al árbitro; pll_ready alimenta su pll_locked, y CLOCK_FAULT entra por
G_ERR a hs_error. No se añade un puerto público nuevo ni se cambia L.
La máscara directa de phy_abort solo pertenece a SAFE: retirarla de pll_ready
evita el lazo combinacional con el árbitro descrito en [datapath](datapath.md).
En un código inválido se retira pll_ready, sin fingir una pérdida real de
LOCK en CLOCK_FAULT. La causa interna es el código de STATE observable en
depuración; el árbitro detecta indisponibilidad si tenía HS activo.

## Comprobación del diseño

`python dphy_gowin_tx/docs/verificar_fsm.py` comprueba tabla completa,
prioridades, códigos no utilizados, esperas de arranque, pérdida de READY,
captura persistente y aborto durante RELEASE. Es una comprobación de
especificación y dibujos, no una simulación RTL de UC_SUP ni de primitivas.
Resultado ejecutado: **PASS**, 1024 filas de transición, 512 combinaciones
de la máscara RELEASE y recorridos de arranque/fallo/reset. Se contrastaron
los seis códigos del modelo con los estados escritos en el Draw.io.

La prueba existente `verificar_contrato.py` sigue comprobando por separado la
cadena RTL con retardo L=2/5; no verifica esta nueva FSM. Las pruebas RTL de `../TB/` añaden eventos entre flancos, aborto en RELEASE,
relojes detenidos, códigos inválidos, pérdida de READY y reset coordinado.
P&R y STA deben comprobar la realización de la captura asíncrona.

La implementación conserva STATE Gray mediante `fsm_encoding="none"`.
Las causas usan set asíncrono y borrado síncrono en REF con `rst` sostenido;
el set incluye `!rst`, por lo que reset tiene prioridad. R_INHIBIT también
usa set asíncrono y se limpia en el flanco REF que termina RELEASE.
Los resets SER8 liberan primero PCLK y después cada FCLK, mediante dos FF
por dominio; SER_READY vuelve a byte_clk con otros dos FF. No dependen de
RUN_B y no existe un lazo de arranque.
