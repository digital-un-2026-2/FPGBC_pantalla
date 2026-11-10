# Arquitectura: de los píxeles a la pantalla

[Inicio](../README.md) · [Documentación](README.md) · [Flujo de trabajo](flujo_de_trabajo.md)

## 1. La idea general

La pantalla necesita dos cosas: **comandos para configurarse** e **imagen para
mostrar**. No basta con conectar píxeles a unos pines: hay que organizarlos en
paquetes, enviarlos en el orden correcto y producir las señales eléctricas
adecuadas.

Este es el recorrido **previsto**, no una lista de bloques ya terminados:

```text
IMAGEN
PPU → adaptador → buffers → preparación de paquetes DSI ──┐
                                                        ▼
                                                planificador
                                                        │
COMANDOS                                                │
Secuenciador autónomo / preparación de paquetes DSI ──────┘
                                                        │
                              ┌─────────────────────────┴──────────────┐
                              ▼                                        ▼
                    motor LPDT / baja potencia              transporte HS / alta velocidad
                              └─────────────────────────┬──────────────┘
                                                        ▼
                                        PHY: estados, drivers y señales
                                                        ▼
                                           red eléctrica de la FPGBC
                                                        ▼
                                                     pantalla
```

La PHY es la **capa física**. Incluye tanto reglas de señalización como los
drivers, circuitos que conducen los pines. El motor LPDT ya implementa parte
de esas reglas lógicas; el dibujo separa responsabilidades, no exige un módulo
independiente por cada caja.

## 2. Recorrido de una imagen

1. **PPU (unidad de procesamiento de imagen).** Produce píxeles y referencias
   de línea/cuadro. Una línea es una fila de píxeles; un cuadro es una imagen
   completa. Su interfaz concreta aún no está definida.
2. **Adaptador.** Acomoda el formato y el ritmo de la PPU al resto del diseño.
   Por ejemplo, convertiría colores al formato que se elija para la pantalla.
3. **Buffers.** Almacenan temporalmente datos. Una FIFO entrega los datos en
   el mismo orden en que entraron; un framebuffer almacena una imagen completa.
   Todavía no se ha elegido la estrategia. Un buffer absorbe pausas, pero no
   resuelve que la fuente sea permanentemente más rápida que el enlace.
4. **Preparación de paquetes DSI.** DSI significa Display Serial Interface:
   organiza píxeles, comandos y eventos en mensajes con encabezado y datos.
   Este bloque añadirá los campos de identificación y protección de errores.
5. **Planificador.** Decide qué paquete enviar y cuándo. Deberá coordinar
   imagen, comandos, tiempos de espera y disponibilidad del transporte.
6. **HS (High Speed, alta velocidad).** Es la vía prevista para imagen.
   Serializar significa convertir bytes en una secuencia de bits. Habrá que
   repartir los bytes entre las dos lanes o canales de datos, D0 y D1, y
   generar el reloj del enlace por CLK. No se reparten los colores por lane.
7. **PHY y red de la placa.** Producen las tensiones, transiciones y conexiones
   que recibe la pantalla. La solución eléctrica de la FPGBC combina ramas
   de baja potencia y de alta velocidad: [mapa y precauciones](hardware.md).

El generador de franjas RGB888, planificador, preparadores, transporte y wrapper
Gowin están unidos en la [integración de pantalla](../dsi_display/README.md),
con control CSR y pruebas hasta pads simulados. PPU, adaptación, buffers de imagen,
calendario definitivo del panel y caracterización física HS siguen pendientes.
El [target autónomo de imagen](imagen_en_pantalla.md) ensaya un perfil de
720×720 a 60 Hz y 480 Mbit/s por canal. Estos valores están implementados
para la prueba; todavía no se ha conseguido imagen en la pantalla física.

## 3. Recorrido de un comando por LPDT

DCS (Display Command Set) define el significado de comandos como reset,
salir de reposo o encender la imagen. DSI los empaqueta. D-PHY define cómo
señalizarlos eléctricamente. Son capas distintas.

