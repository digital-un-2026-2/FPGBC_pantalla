`timescale 1ns / 1ps

module lane_control (
    input clk, input rst,
    input tx_byte_valid, input tx_byte_last, input tx_word_ready,
    output reg tx_byte_ready, output reg tx_word_valid,
    output reg ld_first, output reg ld_second, output reg rst_dp
);
  localparam [1:0] EMPTY = 2'b00, HALF = 2'b01, OUTPUT = 2'b10;
  reg [1:0] state;
  wire byte_fire = tx_byte_valid && tx_byte_ready;
  wire word_fire = tx_word_valid && tx_word_ready;

  // Solo memoria de fase. Sin next_state ni controles registrados.
  always @(posedge clk) begin
    if (rst) begin
      state <= EMPTY;
    end else begin
      case (state)
        EMPTY: if (byte_fire) state <= tx_byte_last ? OUTPUT : HALF;
        HALF: if (byte_fire) state <= OUTPUT;
        OUTPUT: if (word_fire) state <= EMPTY;
        default: state <= EMPTY;
      endcase
    end
  end

  // Las cargas se aplican al mismo posedge que acepta el byte.
  always @(*) begin
    tx_byte_ready = 1'b0;
    tx_word_valid = 1'b0;
    ld_first = 1'b0;
    ld_second = 1'b0;
    rst_dp = rst;
    case (state)
      EMPTY: begin
        tx_byte_ready = !rst;
        ld_first = !rst && tx_byte_valid;
      end
      HALF: begin
        tx_byte_ready = !rst;
        ld_second = !rst && tx_byte_valid;
      end
      OUTPUT: tx_word_valid = !rst;
      // Codigo 11: bloquear handshakes y borrar datos al recuperar EMPTY.
      default: rst_dp = 1'b1;
    endcase
  end
endmodule
