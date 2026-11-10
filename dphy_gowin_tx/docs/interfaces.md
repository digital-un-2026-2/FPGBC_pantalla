# Interfaces y señales de dphy_gowin_tx

**Interfaz RTL implementada; perfil físico aún sin caracterizar.**
[Editable único](DPHY_GOWIN_TX.drawio), página 1: interconexión;
páginas 5–7: datapath; páginas 8–9: FSM del supervisor. [PDF completo](DPHY_GOWIN_TX.pdf).

## Convenciones

`[n]` en el dibujo significa ancho n, no índice de bit. `_s` distingue las
salidas del secuenciador, `_p` el retorno del wrapper hacia el árbitro.
Los sufijos son nombres propuestos de los cables/puertos del wrapper; no
renombran los puertos existentes del RTL. Todos los controles y resets son
activos altos, salvo OEN de los buffers candidatos, activo bajo.

Señales ordinarias se muestrean en posedge de `byte_clk`. El árbitro conserva
su datapath en negedge. `estado_D0` del motor LPDT también cambia en negedge:
su captura en posedge introduce un camino de medio ciclo que exige STA.
No se sincroniza ese bus bit a bit ni se interpreta como un CDC asíncrono.

## Entradas del wrapper

| Puerto propuesto | Bits | Origen exacto | Significado |
|---|---:|---|---|
| `ref_clk` | 1 | Oscilador clk40, pin 11 | Reloj independiente del PLL, 40 MHz |
| `rst` | 1 | Supervisor externo del sistema | Reset coordinado; cubre ambos flancos de la cadena |
| `phy_abort` | 1 | `dphy_mode_ctrl.phy_abort` | Descartar operación e inhibir conducción; no rearma el wrapper |
| `lp_grant` | 1 | `dphy_mode_ctrl.lp_grant` | Selecciona el motor LPDT en M0 y se conserva como OWNER |
| `estado_D0` | 2 | `dsi_lpdt_bridge.estado_D0` | Estado LPDT {P,N}; proviene de su motor interno |
| `hs_frame_data` | 16 | `dphy_hs_tx.hs_frame_data` | Byte bajo para D0, alto para D1; incluye Zero/Sync/payload/Trail |
| `hs_frame_kind` | 2 | `dphy_hs_tx.hs_frame_kind` | 00 Zero, 01 Sync, 10 payload, 11 Trail; diagnóstico y trazabilidad |
| `hs_data_on` | 1 | `dphy_hs_tx.hs_data_on` | Conducción HS conjunta de D0 y D1 |
| `hs_clk_on` | 1 | `dphy_hs_tx.hs_clk_on` | Conducción HS de CLK, incluida la fase HS-0 |
| `clk_toggle` | 1 | `dphy_hs_tx.clk_toggle` | Selecciona patrón AA en M1; cero selecciona 00 |
| `lp_clk`, `lp_d0`, `lp_d1` | 2 cada uno | Puertos homónimos de `dphy_hs_tx` | Estados LP del secuenciador; M0 sustituye solo D0 durante LPDT |
| `clk_prepared_s` | 1 | `dphy_hs_tx.clk_prepared` | Condición lógica de preparación de CLK; retardar con sus controles |
| `data_prepared_s` | 1 | `dphy_hs_tx.data_prepared` | Preparación de D0/D1; el árbitro puede conceder HS tras el retorno retardado |
| `data_stopped_s` | 1 | `dphy_hs_tx.data_stopped` | Retorno lógico de datos tras Trail/Exit |
| `clk_stopped_s` | 1 | `dphy_hs_tx.clk_stopped` | Retorno lógico del reloj tras Trail/Exit |
| `local_stop_s` | 1 | `dphy_hs_tx.hs_local_stop` | Candidato a reposo conjunto; se cualifica tras la tubería |

No entran `hs_word_*`, `hs_word_last`, `hs_grant`, `hs_done`, `lp_done`,
`busy` ni bytes de paquetes al wrapper. Sus rutas se muestran a continuación.
`kind` no vuelve a elegir el dato: `hs_frame_data` ya contiene el byte correcto.

