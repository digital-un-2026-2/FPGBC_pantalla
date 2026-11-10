`timescale 1ns / 1ps

module test_pattern_control (
    input clk, input rst, input start_valid, input tx_byte_ready,
    input is_b, input x_end, input y_end,
    output reg init, output reg step_comp, output reg step_pixel, output reg step_line,
    output start_ready, output tx_byte_valid, output busy, output reg frame_done
);
  localparam IDLE = 1'b0, STREAM = 1'b1;
  (* fsm_encoding = "none" *) reg state;
  wire start_fire = start_valid && start_ready;
  wire byte_fire = tx_byte_valid && tx_byte_ready;
  reg finish;

  assign start_ready = !rst && state == IDLE;
  assign tx_byte_valid = !rst && state == STREAM;
  assign busy = state == STREAM;

  // STATE[1] y R_DONE[1]. Sin next_state ni acciones registradas.
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      frame_done <= 1'b0;
    end else begin
      case (state)
        IDLE: if (start_fire) state <= STREAM;
        STREAM: if (finish) state <= IDLE;
      endcase
      frame_done <= finish;
    end
  end

  // Controles antes del mismo flanco que acepta inicio/byte.
  always @(*) begin
    init = 1'b0;
    step_comp = 1'b0;
    step_pixel = 1'b0;
    step_line = 1'b0;
    finish = 1'b0;
    case (state)
      IDLE: init = start_fire;
      STREAM: begin
        if (byte_fire) begin
          if (!is_b) step_comp = 1'b1;
          else if (!x_end) step_pixel = 1'b1;
          else if (!y_end) step_line = 1'b1;
          else finish = 1'b1;
        end
      end
    endcase
  end
endmodule
