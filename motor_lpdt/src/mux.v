module mux #(
    parameter INPUTS = 2,
    parameter BITS = 8,
    parameter SEL_BITS = (INPUTS > 1) ? $clog2(INPUTS) : 1
) (
    input  [INPUTS*BITS-1:0] data_in,
    input  [SEL_BITS-1:0] sel,
    output [BITS-1:0] data_out
);

  assign data_out = (sel < INPUTS)
                 ? data_in[sel*BITS +: BITS]
                 : {BITS{1'b0}};

endmodule
