module dphy_lpdt_tx #(
    parameter ANCHO_LONGITUD = 3
) (
    input clk,
    input rst,

    input permiso_arranque,
    input solicitud,

    input [ANCHO_LONGITUD-1:0] cantidad_bytes,
    input [7:0] byte_almacen,

    output aceptado,
    output ocupado,
    output terminado,

    output [ANCHO_LONGITUD-1:0] pos,
    output [1:0] estado_D0
);

  wire w_sel_87;
  wire [7:0] w_mux_byte_out;
  wire [7:0] w_byte_actual;

  wire [2:0] w_sel_bit_contador;
  wire w_ld_byte_actual;

  wire [1:0] w_lp_fijo;
  wire w_sel_fijo;
  wire w_mux_bit_out;
  wire [1:0] w_mux_mark_out;

  wire w_ld_estado_D0;

  wire w_ld_longitud;

  wire [ANCHO_LONGITUD-1:0] w_longitud_out;
  wire [ANCHO_LONGITUD-1:0] w_indice_byte;
  localparam [ANCHO_LONGITUD-1:0] UNO = 1;

  lpdt_mux #(
      .INPUTS(2),
      .BITS  (8)
  ) mux_byte (
      .data_in({8'h87, byte_almacen}),
      .sel(w_sel_87),
      .data_out(w_mux_byte_out)
  );

  lpdt_register #(
      .BITS(8)
  ) byte_actual (
      .clk(clk),
      .ld(w_ld_byte_actual),
      .rst(rst),
      .reg_in(w_mux_byte_out),
      .reg_out(w_byte_actual)
  );

  lpdt_mux #(
      .INPUTS(8),
      .BITS  (1)
  ) mux_bit (
      .data_in(w_byte_actual),
      .sel(w_sel_bit_contador),
      .data_out(w_mux_bit_out)
  );

  lpdt_mux #(
      .INPUTS(2),
      .BITS  (2)
  ) mux_mark (
      .data_in({w_lp_fijo, w_mux_bit_out, ~w_mux_bit_out}),
      .sel(w_sel_fijo),
      .data_out(w_mux_mark_out)
  );

  lpdt_register #(
      .BITS(2),
      .RESET_VALUE(2'b11)
  ) reg_estado_D0 (
      .clk(clk),
      .ld(w_ld_estado_D0),
      .rst(rst),
      .reg_in(w_mux_mark_out),
      .reg_out(estado_D0)
  );

  lpdt_register #(
      .BITS(ANCHO_LONGITUD)
  ) reg_longitud (
      .clk(clk),
      .ld(w_ld_longitud),
      .rst(rst),
      .reg_in(cantidad_bytes),
      .reg_out(w_longitud_out)
  );

  wire w_rst_indice_byte;
  wire w_inc_indice_byte;
  lpdt_counter #(
      .BITS(ANCHO_LONGITUD)
  ) count_indice_byte (
      .clk(clk),
      .rst(w_rst_indice_byte),
      .inc(w_inc_indice_byte),
      .count_out(w_indice_byte)
  );

  wire w_z_byte;
  lpdt_compare #(
      .BITS(ANCHO_LONGITUD)
  ) comp_byte (
      .A(w_indice_byte + UNO),
      .B(w_longitud_out),
      .z(w_z_byte)
  );

  wire w_rst_tiempo;
  wire w_inc_tiempo;
  wire [1:0] tiempo_out;
  lpdt_counter #(
      .BITS(2)
  ) count_tiempo (
      .clk(clk),
      .rst(w_rst_tiempo),
      .inc(w_inc_tiempo),
      .count_out(tiempo_out)
  );
  wire w_z_t;
  lpdt_compare #(
      .BITS(2)
  ) comp_tiempo (
      .A(tiempo_out),
      .B(2'd3),
      .z(w_z_t)
  );

  wire w_rst_bit;
  wire w_inc_bit;
  lpdt_counter #(
      .BITS(3)
  ) count_indice_bit (
      .clk(clk),
      .rst(w_rst_bit),
      .inc(w_inc_bit),
      .count_out(w_sel_bit_contador)
  );
  wire w_z_bit;
  lpdt_compare #(
      .BITS(3)
  ) comp_bit (
      .A(w_sel_bit_contador),
      .B(3'd7),
      .z(w_z_bit)
  );

  lpdt_control #(
      .ANCHO_LONGITUD(ANCHO_LONGITUD)
  ) ctrl (
      .clk(clk),
      .rst(rst),
      .z_byte(w_z_byte),
      .z_t(w_z_t),
      .z_bit(w_z_bit),
      .permiso_arranque(permiso_arranque && (cantidad_bytes != {ANCHO_LONGITUD{1'b0}})),
      .idx(w_indice_byte),
      .solicitud(solicitud),
      .ld_len(w_ld_longitud),
      .sel_87(w_sel_87),
      .ld_byte(w_ld_byte_actual),
      .rst_byte(w_rst_indice_byte),
      .inc_byte(w_inc_indice_byte),
      .rst_bit(w_rst_bit),
      .inc_bit(w_inc_bit),
      .ld_t(w_rst_tiempo),
      .inc_t(w_inc_tiempo),
      .sel_fijo(w_sel_fijo),
      .lp_fijo(w_lp_fijo),
      .ld_lp(w_ld_estado_D0),
      .aceptado(aceptado),
      .ocupado(ocupado),
      .terminado(terminado),
      .pos(pos)
  );

endmodule
