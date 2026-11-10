`timescale 1ns / 1ps

module packet_register #(
    parameter BITS = 32,
    parameter [BITS-1:0] RESET_VALUE = {BITS{1'b0}}
) (
    input clk,
    input rst,
    input [BITS-1:0] reg_in,
    input ld,

    output reg [BITS-1:0] reg_out
);

  // Este datapath captura en posedge, según su interfaz valid/ready.
  always @(posedge clk) begin
    if (rst) begin
      reg_out <= RESET_VALUE;
    end else if (ld) begin
      reg_out <= reg_in;
    end
  end

endmodule
