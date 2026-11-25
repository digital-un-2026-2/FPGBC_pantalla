module lp_tx_shift_reg (
    input CLK_BYTE,
    input RST_BYTE,
    input LD_BYTE,
    input SHIFT,
    input [7:0] BYTE,

    output BIT
);
  reg [7:0] Q;

  // Durante la carga, la primera marca no puede depender del Q anterior.
  assign BIT = LD_BYTE ? BYTE[0] : Q[0];

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) Q <= 8'h00;
    else if (LD_BYTE) Q <= BYTE;
    else if (SHIFT) Q <= {1'b0, Q[7:1]};
  end
endmodule
