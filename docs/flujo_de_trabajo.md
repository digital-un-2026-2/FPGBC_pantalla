# Flujo de trabajo LP

Desde la raíz:

```sh
pixi install --locked
pixi run test
pixi run test-init
```

Sin Pixi, con Icarus y make instalados:

```sh
make -C motor_lpdt test-all
make -C secuenciador_init test-all
```

Para ver las ondas de la secuencia capturada:

```sh
pixi run make -C secuenciador_init sim TARGET=secuenciador_init
```

Los ejecutables y ondas son productos ignorados de `build/` y
`motor_lpdt/build/`. Los archivos antiguos de otras ramas que permanezcan allí
no son diseños válidos de esta rama: no usarlos para programar la placa.

La prueba integrada verifica los 18 paquetes capturados desde D0, incluidos
los de 18/19/20/22 bytes, recalcula ECC/CRC y mide las esperas nominales
de 9/65 ms más el overhead del control. No acorta los 265 ms de espera
programados; su ejecución puede tardar considerablemente más que los tests
del motor y del validador.

Esta rama no tiene todavía un target físico de síntesis ni de carga.
No ejecutar bitstreams anteriores como prueba de esta inicialización.
