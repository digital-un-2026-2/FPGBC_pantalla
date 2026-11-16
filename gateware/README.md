# Integración física pendiente

Solo se conserva `platforms/` como referencia de dispositivo, reloj y UART.
No es un target de inicialización ni exporta los pads DSI.

Los antiguos cores y targets de depuración LiteX se retiraron de esta rama.
El top autónomo LP se implementará según
[la arquitectura](../docs/arquitectura.md) y el
[mapa físico](../docs/hardware.md).

No sintetizar ni programar bitstreams antiguos de `build/` como si
correspondieran a esta arquitectura.
