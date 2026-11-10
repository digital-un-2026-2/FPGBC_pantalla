# dsi_long_packet_tx

Preparador de paquetes largos DSI según el flujo, datapath y FSM de
[DSI_LONG_PACKET_TX.drawio](docs/DSI_LONG_PACKET_TX.drawio).
Vistas: [flujo](docs/flujo.svg), [datapath](docs/datapath.svg), [FSM](docs/fsm.svg).

Recibe un descriptor y exactamente WC bytes de carga útil. Entrega:

```text
{VC, DT} → WC[7:0] → WC[15:8] → ECC → carga útil → CRC[7:0] → CRC[15:8]
```

ECC protege los primeros tres bytes. CRC16 protege solo la carga útil:
polinomio 1021 (8408 reflejado), bits de cada byte LSB primero, semilla FFFF
y sin XOR final. La cabecera y el CRC no cuentan dentro de WC.
Se contrastó el algoritmo con el
[driver Linux sun6i_mipi_dsi](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/sun4i/sun6i_mipi_dsi.c)
y [crc-ccitt](https://github.com/torvalds/linux/blob/master/lib/crc-ccitt.c).

## Interfaz

Todos los registros y transferencias usan el flanco ascendente de `clk`.
Reloj previsto: 40 MHz. `rst` es activo en alto y síncrono para los registros;
mientras está activo bloquea los tres handshakes.

| Señal | Dirección | Función |
|---|---|---|
| `clk`, `rst` | Entrada | Reloj y reset interno |
| `cmd_valid`, `cmd_ready` | Entrada / salida | Handshake del descriptor |
| `cmd_vc[1:0]` | Entrada | Canal virtual |
| `cmd_dt[5:0]` | Entrada | Tipo de dato de paquete largo |
| `cmd_wc[15:0]` | Entrada | Cantidad de bytes de carga útil, 0–65535 |
| `payload_data[7:0]` | Entrada | Byte de carga útil |
| `payload_valid`, `payload_ready` | Entrada / salida | Handshake de carga útil |
| `tx_byte_data[7:0]` | Salida | Byte del paquete |
| `tx_byte_valid`, `tx_byte_ready` | Salida / entrada | Handshake de salida |
| `tx_byte_last` | Salida | Marca el CRC alto; significativo con `valid = 1` |
| `busy` | Salida | FSM fuera de IDLE |
| `packet_done` | Salida | Pulso registrado tras aceptar el CRC alto |

Cada transferencia ocurre con `valid && ready` en el mismo flanco. Los
productores conservan `valid` y sus datos hasta la aceptación. Tras capturar
el descriptor, sus entradas pueden cambiar sin alterar el paquete activo.
El bloque guarda un byte de carga útil; conserva dato, `last` y `valid` de
salida cuando el receptor pausa. No hay cola ni timeout.

El productor debe aportar el DT apropiado y una carga útil coherente. En DCS
largo (`DT = 39`), el primer byte de carga útil es el opcode y WC incluye ese
byte. En RGB888 (`DT = 3E`), el productor entrega los bytes de píxeles. El
núcleo no inserta opcodes, convierte píxeles ni valida las restricciones de DT.
Con WC = 0 no acepta carga útil y entrega CRC FFFF.

## Organización RTL

| Archivo en `src/` | Elemento del esquema |
|---|---|
| `dsi_long_packet_tx.v` | Datapath, registros y conexiones al control |
| `long_packet_control.v` | IDLE, SEND_HEADER, CHECK_PAYLOAD, WAIT_PAYLOAD, SEND_PAYLOAD, SEND_CRC |
| `long_packet_ecc.v` | ECC combinacional de cabecera |
| `long_packet_crc16.v` | CRC siguiente a partir del CRC y byte actuales |
| `long_packet_register.v` | Registros de cabecera [32], byte [8] y CRC [16] |
| `long_packet_counter.v` | Índices de cabecera [2], CRC [1] y bytes entregados [16] |
| `long_packet_compare.v` | Fin de cabecera y carga útil |
| `long_packet_mux.v` | M0: cabecera; M1: CRC; M2: byte de salida |

CRC y contador de carga útil avanzan solo cuando el receptor acepta ese byte.
CHECK_PAYLOAD comprueba el contador ya actualizado. Con productores y receptor
siempre disponibles, la carga útil entrega un byte cada tres ciclos, según
la FSM aprobada. El transporte físico HS necesitará almacenamiento o una
adaptación que garantice su ritmo de transmisión.

Al entregar el CRC alto, la FSM vuelve a IDLE y activa `packet_done` durante
un ciclo. `cmd_ready` ya está activo y permite aceptar la siguiente orden en
el siguiente flanco. Reset tiene prioridad sobre cargas e incrementos:
borra registros, contadores y aviso, vuelve a IDLE y aborta sin generar fin.
El CRC se inicializa a FFFF al aceptar cada nuevo descriptor.

Este núcleo entrega bytes DSI; no implementa serialización, reparto entre
lanes, señalización LP/HS, planificación de vídeo ni conexión al panel.
`packet_done` indica fin de entrega del paquete, no recepción por la pantalla.

## Verificación

```sh
pixi run --locked check-rtl
pixi run --locked test-dsi-long-packet
```

También: `make -C dsi_long_packet_tx check` y `make -C dsi_long_packet_tx test`.
Los productos se guardan en `build/dsi_long_packet_tx/`.

El testbench observa los puertos públicos y compara el paquete completo.
Verifica ECC con síndromes por bit y CRC con un modelo MSB de polinomio 1021,
contrastado con vectores fijos. Incluye todos los VC y DT, longitudes cero,
fronteras 255/256/257, una línea RGB888 de 2160 bytes y WC máximo 65535;
pausas de entrada/salida, descriptor pendiente, datos extra, abortos y
recuperación. La simulación y síntesis genérica no verifican timing físico
ni recepción del panel.
