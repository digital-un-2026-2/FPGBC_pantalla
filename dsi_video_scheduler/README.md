# Planificador DSI con LiteX y RISC-V

**RTL implementado en `src/`.** El [módulo de integración](../dsi_display/README.md)
lo conecta a la cadena real y añade control CSR LiteX, software de PC y pruebas
de cuadros completos. El firmware RISC-V y el perfil real del panel siguen pendientes.

- [Draw.io editable: ocho páginas](docs/DSI_VIDEO_SCHEDULER.drawio): dos de flujo, cuatro de datapath y dos de FSM.
- [Flujo del firmware RISC-V](docs/flujo_firmware.svg).
- [Flujo del planificador RTL](docs/flujo_rtl.svg).
- [PDF de ambas páginas](docs/FLUJO.pdf).
- [Contrato y límites del flujo](docs/flujo.md).
- [Datapath: registros, operadores y ecuaciones](docs/datapath.md) · [PDF](docs/DATAPATH.pdf).
- Vistas del datapath: [configuración](docs/datapath_config.svg), [calendario](docs/datapath_calendario.svg), [payload](docs/datapath_payload.svg) y [supervisión](docs/datapath_estado.svg).
- [FSM: estados, prioridades y controles](docs/fsm.md) · [PDF](docs/FSM.pdf).
- Vistas FSM: [transiciones](docs/fsm.svg) y [controles](docs/fsm_controles.svg).

En la arquitectura prevista, RISC-V inicializa el panel y supervisa el vídeo.
La integración actual proporciona ese control desde el PC por UARTWishbone.
El planificador RTL coordina los eventos de línea/cuadro y los paquetes.
LiteX expone órdenes y estado por CSR; los píxeles circulan directamente
entre el generador y la cadena DSI.

Regenerar editable y vistas SVG: `python dsi_video_scheduler/docs/generar_flujo.py`.
Los SVG se generan como vectores a partir de los mismos nodos y conexiones
del editable, sin necesitar abrir Draw.io.

Comprobar guards y acciones del modelo de FSM:
`python dsi_video_scheduler/docs/verificar_fsm.py`.
Es verificación simbólica de la especificación, sin ejecutar RTL.
La prueba RTL integrada se ejecuta con `pixi run --locked test-dsi-display`.
