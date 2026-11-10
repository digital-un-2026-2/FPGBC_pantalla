# Integración de pantalla DSI

Para la imagen de prueba de placa se añade `src/dsi_image_top.v`, construido
por `gateware.targets.display_image`. Inicializa JDI LT031MDZ4000 y transmite
barras 720×720 a 60 Hz con HS activo a 480 Mbit/s/lane. Una ROM entrega líneas
completas con sincronismos/blanking y evita el límite de preparación de la
cadena general descrita debajo. Reutiliza el motor LPDT, árbitro, PHY, wrapper
Gowin y mailbox. [Construcción y carga](../docs/imagen_en_pantalla.md).

`make test-image` verifica los once DCS de inicialización y los paquetes de
vídeo desde pads simulados (J=0 y J=3), además de dos cuadros de 750 líneas y
720 filas activas a la cadencia requerida. La recepción física no se ha probado.

## Cadena general de paquetes

`src/dsi_display_top.v` une el generador de franjas, el planificador, la ruta
RGB888 y la inicialización DCS corta con el wrapper Gowin real. Los modelos
ideales de primitivas solo se incluyen en los testbenches.

```text
LiteX / UARTWishbone → CSR → mailbox → órdenes y snapshots
                              │
      dsi_video_scheduler ─────┼── control / supervisión
                              │
dsi_test_pattern → dsi_long_packet_tx → dsi_lane_packer
                  → dsi_hs_transport → dphy_hs_tx → dphy_gowin_tx
                                             ↑          ↑
DCS corto → dsi_lpdt_bridge → motor LPDT ──────┼──────────┘
                                      dphy_mode_ctrl
```

`dsi_display_core` trabaja enteramente en `byte_clk`. `dsi_display_top` añade
PLL, serializadores, pads y un mailbox entre `ref_clk` y `byte_clk`. Las
órdenes y resultados completos se mantienen estables hasta su confirmación;
los toggles atraviesan sincronizadores. Solo hay una orden pendiente. La prueba
del mailbox usa relojes sin relación de fase ni frecuencia.

El retorno de disponibilidad al árbitro se registra para cortar el camino
`phy_abort → inhibit asíncrono → pll_ready → phy_abort`. La inhibición inmediata
de pads permanece en el wrapper; el registro no retrasa esa protección.

## Estado y límites físicos

- El [target de placa `display_board`](../docs/implementacion_fpga.md) añade los
  doce pines y los estándares eléctricos, bitstream parked/LPDT y proyecto HS.
  LPDT usa 40 MHz directos, sin PLL/OSER; el vídeo se rechaza por hardware.
- Perfil de vídeo y `PROFILE_OK` **deshabilitados por defecto**. No se inventan
  porches, fps, bitrate ni una secuencia del LCD. Las tablas de perfiles se
  pasan como parámetros de elaboración al scheduler.
- El target `gateware.targets.display` incorpora el circuito completo y CSR,
  con reloj de referencia de 40 MHz y control por PC, sin CPU RISC-V. Exporta
  únicamente reloj/UART; sus pads de pantalla permanecen internos. El target
  anterior `debug` sigue disponible.
- `DSIDisplay(platform, pads=..., rtl_parameters=...)` permite al target
  de placa conectar recursos `lp_p/lp_n/hs_p/hs_n`, cada uno de tres bits en orden
  D0, D1, CLK. Rechaza `PROFILE_OK=1` sin pads explícitos. Los parámetros del
  top incluyen tablas de calendario, PLL, fase, orden de bits y latencia J.
- El secuenciador HS conserva S320 por defecto y añade temporizadores de 60 MHz
  para el target de imagen. Los targets de placa incluyen pines, restricciones
  y P&R; faltan mediciones eléctricas del enlace. Los buses estables del mailbox requieren restricciones
  de retardo adecuadas; los atributos de sincronización no sustituyen STA.
- WAIT/RGB/END no genera sincronismos ni blanking DSI. El modo real del panel
  puede requerir ampliar el calendario y los preparadores. LPDT admite aquí
  DCS cortos con cero o un parámetro, VC=0; no admite comandos largos ni BTA.
- No se ha programado la FPGA ni validado recepción por el LCD.

## Órdenes y resultado

En el puerto RTL `command[31:0]`, los bits 3:0 son el opcode. La aceptación del
mailbox no implica ejecución: `response[9]` informa si el core rechazó la orden.

| Opcode | Acción | Campos adicionales |
|---|---|---|
| 0 | Capturar estado | — |
| 1 | Escribir configuración shadow | profile_id[11:4], VC[13:12] |
| 2 | APPLY | Consultar config_ok en el resultado |
| 3 | Autorizar panel inicializado | Solo detenido y con PHY en reposo |
| 4 | Invalidar autorización | Solo detenido |
| 5 | START, repetir cuadros | Requiere perfil válido, autorización y enlace libre |
| 6 | STOP | Se conserva hasta completar el cuadro y liberar el enlace |
| 7 | Enviar DCS corto LPDT | opcode DCS[11:4], has_param[12], param[20:13] |

