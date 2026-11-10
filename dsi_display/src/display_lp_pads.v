`timescale 1ns/1ps

// Board bring-up at 40MHz. No PLL/OSER or HS drive exists in this configuration.
// The three differential buffers reserve the HS pins but remain disabled.
module display_lp_pads #(parameter PROFILE_OK=0) (
    input rst, phy_abort, lp_grant, input [1:0] estado_D0,
    output [2:0] lp_pad_p, lp_pad_n, hs_pad_p, hs_pad_n
);
  wire enable=PROFILE_OK && !rst && !phy_abort;
  wire [1:0] d0=lp_grant ? estado_D0 : 2'b11;
  wire [5:0] data={4'b1111,d0};
  genvar lane;
  generate for(lane=0;lane<3;lane=lane+1) begin: drivers
    TBUF p (.I(data[2*lane+1]),.OEN(!enable),.O(lp_pad_p[lane]));
    TBUF n (.I(data[2*lane]),.OEN(!enable),.O(lp_pad_n[lane]));
    TLVDS_TBUF hs (.I(1'b0),.OEN(1'b1),.O(hs_pad_p[lane]),.OB(hs_pad_n[lane]));
  end endgenerate
endmodule
