# dphy_hs_tx

**RTL implementado desde flujo, datapath y FSM.** Top estructural, transiciones
de UC en `posedge`, salidas combinacionales en `always @(*)` y registros de
DATAPATH también en `posedge`. No hay next_state, ACTION ni lógica en negedge.

Secuenciador lógico HS con perfil sintético **S320**: reloj de bytes/control de
40 MHz, palabras de dos bytes y serialización ideal de 320 Mb/s por lane en
el testbench. El RTL produce FRAME y controles; el generador conductual de
bits/reloj vive solo en TB. No hay OSER8, PLL, E/S Gowin, CDC ni conexión al LCD.

El parámetro `BYTE_HZ=60000000` selecciona una segunda tabla de temporizadores
para 480 Mbit/s/lane, usada por el [target de imagen](../docs/imagen_en_pantalla.md).
El valor por defecto sigue siendo 40 MHz. Las primitivas y los pines los añade
el wrapper Gowin; las pruebas del target de imagen cubren la tabla de 60 MHz.

## Contrato implementado

Un reloj y reset síncrono activo alto. Reset y phy_abort enmascaran ACK,
movimientos de palabras y habilitaciones HS combinacionalmente. El reset
coordinado de la cadena cubre ambos flancos del árbitro existente.

Entrada `hs_word_{data[15:0],keep[1:0],valid,last}`: una palabra por posedge
válido durante la ventana RX, sin ready. Cada palabra tiene byte bajo para
D0 y alto para D1. Solo se admite keep=11; una lane parcial falla antes de
serializar esa palabra, aunque ya se haya transmitido un prefijo. No se agrega
relleno ni se declara éxito tras aborto.

PENDING conserva una palabra durante Sync y ACTIVE la palabra que se emite.
Se publica una trama B8B8 durante un ciclo y después payload continuo. El
modelo serial de TB aplica LSB primero y Trail complementario al último bit
por lane. Las hipótesis normativas y la espera adicional en HS-Zero siguen
identificadas en el [contrato temporal](docs/contrato_temporal.md).

Al aceptar last se cierra RX; la retirada normal de grant no invalida los bits
pendientes. La última palabra se drena, seguida de Trail/Exit. POST corre en
paralelo con Exit de datos. Solo el árbitro genera hs_complete tras el retorno
conjunto. Ninguno de estos eventos confirma recepción del panel.

## Puertos

| Grupo | Señales |
|---|---|
| Reloj y recuperación | clk, rst, phy_abort |
| Órdenes del árbitro | clk_start_req, data_start_req, data_stop_req, clk_stop_req |
| Confirmaciones | clk_prepared, data_prepared, data_stopped, clk_stopped |
| Entrada de transporte | hs_grant; hs_word_data[15:0], hs_word_keep[1:0], hs_word_valid, hs_word_last |
| Trama lógica | hs_frame_data[15:0], hs_frame_kind[1:0]: 0 Zero, 1 Sync, 2 payload, 3 Trail |
| Señalización del modelo | hs_data_on, hs_clk_on, clk_toggle; lp_clk/lp_d0/lp_d1[1:0], orden P/N |
| Diagnóstico | hs_local_stop, phy_error, error_code[2:0] |

FRAME/kind solo tienen significado serial cuando hs_data_on=1. hs_clk_on
habilita HS y clk_toggle la oscilación; durante CLK-Zero/Trail se emite HS-0.
Estas señales no son habilitaciones eléctricas aprobadas de pads.

CAUSE conserva la primera causa: 0 ninguna/aborto externo, 1 máscara,
2 underflow, 3 protocolo, 4 pipeline, 5 estado inválido, 6 selector inválido,
7 reservado. phy_error depende exclusivamente de esa memoria; no de
phy_abort combinacional. Tras aborto, HALTED puede confirmar reposo aun con
phy_abort alto. Solo reset recupera la PHY; clear_error del árbitro no basta.

## Composición con el enlace

La integración de TB conecta phy_error OR hs_error del transporte al árbitro.
Compone stop_ready como `hs_local_stop && !lp_grant && (lp_D0==2'b11)`.
No usa busy del puente LP: ese busy incluye la espera de permiso y provocaría
un bloqueo circular. lp_grant cubre la transacción del motor hasta lp_done,
que llega tras volver a LP-11. Para abortos que alcancen también LP se exige
reset coordinado del motor, puente y productor; este núcleo no los resetea.

