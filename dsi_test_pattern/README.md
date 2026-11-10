# dsi_test_pattern

**RTL implementado desde el flujo, datapath y FSM.** Top estructural, control
separado y datapath con operadores, MUX, comparadores y registros explícitos,
siguiendo las convenciones de `dsi_lane_packer` y `dsi_hs_transport`.

Fuente autónoma de ocho franjas verticales para el primer hito: mostrar una
imagen estática en el panel. No requiere RISC-V ni framebuffer.

- [Draw.io editable](docs/DSI_TEST_PATTERN.drawio).
- [Flujo SVG](docs/flujo.svg) · [PDF](docs/FLUJO.pdf).
- [Datapath: recorrido](docs/datapath_recorrido.svg), [color y salida](docs/datapath_salidas.svg) · [PDF de ambas páginas](docs/DATAPATH.pdf).
- [Contrato, algoritmo y criterios de verificación](docs/flujo.md).
- [Justificación y ecuaciones del datapath](docs/datapath.md).
- [FSM: estados, controles y cronograma](docs/fsm.md) · [SVG](docs/fsm.svg) · [PDF](docs/FSM.pdf).

El módulo entrega bytes de imagen RGB888 y marcas de línea/cuadro. El
preparador existente añade cabecera, ECC y CRC; la planificación de vídeo,
inicialización y transporte físico corresponden a la integración posterior.
720 × 720 es el perfil de prueba, no una identificación de la variante LCD.

El editable único contiene FLUJO (pág. 1), DATAPATH (págs. 2–3) y FSM (pág. 4).
Regenerarlo: `python dsi_test_pattern/docs/generar_flujo.py`.
Comprobar las ecuaciones y conexiones: `python dsi_test_pattern/docs/verificar_datapath.py`.
Comprobar la FSM: `python dsi_test_pattern/docs/verificar_fsm.py`.
El datapath usa 22 bits para 720 × 720. UC añade STATE[1] (IDLE/STREAM)
y R_DONE[1]: **24 bits lógicos en total**, sin estado extra de fin.

## Contrato RTL

Parámetros de elaboración: `WIDTH=720`, `HEIGHT=720`. Se exige WIDTH >= 8,
múltiplo de 8, y HEIGHT >= 1. Una rama `generate` instancia un módulo de
error solo con parámetros inválidos: Icarus y Yosys los rechazan durante
elaboración, antes de ejecutar simulación o generar hardware.

Todos los registros capturan en `posedge clk`. `rst` es síncrono activo alto
y tiene prioridad sobre las cargas. Mientras está activo, bloquea ambos
handshakes y anula byte y marcas combinacionalmente; `busy` y `frame_done`
reflejan la memoria previa hasta el flanco de reset.

| Puerto | Dirección | Bits | Uso |
|---|---|---:|---|
| `clk`, `rst` | Entrada | 1 cada uno | Reloj y reset |
| `start_valid`, `start_ready` | Entrada / salida | 1 cada uno | Aceptar un cuadro con ambos a 1 |
| `tx_byte_data` | Salida | 8 | Componente RGB888, orden R → G → B |
| `tx_byte_valid`, `tx_byte_ready` | Salida / entrada | 1 cada uno | Aceptar el byte con ambos a 1 |
| `tx_line_last`, `tx_frame_last` | Salida | 1 cada uno | Último B de línea / cuadro |
| `busy` | Salida | 1 | FSM en STREAM |
| `frame_done` | Salida | 1 | Pulso registrado al aceptar el último B |

Cada inicio reinicia X/Y/C. El primer R queda válido después de ese flanco;
con ready alto se entrega un byte por ciclo, sin burbujas dentro del cuadro.
Sin aceptación, posición, byte y marcas permanecen estables. Las marcas no
dependen de ready. Con valid bajo, byte y marcas valen cero.

Al entregar el último B, la FSM vuelve a IDLE y activa `frame_done` durante
un ciclo. No acepta inicio en ese mismo flanco; puede aceptarlo en el
siguiente. `start_valid=1` sostenido repite cuadros sin CPU. Una solicitud
presentada solo durante STREAM se ignora, sin quedar en cola. Reset descarta
el cuadro sin evento de éxito.

## Organización RTL

| Fuente en `src/` | Correspondencia con el diseño |
|---|---|
| `dsi_test_pattern.v` | Top estructural, parámetros y conexión UC/datapath |
| `test_pattern_control.v` | STATE[1], R_DONE[1], handshakes y eventos INIT/STEP/FINISH |
| `test_pattern_datapath.v` | Conexiones de R_X/R_Y/R_C, A0–A2, M0–M5, CX/CY/CC, C1–C7 y marcas |
| `test_pattern_register.v` | Registro con enable y reset síncrono prioritario |
| `test_pattern_add.v` | Incrementador del ancho de su registro |
| `test_pattern_compare.v` | Comparación de igualdad o umbral >= |
| `test_pattern_mux.v` | MUX combinacional parametrizable |
| `test_pattern_priority.v` | P0, mayor umbral alcanzado → índice de franja |

Los umbrales usan `i*(WIDTH/8)` constante, con el ancho de X. No hay divisor
variable, registro de color/byte/franja, contador de bytes, FIFO ni framebuffer.
No hay `next_state`, acciones registradas, reloj invertido ni CDC. La codificación
binaria de STATE se conserva con `fsm_encoding="none"`; no se promete detección
de fallos ni recuperación de X/Z o del código ilegal de componente.

## Verificación

```sh
pixi run --locked check-dsi-test-pattern-rtl
pixi run --locked test-dsi-test-pattern
pixi run --locked make -C dsi_test_pattern check-structure
```

También `make -C dsi_test_pattern check test check-structure` con las
herramientas en PATH. Productos en `build/dsi_test_pattern/`; los ejecutables
se recompilan siempre para evitar mezclar versiones de Icarus/VVP.

Cobertura, resultados y límites en [verificación RTL](docs/verificacion.md).
El arnés integrado presenta un descriptor por línea al preparador largo real;
comprueba payload, cabecera, ECC y CRC bajo pausas. Es código de testbench:
la planificación de vídeo no se incorpora al RTL del generador.

`tx_line_last` identifica fin de payload. No se conecta a
`dsi_long_packet_tx.tx_byte_last`, que es una salida y marca el CRC alto.
`frame_done` significa entrega local del payload; puede preceder al fin del
último paquete y no confirma transmisión física ni recepción del LCD.

La capacidad de un byte por ciclo de la fuente no cambia la tasa del
preparador existente. Quedan pendientes el planificador de vídeo, integración
con transporte/PHY/LiteX y temporización física para el panel.