## Salidas del wrapper

| Puerto propuesto | Bits | Destino exacto | Validez y efecto |
|---|---:|---|---|
| `byte_clk` | 1 | clk de transporte, árbitro, secuenciador y ruta LPDT | Dominio común relacionado con PCLK/FCLK |
| `rst_byte` | 1 | rst de esos bloques | Aserción async por rst o pérdida de LOCK; liberación sincronizada en byte_clk |
| `clk_prepared_p` | 1 | `dphy_mode_ctrl.clk_prepared` | SAFE & ACK_P[0] |
| `data_prepared_p` | 1 | `dphy_mode_ctrl.data_prepared` | SAFE & ACK_P[1] |
| `data_stopped_p` | 1 | `dphy_mode_ctrl.data_stopped` | SAFE & ACK_P[2] |
| `clk_stopped_p` | 1 | `dphy_mode_ctrl.clk_stopped` | SAFE & ACK_P[3] |
| `stop_ready` | 1 | `dphy_mode_ctrl.stop_ready` | C_STOP, ecuación completa en datapath |
| `pll_ready` | 1 | `dphy_mode_ctrl.pll_locked` | Dominio/reset listos; no equivale a LOCK_RAW sin cualificar |
| `clock_fault` | 1 | OR externo hacia `dphy_mode_ctrl.hs_error` | Pérdida de LOCK tras habilitar, retenida hasta rst |
| `lp_pad_p/n` | 3 + 3 | Ramas GPIO/LP de CLK, D1 y D0 | Salidas de seis TBUF, orden indicado en tabla de pines |
| `hs_pad_p/n` | 3 + 3 | Ramas diferenciales de CLK, D1 y D0 | Salidas de tres buffers diferenciales con OE independiente |

Los ACK son niveles de condición, no pulsos de fin. La memoria reside en la
tubería R_CTRL, sin cuatro registros ACK adicionales. `lp_complete` y
`hs_complete` pertenecen exclusivamente al árbitro y vuelven a los productores.
Ninguna confirmación demuestra recepción de comandos o imagen por el LCD.

## Conexiones externas que no atraviesan el wrapper

| Fuente | Destino |
|---|---|
| Transporte `hs_req`, `hs_done`, `hs_data_ready` | Árbitro, puertos homónimos |
| Árbitro `hs_req_ready`, `hs_grant`, `hs_complete` | Transporte, puertos homónimos |
| Transporte `hs_word_data[15:0]`, keep[1:0], valid, last | Secuenciador `hs_word_*` (20 bits) |
| Árbitro `hs_grant` | También secuenciador `hs_grant` |
| Árbitro clk/data_start_req y clk/data_stop_req | Secuenciador, órdenes homónimas |
| Puente `lp_req`, `tx_done` | Árbitro `lp_req`, `lp_done` |
| Árbitro `lp_grant` | También puente `permiso_arranque` |
| Árbitro `phy_abort` | También secuenciador y transporte; recuperación LP mediante reset coordinado |

`arbiter.hs_error = transport.hs_error | sequencer.phy_error | wrapper.clock_fault`.
Las causas locales del secuenciador y transporte conservan sus registros y
códigos existentes; el wrapper no los copia ni los borra con clear_error.

## Constantes del perfil y límites concretos

| Parámetro | Tipo | Criterio |
|---|---|---|
| `J` | Entero >=0 | Latencia adicional común de SER8 respecto al modelo de carga; caracterizada en primitivas |
| `L` | Entero, L=2+J | Retardo total de comando; R_CTRL tiene exactamente L etapas |
| `P_LP_RUN_EN` | 6 bits | Habilitaciones LP en operación; modelo=3F |
| `P_LP_BLOCK_EN` | 6 bits | Habilitaciones LP bloqueadas; modelo=00 |
| `P_LP_BLOCK_DATA` | 6 bits | Datos LP en bloqueo; modelo=00, irrelevante si EN=00 |
| Fases / MAP_BITS | Configuración estática | Emisión LSB primero, CLK centrado, latencia común de dato/control hasta pads |
| `PROFILE_OK` | Constante de elaboración | 1 solo si la caracterización demuestra esos requisitos; no configurable por CSR |

