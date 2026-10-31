# Vistas de señales

[Motor](../README.md) · [Cobertura de pruebas](../TB/README.md)

Los archivos `<target>_TB.gtkw` guardan la selección, agrupación y formato de
señales en GTKWave. No contienen las ondas: estas se generan como VCD en
`motor_lpdt/build/` y no se versionan.

Desde la raíz:

```sh
pixi run sim                                      # Integrada y visor
pixi run make -C motor_lpdt sim TARGET=count       # Contador y visor
pixi run make -C motor_lpdt wave TARGET=count      # Solo abrir ondas existentes
```

Si aún no hay VCD, ejecutar `sim` o `test` antes de `wave`. Al guardar una vista,
mantener las rutas relativas como en las existentes para poder compartirla.
La vista facilita diagnosticar; las comprobaciones automáticas están en los
testbenches, no en el archivo `.gtkw`.
