# Flujo de trabajo LP

Desde la raíz:

```sh
pixi install --locked
pixi run test
pixi run test-init
pixi run test-phy
pixi run test-gateware
pixi run test-captures
```

Sin Pixi, con Icarus y make instalados:

```sh
make -C motor_lpdt test-all
make -C secuenciador_init test-all
make -C motor_phy test-all
```

Para ver las ondas de la secuencia capturada:

```sh
pixi run make -C secuenciador_init sim TARGET=secuenciador_init
```

Los ejecutables, ondas y bitstreams son productos locales ignorados de `build/`,
`motor_lpdt/build/` y `motor_phy/build/`. Generarlos desde las fuentes de esta
rama; no usar artefactos de otras ramas para programar la placa.
Las capturas `.kvdat` tampoco se versionan. Las pruebas sintéticas funcionan
sin ellas; la [comparación de capturas](../scripts/README.md) requiere los
archivos locales indicados en cada análisis.

La prueba integrada verifica los 18 paquetes capturados desde D0, incluidos
los de 18/19/20/22 bytes, recalcula ECC/CRC y mide las esperas nominales
de 9/65 ms más el overhead del control. No acorta los 265 ms de espera
programados; su ejecución puede tardar considerablemente más que los tests
del motor y del validador.

La [integración LiteX/Migen](../gateware/README.md) exporta el nuevo target
para revisión; su CLI no ejecuta síntesis, empaquetado ni carga.
La [revisión de E/S](revision_io_lp.md) separa comprobaciones digitales de
las que requieren documentación adicional o medidas.
No ejecutar bitstreams anteriores como prueba de esta inicialización.
