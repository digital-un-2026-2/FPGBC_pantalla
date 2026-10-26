# LPDT: protocolo y vector inicial

[Inicio](../../README.md) · [Hardware](../../docs/hardware.md) · [Interfaz RTL](../README.md)

## Capas distintas

| Especificación | Responsabilidad |
|---|---|
| DCS | Significado de comandos: reset, sleep, display on, etc. |
| DSI | Paquetes de comandos, píxeles y eventos |
| D-PHY | Estados eléctricos, LP/HS y secuencias físicas |

Inicializar con DCS no implica vídeo en Command Mode. Video Mode transmite
vídeo con ventanas de línea/cuadro; Command Mode actualiza mediante comandos,
normalmente una memoria de imagen del panel. LP/HS son modos de señalización,
no modos de imagen. El modo final sigue pendiente.

## Transacción inicial

Convención: `lp[1] = P`, `lp[0] = N`. LP-11 es reposo; LP-10 y LP-01 son
Mark-1 y Mark-0 según contexto; LP-00 es Space. Son estados lógicos, no una
autorización para aplicar tensiones arbitrarias.

En esta etapa D0 transporta el comando, CLK/D1 permanecen en LP-11 y los drivers
HS no conducen. Esa preparación es externa al motor RTL actual.

```text
Reposo LP-11
Entrada a escape: 11 → 10 → 00 → 01 → 00
Selector LPDT:    87
Paquete DSI:      05 01 00 10
Salida:          último Space 00 → 10 → 11
Espera de ejecución del comando
```

Los bytes se transmiten **LSB primero**. `0x87` sale temporalmente como
`1 1 1 0 0 0 0 1`: no se debe cargar `0xE1`. El selector es D-PHY, no parte
del paquete DSI ni de su ECC. No se añade sincronización HS `0xB8`.

La codificación spaced one-hot representa cada bit con Mark seguido de Space:

```text
0 → 01 → 00
1 → 10 → 00
```

No hay bits UART de inicio/parada ni LP-11 entre bytes. El Mark-1 de salida
no es un bit adicional porque le sigue LP-11, no Space. LPDT se sincroniza
por sus transiciones y no necesita oscilación del par CLK.

## Paquete DSI de prueba

| Campo | Valor | Significado |
|---|---|---|
| Data ID | `05` | VC 0, escritura DCS corta sin parámetros |
| Data 0 | `01` | DCS Software Reset |
| Data 1 | `00` | No utilizado |
| ECC | `10` | ECC de `05 01 00` |

El paquete corto no lleva CRC. La secuencia codificada completa es
**`87 05 01 00 10`**. El motor recibe el paquete ya preparado: no calcula ECC.
`terminado` indica fin de transmisión, no recepción ni ejecución confirmadas.
Lecturas, BTA, ACK y errores retornados quedan pendientes; el panel no responde
espontáneamente a cualquier escritura.

## Tiempos de trabajo a 40 MHz

Son parámetros iniciales, **no certificación de conformidad**.

| Intervalo | Tiempo | Ciclos de 25 ns | Responsable actual |
|---|---:|---:|---|
| Cada paso de entrada tras el reposo | 100 ns | 4 | Motor |
| Mark de cada bit | 100 ns | 4 | Motor |
| Space de cada bit | 100 ns | 4 | Motor |
| Mark-1 de salida | 100 ns | 4 | Motor |
| Reposo inicial propuesto | 200 µs | 8000 | Supervisor pendiente |

Mark + Space = 200 ns por bit: **5 Mbit/s**, 1,6 µs por byte.
Para el vector inicial: entrada 0,4 µs + cinco bytes 8 µs + salida 0,1 µs =
**8,5 µs (340 ciclos)** desde abandonar LP-11 hasta volver a LP-11.

Los mínimos clásicos de referencia son T_LPX = 50 ns y T_INIT = 100 µs;
no bastan para validar pulsos, niveles, flancos o restricciones del receptor.
El reposo propuesto no sustituye la secuencia de alimentación del panel.
La espera posterior a Software Reset está pendiente y deberá ser configurable;
no confundirla con la de Exit Sleep.

Se usan contadores sobre 40 MHz, no relojes combinacionales derivados. El RTL
actual fija cuatro ciclos por fase; verificar permanencias reales evita errores
de un ciclo. La transmisión no incluye reposos ni retardos de ejecución DCS.

## Referencias

- [MIPI DSI](https://www.mipi.org/specifications/dsi) y [D-PHY](https://www.mipi.org/specifications/d-phy).
- [ST AN4860](https://www.st.com/resource/en/application_note/an4860-introduction-to-dsi-host-on-stm32-mcus-and-mpus-stmicroelectronics.pdf): introducción, escape y spaced one-hot.
- [AMD: LPDT](https://docs.amd.com/r/en-US/pg436-mipi-tx-phy/Low-Power-Data-Transmission).
- [NXP AN13573](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imx-graphics/507/1/AN13573(i.MX%208RT%20MIPI%20DSICSI-2).pdf).

Estas notas no sustituyen las especificaciones normativas aplicables.