Inicialización y vídeo se excluyen desde la admisión de la orden, incluida la
captura del paquete LP antes de que el árbitro tome propiedad. Cada DCS aceptado
invalida la autorización previa. La configuración no cambia durante vídeo.
Un fallo requiere reset coordinado, nueva configuración y nueva inicialización.
Un error local del scheduler no corta arbitrariamente un paquete HS en curso.

Snapshot RTL de 128 bits:

| Bits | Contenido |
|---|---|
| 31:0 | flags |
| 63:32 | Cuadros completos |
| 95:64 | Transacciones LPDT completas, tras reposo confirmado por el árbitro |
| 127:96 | HEIGHT[15:0], WIDTH[15:0] |

Flags: running[0], stopped sin LP pendiente[1], config_ok[2], panel_initialized[3],
fallo de cadena[4], disponibilidad del wrapper[5], LP pendiente[6], árbitro ocupado[7],
clock_fault[8], orden rechazada[9], causa del scheduler[13:10], causa PHY[16:14],
causa del árbitro[18:17], causa del transporte[20:19]. El resto vale cero.
Los contadores certifican finalización local, no recepción por el LCD.

## CSR y software

El prefijo CSR es `display_`; usar las direcciones generadas en `csr.csv`.

| Registro | Acceso | Uso |
|---|---|---|
| reset | RW | Nivel de reset coordinado, arranca en 1; escribir 0 para liberar |
| command | RW | Cada escritura presenta una orden completa |
| clear | RW | Escribir 1 limpia rechazo retenido del puente |
| bridge | RO | ready[0], resultado válido[1], escritura rechazada[2], PHY disponible[3], clock_fault[4], reset byte[5], pendiente[6] |
| sequence | RO | Incrementa al recibir un snapshot; reset lo pone a cero |
| flags, frames, lp_completed, geometry | RO | Último snapshot completo |

Esperar `bridge.ready`, escribir una orden y esperar que cambie `sequence`.
Los cuatro registros de resultado se actualizan juntos y se conservan hasta
la siguiente respuesta; no emitir otra orden mientras se leen. Las escrituras
con el puente ocupado se rechazan sin sobrescribir la orden activa. El reset
coordinado y la pérdida de PLL descartan solicitudes y respuestas pendientes.

Generar el target y comprobarlo sin hardware:

```sh
pixi run --locked generate-display
pixi run --locked check-rtl
pixi run --locked test-dsi-display
```

Productos en `build/display/` (LiteX) y `build/dsi_display/` (pruebas).
La generación produce Verilog, CSR y archivos de construcción, sin síntesis
ni programación. `python -m gateware.targets.display --build` añade síntesis
e implementación de ese target de depuración con pads internos.

`scripts/display_control.py` usa un `litex_server` ya activo. Proporciona
`status`, `reset`, `configure --profile N --vc N`, `initialize archivo.json`,
`start` y `stop`. Ejemplo de consulta: `pixi run --locked python
scripts/display_control.py status`. `stop` espera la terminación del cuadro.
`reset` afirma el reset y lo libera; nunca programa la FPGA.

`initialize` exige una secuencia JSON explícita y validada para el panel:
una lista de objetos con `opcode` entero 0–255, `param` opcional 0–255 y
`delay_ms` no negativo. Espera el contador LP completo antes de aplicar cada
retardo y solo autoriza el panel después del último paso. No se incluye una
secuencia corta para LCD-49754. La secuencia pública JDI con comandos largos
se ejecuta en hardware en el target `display_image`. El target por defecto rechaza la inicialización
porque su perfil físico está bloqueado.

## Verificación ejecutable

- Cadena completa con los RTL reales, perfiles sintéticos de prueba y modelos
  ideales de primitivas: reconstrucción RGB888 desde D0/D1/CLK, ECC y CRC con
  oráculo independiente, franjas 720×2 y geometría alternativa, dos latencias
  J=0/J=3; LPDT desde pads con y sin parámetro.
- START sin autorización, órdenes desconocidas, exclusión LP/vídeo, cambios de
  configuración activos, cuadros repetidos, STOP/reinicio, plazos vencidos,
  pérdida del PLL con relojes detenidos, reset de paquete parcial y recuperación.
- Instancia adicional con parámetros por defecto: todos los pads siguen en Z.
- Mailbox con 100 transacciones entre relojes independientes, reset en vuelo
  y recuperación, sin datos mezclados ni respuestas repetidas.
- Adaptador Migen y CSRBank reales convertidos a Verilog: lecturas/escrituras
  CSR, LP completo, cuadro/STOP, rechazo de escritura durante ocupación,
  limpieza de rechazo y reset sin respuestas antiguas.
- Yosys con calendario y perfil físico habilitados para evitar que constantes
  oculten conexiones: elaboración, `proc/flatten/opt/check`, cero SCC y latches;
  `synth_gowin` de la cadena completa para GW2A, sin P&R/STA.

Estas pruebas validan la integración digital. Los modelos ideales no demuestran
temporización real de primitivas, conformidad D-PHY ni funcionamiento del panel.
