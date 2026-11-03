// Arranque autonomo: secuenciador -> motor -> interfaz fisica LP.
// clk: 40 MHz. rst: cubrir un posedge y el negedge posterior.
// No genera clk/reset de arranque; deben proceder de la integracion exterior.
module panel_init_top #(
    parameter W = 23,
    parameter [W-1:0] T_ESTABILIZACION = 800000,
    parameter [W-1:0] T_REPOSO_INICIAL = 8000,
    parameter [W-1:0] TIMEOUT_PREPARACION = 40000,
    parameter [W-1:0] TIMEOUT_ACEPTACION = 16,
    parameter [W-1:0] TIMEOUT_TRANSMISION = 2048
) (
    input clk,
    input rst,

    inout D0_P,
    inout D0_N,
    output CLK_P,
    output CLK_N,
    output D1_P,
    output D1_N,
    output [5:0] hs_pads,

    output d0_pad_p,
    output d0_pad_n,
    output init_en_curso,
    output init_completa,
    output fallo,
    output [2:0] codigo_fallo
);

  wire w_preparar_lp, w_lp_preparada, w_rst_motor;
  wire w_solicitud, w_permiso_arranque;
  wire w_aceptado, w_ocupado, w_terminado;
  wire [3:0] w_pos, w_cantidad_bytes;
  wire [7:0] w_byte_almacen;
  wire [1:0] w_estado_D0;
  wire [5:0] w_hs_oen;
  wire w_liberar_d0;

  // No hay controlador BTA: el arranque normal nunca solicita escucha.
  assign w_liberar_d0 = 1'b0;

  secuenciador_init #(
      .W(W),
      .T_ESTABILIZACION(T_ESTABILIZACION),
      .T_REPOSO_INICIAL(T_REPOSO_INICIAL),
      .TIMEOUT_PREPARACION(TIMEOUT_PREPARACION),
      .TIMEOUT_ACEPTACION(TIMEOUT_ACEPTACION),
      .TIMEOUT_TRANSMISION(TIMEOUT_TRANSMISION)
  ) init (
      .clk(clk), .rst(rst),
      .lp_preparada(w_lp_preparada), .preparar_lp(w_preparar_lp),
      .aceptado(w_aceptado), .ocupado(w_ocupado), .terminado(w_terminado),
      .pos(w_pos), .solicitud(w_solicitud), .permiso_arranque(w_permiso_arranque),
      .cantidad_bytes(w_cantidad_bytes), .byte_almacen(w_byte_almacen),
      .rst_motor(w_rst_motor),
      .init_en_curso(init_en_curso), .init_completa(init_completa),
      .fallo(fallo), .codigo_fallo(codigo_fallo)
  );

  motor_lpdt #(.ANCHO_LONGITUD(4)) motor (
      .clk(clk), .rst(w_rst_motor),
      .permiso_arranque(w_permiso_arranque), .solicitud(w_solicitud),
      .cantidad_bytes(w_cantidad_bytes), .byte_almacen(w_byte_almacen),
      .aceptado(w_aceptado), .ocupado(w_ocupado), .terminado(w_terminado),
      .pos(w_pos), .estado_D0(w_estado_D0)
  );

  fisical_layer fisica (
      .preparar_lp(w_preparar_lp), .rst_motor(w_rst_motor),
      .estado_D0(w_estado_D0), .liberar_d0(w_liberar_d0),
      .lp_preparada(w_lp_preparada), .d0_pad_p(d0_pad_p), .d0_pad_n(d0_pad_n),
      .hs_oen(w_hs_oen),
      .D0_P(D0_P), .D0_N(D0_N), .CLK_P(CLK_P), .CLK_N(CLK_N),
      .D1_P(D1_P), .D1_N(D1_N), .hs_pads(hs_pads)
  );

endmodule
