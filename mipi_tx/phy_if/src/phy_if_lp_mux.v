module phy_if_lp_mux (
    input [1:0] LP_D0,
    input LP_USE_D0,
    input [1:0] FORCED_PN,

    output [2:0] LP_P_D,
    output [2:0] LP_N_D
);
  wire [1:0] D0, D1;
  assign D0 = LP_USE_D0 ? LP_D0 : FORCED_PN;
  assign D1 = LP_USE_D0 ? 2'b11 : FORCED_PN;

  // Cada símbolo es {P,N}; en los buses de salida: {CLK,D1,D0}.
  assign LP_P_D = {1'b1, D1[1], D0[1]};
  assign LP_N_D = {1'b1, D1[0], D0[0]};
endmodule
