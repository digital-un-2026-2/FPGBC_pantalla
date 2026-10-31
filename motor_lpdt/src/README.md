# Fuentes Verilog del motor

[Motor e interfaz](../README.md) · [Pruebas](../TB/README.md)

| Archivo | Función |
|---|---|
| `motor_lpdt.v` | Une el control y la lógica de datos; interfaz pública del motor |
| `motor_control.v` | Máquina de estados: entrada LPDT, envío de bits y retorno al reposo |
| `count.v` | Contadores configurables para tiempo, bit y byte |
| `comp.v` | Comparadores para evaluar índices y tiempos |
| `reg_0.v` | Registros con habilitación de carga |
| `mux.v` | Selección entre varias entradas de datos |

Control en flanco ascendente y registros/contadores en descendente: preservar
los caminos de medio ciclo. Antes de modificar interfaces leer el contrato
del README superior; el almacén debe entregar los bytes con la anticipación
exigida, sin un protocolo de espera adicional.

Desde la raíz, sin FPGA:

```sh
pixi run test
pixi run make -C motor_lpdt test TARGET=reg
```

La síntesis no se ejecuta aquí: el target LiteX añade estas fuentes explícitamente.
