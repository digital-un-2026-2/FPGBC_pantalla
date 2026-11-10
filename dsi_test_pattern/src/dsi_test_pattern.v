`timescale 1ns / 1ps

// Fuente RGB888: top estructural, un unico dominio posedge clk.
module dsi_test_pattern #(
    parameter integer WIDTH = 720,
    parameter integer HEIGHT = 720
) (
    input clk, input rst,
    input start_valid, output start_ready,
    output [7:0] tx_byte_data,
    output tx_byte_valid, input tx_byte_ready,
    output tx_line_last, output tx_frame_last,
    output busy, output frame_done
);
  wire init, step_comp, step_pixel, step_line;
  wire is_b, x_end, y_end;

  // Rama ausente para parametros legales. Un perfil invalido falla tambien
  // en elaboracion/sintesis, sin depender de ejecutar un initial de simulacion.
  generate
    if (WIDTH < 8 || WIDTH % 8 != 0 || HEIGHT < 1) begin : invalid_dimensions
      DSI_TEST_PATTERN_REQUIRES_WIDTH_MULTIPLE_OF_8_AND_POSITIVE_HEIGHT invalid_config ();
    end
  endgenerate

  test_pattern_control control (
      .clk(clk), .rst(rst), .start_valid(start_valid),
      .tx_byte_ready(tx_byte_ready), .is_b(is_b), .x_end(x_end), .y_end(y_end),
      .init(init), .step_comp(step_comp), .step_pixel(step_pixel), .step_line(step_line),
      .start_ready(start_ready), .tx_byte_valid(tx_byte_valid),
      .busy(busy), .frame_done(frame_done)
  );
  test_pattern_datapath #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) datapath (
      .clk(clk), .rst(rst), .init(init), .step_comp(step_comp),
      .step_pixel(step_pixel), .step_line(step_line), .tx_byte_valid(tx_byte_valid),
      .is_b(is_b), .x_end(x_end), .y_end(y_end),
      .tx_byte_data(tx_byte_data), .tx_line_last(tx_line_last),
      .tx_frame_last(tx_frame_last)
  );
endmodule
