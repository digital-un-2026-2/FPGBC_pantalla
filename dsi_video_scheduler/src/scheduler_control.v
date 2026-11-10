`timescale 1ns / 1ps

module scheduler_control (
    input clk, input rst,
    input cfg_write, input cfg_apply, input panel_set, input panel_clear,
    input start, input cfg_match, input chain_free, input phy_available,
    input external_fault, input error_valid, input urgent_fault, input fault_req,
    input source_start_ready, input cmd_ready, input last_bf,
    input ip_ok, input next_ip_ok, input [1:0] kind,
    input released, input pkt_ok, input end_ok, input stop_next,
    output reg [3:0] state,
    output reg config_ok, output reg panel_initialized,
    output running, output stopped, output frame_active, output event_valid,
    output illegal_state, output hard_block,
    output cfg_accept, output start_accept,
    output source_start_valid, output cmd_valid, output payload_window,
    output source_fire, output descriptor_fire,
    output pkt_window, output frame_window, output stop_window,
    output frame_begin, output event_load, output event_advance,
    output rgb_complete, output frame_complete
);
  localparam [3:0] IDLE=0, ARM=1, LOAD=2, RELEASE=3, CMD=4,
                   PAYLOAD=5, TX_WAIT=6, ADVANCE=7, FINISH=8, FAULT=9;
  // Conserva los diez codigos del diagrama, incluidos los ilegales 10..15.
  // Solo estos seis bits pertenecen a UC.
  assign illegal_state = state > FAULT;
  assign running = state >= ARM && state <= FINISH;
  assign stopped = state == IDLE && chain_free && !error_valid && !rst;
  assign frame_active = state >= LOAD && state <= ADVANCE;
  assign event_valid = state >= RELEASE && state <= TX_WAIT;
  // Nunca depende de fallos locales derivados de DF/BF.
  assign hard_block = rst || illegal_state || state == FAULT || error_valid || urgent_fault;
  assign cfg_accept = cfg_write && stopped;
  assign start_accept = stopped && !hard_block && !external_fault &&
                        !cfg_write && !cfg_apply && !panel_set && !panel_clear &&
                        start && config_ok && panel_initialized && phy_available;
  assign source_start_valid = state == ARM && !hard_block;
  assign cmd_valid = state == CMD && !hard_block;
  assign payload_window = state == PAYLOAD && !hard_block;
  assign source_fire = source_start_valid && source_start_ready;
  assign descriptor_fire = cmd_valid && cmd_ready;
  assign pkt_window = descriptor_fire || state == PAYLOAD || state == TX_WAIT;
  // SF, previo a validar exito, evita realimentar FAULT_REQ por FRAME_BEGIN.
  assign frame_window = source_fire || frame_active;
  assign stop_window = start_accept || running;
  assign frame_begin = source_fire && !fault_req;
  assign event_load = state == LOAD && ip_ok && !hard_block && !fault_req;
  assign event_advance = state == ADVANCE && next_ip_ok && !hard_block && !fault_req;
  assign rgb_complete = state == TX_WAIT && pkt_ok && !hard_block && !fault_req;
  assign frame_complete = state == RELEASE && end_ok && !hard_block && !fault_req;

  (* fsm_encoding = "none" *) reg [3:0] state_reg;
  always @(*) state = state_reg;
  always @(posedge clk) begin
    if (rst) begin
      state_reg <= IDLE;
      config_ok <= 0;
      panel_initialized <= 0;
    end else if (fault_req || error_valid || state == FAULT) begin
      state_reg <= FAULT;
      config_ok <= 0;
      panel_initialized <= 0;
    end else begin
      if (stopped) begin
        if (cfg_write) config_ok <= 0;
        else if (cfg_apply) config_ok <= cfg_match;
        else if (panel_set || panel_clear) panel_initialized <= !panel_clear;
      end
      case (state)
        IDLE: if (start_accept) state_reg <= ARM;
        ARM: if (source_fire) state_reg <= LOAD;
        LOAD: if (ip_ok) state_reg <= RELEASE;
        RELEASE: if (released) begin
          case (kind)
            0: state_reg <= ADVANCE;
            1: state_reg <= CMD;
            2: if (end_ok) state_reg <= FINISH;
          endcase
        end
        CMD: if (descriptor_fire) state_reg <= PAYLOAD;
        PAYLOAD: if (last_bf) state_reg <= TX_WAIT;
        TX_WAIT: if (pkt_ok) state_reg <= ADVANCE;
        ADVANCE: if (next_ip_ok) state_reg <= LOAD;
        FINISH: state_reg <= stop_next ? IDLE : ARM;
        default: state_reg <= FAULT;
      endcase
    end
  end
endmodule
