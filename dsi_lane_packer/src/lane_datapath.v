`timescale 1ns / 1ps

module lane_datapath (
    input clk, input rst_dp,
    input [7:0] tx_byte_data, input tx_byte_last,
    input ld_first, input ld_second,
    output [15:0] tx_word_data,
    output [1:0] tx_word_keep,
    output tx_word_last
);
  wire ld_meta = ld_first | ld_second;
  wire [7:0] high_in;
  wire second_valid;

  lane_mux #(.INPUTS(2), .BITS(8)) m0 (
      .data_in({tx_byte_data, 8'h00}), .sel(ld_second), .data_out(high_in)
  );

  // WORD [16]: dos secciones de 8 bits con enables independientes.
  lane_register #(.BITS(8)) word_lo (
      .clk(clk), .rst(rst_dp), .reg_in(tx_byte_data),
      .ld(ld_first), .reg_out(tx_word_data[7:0])
  );
  lane_register #(.BITS(8)) word_hi (
      .clk(clk), .rst(rst_dp), .reg_in(high_in),
      .ld(ld_meta), .reg_out(tx_word_data[15:8])
  );
  lane_register #(.BITS(1)) second (
      .clk(clk), .rst(rst_dp), .reg_in(ld_second),
      .ld(ld_meta), .reg_out(second_valid)
  );
  lane_register #(.BITS(1)) last (
      .clk(clk), .rst(rst_dp), .reg_in(tx_byte_last),
      .ld(ld_meta), .reg_out(tx_word_last)
  );

  assign tx_word_keep = {second_valid, 1'b1};
endmodule
