# dsi_hs_transport

**RTL implementado desde flujo, datapath y FSM.** Top estructural;
transiciones en `posedge`, salidas de UC en `always @(*)`, registros de
datapath en `posedge`. Sin `next_state` ni ACTION.

Transporte lógico de un paquete completo, entre `dsi_lane_packer` y un receptor
HS funcional. No serializa ni determina temporizaciones D-PHY.

## Contrato aprobado

Un único reloj (40 MHz en las pruebas), registros en posedge, reset síncrono
activo alto. Reset bloquea combinacionalmente entrada, petición y salida.
La entrada `tx_word_{data[15:0],keep[1:0],valid,last,ready}` conserva el contrato
del packer: captura con valid && ready. Cada paquete empieza en D0.
`keep=11` es válido; `keep=01` solo en la última palabra. El byte alto parcial
no se transmite. No se validan ECC, CRC ni tipos DSI.

`BUFFER_WORDS=2048` almacena hasta 4096 bytes completos. Debe ser positivo;
se admiten profundidad uno y valores no potencia de dos. Un paquete que llena
la última posición sin last falla inmediatamente: no se espera otra palabra.
Sin last ni buffer lleno se espera sin timeout. No hay aceptación simultánea
de paquetes ni almacenamiento del siguiente durante la operación activa.

El enlace usa `hs_req/hs_req_ready` para reservar una vez, `hs_data_ready`
desde la precarga hasta la última entrega, y espera `hs_grant`. El receptor
consume `hs_word_{data[15:0],keep[1:0],valid,last}` en cada posedge válido,
sin ready. La primera palabra se publica tras observar grant en posedge;
las siguientes aparecen sin burbujas. `hs_done` dura un ciclo después de
consumir la última. El transporte espera `hs_complete` antes de recibir otro
paquete. Ninguno de estos eventos confirma recepción del panel.

`busy` indica datos parciales, operación o fallo. `error` y `hs_error` son
persistentes; `error_code[1:0]`: 00 ninguno, 01 capacidad, 10 máscara, 11 aborto
PHY, pérdida de grant durante envío o estado no usado. La primera causa se conserva. El error
local se comunica al árbitro mediante hs_error, incluso durante preparación.
`phy_abort` invalida cualquier operación; durante reset no registra fallo.
La recuperación exige reset coordinado de productores, packer, transporte y
árbitro: no se intenta reconstruir el límite de un paquete descartado.

## Diseño y orden de desarrollo

Contrato → [flujo](docs/flujo.svg) → [datapath](docs/datapath.md) →
[FSM](docs/fsm.svg) → [plan de pruebas](docs/verificacion.md) → RTL.
Fuente de estas decisiones: plan aprobado en la conversación del proyecto,
2026-11-08, estado CONFIRMADO POR USUARIO para el diseño lógico;
implementación comprobada en simulación y síntesis genérica. No son reglas eléctricas.
Editable único: [DSI_HS_TRANSPORT.drawio](docs/DSI_HS_TRANSPORT.drawio),
con el flujo, dos páginas de datapath y dos páginas de FSM.
Vistas: [flujo PDF](docs/flujo.pdf), [almacenamiento](docs/datapath_almacenamiento.svg),
[contadores y condiciones](docs/datapath_control.svg), [datapath PDF](docs/DATAPATH.pdf),
[FSM: transiciones](docs/fsm.svg), [FSM: controles](docs/fsm_control.svg) y
[FSM PDF](docs/FSM.pdf).

Top estructural, control separado y datapath con RAM síncrona de 18 bits por
palabra (datos y máscara). El número de palabras determina last, por lo que
no se guarda last por entrada. Contadores con un bit extra para ocupación y
anchuras mínimas de uno. La RAM no tiene reset; los contadores invalidan datos.
No hay CDC, primitivas Gowin, pins, LiteX, SoT ni política eléctrica de lane
parcial. El ciclo lógico de consumo no fija un bitrate físico.

```sh
pixi run --locked check-dsi-hs-transport-rtl
pixi run --locked test-dsi-hs-transport
pixi run --locked make -C dsi_hs_transport check-structure
pixi run --locked make -C dsi_hs_transport waves
```

