# Flujo de dphy_gowin_tx

**RTL implementado, 2026-11-09; perfil físico pendiente.** [Único editable](DPHY_GOWIN_TX.drawio), páginas
1–4: interconexión, flujo general/LPDT, HS y recuperación.
[PDF completo](DPHY_GOWIN_TX.pdf). [Señales](interfaces.md).

## Arranque y captura continua

1. Durante rst: INHIBIT=1, HS_OE=000, tubería inválida, ACK y stop_ready a cero.
   La política LP de bloqueo procede de constantes explícitas del perfil.
2. UC_SUP dispone de BOOT_ALLOWED tras reset. Esperar rst=0, phy_abort=0,
   LOCK sincronizado y PROFILE_OK. Emitir RELEASE_SAFE una sola vez.
3. Liberar los resets físicos por dominio. Con SER_READY_B, RUN_B habilita
   LD_CMD y desactiva RST_PIPE. L capturas llenan la tubería de control.
4. Con V_P=1 y SAFE=1, publicar LP/HS y los ACK retardados. Mantener captura
   continua: las transiciones de retorno deben recorrer la tubería completa.

PROFILE_OK es una constante de elaboración validada por caracterización, no
un sensor de la placa ni un permiso de ejecución. L=2+J es el retardo común
de tramas y controles, definido en [datapath](datapath.md).

## LPDT

M0 selecciona estado_D0 mientras lp_grant=1. Capturar ese mismo grant como
OWNER. El motor LPDT mantiene la secuencia lógica y el árbitro la propiedad.
Cuando el puente emite tx_done, el árbitro recibe lp_done y entra en retorno.
La tubería sigue publicando los estados previos: todavía no se declara reposo.
Esperar LP-11 conducido, HS apagado, OWNER retardado=0, lp_grant actual=0 y
estado_D0=11. C_STOP activa stop_ready; solo el árbitro genera lp_complete.
Con C_STOP=0 se sigue capturando, sin bloquear la tubería esperando su propio
vaciado. No conectar busy del puente a esa condición.

## HS: origen y efecto de cada fase

El secuenciador conserva la responsabilidad de LPX/Prepare/Zero, Sync,
payload, Trail, Exit y POST. El wrapper desplaza el comando completo L ciclos;
no vuelve a contar esas fases ni añade otro planificador.

| Origen en dphy_hs_tx | Efecto en el wrapper |
|---|---|
| Preparar CLK y comenzar oscilación | M1 cambia 00→AA en el camino de S2; HS_OE/LP se alinean con el pin |
| clk_prepared_s | clk_prepared_p retardado; el árbitro puede pedir datos |
| Preparar datos; esperar primera palabra | Conducir HS-0 hasta la llegada de Sync; data_prepared_p permite grant |
| Sync B8B8 y payload | R_FRAME y S0/S1 recorren un camino único, sin huecos |
| Último payload, retirada normal de grant | Continuar captura y drenaje; no usar grant como enable |
| Trail ya construido en FRAME | Emitirlo después del último bit payload, sin recrearlo |
| Retorno LP de datos y Exit | Publicar estados y data_stopped_p con el mismo retardo |
| POST, Trail/Exit de CLK | Preservar las duraciones; clk_stopped_p llega tras el retorno físico programado |
| local_stop_s | Cualificar reposo con C_STOP; el árbitro genera hs_complete |

El retardo debe incluir datos, reloj, LP, enables y ACK hasta la frontera
física. Retrasar solo ACK no cumple este contrato. Si el perfil no permite
latencia común, debe rechazarse y revisarse el diseño; no se oculta esa
incompatibilidad con una caja de guardas sin definición.

## Recuperación global

Reset, phy_abort o pérdida de LOCK inhiben HS sin esperar a FCLK; invalidan
la tubería y los ACK, y aplican el perfil LP de bloqueo. No fuerzan LP-11 contra
un motor activo ni generan éxito por un prefijo enviado.

La pérdida de LOCK solo crea CLOCK_FAULT después de RUN_STARTED. En arranque,
LOCK bajo mantiene espera, sin inventar fallo de trama. CLOCK_FAULT se conserva
hasta rst; phy_abort por sí solo no crea esa causa. Tras aborto/fallo no se
emite otro RELEASE_SAFE por una simple recuperación de LOCK o clear_error:
hace falta reset coordinado de transporte, árbitro, secuenciador y ruta LPDT.
El retorno normal y el descarte por fallo son rutas diferentes.

## Qué sigue siendo físico

L, fases, primitiva SER8, buffers y política LP son parámetros precisos del
perfil que debe caracterizarse, no decisiones implícitas del implementador.
S320-MODEL es referencia funcional. No fija bitrate del LCD, divisores del PLL,
estándar de E/S o autorización para conectar la pantalla. El wrapper RTL implementa este flujo; el target de hardware conserva
su integración anterior.

La [FSM](fsm.md) concreta el supervisor en páginas 8–9 del editable.
BOOT_ALLOWED se decodifica del estado; ABORT_SEEN retiene abortos breves y
EV_RAW impide una nueva liberación de INHIBIT dentro del mismo ciclo RELEASE.
UC_BLOCK protege BLOCKED y los códigos no utilizados; estas señales también
cualifican SAFE/pll_ready en el datapath.
