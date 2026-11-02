# Fuentes del secuenciador

[Función e interfaz](../README.md)

| Archivo | Función |
|---|---|
| `secuenciador_init.v` | Top: conecta FSM, ROM, registros, contador y comparadores |
| `secuenciador_control.v` | FSM de 15 estados: arranque, handshake, esperas y fallo enclavado |
| `rom_descriptores.v` | 11 descriptores: base [7], longitud [4], espera [23] |
| `rom_paquetes.v` | 75 bytes DSI con ECC/CRC precalculados; sin selector LPDT |
| `validador_descriptor.v` | Comprueba paso, longitud no nula y fin de paquete dentro de ROM |

Reutiliza `count.v`, `reg_0.v`, `mux.v` y `comp.v` de `motor_lpdt/src/`.
El top **no instancia el motor ni los drivers físicos**. Conectar un motor de
ancho 4; `rst_motor` debe llegar a su reset y `pos` a la ROM combinacional.
FSM en posedge; registros y contadores en negedge. Preservar los 12,5 ns
de medio ciclo, especialmente `pos → suma → ROM → byte_actual` del motor.

Desde la raíz: `pixi run make -C secuenciador_init test-all`.
