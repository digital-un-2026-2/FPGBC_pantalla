# Revisión del firmware V1.4 250217

Análisis estático realizado el 2026-11-10. Se extrajo el RAR y se comparó el
binario con el repositorio indicado por el usuario. No se ejecutó ni se cargó
firmware en la consola. No se recuperó todavía la lógica de pantalla.

## Archivo identificado

`V1.4 250217.rar` contiene:

| Archivo | Tamaño |
|---|---:|
| `update.bin` | 907 930 bytes |
| `v1.4 250217.txt` | 317 bytes |

El RAR descargado no se versiona. Para reproducir el análisis, obtener
`update.bin` de la referencia enlazada abajo, comprobar su SHA-256 y colocarlo
en `build/reverse_v1_4/original/` (o indicar su ruta mediante `--input`).

SHA-256 de `update.bin`:

```text
655de4c5f3c4d0f8866069e710ce9e07c3409829b8940b3fd4d359ce9efece46
```

Coincide byte por byte con
[`HWv1_1/2025.02.17/update.bin`](https://github.com/makhowastaken/GWGBC_FW/blob/main/HWv1_1/2025.02.17/update.bin).
La referencia se descargó del árbol Git
`6868254f2744a6b40f59cf7b21ed1d8e41608846`; también se verificaron los hashes
de objeto Git de los archivos descargados.

Las notas incluidas anuncian correcciones para los cartuchos originales de
Pokémon, estabilidad de EZ y cambios de logo/tiempo de arranque. El
[README de HWv1_1](https://github.com/makhowastaken/GWGBC_FW/tree/main/HWv1_1)
identifica esta publicación como versión 1.14 en el menú. El nombre V1.4 del
paquete no establece una revisión de hardware.

## Formato observado

- Los primeros ocho bytes son ASCII `19450815`. Su significado no se ha
  establecido; no se interpretan como clave ni fecha de compilación.
- La entropía del resto es aproximadamente 7,999824 bits por byte. Las
  ventanas de 64 KiB también presentan entropía alta y uniforme.
- No aparece la secuencia completa de identificación Gowin GW2A-18
  `06 00 00 00 00 00 08 1b`, presente en el bitstream local de referencia.
  Tampoco apareció al invertir todos los bits, invertir su orden dentro de
  cada byte o comprobar una máscara XOR constante de un byte.
- No se encontró la firma ELF. Esto no excluye código de procesador dentro
  del contenido cifrado ni identifica la arquitectura de ese contenido.

La entropía por sí sola no demuestra cifrado ni distingue cifrado de
compresión. Como evidencia independiente, el
[README del repositorio](https://github.com/makhowastaken/GWGBC_FW#readme)
declara que sus firmwares están precompilados y cifrados y que Makho no tiene
el código fuente. El inventario del árbol no incluye una herramienta de
descifrado ni fuentes HDL para reconstruir el diseño.

## Comparación con la variante de otro logo

[`patched_fw/update.bin`](https://github.com/makhowastaken/GWGBC_FW/blob/main/HWv1_1/2025.02.17/patched_fw/update.bin)
tiene también 907 930 bytes. Comparte los primeros ocho bytes, pero difiere
en 904 272 posiciones a partir del offset 8, aproximadamente el 99,6 % del
resto del archivo. Su SHA-256 es:

```text
99e6402394e7860b572cda0fa5e8bfab045c91202e0c88b1874be1bb341a27dc
```

No se puede localizar un parche de logo pequeño mediante esta comparación
directa. La diferencia es compatible con cifrado, pero no identifica el
algoritmo, el modo, la clave, un IV ni qué cambios existen tras descifrar.
La existencia de esta variante no demuestra que Makho descifrara el archivo.

## Alcance de REA y trabajo restante

REA no está instalado ni conectado en esta sesión. No se ejecutaron REA,
Binwalk o Ghidra. Según la
[guía oficial de firmware de REA](https://github.com/morluto/rea/blob/main/docs/guides/firmware/firmware-analysis.md),
su flujo utiliza Binwalk/Unblob para identificar y extraer regiones y deriva
ejecutables compatibles al análisis nativo. Eso no proporciona por sí mismo
la clave de este contenedor ni reconstruye una configuración FPGA cifrada.

Para revisar la implementación interna falta obtener contenido decodificado:

1. Investigar el formato de actualización y el componente que lo procesa.
   Haría falta identificar el MCU/bootloader y determinar dónde se descifra;
   no se ha demostrado que sea en la FPGA o en el MCU.
2. Obtener, si las interfaces y protecciones del equipo lo permiten, una
   copia de la configuración sin cifrar o una captura del enlace de carga.
   Una lectura de flash no garantiza encontrar contenido sin cifrar.
3. Si se obtiene un bitstream Gowin compatible, probar el desempaquetado con
   Apicula para recuperar primitivas, conexiones y memorias. La recuperación
   puede ser parcial y no equivale al HDL original.

Para el objetivo concreto de pantalla hay otra vía: capturar el tráfico DSI
del firmware original desde el arranque. Los comandos LP y el vídeo HS
requieren instrumentación adecuada a sus velocidades y niveles. Eso puede
revelar inicialización y temporizaciones sin reconstruir toda la consola.
El control eléctrico de retroiluminación puede requerir una medición aparte.

## Evidencia local

- `build/reverse_v1_4/original/`: archivos extraídos del RAR.
- `build/reverse_v1_4/reference/`: documentos y binarios de referencia.
- `build/reverse_v1_4/reference/tree.json`: inventario remoto completo.
- `build/reverse_v1_4/reference/inventory.json`: procedencia, hashes y comparación.
- `build/reverse_v1_4/analysis.json`: estadísticas del archivo local.

Los archivos de `build/` son artefactos locales y pueden estar excluidos de Git.

## Intento adicional y acceso al microcontrolador

Se descargaron 26 binarios del mismo árbol Git y se verificaron sus hashes.
Son 25 contenidos distintos: `HWv1_0/0823` y `HWv1_0/082301` son idénticos.
Todos tienen 907 930 bytes y la misma cabecera de ocho bytes. Los 300 pares
de contenidos distintos tienen entropía XOR alta; no apareció un patrón que
permitiera recuperar un flujo XOR reutilizado. Tampoco hay bloques repetidos
de 16 bytes alineados desde el offset 8 dentro de cada archivo.

Se creó y ejecutó `scripts/probe_fpgbc_firmware.py`, con estos resultados:

| Prueba | Resultado |
|---|---|
| CRC16 de ocho variantes, sumas y partes bajas de CRC32/Adler32 sobre rangos desde 0, 8 y 24 hasta los dos bytes finales | Ninguna coincidencia para V1.4; los dos bytes finales podrían no ser un checksum sin cifrar |
| zlib, gzip, DEFLATE sin cabecera, XZ, LZMA y bzip2 en offsets 0–64 | Ningún flujo completo que produzca al menos 4096 bytes; salida limitada a 1 MiB |
| Coincidencias de bytes a retardos de 1 a 4096 | Sin evidencia fuerte de una máscara XOR periódica corta |
| 122 claves candidatas para AES, seis modos, cuatro disposiciones de bytes y seis offsets | Ninguna cabecera de identificación GW2A-18 en los prefijos de 512 bytes examinados |
| RC4 con las claves candidatas y el texto de la cabecera, con cuatro descartes iniciales | Ninguna cabecera GW2A-18 en los prefijos examinados |

En total se examinaron 64 440 combinaciones de cifrado con claves candidatas,
sin recuperar texto claro verificado. **No es una búsqueda exhaustiva y no
descarta AES, RC4 ni otros cifrados con claves o formatos diferentes.** La
alineación `8 + 907920 + 2` permite plantear un cuerpo múltiplo de 16 bytes,
pero no demuestra que esos sean los límites reales del contenedor.

Las funciones CRC se contrastaron con valores de comprobación conocidos y
la implementación RC4 con un vector de [RFC 6229](https://www.rfc-editor.org/rfc/rfc6229).
Resultados detallados en `build/reverse_v1_4/probes/report.json`.

En la [fotografía de la placa v1.1 del repositorio](https://github.com/makhowastaken/GWGBC_FW/blob/main/media/v1.1_Front.jpg)
se lee **WCH CH32V203C8T6**. El recorte local está en
`build/reverse_v1_4/mcu_marking.png`. Es la identificación de la placa de
referencia; falta confirmar el marcado y cableado de la placa del usuario.
El MCU es candidato para procesar la actualización, pero no se ha demostrado
que contenga la rutina de descifrado.

El usuario dispone de WCH-Link/WCH-LinkE. La siguiente prueba será identificar
el chip y su estado de protección, y leer su firmware si está accesible.
La herramienta [wlink](https://github.com/ch32-rs/wlink) permite consultar
estado y volcar memoria. Su código separa `dump` de `flash`/`unprotect`;
no se ejecutó ninguna de esas operaciones ni se instaló aún la herramienta.
La conexión de depuración corresponde a PA13 (datos), PA14 (reloj) y GND,
según su [tabla de conexiones](https://github.com/ch32-rs/wlink/blob/main/docs/references.md#swd-pin-matrix).
Los pads físicos de esta consola deben comprobarse antes de conectar.

No se debe intentar quitar la protección de lectura para obtener la copia:
esa operación puede borrar el firmware y las opciones que se intentan
preservar. No se ha comprobado todavía si esta consola tiene esa protección.
