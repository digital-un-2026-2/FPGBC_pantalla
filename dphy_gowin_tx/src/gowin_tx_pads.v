`timescale 1ns/1ps
// Candidate buffers. Pin/bank/IO standard/OE timing remain profile obligations.
module gowin_tx_pads (
    input [5:0] lp_dat, lp_en, input [2:0] serial, hs_oe,
    output [2:0] lp_pad_p, lp_pad_n, hs_pad_p, hs_pad_n
);
  genvar lane;
  generate for (lane=0;lane<3;lane=lane+1) begin: drivers
    TBUF lp_p (.I(lp_dat[2*lane+1]),.OEN(~lp_en[2*lane+1]),.O(lp_pad_p[lane]));
    TBUF lp_n (.I(lp_dat[2*lane]),.OEN(~lp_en[2*lane]),.O(lp_pad_n[lane]));
    TLVDS_TBUF hs (.I(serial[lane]),.OEN(~hs_oe[lane]),
        .O(hs_pad_p[lane]),.OB(hs_pad_n[lane]));
  end endgenerate
endmodule
