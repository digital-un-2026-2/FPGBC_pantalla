# Verificación RTL de dsi_test_pattern

El RTL conserva la interfaz, ecuaciones y cronograma del [flujo](flujo.md),
[datapath](datapath.md) y [FSM](fsm.md). Los scripts documentales siguen
comprobando sus modelos y conexiones; no sustituyen las pruebas RTL.

## Pruebas reproducibles

Desde la raíz, con el entorno bloqueado de Pixi:

```sh
pixi run --locked check-rtl
pixi run --locked test-dsi-test-pattern
pixi run --locked make -C dsi_test_pattern check-structure
```

El Makefile permite ejecutar por separado `test-unit`, `test-control`,
`test-link`, `check-parameters` y `check-structure`. Solo `test-control`
inyecta memoria interna, para recorrer exhaustivamente la tabla de UC.
Los demás monitores comparan los puertos públicos.

| Prueba | Cobertura |
|---|---|
| `dsi_test_pattern_TB.v` | 8×1, 16×2, 24×3 y 720×720; RGB, fronteras, bytes y marcas por índice lineal |
| Primer cuadro de cada perfil | ready siempre alto; valid continuo, sin ciclos de preparación entre bytes |
| Segundo cuadro de cada perfil | ready pseudoaleatorio reproducible, pausas dirigidas en R/G/B y tres ciclos en cada fin de línea/cuadro |
| Perfiles pequeños | Seis abortos por reset: primer R/G/B, último B de línea, último G y último B de cuadro; reinicio y solicitud ignorada durante STREAM |
| `test_pattern_control_TB.v` | 256 combinaciones de STATE, R_DONE, reset, inicio, ready y tres comparadores; controles y transición en el mismo flanco |
| `test_pattern_link_TB.v` | Dos cuadros 720×2, descriptor RGB888 por línea (VC=2, DT=3E, WC=2160), pausas entre líneas y a la salida del preparador |
| `check_parameters.py` | Cuatro perfiles válidos y seis inválidos en elaboración Icarus y jerarquía Yosys |
| `check_structure.py` | Netlist genérica optimizada 720×720: bits, bancos, reloj, polaridad, ausencia de latches/RAM/divisor/reset asíncrono |

El monitor de la fuente comprueba cada byte ofrecido contra una paleta
independiente por posición lineal. Solo avanza su referencia al aceptar el
byte. Comprueba marcas aunque ready=0, salida nula en reposo/reset, pulso de
fin, ocupación tras el flanco y retención en negedge. Al afirmar reset entre
flancos, exige anulación inmediata de handshakes/datos/marcas y conservación
de busy/frame_done hasta el posedge.

El arnés de paquetes comprueba también bytes de cabecera, ECC mediante
columnas de síndrome y CRC con polinomio MSB 1021 y reflexión de resultado.
Contrasta payload con la referencia de franjas, sin reutilizar los operadores
ECC/CRC del preparador como oráculo. Comprueba WC, fin de payload, fin de
paquete y estabilidad con backpressure.

Perfiles inválidos: (WIDTH, HEIGHT) = (0,1), (7,1), (9,1), (-8,1), (8,0),
(8,-1). Se exige fallo debido a la rama de configuración inválida del top,
sin ejecutar VVP.

## Resultado local, 2026-11-09

| Comprobación | Resultado |
|---|---|
| Elaboración global `check-rtl` | PASS, incluido el generador |
| Fuente 8×1, 16×2 y 24×3 | PASS: tres cuadros completos y seis abortos por perfil |
| Fuente 720×720 | PASS: dos cuadros completos, 3.110.400 bytes aceptados y 1.440 finales de línea |
| Matriz UC | PASS: 256 combinaciones |
| Enlace con preparador largo real | PASS: cuatro paquetes, 8.640 bytes de payload, cabeceras/ECC/CRC exactos |
| Parámetros | PASS: cuatro perfiles válidos y seis rechazos en ambas herramientas |
| Yosys `proc; flatten; opt; check -assert` | PASS: 24 bits en cinco bancos posedge, sin latches, RAM, reset asíncrono ni divisor |

El desglose es X[10] + Y[10] + C[2] + STATE[1] + R_DONE[1]. No se añade
memoria de imagen ni fase de fin. La comprobación Yosys es genérica, anterior
al mapeo de FPGA: no acredita uso final de LUT, cierre de timing ni recepción
del panel. Los testbenches usan reloj de 40 MHz y no modelan la señal eléctrica.

Quedan fuera la inicialización del LCD, eventos/blanking/ritmo DSI, planificación
RTL de descriptores y la integración con el resto del transporte físico.
