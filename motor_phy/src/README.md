# Fuentes RTL

Los bloques están en archivos independientes y se conectan en el top:

- `motor_phy.v`: top lógico y parámetro `T_HABILITACION >= 1` (por defecto 4).
- `phy_control.v`: FSM de cinco estados. Solo `state` se registra en
  `always @(posedge clk)`; todas las salidas se decodifican en `always @(*)`.
- `phy_mask.v`: inhibición combinacional de habilitación, preparación y selección.
- `phy_lanes.v`: concatenación D0/D1/CLK y deshabilitación constante de HS.
- `../../motor_lpdt/src/count.v`: contador de habilitación en `negedge`.
- `../../motor_lpdt/src/comp.v`: comparación combinacional contra N.
- `../../motor_lpdt/src/mux.v`: selección combinacional entre `11` y `estado_D0`.

No hay registro adicional en D0. Solo el contador almacena datos en el datapath.
El reset global debe cubrir un posedge y un negedge; la máscara inhibe las
salidas mientras `rst` está activo, sin esperar al flanco de la FSM.
Las entradas funcionales deben pertenecer al mismo dominio de reloj.

Compilación y pruebas desde la raíz: `make -C motor_phy test-all`.
En una compilación conjunta, incluir los bloques compartidos una sola vez.

No duplicar Escape, serialización LPDT ni temporizadores de paquetes:
ya pertenecen a `motor_lpdt` y `secuenciador_init`.
No implementar un transmisor HS en este objetivo.

No se necesita `phy_gowin_pads.v`: el adaptador está en
`../../gateware/cores/phy_pads.py` y trata los doce pines desde Migen/LiteX.
Las primitivas y restricciones candidatas se describen en
`../../gateware/README.md`; su validación eléctrica sigue pendiente.
Contrato y diagramas: [motor_phy](../README.md).
