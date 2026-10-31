# Documentación

[Inicio del proyecto](../README.md)

## Recorrido recomendado

1. [Arquitectura](arquitectura.md): entender el recorrido de imagen y comandos,
   las palabras técnicas y el estado real de cada bloque.
2. [Flujo de trabajo](flujo_de_trabajo.md): preparar el entorno, simular,
   sintetizar, cargar en SRAM y capturar señales internas.
3. [Hardware y seguridad](hardware.md): conexiones confirmadas, medidas y
   precauciones. Leer antes de cualquier programación o trabajo eléctrico.
4. [Depuración LiteX](litex_debug.md): registros y comportamiento del supervisor.

## Referencias del motor

- [Interfaz RTL](../motor_lpdt/README.md): contrato entre el motor y su supervisor.
- [LPDT y vector inicial](../motor_lpdt/docs/lpdt.md): protocolo y tiempos.
- [Cobertura de pruebas](../motor_lpdt/TB/README.md): qué se comprueba y qué falta.
- [Diagramas](../motor_lpdt/README.md#diagramas): fuente Draw.io, PDF y SVG.

Los procedimientos generales viven en `flujo_de_trabajo.md`; los README locales
explican las carpetas y enlazan esos procedimientos. Los diagramas son
conceptuales: para usar el motor prevalece su contrato RTL.
