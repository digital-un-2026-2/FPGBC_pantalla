# Arquitectura: inicialización LP capturada

## Alcance

Reproducir los 18 paquetes de `LP_MIPI_DSI.kvdat` y sus esperas.
No incluye vídeo, HS, PPU, BTA, lectura de registros, CPU ni control por PC.
No se usa `DATA HS.kvdat` como referencia.

## Bloques

| Bloque | Responsabilidad |
|---|---|
| `secuenciador_init` | Recorrer los 18 descriptores, solicitar cada envío, supervisar el motor y contar la espera posterior |
| `rom_descriptores` | Base del paquete, número de bytes DSI y espera posterior en ciclos |
| `rom_paquetes` | Bytes exactos capturados: cabecera, ECC, payload y CRC cuando corresponda |
| `motor_lpdt` | Entrada Escape, selector `87`, datos LSB primero, salida a LP-11 |
| Interfaz física LP | Llevar los estados lógicos a los pads, mantener D1/CLK en reposo LP y evitar que las ramas HS conduzcan |
| Top autónomo | Conectar reloj, reset, secuenciador, motor e interfaz física |

Se reutilizan la FSM y el datapath de `main`, con anchos y ROM ampliados;
no se necesita un generador
dinámico de paquetes, ECC ni CRC. Almacenar el paquete completo evita alterar
los bytes Data1 observados en los DCS cortos y permite emitir Null Packets.

## Flujo

```text
RESET → preparación física LP → espera inicial configurable
      → cargar descriptor → validar → solicitar paquete
      → esperar aceptado → esperar terminado → espera posterior
      → siguiente descriptor / LISTO
```

El orden exacto de preparación y estabilización del controlador heredado
debe revisarse al integrar los pads; nunca autorizar el motor sin LP preparada.
Un timeout, descriptor inválido o pérdida de preparación conduce a FALLO.
No hay reintentos ni paquetes adicionales automáticos.

## Interfaces y tamaños implementados

- Reloj de control: **40 MHz**.
- `pos` y `cantidad_bytes`: **5 bits**; máximo observado: 22 bytes DSI.
- Índice de paso: **5 bits**, valores 0…17.
- Dirección de ROM: **8 bits**, para **204 bytes**.
- Descriptor: **36 bits**, base [35:28], longitud [27:23], espera [22:0].
- Validación: paso 0…17, longitud 1…22 y suma de 9 bits para comprobar
  que base + longitud ≤204 sin desbordamiento.
- Handshake: `solicitud`, `permiso_arranque`, `aceptado`, `ocupado`, `terminado`.
- Estado de salida del motor: `estado_D0[1:0] = {D0P,D0N}`.
- Preparación física: `preparar_lp` / `lp_preparada`; es un handshake local,
  **no una respuesta de la pantalla**.
- Estado público: `init_en_curso`, `init_completa`, `fallo`, `codigo_fallo`.

`init_completa` solo confirma transmisión y cumplimiento de las esperas.
Después se permanece en LP-11 hasta reset.

## Temporización

El motor existente usa cuatro ciclos por fase: 100 ns Mark + 100 ns Space,
aproximadamente **5 Mbit/s LPDT**.

Las esperas ordinarias capturadas son aproximadamente 9 ms y las largas
65 ms: **360000 y 2600000 ciclos** a 40 MHz. Se miden desde el retorno
físico a LP-11 hasta la siguiente entrada Escape; no desde la solicitud.
La prueba integrada mide **9 ciclos adicionales (225 ns)** de control
entre retorno a LP-11 y siguiente Escape: las pausas resultan de
9,000225 ms y 65,000225 ms, respectivamente.

El último paquete no tiene un paquete LP siguiente en la captura.
Su espera final programada es explícitamente **cero**: se entra a LISTO
tras observar la finalización local y permanece LP-11. No se añade una
espera de 7 ms a partir de HS ni se inicia HS.

La espera inicial debe ser configurable: no se capturó alimentación/RESET.
No interpretar los 382 ms del primer paquete como una especificación de arranque.

El motor produce una codificación LPDT regular. La reproducción de bytes y
esperas no implica copiar exactamente las fases extendidas de salida observadas
en el emisor original. La comparación temporal debe registrar esa diferencia.

## Interfaz física: implementación candidata

El bloque [motor_phy](../motor_phy/README.md) tiene RTL, fuente Draw.io,
diagrama de flujo, datapath y FSM. Su estado cambia en posedge, el contador
en negedge y todas las salidas de la FSM son combinacionales.
La [integración LiteX/Migen](../gateware/README.md) conecta los tres tops y
sitúa los buffers Gowin fuera del RTL lógico, sin CPU ni servicios de SoC.

Conservar el mapa y las precauciones de [hardware](hardware.md).
La rama LP utiliza el banco medido a 1,21 V; las ramas HS deben quedar
eléctricamente deshabilitadas durante este objetivo exclusivamente LP.
No basta con fijar a cero sus datos.

La implementación debe definir el estado de los doce pines relacionados con
DSI, incluidos reset y fallo, y verificarlo antes de cargar un bitstream.
No se asume que el reset del motor produzca por sí solo niveles seguros.

## Validación lógica implementada

1. ROM y vectores de test contrastados byte a byte con la captura: 204 bytes.
2. Motor probado en longitudes 1…31, incluido el B7 de 22 bytes y reset
   después del cruce al índice 16.
3. Reconstrucción desde D0 de los 18 paquetes, con 18 ECC y 16 CRC válidos.
4. Esperas completas de 265 ms, intervalos entre ráfagas, LP-11 final y
   ausencia de duplicados.
5. Control con 18 pasos, aceptación retrasada, timeouts, reset y pérdida LP
   usando datapath/motor modelados; prueba integrada de pérdida LP en LISTO.
6. Validación exhaustiva de 262144 combinaciones de paso/base/longitud.

La nueva prueba del top generado reconstruye también los 18 paquetes / 204 bytes
desde los pads modelados y comprueba abortos por reset/fallo durante transmisión.
Pendiente: ampliar las inyecciones a cada fase con todos los tops reales,
cierre temporal completo hasta pads y validación física autorizada.
LiteX/Migen se usa solo como integración de platform, instancias y pads;
no se añade CPU, UART, CSR ni LiteScope.

Los diagramas Draw.io/PDF/SVG conservados del secuenciador son históricos,
de la ROM de 11 comandos. El RTL y esta arquitectura describen la versión
actual de 18 paquetes.
