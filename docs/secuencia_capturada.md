# Secuencia LP objetivo

Fuente: `LP_MIPI_DSI.kvdat`, CH0=D0P, CH1=D0N.
SHA-256: `aeab1015857e9e58ebfc47017390ecb5971a0ecf97eae83107e868e28f0d8292`.
Adquisición: 100 MS/s; LPDT aproximadamente 5 Mbit/s.
Se verificaron 18 ECC y 16 CRC aplicables, todos correctos.

Los tiempos son relativos al inicio de captura, no a alimentación/RESET.
En Generic Long Write se muestra el payload; en DCS Short Write se muestra
el opcode y Data1 por separado. El selector `87` lo añade el motor.

| Paso | Inicio (ms) | DT | Payload / opcode | Data1 DCS | Espera posterior nominal |
|---:|---:|---|---|---|---:|
| 0 | 382,38212 | `29` | `B0 00` | — | 9 ms |
| 1 | 391,39751 | `29` | `E4 00 00 00 00 08` | — | 9 ms |
| 2 | 400,41930 | `29` | `D0 45 45 71` | — | 9 ms |
| 3 | 409,43788 | `09` | `00 00` | — | 9 ms |
| 4 | 418,45327 | `05` | `11` Sleep Out | `45` | 65 ms |
| 5 | 483,46217 | `29` | `D0 52 4A` | — | 9 ms |
| 6 | 492,47916 | `29` | `B9 02 00 76 00 BA BB BF CC E3 46 81 31` | — | 9 ms |
| 7 | 501,51215 | `29` | `BD FF FE FE FE FE FE FE 80 20 00 00` | — | 9 ms |
| 8 | 510,54354 | `29` | `BE FF 0F 00 18 04 04 00 5D` | — | 9 ms |
| 9 | 519,57012 | `29` | `B0 03` | — | 65 ms |
| 10 | 584,58543 | `09` | `00 00` | — | 9 ms |
| 11 | 593,60081 | `05` | `29` Display On | `03` | 9 ms |
| 12 | 602,60980 | `29` | `B0 00` | — | 9 ms |
| 13 | 611,62519 | `29` | `BE FF 0F 00 18 04 04 00 5D` | — | 9 ms |
| 14 | 620,65177 | `29` | `B7 18 00 18 18 0C 09 AC 09 5C 09 0C 09 00 10 00` | — | 9 ms |
| 15 | 629,68956 | `29` | `B8 F8 DA 6D FB FF FF 4F 1F 7F 9F BF DF FF` | — | 9 ms |
| 16 | 638,72415 | `29` | `BB 2F` | — | 9 ms |
| 17 | 647,73953 | `29` | `B0 03` | — | Sin siguiente paquete LP |

`DT=29` significa Generic Long Write, no Display On.
`DT=09` significa Null Packet. No convertirlos a comandos DCS.
Los DCS `DT=05` no tienen parámetros: Data1 se conserva como byte de
cabecera, junto con su ECC, no como parámetro adicional del opcode.

Ejemplos completos, sin selector:

```text
Paso 0:  29 02 00 00 B0 00 D6 CA
Paso 3:  09 02 00 15 00 00 B8 F0
Paso 4:  05 11 45 04
Paso 11: 05 29 03 1F
```

Las esperas reales ordinarias son aproximadamente 8,99978–8,99979 ms;
las largas, 64,99970 ms. La futura implementación debe declarar la tolerancia
del redondeo y del control a 40 MHz.

No añadir Software Reset, `6F 01`, escrituras de brillo ni ACK/BTA:
no forman parte de estos 18 paquetes. No corregir los valores privados para
hacerlos coincidir con otro driver.
