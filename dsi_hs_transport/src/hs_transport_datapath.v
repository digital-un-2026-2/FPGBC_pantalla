`timescale 1ns / 1ps

module hs_transport_datapath #(
    parameter integer BUFFER_WORDS = 2048
) (
    input clk, input rst,
    input [15:0] data_in, input [1:0] keep_in, input last_in,
    input write_en, input read_en, input prime, input advance, input clear_count,
    output mask_ok, output full, output occupied, output final_word,
    output [15:0] data_out, output [1:0] keep_out
);
  localparam integer A = (BUFFER_WORDS > 1) ? $clog2(BUFFER_WORDS) : 1;
  localparam [A:0] LAST_POSITION = BUFFER_WORDS - 1;
  wire [A:0] count, count_next, count_minus_one;
  wire [A-1:0] index, index_next, read_address;
  wire [17:0] q;
  wire rst_dp = rst || clear_count;

  hs_transport_add #(.BITS(A+1)) sigma0 (
      .data_in(count), .data_out(count_next)
  );
  hs_transport_register #(.BITS(A+1)) count_reg (
      .clk(clk), .rst(rst_dp), .ld(write_en),
      .reg_in(count_next), .reg_out(count)
  );
  hs_transport_add #(.BITS(A)) sigma1 (
      .data_in(index), .data_out(index_next)
  );
  hs_transport_register #(.BITS(A)) index_reg (
      .clk(clk), .rst(rst_dp), .ld(advance),
      .reg_in(index_next), .reg_out(index)
  );
  hs_transport_add #(.BITS(A+1), .SUBTRACT(1)) sigma2 (
      .data_in(count), .data_out(count_minus_one)
  );
  hs_transport_mux #(.BITS(A)) m0 (
      .in0(index_next), .in1({A{1'b0}}), .sel(prime), .data_out(read_address)
  );
  hs_transport_memory #(.WORDS(BUFFER_WORDS)) ram (
      .clk(clk), .write_en(write_en), .read_en(read_en),
      .write_address(count[A-1:0]), .read_address(read_address),
      .data_in({keep_in, data_in}), .q(q)
  );
  hs_transport_compare #(.BITS(A+1)) c0 (
      .a(count), .b(LAST_POSITION), .z(full)
  );
  hs_transport_compare #(.BITS(A+1), .NOT_EQUAL(1)) c1 (
      .a(count), .b({(A+1){1'b0}}), .z(occupied)
  );
  hs_transport_compare #(.BITS(A+1)) c2 (
      .a({1'b0, index}), .b(count_minus_one), .z(final_word)
  );
  // L0: validacion combinacional de mascara. No se almacena last por palabra.
  assign mask_ok = (keep_in == 2'b11) || ((keep_in == 2'b01) && last_in);
  assign data_out = q[15:0];
  assign keep_out = q[17:16];
endmodule
