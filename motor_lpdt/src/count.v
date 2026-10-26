module count #(
    parameter BITS = 10
) (
    input clk,
    input rst,
    input inc,


    output reg [BITS-1:0] count_out
);

  always @(negedge clk) begin
    if (rst) begin
      count_out <= 0;
    end else if (inc) begin
      count_out <= count_out + 1;
    end
  end


endmodule
