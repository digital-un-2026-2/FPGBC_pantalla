# FPGBC_pantalla

Transmisor MIPI DSI para la pantalla de la FunnyPlaying FPGBC,
con FPGA Gowin GW2AR-LV18EQ144PC8/I7.

La cadena digital completa integra LPDT, generador de franjas, planificador,
paquetes y transporte HS con el wrapper Gowin y control CSR de LiteX.
El target `display_image` inicializa el panel con la secuencia pública JDI
LT031MDZ4000 y transmite automáticamente ocho barras RGB888 de 720×720 a
60 Hz, con HS habilitado a 480 Mbit/s/lane y los doce pines de placa asignados.
El bitstream está construido y supera timing. En la primera prueba del usuario
no hubo imagen y la retroiluminación permaneció apagada; con el firmware original
sí funciona. Se añade una variante de diagnóstico con comandos de brillo DCS.
[Construcción, carga y diagnóstico](docs/imagen_en_pantalla.md).

```sh
pixi run --locked build-display-image
pixi run --locked check-display-image
```

El archivo para cargar es `build/display_image/gateware/display_image.fs`.
Los targets de depuración y LPDT siguen disponibles por separado.

## Archivos principales

- [Implementación en FPGA](docs/implementacion_fpga.md): pines, estándares, bitstreams de placa, CST/SDC y pruebas de construcción.
- [Imagen en pantalla](docs/imagen_en_pantalla.md): target autónomo, inicialización, vídeo activo y carga en SRAM.
- [Identificación de pantalla](docs/panel_lcd49754.md): fuentes encontradas para LCD-49754/LT031MDZ4000 y controlador candidato R63308.
- [dsi_display/](dsi_display/README.md): integración completa, mailbox entre relojes, control CSR y pruebas desde los pads simulados; target LiteX y controlador Python.
- [dsi_video_scheduler/](dsi_video_scheduler/README.md): planificador RTL WAIT/RGB/END, especificación Draw.io/PDF y verificación integrada.
- [dsi_test_pattern/](dsi_test_pattern/README.md): generador RTL autónomo de ocho franjas RGB888; control/datapath separados y pruebas con el preparador largo real.
- [dphy_lpdt_tx/src/dphy_lpdt_tx.v](dphy_lpdt_tx/src/dphy_lpdt_tx.v): motor LPDT.
- [dsi_lp_packet_tx/](dsi_lp_packet_tx/README.md): preparador RTL de paquetes DCS cortos con ECC y salida `valid/ready`.
- [dsi_long_packet_tx/](dsi_long_packet_tx/README.md): preparador RTL de paquetes largos DSI con ECC, CRC16 y carga útil mediante `valid/ready`.
- [dsi_lane_packer/](dsi_lane_packer/README.md): empaquetador lógico de dos bytes para D0/D1, con máscara del último grupo parcial y simulación con los preparadores reales.
- [dsi_hs_transport/](dsi_hs_transport/README.md): transporte lógico con buffer de paquete completo y salida HS continua en simulación.
- [dphy_hs_tx/](dphy_hs_tx/README.md): secuenciador HS RTL con perfil sintético S320 y verificación serial de testbench; sin primitivas ni pads.
- [dphy_gowin_tx/](dphy_gowin_tx/README.md): wrapper RTL Gowin con retardo común, supervisor y adaptadores de primitivas; probado con modelos ideales y perfil físico bloqueado por defecto.
- [dsi_lpdt_bridge/](dsi_lpdt_bridge/README.md): puente de prueba de cuatro bytes entre el preparador corto y el motor LPDT, con simulación hasta los estados de D0.
- [dphy_mode_ctrl/](dphy_mode_ctrl/README.md): árbitro LPDT/HS en simulación, con preparación/parada mediante confirmaciones de un modelo de PHY.
- [dsi_lp_packet_tx/docs/DSI_LP_PACKET_TX.drawio](dsi_lp_packet_tx/docs/DSI_LP_PACKET_TX.drawio): flujo, datapath y FSM del preparador de paquetes DCS cortos, editables con Draw.io. Vistas del [datapath](dsi_lp_packet_tx/docs/datapath.svg) y la [FSM](dsi_lp_packet_tx/docs/fsm.svg).
- [gateware/](gateware/README.md): integración LiteX y depuración por UART.
- [scripts/](scripts/README.md): captura interna y preparación del entorno.
- [docs/hardware.md](docs/hardware.md): conexiones, alimentación y precauciones.
- [docs/flujo_de_trabajo.md](docs/flujo_de_trabajo.md): herramientas y uso del target.

## Entorno

```sh
pixi install --locked
pixi run check-rtl
pixi run test-dsi-packet
pixi run test-dsi-long-packet
pixi run test-dsi-lane-packer
pixi run test-dsi-hs-transport
pixi run test-dsi-lpdt-bridge
pixi run test-dphy-mode
pixi run test-dphy-hs
pixi run test-dphy-gowin
pixi run test-dsi-test-pattern
pixi run test-dsi-display
pixi run test-display-image
pixi run generate-display
pixi run build-display-lpdt
pixi run check-display-lpdt
```

`check-rtl` comprueba con Icarus el motor LPDT, los dos preparadores DSI,
el empaquetador de dos lanes, el transporte lógico HS, el secuenciador HS,
el puente de prueba, el árbitro LP/HS, el wrapper Gowin (declaraciones de primitivas)
y el generador de franjas RGB888 y la integración completa de pantalla.
`test-dsi-packet` simula el preparador de paquetes; no requiere hardware.

El reloj de control es de 40 MHz y el de byte de `display_image` es de 60 MHz.
El usuario identificó el marcado LCD-49754-001/111, correspondiente al
LT031MDZ4000 documentado. La recepción DSI y el control de retroiluminación
siguen pendientes de validación física.
