# Plataforma FPGBC

[Gateware](../README.md) · [Hardware y seguridad](../../docs/hardware.md)

`fpgbc.py` describe **dónde** se implementa el circuito: FPGA Gowin
`GW2AR-LV18EQ144PC8/I7`, reloj de 40 MHz y UART de depuración. Se usa la cadena
de herramientas abierta Apycula (`apicula` en la API de LiteX).

| Recurso | Pin de FPGA | Configuración del target |
|---|---|---|
| `clk40` | 11 | Entrada de reloj, periodo 25 ns |
| `serial.rx` | 28 | Recepción UART en la FPGA |
| `serial.tx` | 27 | Transmisión UART desde la FPGA |

La referencia y el pinout están confirmados por el responsable. El código declara
`LVCMOS33` para esos recursos; esa configuración no se aplica a las líneas DSI.
El mapa eléctrico completo y sus precauciones viven en `docs/hardware.md`.

No tiene un comando independiente ni un target que la instancie en esta rama.
Se conserva como referencia para la futura integración autónoma LP.
Revisar el tratamiento de los doce pines DSI y los no utilizados antes
de implementar o programar un diseño.
