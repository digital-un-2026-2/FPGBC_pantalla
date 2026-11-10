`timescale 1ns / 1ps

// P0: indice del mayor umbral alcanzado, sin registro de franja.
module test_pattern_priority (
    input [6:0] thresholds, output reg [2:0] stripe
);
  always @(*) begin
    stripe = 3'd0;
    if (thresholds[6]) stripe = 3'd7;
    else if (thresholds[5]) stripe = 3'd6;
    else if (thresholds[4]) stripe = 3'd5;
    else if (thresholds[3]) stripe = 3'd4;
    else if (thresholds[2]) stripe = 3'd3;
    else if (thresholds[1]) stripe = 3'd2;
    else if (thresholds[0]) stripe = 3'd1;
  end
endmodule
