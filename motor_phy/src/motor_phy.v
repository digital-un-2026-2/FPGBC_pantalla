// Top lógico; no instancia pads ni fija restricciones eléctricas.
// rst es el reset global, NO rst_motor. Mantenerlo durante posedge y negedge.
// T_HABILITACION >= 1; a 40 MHz el valor inicial 4 corresponde a 100 ns.
module motor_phy #(
    parameter integer T_HABILITACION = 4
) (
    input clk,
    input rst,
    input preparar_lp,
    input fallo_init,
    input [1:0] estado_D0,

    output lp_preparada,
    output [2:0] lp_p,
    output [2:0] lp_n,
    output [2:0] lp_oe,
    output [2:0] hs_oen
);
  localparam integer W = (T_HABILITACION < 2) ? 1 : $clog2(T_HABILITACION + 1);
  localparam [W-1:0] LIMITE = T_HABILITACION;

  wire w_rst_t;
  wire w_inc_t;
  wire w_en_lp;
  wire w_sel_d0;
  wire w_listo_ctrl;
  wire w_estado_valido;
  wire w_fallo_activo;
  wire w_z_t;
  wire w_sel;
  wire [W-1:0] w_tiempo;
  wire [1:0] w_d0;

  phy_control ctrl (
      .clk(clk),
      .rst(rst),
      .preparar_lp(preparar_lp),
      .fallo_init(fallo_init),
      .z_t(w_z_t),
      .rst_t(w_rst_t),
      .inc_t(w_inc_t),
      .en_lp(w_en_lp),
      .sel_d0(w_sel_d0),
      .listo_ctrl(w_listo_ctrl),
      .estado_valido(w_estado_valido),
      .fallo_activo(w_fallo_activo)
  );

  // Bloques compartidos con motor_lpdt y secuenciador_init.
  // Comparar contra N, no N-1: la FSM observa Z_T en el posedge posterior.
  count #(.BITS(W)) count_tiempo (
      .clk(clk),
      .rst(rst | w_rst_t),
      .inc(w_inc_t),
      .count_out(w_tiempo)
  );

  comp #(.BITS(W)) comp_tiempo (
      .A(w_tiempo),
      .B(LIMITE),
      .z(w_z_t)
  );

  phy_mask mask (
      .rst(rst),
      .preparar_lp(preparar_lp),
      .fallo_init(fallo_init),
      .estado_valido(w_estado_valido),
      .fallo_activo(w_fallo_activo),
      .en_lp(w_en_lp),
      .sel_d0(w_sel_d0),
      .listo_ctrl(w_listo_ctrl),
      .sel(w_sel),
      .lp_oe(lp_oe),
      .lp_preparada(lp_preparada)
  );

  // Sin registro adicional: motor_lpdt ya actualiza estado_D0 en negedge.
  mux #(.INPUTS(2), .BITS(2)) mux_d0 (
      .data_in({estado_D0, 2'b11}),
      .sel(w_sel),
      .data_out(w_d0)
  );

  phy_lanes lanes (
      .d0(w_d0),
      .lp_p(lp_p),
      .lp_n(lp_n),
      .hs_oen(hs_oen)
  );

`ifndef SYNTHESIS
  initial begin
    if (T_HABILITACION < 1) $fatal(1, "T_HABILITACION debe ser >= 1");
  end
`endif
endmodule
