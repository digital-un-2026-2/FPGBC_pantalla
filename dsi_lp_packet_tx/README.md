# dsi_lp_packet_tx

Preparador de escrituras DCS cortas, VC = 0. Recibe un descriptor de comando,
forma la cabecera y su ECC, y entrega cuatro bytes mediante `valid/ready`.
Implementa el [datapath](docs/datapath.svg) y la [FSM](docs/fsm.svg) del
[Draw.io](docs/DSI_LP_PACKET_TX.drawio).

| `cmd_has_param` | Bytes en orden de entrega |
|---|---|
| 0 | `05`, `cmd_opcode`, `00`, ECC |
| 1 | `15`, `cmd_opcode`, `cmd_param`, ECC |

Sin parámetro, se ignora `cmd_param`. Ejemplos: `01` sin parámetro produce
`05 01 00 10`; `3A` con parámetro `55` produce `15 3A 55 02`.
El productor elige el comando y sus esperas; el núcleo no valida la semántica
del opcode. Este bloque no genera paquetes largos ni CRC.

## Interfaz

Todas las transferencias y registros usan el **flanco ascendente** de `clk`.
El reloj de trabajo previsto es de 40 MHz. `rst` es activo en alto y síncrono
para el almacenamiento, con prioridad sobre carga e incremento.

| Señal | Dirección | Función |
|---|---|---|
| `clk`, `rst` | Entrada | Reloj y reset interno |
| `cmd_valid` | Entrada | Descriptor disponible |
| `cmd_opcode[7:0]` | Entrada | Comando DCS |
| `cmd_has_param` | Entrada | Selecciona escritura con un parámetro |
| `cmd_param[7:0]` | Entrada | Parámetro opcional |
| `cmd_ready` | Salida | Puede aceptar un descriptor |
| `tx_byte_data[7:0]` | Salida | Byte seleccionado del paquete capturado |
| `tx_byte_valid` | Salida | Byte disponible |
| `tx_byte_last` | Salida | Marca el cuarto byte; significativo con `valid = 1` |
| `tx_byte_ready` | Entrada | El receptor acepta un byte |
| `busy` | Salida | Estado `SEND` |
| `packet_done` | Salida | Pulso registrado de un ciclo tras entregar el ECC |

El productor mantiene `valid` y el descriptor hasta un flanco con
`cmd_valid && cmd_ready`. En ese flanco se capturan los cuatro bytes y se
inicia el índice en cero. Cambiar las entradas después no altera el paquete.

Solo un flanco con `tx_byte_valid && tx_byte_ready` transfiere un byte.
Si el receptor pausa, se conservan dato, índice, `last` y `valid`, salvo reset.
El cuarto byte vuelve la FSM a `IDLE`, sin incrementar el índice, y activa
`packet_done`. En ese ciclo `cmd_ready` ya está activo: la siguiente orden
puede aceptarse en el siguiente flanco. No hay cola ni aceptación de una orden
nueva en el mismo flanco que entrega el ECC.

Con `valid` y `ready` continuos hay cuatro transferencias tras la captura y
cinco ciclos entre aceptaciones. Mientras `rst = 1`, ambos handshakes quedan
bloqueados. En el flanco de reset se borran paquete, índice y aviso, y la FSM
vuelve a `IDLE` sin `packet_done`. `busy` cambia al registrar ese estado.

## Estructura RTL

Se mantiene la organización por componentes de `dphy_lpdt_tx`. Los registros
y el contador de este núcleo usan `posedge`; los componentes equivalentes del
motor LPDT usan `negedge` y no se modifican.

| Archivo en `src/` | Elemento del esquema |
|---|---|
| `dsi_lp_packet_tx.v` | Conexión del datapath y su control |
| `packet_mux.v` | M0: Data ID; M1: Data 1; M2: selección de byte |
| `packet_ecc.v` | Red XOR de los 24 bits de cabecera; ECC[7:6] = 0 |
| `packet_register.v` | Registro de 32 bits `{ECC, Data 1, Data 0, Data ID}` |
| `packet_counter.v` | Índice de byte, dos bits |
| `packet_compare.v` | `Z_LAST = (índice == 3)` |
| `packet_control.v` | FSM `IDLE` / `SEND` y pulso `packet_done` |

La matriz ECC coincide con `dsi_header_ecc` del script existente
`scripts/test_lpdt_hw.py` y se contrastó con la matriz del
[driver Linux sun6i_mipi_dsi](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/sun4i/sun6i_mipi_dsi.c).

El [puente de prueba `dsi_lpdt_bridge`](../dsi_lpdt_bridge/README.md) conecta
este flujo al motor `dphy_lpdt_tx`, que usa `cantidad_bytes`, `pos` y
`byte_almacen`. La conexión se verifica en simulación y aún no está integrada
en el target LiteX. El motor añade el selector LPDT `87`;
`packet_done` no sustituye a su señal `terminado`.

## Verificación sin hardware

Desde la raíz del repositorio:

```sh
pixi run check-rtl
pixi run test-dsi-packet
```

Con Icarus, VVP y Make disponibles también se puede ejecutar directamente:

```sh
make -C dsi_lp_packet_tx check
make -C dsi_lp_packet_tx test
```

El testbench compara exclusivamente los puertos públicos contra un modelo
que conserva el descriptor aceptado. Para ECC utiliza síndromes por bit,
contrastados con vectores fijos, en lugar de repetir las ecuaciones del RTL.
Comprueba los 256 opcodes sin parámetro, los 65.536 pares opcode/parámetro,
los 24 bits individuales del generador ECC, pausas en todos los bytes,
inmutabilidad del paquete, una orden pendiente y `valid/ready` continuos.
También comprueba reset antes de cada byte, incluyendo ECC listo para
transferirse, y durante el aviso de fin, seguido de recuperación.

El ejecutable se guarda en `build/dsi_lp_packet_tx/`. Estas pruebas no requieren
FPGA. La síntesis genérica y la simulación no comprueban timing a 40 MHz,
integración LPDT/LiteX ni recepción del panel.
