module comp #(
    parameter BITS = 3
) (
    input [BITS-1:0] A,
    input [BITS-1:0] B,

    output reg z
);

  assign z = (A == B);

endmodule