LPDT significa Low-Power Data Transmission: envío de datos mediante estados
de baja potencia. En este proyecto es la primera vía de transporte desarrollada.
**No es una UART** y no necesita que el par CLK oscile para enviar sus bits.

Ejemplo: un Software Reset se prepara como `05 01 00 10`:

1. El software del PC prepara el paquete completo, incluido ECC/CRC
   cuando corresponda.
2. Un supervisor conserva una copia estable y pide al motor que lo envíe.
3. El motor espera permiso, acepta la petición y añade el selector LPDT `87`.
4. Codifica cada bit en los estados lógicos del par D0, en orden LSB primero
   (primero el bit de menor peso del byte).
5. Regresa al reposo LP-11 y emite `terminado`.
6. El software respeta las esperas antes del siguiente comando.
   `terminado` **no confirma que el panel lo recibió**.

Los estados LP-00, LP-01, LP-10 y LP-11 nombran los valores lógicos de los
conductores P y N. No son valores de tensión ni autorizan usar 3,3 V.
El núcleo está en [dphy_lpdt_tx.v](../dphy_lpdt_tx/src/dphy_lpdt_tx.v).

También existe una ruta de prueba RTL independiente del PC:
`dsi_lp_packet_tx → dsi_lpdt_bridge → dphy_lpdt_tx → estado_D0`.
El [puente de prueba](../dsi_lpdt_bridge/README.md) almacena los cuatro bytes
del paquete corto y espera el fin del motor. Esta ruta se verifica en
simulación y se integra en el target LiteX `display`; el target `debug`
conserva su supervisor LPDT de depuración.

El [controlador de modos](../dphy_mode_ctrl/README.md) añade arbitraje entre
esa ruta LPDT y la cadena HS. Prepara reloj antes de datos y
detiene datos antes de reloj mediante confirmaciones de un modelo de PHY.
Los bits y controles de pads los proporcionan el secuenciador HS y el wrapper,
ahora conectados en `dsi_display`; la validación eléctrica sigue pendiente.

El [secuenciador HS](../dphy_hs_tx/README.md) ejecuta esas órdenes con el perfil
sintético S320. Su RTL entrega tramas de 16 bits y controles de fases; el
testbench genera la serialización ideal y reconstruye los bytes de D0/D1.
La integración con preparadores, packer, transporte, árbitro y motor LPDT
reales se comprueba en simulación. No incluye OSER8, PLL ni pads Gowin;
solo completa paquetes pares y rechaza lane parcial con fallo persistente.

LP y HS son modos de señalización, no modos de imagen. Video Mode envía un
flujo de vídeo con tiempos de línea/cuadro; Command Mode actualiza mediante
comandos, normalmente una memoria de imagen del panel. La elección sigue abierta.
El uso de DCS para inicializar no determina esa elección.

## 4. Lo que existe hoy: depuración interna

```text
PC: script Python
      │ conexión local al servidor
      ▼
litex_server → UART → puente UARTWishbone → registros CSR
                                              │
                                    supervisor LPDTDebug
                                              │ copia privada de bytes
                                              ▼
                                      motor LPDT Verilog
                                              │ estados D0 internos
                                              ▼
                                 LiteScope → captura leída por el PC

                                 SIN conexión D0 al panel
```

- **LiteX** construye la integración digital. **Migen** es la biblioteca Python
  usada para describir hardware; ese Python genera circuitos, no se ejecuta
  como programa dentro de la FPGA.
- **SoCMini** reúne los bloques de este target. Aquí no incorpora una CPU:
  el control lo hace el PC. No es la integración RISC-V futura.
- **UART** es la comunicación serie de depuración, a 115200 baudios.
- **Wishbone** es un bus interno: permite leer y escribir direcciones.
  UARTWishbone convierte accesos del PC en operaciones sobre ese bus.
- **CSR** son registros de control y estado: posiciones donde el PC escribe
  bytes/órdenes y lee resultados.
- **LiteScope** toma muestras de señales internas y permite descargarlas como
  ondas VCD, archivos que puede mostrar GTKWave.

