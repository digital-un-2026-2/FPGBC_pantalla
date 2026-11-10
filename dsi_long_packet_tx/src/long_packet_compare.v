`timescale 1ns / 1ps

module long_packet_compare #(
    parameter BITS = 2
) (
    input [BITS-1:0] A,
    input [BITS-1:0] B,

    output z
);

  assign z = (A == B);

endmodule
