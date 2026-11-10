`timescale 1ns / 1ps

module packet_control (
    input clk,
    input rst,
    input cmd_valid,
    input tx_byte_ready,
    input z_last,

    output ld_packet,
    output rst_byte,
    output inc_byte,
    output cmd_ready,
    output tx_byte_valid,
    output busy,
    output reg packet_done
);

  localparam IDLE = 1'b0;
  localparam SEND = 1'b1;

  reg state;
  wire cmd_fire = cmd_valid && cmd_ready;
  wire tx_fire = tx_byte_valid && tx_byte_ready;
  wire fin_evt = tx_fire && z_last;

  assign cmd_ready = (state == IDLE) && !rst;
  assign tx_byte_valid = (state == SEND) && !rst;
  assign busy = (state == SEND);

  assign ld_packet = cmd_fire;
  assign rst_byte = rst || cmd_fire;
  assign inc_byte = tx_fire && !z_last;

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      packet_done <= 1'b0;
    end else begin
      // El pulso coincide con IDLE tras entregar el cuarto byte.
      packet_done <= fin_evt;
      case (state)
        IDLE: if (cmd_fire) state <= SEND;
        SEND: if (fin_evt) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end

endmodule
