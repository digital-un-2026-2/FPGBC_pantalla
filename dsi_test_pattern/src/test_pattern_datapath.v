`timescale 1ns / 1ps

module test_pattern_datapath #(
    parameter integer WIDTH = 720,
    parameter integer HEIGHT = 720
) (
    input clk, input rst,
    input init, input step_comp, input step_pixel, input step_line,
    input tx_byte_valid,
    output is_b, output x_end, output y_end,
    output [7:0] tx_byte_data, output tx_line_last, output tx_frame_last
);
  localparam integer NX = WIDTH > 1 ? $clog2(WIDTH) : 1;
  localparam integer NY = HEIGHT > 1 ? $clog2(HEIGHT) : 1;
  localparam [NX-1:0] LAST_X = WIDTH - 1;
  localparam [NY-1:0] LAST_Y = HEIGHT - 1;
  wire [NX-1:0] x, x_plus, x_in;
  wire [NY-1:0] y, y_plus, y_in;
  wire [1:0] comp, comp_plus, comp_in;
  wire [6:0] thresholds;
  wire [2:0] stripe;
  wire [23:0] rgb;
  wire [7:0] component_byte;
  wire line_end = is_b & x_end;
  wire frame_end = line_end & y_end;

  test_pattern_add #(.BITS(NX)) a0 (.data_in(x), .data_out(x_plus));
  test_pattern_add #(.BITS(NY)) a1 (.data_in(y), .data_out(y_plus));
  test_pattern_add #(.BITS(2)) a2 (.data_in(comp), .data_out(comp_plus));
  test_pattern_mux #(.BITS(NX)) m0 (
      .data_in({x_plus, {NX{1'b0}}}), .sel(step_pixel), .data_out(x_in)
  );
  test_pattern_mux #(.BITS(NY)) m1 (
      .data_in({y_plus, {NY{1'b0}}}), .sel(step_line), .data_out(y_in)
  );
  test_pattern_mux #(.BITS(2)) m2 (
      .data_in({comp_plus, 2'b00}), .sel(step_comp), .data_out(comp_in)
  );
  test_pattern_register #(.BITS(NX)) r_x (
      .clk(clk), .rst(rst), .reg_in(x_in),
      .ld(init | step_pixel | step_line), .reg_out(x)
  );
  test_pattern_register #(.BITS(NY)) r_y (
      .clk(clk), .rst(rst), .reg_in(y_in), .ld(init | step_line), .reg_out(y)
  );
  test_pattern_register #(.BITS(2)) r_c (
      .clk(clk), .rst(rst), .reg_in(comp_in),
      .ld(init | step_comp | step_pixel | step_line), .reg_out(comp)
  );
  test_pattern_compare #(.BITS(NX)) cx (.a(x), .b(LAST_X), .z(x_end));
  test_pattern_compare #(.BITS(NY)) cy (.a(y), .b(LAST_Y), .z(y_end));
  test_pattern_compare #(.BITS(2)) cc (.a(comp), .b(2'd2), .z(is_b));

  // C1..C7: constantes de elaboracion del mismo ancho que X. Sin divisor.
  genvar i;
  generate
    for (i = 1; i <= 7; i = i + 1) begin : stripe_threshold
      localparam [NX-1:0] LIMIT = i * (WIDTH / 8);
      test_pattern_compare #(.BITS(NX), .GREATER_EQUAL(1)) comparator (
          .a(x), .b(LIMIT), .z(thresholds[i-1])
      );
    end
  endgenerate
  test_pattern_priority p0 (.thresholds(thresholds), .stripe(stripe));
  test_pattern_mux #(.INPUTS(8), .BITS(24)) m3 (
      .data_in({24'h000000, 24'h0000ff, 24'hff0000, 24'hff00ff,
                24'h00ff00, 24'h00ffff, 24'hffff00, 24'hffffff}),
      .sel(stripe), .data_out(rgb)
  );
  test_pattern_mux #(.INPUTS(4), .BITS(8)) m4 (
      .data_in({8'h00, rgb[7:0], rgb[15:8], rgb[23:16]}),
      .sel(comp), .data_out(component_byte)
  );
  test_pattern_mux #(.BITS(8)) m5 (
      .data_in({component_byte, 8'h00}), .sel(tx_byte_valid), .data_out(tx_byte_data)
  );
  assign tx_line_last = tx_byte_valid & line_end;
  assign tx_frame_last = tx_byte_valid & frame_end;
endmodule
