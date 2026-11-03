# Pruebas de la interfaz física LP

[Función y contrato](../README.md) · [Fuentes](../src/README.md)

Desde la raíz, sin placa:

```sh
pixi run make -C fisical_layer test                         # Solo física
pixi run make -C fisical_layer test TARGET=panel_init_top   # Tres bloques conectados
pixi run make -C fisical_layer test-all                     # Ambas pruebas
```

`sim TARGET=panel_init_top` ejecuta la integrada, guarda FST y abre GTKWave;
`wave TARGET=panel_init_top` abre ondas existentes. Las pruebas normales no
generan ondas. Resultados en `build/fisical_layer/`, ignorados por Git.
No se modifican las tareas Pixi ni las pruebas de los módulos existentes.

## Cobertura

### `fisical_layer_TB`

- Las 32 combinaciones de `rst_motor`, `preparar_lp`, `liberar_d0` y los cuatro
  valores de D0; CLK/D1 en LP-11 o liberados según corresponda.
- Prioridad de reset/deshabilitación y datos inicialmente desconocidos con
  salidas deshabilitadas.
- Lectura de ambos pads al transmitir y al liberar; fuentes externas de prueba
  recorren 00, 01, 10 y 11 solo cuando D0 está liberado.
- Ambas ramas D0 se liberan juntas; CLK/D1 permanecen habilitados al escuchar.
- Seis ramas HS liberadas en todos los casos, comprobadas sin fuente externa
  y con fuentes externas a cero y uno para detectar drivers activos constantes.
- Cambios combinacionales sin reloj. Volver a conducir se ordena expresamente
  desde la prueba, no mediante detección de propiedad del enlace.

### `panel_init_top_TB`

- Secuenciador, ROM y motor reales, con la interfaz física; no se sustituye
  `lp_preparada` por un valor fijo ni se modifican los paquetes del DUT.
- Reconstrucción desde D0_P/N **después de los IOBUF**: selector 87 y los 11
  paquetes DCS, incluidos los 15 bytes de BE. ECC y CRC recalculados.
- Estados y tiempos de cada fase LP, reposo antes del primer envío y esperas
  DCS completas: 285 ms más overhead. Se acortan únicamente estabilización
  (2 ciclos), reposo inicial (3 ciclos) y timeout de preparación (8 ciclos).
- Monitor por eventos del camino directo motor → pads; LP-11 al habilitar,
  CLK/D1 constantes, lectura de pads y HS siempre sin conducir.
- Once aceptaciones y once finalizaciones; ausencia de envíos duplicados en
  LISTO; reset durante transmisión y durante espera DCS; reinicio desde el
  primer comando.
- Inyección por `force` de `w_liberar_d0`, fijado a cero en el top normal:
  pérdida LP durante transmisión y en LISTO, timeout de preparación, fallo
  enclavado y liberación de todas las ramas LP. Reset aborta sin `terminado`.

Los timeouts de prueba y las discrepancias usan `$fatal`. El decodificador
depende de los tiempos conocidos del motor: **no es un receptor LP general**.
La inyección de liberación es un fallo lógico deliberado, no BTA ni una prueba
de respuesta del panel.

## Modelos y límites

`gowin_io_sim.v` proporciona modelos funcionales propios, ideales, de IOBUF y
TBUF con OEN activo a cero. Se compilan solo en las pruebas; no son fuentes
RTL del diseño ni deben coexistir con otra biblioteca que defina esos nombres.
Para probar otra biblioteca se puede sustituir `IO_MODELS` en Make.

Los puertos HS se observan aislados de los puertos LP para verificar su
ausencia de conducción. En la placa ambas ramas se unen tras las resistencias
LP: **no se modelan la red resistiva, niveles analógicos ni carga del panel**.

No hay modelo de panel ni respuestas; leer la propia transmisión no confirma
recepción. Tampoco se verifican BTA, receptor, D-PHY, alimentación, backlight,
imagen, síntesis, timing colocado, legalidad de E/S o estado durante
configuración. Quedan pendientes aceptación retrasada, timeouts de aceptación
y transmisión en este top, y reset/fallos en cada fase de la integración.
