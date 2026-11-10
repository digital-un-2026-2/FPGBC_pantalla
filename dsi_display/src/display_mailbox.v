`timescale 1ns/1ps

// One outstanding command. Bundled buses remain stable until the return ACK.
// Synchronizers precede either bundled-bus capture. Both sides must reset
// together, including when the byte clock stops; reset assertion is asynchronous.
module display_mailbox (
    input ref_clk, ref_rst, byte_clk, byte_rst,
    input [31:0] command, input command_valid, output command_ready,
    output reg [127:0] response, output reg response_valid,
    output [31:0] byte_command, output byte_valid, input byte_ready,
    input [127:0] byte_response, input byte_response_valid
);
  reg request = 0, acknowledge = 0;
  reg [31:0] held_command;
  reg [127:0] held_response;
  (* async_reg = "true" *) reg [2:0] req_sync = 0, ack_sync = 0;
  reg waiting = 0;
  assign command_ready = !ref_rst && request == ack_sync[2];
  assign byte_valid = !byte_rst && !waiting && req_sync[2] != acknowledge;
  assign byte_command = held_command;
  always @(posedge ref_clk or posedge ref_rst) begin
    if (ref_rst) begin
      request <= 0; ack_sync <= 0; response <= 0; response_valid <= 0;
      held_command <= 0;
    end else begin
      ack_sync <= {ack_sync[1:0], acknowledge};
      response_valid <= 0;
      if (command_valid && command_ready) begin
        held_command <= command;
        request <= !request;
      end
      // Capture only on ACK arrival; the response stays held through the
      // following transaction. Extra stage gives the bundled bus settling time.
      if (ack_sync[2] != ack_sync[1]) begin
        response <= held_response;
        response_valid <= 1;
      end
    end
  end
  always @(posedge byte_clk or posedge byte_rst) begin
    if (byte_rst) begin
      acknowledge <= 0; req_sync <= 0; waiting <= 0; held_response <= 0;
    end else begin
      req_sync <= {req_sync[1:0], request};
      if (byte_valid && byte_ready) waiting <= 1;
      if (waiting && byte_response_valid) begin
        held_response <= byte_response;
        acknowledge <= req_sync[2];
        waiting <= 0;
      end
    end
  end
endmodule
