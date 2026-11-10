`timescale 1ns / 1ps

// FSM aprobada: siete fases; UC y datapath comparten posedge.
module hs_transport_control (
    input clk, input rst, input phy_abort,
    input valid, input last, input mask_ok, input full,
    input occupied, input final_word,
    input hs_req_ready, input hs_grant, input hs_complete,
    output reg ready, output reg req, output reg data_ready,
    output reg out_valid,
    output reg write_en, output reg read_en, output reg prime,
    output reg advance, output reg clear_count,
    output reg busy, output reg error,
    output reg [1:0] error_code, output reg done
);
  localparam [2:0] FILL = 3'b000, PRIME = 3'b001, REQUEST = 3'b010,
                   WAIT_GRANT = 3'b011, SEND = 3'b100,
                   WAIT_COMPLETE = 3'b101, FAULT = 3'b110;
  reg [2:0] state;
  reg done_reg;
  reg [1:0] cause_reg;

  // Memoria de fase, pulso y primera causa. Sin next_state ni ACTION.
  always @(posedge clk) begin
    if (rst) begin
      state <= FILL;
      done_reg <= 1'b0;
      cause_reg <= 2'b00;
    end else begin
      done_reg <= 1'b0;
      if (state == FAULT) begin
        state <= FAULT;
      end else if (phy_abort) begin
        state <= FAULT;
        cause_reg <= 2'b11;
      end else begin
        case (state)
          FILL: if (valid) begin
            if (!mask_ok) begin
              state <= FAULT;
              cause_reg <= 2'b10;
            end else if (full && !last) begin
              state <= FAULT;
              cause_reg <= 2'b01;
            end else if (last) state <= PRIME;
          end
          PRIME: state <= REQUEST;
          REQUEST: if (hs_req_ready) state <= WAIT_GRANT;
          WAIT_GRANT: if (hs_grant) state <= SEND;
          SEND: begin
            if (!hs_grant) begin
              state <= FAULT;
              cause_reg <= 2'b11;
            end else if (final_word) begin
              state <= WAIT_COMPLETE;
              done_reg <= 1'b1;
            end
          end
          WAIT_COMPLETE: if (hs_complete) state <= FILL;
          default: begin
            state <= FAULT;
            cause_reg <= 2'b11;
          end
        endcase
      end
    end
  end

  // Enables presentes ANTES del flanco: captura en el mismo posedge.
  always @(*) begin
    ready = 1'b0;
    req = 1'b0;
    data_ready = 1'b0;
    out_valid = 1'b0;
    write_en = 1'b0;
    read_en = 1'b0;
    prime = (state == PRIME);
    advance = 1'b0;
    clear_count = 1'b0;
    busy = (state != FILL) || occupied;
    error = (state == FAULT);
    error_code = cause_reg;
    done = !rst && !phy_abort && done_reg;

    if (!rst && !phy_abort) begin
      case (state)
        FILL: begin
          ready = 1'b1;
          write_en = valid && mask_ok;
        end
        PRIME: read_en = 1'b1;
        REQUEST: begin
          req = 1'b1;
          data_ready = 1'b1;
        end
        WAIT_GRANT: data_ready = 1'b1;
        SEND: begin
          data_ready = 1'b1;
          out_valid = hs_grant;
          read_en = hs_grant && !final_word;
          advance = hs_grant && !final_word;
        end
        WAIT_COMPLETE: clear_count = hs_complete;
        default: begin end
      endcase
    end
  end
endmodule