La corrección de stop_ready sustituye la propuesta documental anterior con
!lp_busy. La prueba compite con LP real en ambos órdenes y comprueba la
exclusión. Las confirmaciones complete se observan tras el negedge que las
publica, antes de que pueda aceptarse un nuevo dueño en el siguiente posedge.

## Diseño y fuentes

- [Especificación inicial](docs/especificacion.md), [flujo](docs/flujo.md) y [cronograma](docs/contrato_temporal.md).
- [Datapath](docs/datapath.md): 52 bits; [PDF](docs/DATAPATH.pdf).
- [FSM](docs/fsm.md): 25 estados y ocho bits de UC; [PDF](docs/FSM.pdf).
- [Editable único de siete páginas](docs/DPHY_HS_TX.drawio).
- [Plan de verificación](docs/verificacion.md).

La autorización para implementar RTL corresponde a la instrucción del usuario
«Realiza el rtl» del 2026-11-08. El perfil de pruebas no constituye elección
para el panel. Fuentes externas y límites permanecen en los documentos.

| Fuente RTL | Bloques del diseño |
|---|---|
| src/dphy_hs_tx.v | Top estructural UC/datapath |
| src/hs_phy_control.v | STATE[5], CAUSE[3], transiciones, prioridades y controles |
| src/hs_phy_datapath.v | PENDING/ACTIVE, M0–M3, Σ0/Σ1, C0/C1 y condiciones |
| src/hs_phy_register.v | Registro parametrizable con enable |
| src/hs_phy_mux.v | Selector parametrizable |
| src/hs_phy_sub.v | Decremento parametrizable |
| src/hs_phy_zero.v | Comparación con cero |

La UC valida el selector **nominal** antes de sustituirlo por Exit ante fallo;
realimentar TIME_SEL_OK del selector ya sustituido crearía dependencia circular.
El indicador del datapath se conserva como diagnóstico interno. La validación
nominal y la primera causa se comprueban con inyección de fallos en la UC.

## Comprobaciones reproducibles

```sh
pixi run --locked check-rtl
pixi run --locked test-dphy-hs
pixi run --locked make -C dphy_hs_tx waves
```

Productos en `build/dphy_hs_tx/`. Las simulaciones siempre se recompilan.

| Comprobación ejecutada, 2026-11-08 | Resultado |
|---|---|
| Elaboración Icarus del núcleo y check-rtl del proyecto | PASS |
| Comparación por puertos públicos con especificación previa | PASS: 257 586 ciclos; recorridos, reset/aborto por estado y fallos |
| Matriz UC | PASS: 4096 combinaciones reproducibles, 32 códigos y selector corrupto durante carga |
| Cadena con preparadores, packer, transporte, árbitro y LPDT reales | PASS: siete paquetes HS reconstruidos desde bits y siete paquetes LPDT decodificados de D0; WC=0/2/18/2160/4090 y cortos |
| Fallos de enlace | PASS: pérdida de PLL en cinco fases, lane parcial y recuperación por reset coordinado |
| Yosys proc/flatten/check | PASS: 60 bits FF, posedge, sin latches/RAM ni reset asíncrono |
| Regresiones de preparadores, packer, transporte, puente y árbitro | PASS: 65 815 cortos, 311 largos, 54 paquetes del packer y todas las pruebas de enlace/control existentes |
| Ondas de integración | PASS: build/dphy_hs_tx/link.vcd |

Los modelos de referencia ejecutables comprueban coherencia con los documentos;
la integración serial tiene un monitor independiente que busca Sync y compara
bytes con los aceptados a la entrada del packer. El monitor de reloj comprueba
cadencia, Trail y POST. Los algoritmos ECC/CRC se verifican en sus preparadores.
Las referencias jerárquicas solo inyectan fallos o seleccionan su instante;
los resultados funcionales se contrastan por puertos públicos.

El núcleo aislado elabora sin avisos. La integración conserva los avisos de
timescale heredado de las fuentes LPDT existentes. No se han ejecutado P&R,
STA, programación FPGA ni mediciones eléctricas. El bitrate del panel, su
variante, lane parcial física y wrapper Gowin continúan pendientes.

Para retirar el bloque: eliminar este directorio, sus tareas Pixi y enlaces;
no se cambian las interfaces RTL existentes de los demás núcleos.
