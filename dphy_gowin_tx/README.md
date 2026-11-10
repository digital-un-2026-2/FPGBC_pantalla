# dphy_gowin_tx

Wrapper RTL de salida Gowin para el secuenciador `dphy_hs_tx` y la ruta LPDT.
Implementa el [DPHY_GOWIN_TX.drawio](docs/DPHY_GOWIN_TX.drawio) de nueve páginas,
con separación de UC/datapath y adaptadores de primitivas. Conserva las
interfaces y los flancos de los módulos anteriores. **El perfil físico sigue
sin caracterizar y PROFILE_OK=0 por defecto.** La [integración de pantalla](../dsi_display/README.md)
lo conecta al target LiteX `display` con pads internos y al testbench completo;
el target `debug` conserva su ruta LPDT de depuración.

- [Top RTL](src/dphy_gowin_tx.v), [puertos y parámetros](docs/interfaces.md).
- [Flujo](docs/flujo.md), [datapath](docs/datapath.md), [FSM](docs/fsm.md).
- [PDF completo](docs/DPHY_GOWIN_TX.pdf), [datapath](docs/DATAPATH.pdf), [FSM](docs/FSM.pdf).

El secuenciador conserva LPX/Prepare/Zero/Sync/payload/Trail/Exit/POST; el árbitro
conserva propiedad y pulsos complete. El wrapper captura continuamente, incluso
al retirar grant, con un retardo común L=2+J para datos, reloj, LP, OE y ACK.
No añade FIFO, contadores de fase, last/keep ni registros de ACK independientes.

| Fuente | Bloques del dibujo |
|---|---|
| src/dphy_gowin_tx.v | Top estructural y conexiones de UC/datapath/primitivas |
| src/gowin_tx_control.v | UC_SUP: STATE Gray[3], RUN_STARTED, ABORT_SEEN, CLOCK_FAULT |
| src/gowin_tx_datapath.v | R_FRAME, R_CTRL de L etapas, M0–M3, G0–G3 y C1–C4 |
| src/gowin_tx_register.v, gowin_tx_mux.v | Registro con LD/reset y MUX parametrizables |
| src/gowin_tx_safety.v | R_INHIBIT, RUN_B y disponibilidad de SER8 |
| src/gowin_tx_reset_sync.v, gowin_tx_sync.v | Reset por dominio y CDC de un bit |
| src/gowin_tx_pll.v | Adaptador candidato rPLL: PCLK, FCLK_D y FCLK_C |
| src/gowin_tx_ser8.v | Tres instancias OSER8, MAP_BITS y selección HWL |
| src/gowin_tx_pads.v | Seis TBUF LP y tres TLVDS_TBUF HS |

Memoria ordinaria: **16+18L bits**; con L=2 son 52. UC: seis bits.
Seguridad/reset/CDC: 21 bits. Los registros ordinarios usan posedge byte_clk;
no se resetea R_FRAME. Las excepciones asíncronas están aisladas en seguridad,
resets y captura de eventos. R_INHIBIT permite inhibir aunque se detenga FCLK.
La recuperación tras aborto o pérdida de LOCK exige reset coordinado.

Se corrigió una ecuación de la propuesta: `pll_ready` ya no depende
combinacionalmente de `phy_abort`, porque el árbitro real cerraba ese lazo.
SAFE mantiene la máscara inmediata de aborto en pads y ACK; INHIBIT/EV_RAW
retienen el bloqueo. [Explicación y diagnósticos](docs/datapath.md#corrección-de-la-revisión-rtl-retorno-de-disponibilidad).
Una pérdida de LOCK reinicia la cadena mediante rst_byte: el diagnóstico que
sobrevive es clock_fault del wrapper, aunque el árbitro pierda su causa previa.

## Comprobaciones reproducibles

```sh
pixi run --locked check-rtl
pixi run --locked test-dphy-gowin
```

También puede usarse `make -C dphy_gowin_tx test` con Icarus, Python y Yosys.
Productos en `build/dphy_gowin_tx/`. `GOWIN_LIB` permite cambiar la ruta de las
declaraciones de Yosys, por defecto `/usr/share/yosys/gowin`.

| Prueba ejecutada | Resultado |
|---|---|
| Elaboración con declaraciones Gowin instaladas | PASS |
| Unidad con J=0/L=2 y J=3/L=5 | PASS: 128 comandos consecutivos por perfil, bits D0/D1/CLK, LP y ACK alineados |
| Arranque, aborto breve, LOCK breve, relojes detenidos, aborto en RELEASE, STATE inválido, READY y reset | PASS en ambos perfiles |
| Cadena con preparadores, packer, transporte, secuenciador, árbitro y LPDT reales | PASS: siete HS y siete LPDT reconstruidos desde pads por perfil; WC=0/2/18/2160/4090 y cortos, ambas prioridades LP/HS |
| Fallos de cadena | PASS en ambos perfiles: PLL con relojes detenidos, aborto y reset en cinco fases HS; lane parcial; reset coordinado y nuevo paquete completo |
| Yosys proc/flatten/check y presupuesto de memoria | PASS: 52+6+21 bits, sin latches/RAM |
| Yosys SCC con wrapper, árbitro, secuenciador y transporte | PASS: cero lazos combinacionales |
| synth_gowin para GW2A | PASS: mapeo de lógica y primitivas; sin P&R/STA |

`TB/gowin_ideal_cells.v` es un modelo ideal del **contrato**, separado del RTL.
No modela latencia real, adquisición del PLL, restricciones de IOLOGIC ni
respuesta eléctrica. Los monitores seriales leen los pads del wrapper; no
sustituyen la salida por tramas retardadas en el testbench. La prueba histórica
`docs/verificar_contrato.py` sigue disponible como contraste del calendario;
`docs/verificar_fsm.py` comprueba la especificación y los códigos del editable.

## Perfil físico pendiente

Los adaptadores rPLL/OSER8/TLVDS_TBUF son candidatos parametrizables. Los valores
PLL por defecto solo expresan ratios nominales; PHASE="0000" no centra CLK.
MAP_BITS identidad y HWL="false" tampoco prueban un orden o latencia reales.
J describe latencia interna de la primitiva; no añade registros al datapath.
La igualdad L=2+J y SDIV=4 se comprueba antes de permitir el arranque.

Para activar PROFILE_OK debe caracterizarse el conjunto completo: divisores,
fases y distribución de reloj, latencia común hasta pads, orden de bits,
OE, bancos/encapsulado y estándares eléctricos. Faltan simulación del fabricante,
P&R, STA y medición. El modelo S320 no selecciona el bitrate del LCD.
El target `debug` y sus restricciones de pines permanecen sin modificar.
El nuevo target `display` no exporta pads al panel.

Regenerar el editable: `python dphy_gowin_tx/docs/generar_flujo.py`.
En Draw.io >=27.0.2 se usan índices de página 1–9 para exportar las vistas.