S320-MODEL usa PCLK=40 MHz, FCLK_D=FCLK_C=160 MHz, J=0 y L=2.
Es una referencia funcional de diagramas; no una elección del bitrate del LCD.
No se suministran divisores PLL, fases o un estándar de E/S físico ficticios.
Si la primitiva no permite realizar la latencia común con alineación estática,
ese perfil se rechaza: cambiarlo exige revisar el contrato, no añadir una
guarda indefinida o retrasar únicamente los ACK.

## Pines según el mapa de la placa

Orden de buses de seis bits: {CLK_P,CLK_N,D1_P,D1_N,D0_P,D0_N}.
Orden HS_OE: {CLK,D1,D0}. La red externa une cada rama LP con su rama HS.

| Conductor | Pin LP | Resistencia de rama | Pin HS |
|---|---:|---:|---:|
| CLK_P | 126 | 100 ohmios | 113 |
| CLK_N | 128 | 100 ohmios | 112 |
| D1_P | 124 | 100 ohmios | 115 |
| D1_N | 125 | 100 ohmios | 114 |
| D0_P | 122 | 100 ohmios | 117 |
| D0_N | 123 | 100 ohmios | 116 |

Fuente: [hardware.md](../../docs/hardware.md). Son pines FPGA, no contactos del
conector. La conectividad documentada no valida estándares, pares utilizables,
timing de OE ni estado durante configuración. El target actual no se modifica.

## Controles internos concretados por la FSM

[UC_SUP](fsm.md) tiene seis estados y seis bits de memoria. RELEASE_SAFE
libera R_INHIBIT una vez por reset; UC_BLOCK es alto en BLOCKED y códigos
inválidos. EV_RAW=ABORT_SEEN|CLOCK_FAULT retiene eventos breves; se añade a
la inhibición y a las máscaras SAFE/pll_ready. READY_REF observa RUN_B y V_P
mediante dos FF REF; ABORT_REF y EV_REF usan también dos FF REF por señal.
Son conexiones internas de UC/datapath, sin puertos públicos nuevos.

## Adaptadores RTL y perfil de elaboración

`src/dphy_gowin_tx.v` implementa estos puertos sin modificar los módulos
anteriores. `PROFILE_OK=0` es el valor predeterminado. La rPLL candidata
expone PLL_IDIV/FBDIV/ODIV/SDIV/PHASE y DEVICE. Los valores nominales
0/3/4/4 y PHASE="0000" no describen un reloj de CLK centrado ni un perfil
aprobado. La selección DEVICE debe cotejarse con la herramienta y la pieza.
MAP_BITS[3*i+:3] indica qué bit de entrada alimenta Di de OSER8;
24'hfac688 es identidad. SER_HWL se propaga a HWL. TX0..TX3 se atan a cero
y Q1 se deja abierto: OE se controla por el camino separado del diagrama.
La función de Q1 y RESET está documentada en
[Gowin UG289, §4.3](https://cdn.gowinsemi.com.cn/UG289E.pdf).

L debe ser 2+J, J>=0; el adaptador candidato requiere SDIV=4.
Una incoherencia mantiene PROFILE_OK efectivo a cero. J describe la latencia
interna caracterizada de SER8; no inserta registros de FRAME en la lógica
ordinaria. El modelo ideal de pruebas introduce esa latencia en OSER8.

Se corrigió `pll_ready` para eliminar su dependencia combinacional directa
de `phy_abort`, que cerraba un lazo con el árbitro existente. La ecuación
actual y el efecto sobre diagnósticos se explican en [datapath](datapath.md).
Los pads y ACK sí mantienen su inhibición directa por phy_abort.
