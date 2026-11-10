`timescale 1ns / 1ps

module long_packet_control (
    input clk,
    input rst,
    input cmd_valid,
    input payload_valid,
    input tx_byte_ready,
    input z_header_last,
    input z_payload_done,
    input z_crc_last,

    output ld_desc,
    output ld_payload,
    output init_crc,
    output upd_crc,
    output clr_header,
    output inc_header,
    output clr_payload,
    output inc_payload,
    output clr_crc,
    output inc_crc,
    output [1:0] sel_tx,
    output cmd_ready,
    output payload_ready,
    output tx_byte_valid,
    output tx_byte_last,
    output busy,
    output reg packet_done
);
  localparam [2:0] IDLE = 3'd0,
                   SEND_HEADER = 3'd1,
                   CHECK_PAYLOAD = 3'd2,
                   WAIT_PAYLOAD = 3'd3,
                   SEND_PAYLOAD = 3'd4,
                   SEND_CRC = 3'd5;
  reg [2:0] state;
  wire cmd_fire = cmd_valid && cmd_ready;
  wire pay_fire = payload_valid && payload_ready;
  wire tx_fire = tx_byte_valid && tx_byte_ready;
  wire fin_evt = (state == SEND_CRC) && tx_fire && z_crc_last;

  assign cmd_ready = (state == IDLE) && !rst;
  assign payload_ready = (state == WAIT_PAYLOAD) && !rst;
  assign tx_byte_valid = !rst && ((state == SEND_HEADER) ||
                                (state == SEND_PAYLOAD) || (state == SEND_CRC));
  assign tx_byte_last = (state == SEND_CRC) && z_crc_last;
  assign busy = (state != IDLE);
  assign sel_tx = (state == SEND_PAYLOAD) ? 2'd1 :
                  (state == SEND_CRC) ? 2'd2 : 2'd0;

  assign ld_desc = cmd_fire;
  assign ld_payload = pay_fire;
  assign init_crc = cmd_fire;
  assign upd_crc = (state == SEND_PAYLOAD) && tx_fire;
  assign clr_header = cmd_fire;
  assign clr_payload = cmd_fire;
  assign clr_crc = cmd_fire;
  assign inc_header = (state == SEND_HEADER) && tx_fire && !z_header_last;
  assign inc_payload = (state == SEND_PAYLOAD) && tx_fire;
  assign inc_crc = (state == SEND_CRC) && tx_fire && !z_crc_last;

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      packet_done <= 1'b0;
    end else begin
      packet_done <= fin_evt;
      case (state)
        IDLE: if (cmd_fire) state <= SEND_HEADER;
        SEND_HEADER: if (tx_fire && z_header_last) state <= CHECK_PAYLOAD;
        CHECK_PAYLOAD: state <= z_payload_done ? SEND_CRC : WAIT_PAYLOAD;
        WAIT_PAYLOAD: if (pay_fire) state <= SEND_PAYLOAD;
        SEND_PAYLOAD: if (tx_fire) state <= CHECK_PAYLOAD;
        SEND_CRC: if (fin_evt) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
