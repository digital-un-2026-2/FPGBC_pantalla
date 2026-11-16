// Concatenación combinacional: bit 0 = D0, bit 1 = D1, bit 2 = CLK.
module phy_lanes (
    input [1:0] d0,
    output [2:0] lp_p,
    output [2:0] lp_n,
    output [2:0] hs_oen
);
  assign lp_p = {2'b11, d0[1]};
  assign lp_n = {2'b11, d0[0]};
  // Polaridad física activa baja: 1 deshabilita los drivers HS.
  assign hs_oen = 3'b111;
endmodule