Productos en `build/dsi_hs_transport/`. Para retirar el módulo, eliminar su
directorio, tareas Pixi y enlaces; las interfaces existentes no cambian.

## Organización RTL

| Fuente en src/ | Correspondencia con los diagramas |
|---|---|
| dsi_hs_transport.v | Top: conexión de UC y datapath, alias de error y marca final |
| hs_transport_control.v | STATE[3], DONE[1], CAUSE[2]; transición secuencial y salidas combinacionales |
| hs_transport_datapath.v | Instancias de COUNT, INDEX, M0, Σ0–Σ2, C0–C2, RAM y lógica L0 |
| hs_transport_register.v | Registro con enable y reset síncrono prioritario |
| hs_transport_mux.v | Selector parametrizable M0 de dos entradas |
| hs_transport_add.v | Operador parametrizable de incremento/decremento |
| hs_transport_compare.v | Comparador parametrizable de igualdad/desigualdad |
| hs_transport_memory.v | RAM y registro Q de lectura, sin reset |

COUNT tiene A+1 bits e INDEX A; A=max(1,ceil(log2(BUFFER_WORDS))). Q es el
registro de lectura de RAM, sin etapa adicional. En el valor predeterminado
hay 36 905 bits lógicos de datapath y seis de UC. La netlist genérica integra
Q en el puerto de RAM y conserva 29 bits de flip-flops fuera de la memoria:
23 de contadores y seis de UC. No se ha medido la asignación física Gowin.

## Verificación realizada (2026-11-08)

| Comprobación | Resultado |
|---|---|
| check-rtl de todo el proyecto | PASS, incluido el transporte |
| Prueba unitaria | PASS para profundidades 1, 3 y 2048; cinco paquetes correctos por profundidad, capacidad exacta, parciales, pausas, máscaras incorrectas, exceso y recuperación |
| Reset/aborto de la cadena local | PASS en las siete fases, incluidas precarga, envío y espera de liberación |
| Matriz de UC | PASS: 16 384 combinaciones, ocho códigos, prioridades, primera causa, controles y captura en el mismo posedge |
| Integración | PASS: siete paquetes HS y siete LPDT decodificados de D0, cuatro latencias PHY, WC=0/1/17/2160/4090 y paquetes cortos |
| Yosys proc/check + netlist | PASS, sin latches; RAM 2048×18 síncrona, flancos positivos y ausencia de reset asíncrono |
| Regresión preparador corto | PASS: 65 815 completos, ocho abortos |
| Regresión preparador largo | PASS: 311 completos, 22 abortos |
| Regresión packer | PASS: 54 paquetes y 64 combinaciones de controles |
| Regresión puente LPDT | PASS: 26 paquetes, siete rechazos, siete abortos |
| Regresión árbitro | PASS: unitaria, integrada y entre flancos |
| Ondas de integración | VCD generado en build/dsi_hs_transport/link.vcd |

La prueba pública compara palabras aceptadas con palabras consumidas y verifica
continuidad por ciclo y pulso done. La integración reconstruye bytes desde D0/D1
y los compara con los bytes reales aceptados por el packer, incluidos ECC/CRC;
los algoritmos se comprueban en las regresiones de los preparadores. La matriz
de UC usa inyección de estado únicamente para cubrir todas las combinaciones,
incluido 111; los monitores de paquetes observan los puertos públicos.

Los errores y resets de la cadena de datos se comprueban en la prueba unitaria;
la integración con LPDT real comprueba operaciones correctas y competencia por
el enlace. La prueba no demuestra continuidad de un flujo de vídeo indefinido:
el buffer recibe un paquete, lo transmite y espera liberación antes del siguiente.

El Makefile recompila simulaciones en cada ejecución para evitar mezclar Icarus
del sistema y Pixi. El transporte aislado elabora sin avisos. La integración
conserva los avisos existentes de timescale heredado del motor LPDT.
No se han realizado P&R, STA, programación de FPGA ni medidas eléctricas.
