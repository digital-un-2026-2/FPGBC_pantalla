`timescale 1ns / 1ps

// Top estructural: contrato logico, sin PHY electrica ni primitivas Gowin.
module dsi_hs_transport #(parameter integer BUFFER_WORDS = 2048) (
    input clk, input rst,
    input [15:0] tx_word_data, input [1:0] tx_word_keep,
    input tx_word_valid, input tx_word_last, output tx_word_ready,
    output hs_req, input hs_req_ready, output hs_data_ready,
    input hs_grant, output hs_done, output hs_error,
    input hs_complete, input phy_abort,
    output [15:0] hs_word_data, output [1:0] hs_word_keep,
    output hs_word_valid, output hs_word_last,
    output busy, output error, output [1:0] error_code
);
  wire mask_ok, full, occupied, final_word;
  wire write_en, read_en, prime, advance, clear_count;

  initial begin
    if (BUFFER_WORDS < 1) $fatal(1, "BUFFER_WORDS must be positive");
  end
  assign hs_error = error;
  assign hs_word_last = final_word;

  hs_transport_control control (
      .clk(clk), .rst(rst), .phy_abort(phy_abort),
      .valid(tx_word_valid), .last(tx_word_last),
      .mask_ok(mask_ok), .full(full), .occupied(occupied), .final_word(final_word),
      .hs_req_ready(hs_req_ready), .hs_grant(hs_grant), .hs_complete(hs_complete),
      .ready(tx_word_ready), .req(hs_req), .data_ready(hs_data_ready),
      .out_valid(hs_word_valid), .write_en(write_en), .read_en(read_en),
      .prime(prime), .advance(advance), .clear_count(clear_count),
      .busy(busy), .error(error), .error_code(error_code), .done(hs_done)
  );
  hs_transport_datapath #(.BUFFER_WORDS(BUFFER_WORDS)) datapath (
      .clk(clk), .rst(rst), .data_in(tx_word_data), .keep_in(tx_word_keep),
      .last_in(tx_word_last), .write_en(write_en), .read_en(read_en),
      .prime(prime), .advance(advance), .clear_count(clear_count),
      .mask_ok(mask_ok), .full(full), .occupied(occupied), .final_word(final_word),
      .data_out(hs_word_data), .keep_out(hs_word_keep)
  );
endmodule
