module reg_0 #(
  parameter BITS = 8
) (
  input clk,
  input [BITS-1:0] reg_in,
  input ld,

  output reg [BITS-1:0] reg_out
);

always @(negedge clk) begin
  if (ld) begin
    reg_out <=reg_in;
  end
end

endmodule
