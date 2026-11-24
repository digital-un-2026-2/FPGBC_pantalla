# Secuenciador autónomo de inicialización LP

Emite los **18 paquetes de `LP_MIPI_DSI.kvdat`**, sin CPU ni LiteX.
El motor LPDT y la interfaz física son externos.

## Datapath

```text
PASO[5] → ROM_DESCRIPTORES → DESC_ACTIVO[36]
                              ├→ longitud[5] → motor
                              ├→ base[8] + pos[5] → ROM_PAQUETES → byte[8]
                              └→ espera[23] → temporizador[W]
```

La FSM conserva sus 15 estados y la supervisión de preparación, aceptación,
transmisión y pérdida de LP. El paso final es 17, no 10.

| Archivo | Función |
|---|---|
| `src/secuenciador_init.v` | Conexión del control y datapath |
| `src/secuenciador_control.v` | FSM, esperas y primera causa de fallo enclavada |
| `src/rom_descriptores.v` | 18 descriptores de 36 bits: base [35:28], longitud [27:23], espera [22:0] |
| `src/rom_paquetes.v` | 204 bytes exactos, sin selector `87` |
| `src/validador_descriptor.v` | Paso 0…17, largo 1…22 y fin exclusivo ≤204, con suma de 9 bits |

## Interfaz

| Señal | Dirección | Uso |
|---|---|---|
| `clk`, `rst` | Entrada | 40 MHz; mantener reset durante posedge y negedge posterior |
| `lp_preparada` | Entrada | Preparación local de la interfaz física; no es ACK del panel |
| `preparar_lp` | Salida | Petición de preparación física |
| `aceptado`, `ocupado`, `terminado` | Entrada | Handshake del motor |
| `pos[4:0]` | Entrada | Dirección anticipada dentro del paquete |
| `solicitud`, `permiso_arranque` | Salida | Solicitud al motor |
| `cantidad_bytes[4:0]` | Salida | Número de bytes DSI, sin `87` |
| `byte_almacen[7:0]` | Salida | ROM combinacional en base + pos |
| `rst_motor` | Salida | Reset externo OR aborto por fallo |
| `init_en_curso`, `init_completa`, `fallo` | Salida | Estado de la secuencia |
| `codigo_fallo[2:0]` | Salida | Primera causa; cero después de reset |

Conectar **`motor_lpdt #(.ANCHO_LONGITUD(5))`**.
El motor sigue aceptando hasta 31 bytes con ese ancho; el secuenciador limita
sus descriptores a los 22 bytes máximos de esta secuencia.

El paquete permanece inmutable durante el envío. No registrar adicionalmente
`pos → suma → ROM → byte_almacen` sin revisar la anticipación del motor.
Control en posedge, datapath en negedge: requiere cierre temporal de medio ciclo.

## Secuencia y esperas

La [tabla de los 18 paquetes](../docs/secuencia_capturada.md) identifica los
payloads. La ROM conserva Generic Long Write `29`, los dos Null Packets `09`
y los DCS cortos `05`, incluidos Data1 y ECC originales.
No añade Software Reset ni cambia los registros para ajustarlos a otro driver.

- Pasos 4 y 9: **2600000 ciclos**, 65 ms.
- Otros pasos salvo el último: **360000 ciclos**, 9 ms.
- Paso 17: cero espera adicional; permanecer en LP-11.
- Total de esperas programadas: **265 ms**.

La FSM sale del estado de espera N+1 ciclos después de entrar.
Con el motor real, entre retorno a LP-11 y siguiente entrada Escape hay
**N+9 ciclos**: 9 ms +225 ns o 65 ms +225 ns. Las pruebas miden ambos
intervalos. No se pretende reproducir cada flanco nanosegundo a nanosegundo
del emisor capturado; las fases extendidas de salida difieren.

## Parámetros de tiempo

Ciclos de 40 MHz. `W=23` por defecto; mantener W ≥23 y dimensionarlo también
para cualquier parámetro ampliado. No configurar tiempos negativos o truncados.

| Parámetro | Default | Significado |
|---|---:|---|
| `T_ESTABILIZACION` | 800000 (20 ms) | Espera inicial configurable; no medida respecto a alimentación/RESET |
| `T_REPOSO_INICIAL` | 8000 (200 µs) | Reposo LP inicial propuesto, no validado físicamente |
| `TIMEOUT_PREPARACION` | 40000 (1 ms) | Límite para la preparación física |
| `TIMEOUT_ACEPTACION` | 16 (400 ns) | Límite del handshake local |
| `TIMEOUT_TRANSMISION` | 2048 (51,2 µs) | Superior a los 1492 ciclos LP del paquete de 22 bytes |

Estos defaults iniciales no garantizan alimentaciones ni requisitos eléctricos.
El timeout no cubre paquetes arbitrarios de 31 bytes: están fuera de esta ROM.

`codigo_fallo`: 0=sin fallo, 1=timeout LP, 2=timeout aceptación,
3=timeout transmisión, 4=descriptor inválido, 5=pérdida LP,
6=handshake incoherente. Solo reset reinicia; no hay reintentos.
`init_completa` confirma transmisión local, **no recepción del panel**.

## Pruebas

```sh
pixi run test-init
pixi run make -C secuenciador_init test TARGET=validador_descriptor
pixi run make -C secuenciador_init sim TARGET=secuenciador_init
```

[Cobertura y límites](TB/README.md). Se comprueban los 18 paquetes desde D0,
ECC/CRC y esperas completas; no se acortan los 265 ms programados.
Solo se reducen estabilización, reposo inicial y timeout de preparación.
`test` no genera ondas integradas; `sim` genera FST en `build/secuenciador_init/`.

## Diagramas

Los archivos Draw.io/PDF/SVG de `docs/` son **históricos**, del diseño de
11 comandos. No reflejan los anchos, ROM ni esperas actuales.
Para el diseño vigente prevalecen el RTL y
[la arquitectura LP](../docs/arquitectura.md).
