# Plataforma FPGBC

[Gateware](../README.md) · [Hardware y seguridad](../../docs/hardware.md)

`fpgbc.py` describe **dónde** se implementa el circuito: FPGA Gowin
`GW2AR-LV18EQ144PC8/I7`, reloj de 40 MHz, botón de reset y doce pads DSI.
Se usa la cadena
de herramientas abierta Apycula (`apicula` en la API de LiteX).

| Recurso | Pin de FPGA | Configuración del target |
|---|---|---|
| `clk40` | 11 | Entrada de reloj, periodo 25 ns |
| `global_rst_n` | 120 | Reset global activo bajo, con pull-up |
| `dsi_lp.p` / `dsi_lp.n` | 122/124/126 y 123/125/128 | TBUF, LVCMOS12, sin pulls |
| `dsi_hs.p` / `dsi_hs.n` | 117/115/113 y 116/114/112 | IOBUF, LVCMOS25, salida deshabilitada |

La referencia y el pinout están confirmados por el responsable. El código declara
`LVCMOS33` solo para reloj y reset; esa configuración no se aplica a las líneas DSI.
El mapa eléctrico completo y sus precauciones viven en `docs/hardware.md`.

La instancia `gateware.targets.fpgbc_lp_init`. El recurso UART se conserva
como referencia en el platform, pero este target no lo solicita ni lo utiliza.
Revisar el tratamiento de los doce pines DSI y los no utilizados antes
de implementar o programar un diseño.
