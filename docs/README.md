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

Transporte lógico HS: [contrato, diseño y pruebas](../dsi_hs_transport/README.md).

Primer hito de imagen estática: [generador autónomo de franjas RGB888](../dsi_test_pattern/README.md).
RTL desde flujo/datapath/FSM, sin RISC-V ni framebuffer; verificado con el preparador largo real.

Planificación de vídeo: [flujo propuesto con LiteX y RISC-V](../dsi_video_scheduler/README.md).
Dos páginas de flujo, cuatro de datapath y dos de FSM: transiciones y controles.

Secuenciador PHY HS: [RTL, diseño y pruebas](../dphy_hs_tx/README.md).
Tablas de 40/60 MHz y pruebas de la secuencia HS; el target de imagen usa 60 MHz.

PHY física Gowin: [flujo y datapath propuestos](../dphy_gowin_tx/README.md),
con arranque, transmisión, ramas LP/HS, relojes y recuperación. Incluye RTL
de primitivas Gowin y modelos ideales para pruebas.

Su [FSM de supervisor](../dphy_gowin_tx/docs/fsm.md) está en las páginas 8–9
del mismo Draw.io, con estados, prioridades, controles y cruces de dominio.

## Implementación de placa y panel

- [Imagen en pantalla](imagen_en_pantalla.md): bitstream autónomo con inicialización
  JDI, HS activo, barras 720×720 y comandos de carga.
- [Implementación FPGA](implementacion_fpga.md): doce pines, CST/SDC, bitstreams,
  modos parked/LPDT/HS y resultados de P&R.
- [Investigación LCD-49754](panel_lcd49754.md): referencias JDI y controlador
  candidato R63308, con fuentes y límites de identificación.
- [Análisis del firmware original](analisis_firmware_v1_4.md): formato del
  contenedor V1.4, procedencia, hashes y límites del análisis estático.
- [Propuesta de arquitectura original](referencias/arquitectura_2026_11_08/README.md):
  referencia histórica del 8 de noviembre de 2026.
