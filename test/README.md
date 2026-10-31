# Prueba experimental del entorno EDA

[Inicio](../README.md) · [Pruebas del motor](../motor_lpdt/TB/README.md) · [Flujo FPGBC](../docs/flujo_de_trabajo.md)

EDA es el conjunto de herramientas para convertir una descripción digital en
un circuito implementado en FPGA. `env/eda_test.sh` ensaya esa cadena usando el
target externo `sipeed_tang_nano_9k` de `litex-boards`, **no la plataforma FPGBC**.

**Advertencia:** la tarea `pixi run test-EDA` incluye `--build --load`: intenta
programar hardware. No ejecutarla para verificar la FPGBC ni como test rutinario.
No es equivalente a `pixi run test`, que solo simula el RTL original.

| Archivo | Efectos |
|---|---|
| `env/eda_test.sh` | Borra `build_test/` y `eda_test.log` relativos al directorio de ejecución, construye el diseño de otra placa e intenta cargarlo |

Su criterio de éxito es encontrar un bitstream y una mención a openFPGALoader
en el log. Recoge el código de salida, pero no lo utiliza: un mensaje de éxito
no demuestra que la programación funcionó. También elimina resultados al finalizar.

Se documenta por existir en el repositorio; **no se recomienda como procedimiento
de aceptación**. Para FPGBC usar el target `gateware.targets.debug` y la carga
explícita en SRAM del manual general. El script no se modifica en esta revisión.
