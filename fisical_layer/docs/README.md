# Diagramas de la interfaz física LP

[Función e interfaz propuesta](../README.md)

| Archivo | Contenido |
|---|---|
| `FISICAL_LAYER.drawio` | Dos páginas editables: flujo y datapath de la interfaz LP |

Estilo basado en `ejemplo.drawio` y
`secuenciador_init/docs/SECUENCIADOR_INIT.drawio`: inicio, decisiones y procesos
con asignaciones explícitas. Las notas distinguen señales existentes, propuestas
y requisitos pendientes.

**Describe el RTL combinacional, no una FSM física.** No hay memoria de
modo, reloj propio ni tiempos nuevos. Las ramas son alternativas de una misma
evaluación; los procesos no se ejecutan secuencialmente entre ciclos.

Páginas:

1. `INTERFAZ_FISICA_LP`: decisiones y procesos del flujo.
2. `DATAPATH_LP`: puertas NOT/AND/OR, dos IOBUF con lectura de pads, cuatro
   TBUF auxiliares y seis TBUF HS deshabilitados mediante `hs_oen[5:0]=111111`.
   D0 conectado directamente al motor, sin mux. Sin pines, resistencias ni constraints.

El datapath usa bloques sin relleno de color, puertos I/O/OEN y señales
nombradas como los otros diagramas. `rst_motor` combina el reset y el aborto
del secuenciador; no se añaden entradas separadas `rst`, `fallo` u `ocupado`.
La página de flujo se ha ajustado a esta simplificación, conservando sus notas
de integración eléctrica.

Los bloques de habilitación son lógica combinacional, no una FSM. Las señales
nuevas se identifican dentro del dibujo. No se generan FSM, PDF ni SVG.
Abrir `FISICAL_LAYER.drawio` con Draw.io para revisarlo. Las ecuaciones se
explican en [datapath](../README.md#datapath). El cableado entre los tres bloques
está en [fuentes e integración](../src/README.md). La simulación con modelos
ideales de buffers no valida la implementación eléctrica.

Contratos contrastados con `motor_lpdt/src/motor_control.v`,
`motor_lpdt/src/motor_lpdt.v`, `secuenciador_init/src/secuenciador_control.v`
y sus README. Ver [condiciones de integración](../README.md#coordinación-y-límites-pendientes)
antes de convertir el dibujo en hardware.
