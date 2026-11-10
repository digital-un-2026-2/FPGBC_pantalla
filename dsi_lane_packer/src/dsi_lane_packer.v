`timescale 1ns / 1ps

// Agrupación lógica por paquete. keep=01 NO autoriza transmitir padding.
module dsi_lane_packer (
    input clk, input rst,
    input [7:0] tx_byte_data,
    input tx_byte_valid, input tx_byte_last,
    output tx_byte_ready,
    output [15:0] tx_word_data,
    output [1:0] tx_word_keep,
    output tx_word_valid, output tx_word_last,
    input tx_word_ready
);
  wire ld_first, ld_second, rst_dp;

  lane_control control (
      .clk(clk), .rst(rst),
      .tx_byte_valid(tx_byte_valid), .tx_byte_last(tx_byte_last),
      .tx_word_ready(tx_word_ready),
      .tx_byte_ready(tx_byte_ready), .tx_word_valid(tx_word_valid),
      .ld_first(ld_first), .ld_second(ld_second), .rst_dp(rst_dp)
  );

  lane_datapath datapath (
      .clk(clk), .rst_dp(rst_dp),
      .tx_byte_data(tx_byte_data), .tx_byte_last(tx_byte_last),
      .ld_first(ld_first), .ld_second(ld_second),
      .tx_word_data(tx_word_data), .tx_word_keep(tx_word_keep),
      .tx_word_last(tx_word_last)
  );
endmodule
