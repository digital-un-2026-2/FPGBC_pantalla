# Depuración interna del motor LPDT

[Inicio](../README.md) · [Arquitectura y glosario](arquitectura.md) · [Comandos paso a paso](flujo_de_trabajo.md)

## Qué hace esta integración

El target `gateware/targets/debug.py` integra UARTWishbone, el wrapper del
motor Verilog, un supervisor CSR y LiteScope. Añade el banco auxiliar `debug_regs`.
**No conecta `estado_D0` a pines ni implementa drivers, CLK/D1 o D-PHY.**
El permiso del motor está fijado a uno exclusivamente para esta prueba lógica.
No usar esa condición como autorización eléctrica para transmitir al panel.

En palabras simples: el PC escribe un paquete en registros de la FPGA, pide
su envío y descarga una captura de cómo lo procesó el motor. Un wrapper adapta
la interfaz Verilog a Migen; no es otro motor. El supervisor organiza la petición
y conserva una copia privada de los datos. Los CSR son registros de control y
estado, accesibles por el bus interno Wishbone a través de la UART.

```text
PC → litex_server → UARTWishbone → CSR → supervisor → motor Verilog
                                                       │
PC ← captura de LiteScope ← señales internas del motor ──┘
```

No hay CPU en este `SoCMini`. El supervisor de diagnóstico tampoco es el
supervisor futuro del panel: no controla sus drivers, CLK/D1 o esperas DCS.
Para instalación, build, programación y capturas seguir el
[flujo de trabajo](flujo_de_trabajo.md), sin saltarse la revisión de hardware.

## Registros del banco `lpdt`

Consultar las direcciones reales en el `build/debug/csr.csv` generado.

| Nombre en el cliente | Acceso | Función |
|---|---|---|
| `lpdt_byte0` … `lpdt_byte6` | RW, 8 bits | Almacén de preparación, en orden de envío |
| `lpdt_longitud` | RW, 8 bits | Longitud válida 1–7; no incluye el selector `87` |
| `lpdt_iniciar` | RW, 1 bit | Cada escritura de 1 solicita un envío; 0 no hace nada |
| `lpdt_estado` | RO, 6 bits | Estado descrito abajo |
| `lpdt_finalizado` | RO, 1 bit | Finalización persistente; no es el pulso del motor |

Bits de `lpdt_estado`:

| Bit | Significado |
|---|---|
| 0 | Listo para admitir una orden |
| 1 | Supervisor o motor ocupado |
| 2 | Solicitud pendiente de aceptación por el motor |
| 3 | `ocupado` del motor |
| 4 | Última orden procesada rechazada |
| 5 | Longitud inválida en esa orden rechazada |

Una orden válida estando libre copia simultáneamente los siete bytes y la
longitud a registros privados. Esa copia no cambia hasta otro envío admitido;
el PC puede modificar el almacén de preparación sin alterar el envío actual.
No debe haber varios clientes escribiendo concurrentemente el paquete de
preparación: la copia no hace atómica una secuencia de escrituras del PC.

El supervisor mantiene `solicitud` hasta observar `aceptado` y después la retira.
Las órdenes durante ocupado se rechazan sin cola y sin abortar el envío.
Los indicadores de rechazo se actualizan con cada orden y se borran al admitir
una válida. `finalizado` se borra cuando el motor acepta un nuevo envío y se
activa al observar `terminado`; reset borra el estado y aborta sin finalización.
El software debe completar todas las escrituras del paquete antes de iniciar.

`finalizado=1` no confirma recepción ni ejecución del comando en un panel.
El motor no calcula ECC/CRC: los bytes deben formar el paquete completo cuando
se pretenda transmitir DSI. Los patrones de prueba arbitrarios no son comandos.

RW significa lectura/escritura; RO, solo lectura. ECC protege el encabezado DSI
y CRC los datos de paquetes largos. El script del PC calcula ECC para los tres
comandos DCS de su secuencia interna; el motor solo transporta bytes.

## Banco auxiliar `debug_regs`

| Nombre en el cliente | Uso |
|---|---|
| `debug_regs_entrada` | Registro de 32 bits escrito por el PC |
| `debug_regs_salida` | Devuelve entrada + 1, limitada a 32 bits |
| `debug_regs_contador` | Contador libre de ciclos; permite comprobar actividad del reloj |

Sirve para diagnosticar acceso a registros independientemente de un envío LPDT.
Consultar las direcciones generadas, no fijarlas manualmente en el cliente.

## LiteScope

Captura el control del supervisor, handshake, longitud activa, dirección,
byte suministrado y estado lógico D0. Profundidad: 2048 muestras a 40 MHz,
ventana nominal 51,2 µs sin subsampling. Los cambios de D0 en negedge se
observan en los posedge siguientes; no se mide su instante de transición.
No valida integridad eléctrica, D-PHY, CDC ni cierre de timing.

Un trigger es la condición que inicia la captura; el script usa `solicitud=1`.
El subsampling toma una de cada N muestras; esta prueba requiere N=1.
No hay RLE, compresión de repeticiones, en el analizador esperado por el script.
La ventana nominal no garantiza que toda su profundidad sea dato útil: la
verificación exige que la transacción quede completa dentro de la captura.

`csr.csv` describe los registros; `analyzer.csv` describe las señales del
analizador. Ambos deben corresponder al bitstream cargado. Los nombres de
señales para configurar triggers se obtienen del `analyzer.csv` generado,
no se presuponen a partir del nombre Python.

`scripts/test_lpdt_hw.py` fija los nombres esperados en `SIGNALS`. Si cambian
por la elaboración (conversión del diseño a hardware), comparar esos nombres
con el CSV real y adaptar el código; no basta con cambiar el nombre del archivo.
Bitstream, `csr.csv` y `analyzer.csv` deben proceder del mismo diseño generado.

## Generación y límites de verificación

Desde la raíz, `pixi run python -m gateware.targets.debug` genera archivos sin
síntesis. `--build` añade síntesis e implementación, no programación de FPGA.
El RTL usa posedge y negedge: revisar los caminos de medio ciclo a 40 MHz
(12,5 ns) en los informes nuevos, no reutilizar el resultado del target anterior.
Comprobar también los caminos combinacionales del almacén hacia el motor.

Hay exportadores y dos simulaciones en `gateware/sim/`: reset de arranque y
wrapper con una transacción. No se incluyen en `pixi run test`, que ejecuta
solo las cinco pruebas del RTL original. Tampoco cubren el supervisor CSR completo.

Durante la revisión documental se encontraron un bitstream, un informe de
implementación y capturas locales, incluido un resumen `PASS` de la secuencia
DCS interna. Esos archivos no identifican por sí solos la revisión exacta probada
ni certifican la recepción del panel. No se han vuelto a ejecutar esas pruebas
como parte de esta actualización documental.

Falta una prueba automatizada específica del supervisor para longitudes
inválidas, órdenes durante ocupado, cambios del almacén mientras transmite,
envíos consecutivos y reset. Una captura exitosa del recorrido normal no cubre
estos casos. El build observado permite fallos de timing con
`--timing-allow-fail`: revisar informes, no solo la existencia del bitstream.

Antes de programar siguen vigentes las precauciones de `hardware.md`, incluida
la configuración de los pines no utilizados y los bancos conectados al panel.