El supervisor de esta prueba admite paquetes de 1–7 bytes, rechaza órdenes
mientras está ocupado y no tiene cola. No implementa todavía el supervisor
completo del panel, ni sus esperas o recuperación eléctrica.

La inicialización será por software: comandos, orden y esperas. El arnés
LiteX permite preparar paquetes desde el PC y observar el envío interno.
La interfaz física LP sigue pendiente.

## 5. Reloj y límites de la prueba

El reloj de control es de **40 MHz**: un ciclo dura **25 ns**. El handshake del
motor cambia en el flanco ascendente (posedge); la secuencia de fases, datos y
salida LP cambian en el descendente (negedge). Entre ambos hay **12,5 ns**.

El análisis de timing comprueba que los datos llegan antes de que el registro
destino los capture. Estos caminos de medio ciclo deben revisarse después de
implementar el circuito; una simulación ideal no mide esos retardos físicos.
Los 40 MHz no son la velocidad ni el reloj HS.

Una captura interna correcta no comprueba tensiones, flancos eléctricos,
drivers HS/LP, CLK/D1, recepción del panel ni conformidad D-PHY.

## 6. Siguientes etapas

1. Completar pruebas del motor y del supervisor CSR, incluidos reset, rechazos
   y envíos consecutivos; revisar timing del diseño integrado.
2. Validar la PHY LP y las E/S antes de conectar la salida lógica al panel.
3. Integrar la inicialización por software con la interfaz LP y confirmar
   la variante de pantalla antes de validar la secuencia en el panel.
4. Desarrollar HS: reloj, serialización, cambios LP/HS y reparto entre canales.
5. Añadir paquetes de imagen, buffers, adaptación e integración con PPU.
6. Definir la integración RISC-V y evaluar recepción de respuestas del panel.

## Glosario de consulta

| Término | Significado en este proyecto |
|---|---|
| FPGA | Circuito digital reconfigurable: al cargar su configuración se establece qué lógica y conexiones utiliza |
| CPU / RISC-V | CPU es un procesador que ejecuta instrucciones; RISC-V es una arquitectura de instrucciones prevista para una integración futura |
| Síntesis | Conversión de la descripción del circuito en registros, puertas y otros recursos de la FPGA |
| Implementación | Colocación de esos recursos en la FPGA y trazado de sus conexiones |
| Timing / cierre temporal | Comprobación de retardos / cumplimiento de los límites de tiempo exigidos por el reloj |
| E/S | Entradas y salidas físicas de la FPGA |
| SRAM / flash | Memoria temporal que pierde el contenido sin alimentación / memoria que lo conserva |
| LVCMOS33 | Estándar de E/S CMOS de 3,3 V declarado para reloj y UART; no para las ramas LP del panel |
| Baudios | Símbolos transmitidos por segundo; en esta UART, 115200 baudios no equivalen a 115200 bytes por segundo |
| RTL | Descripción del comportamiento de registros y lógica digital, aquí principalmente Verilog |
| FSM | Máquina de estados: decide la siguiente acción según el estado actual y las entradas |
| Handshake | Señales de petición y aceptación que coordinan dos bloques |
| ECC | Bits que protegen el encabezado de un paquete DSI frente a errores |
| CRC | Comprobación de integridad de los datos de un paquete largo; no aparece en los cortos |
| VC | Canal virtual: identificador lógico dentro del enlace, distinto de una lane física |
| WC | Número de bytes de datos de un paquete largo |
| CDC | Paso de señales entre dominios de reloj distintos; requiere tratamiento específico |
| Backpressure | Aviso al productor para que espere porque el receptor no puede aceptar más datos |
| Underflow / overflow | Intentar leer un buffer vacío / escribir en uno lleno |
| BTA | Cambio de quién conduce el enlace para permitir una respuesta del panel; pendiente |
| Bitstream | Archivo de configuración que se carga en la FPGA para crear el circuito |

Referencia de paquetes: corto = encabezado de 3 bytes + ECC; largo =
encabezado de 3 bytes + ECC + WC bytes de datos + CRC de 2 bytes.
El motor actual no genera estos campos: recibe el paquete ya preparado.
