`timescale 1ns/1ps
// UC: sequential transitions, combinational controls. No next_state/ACTION.
module hs_phy_control (
    input clk, rst, phy_abort,
    input cs, ds, dt, ct, valid, last, grant,
    input p_valid, p_last, a_valid, a_last, mask_ok, time_last, post_last,
    output reg capture, move, retire, clear_pipe,
    output reg [1:0] sel_word, output reg [3:0] time_sel,
    output reg time_load, time_step, post_load, post_step,
    output reg clk_prepared, data_prepared, data_stopped, clk_stopped,
    output reg local_stop, hs_data_on, hs_clk_on, clk_toggle,
    output reg [1:0] lp_clk, lp_d0, lp_d1,
    output phy_error, output [2:0] error_code
);
  localparam [4:0] BOOT = 5'd0;
  localparam [4:0] INIT = 5'd1;
  localparam [4:0] IDLE = 5'd2;
  localparam [4:0] CLK_LPX = 5'd3;
  localparam [4:0] CLK_PREP = 5'd4;
  localparam [4:0] CLK_ZERO = 5'd5;
  localparam [4:0] CLK_PRE = 5'd6;
  localparam [4:0] WAIT_DATA = 5'd7;
  localparam [4:0] DATA_LPX = 5'd8;
  localparam [4:0] DATA_PREP = 5'd9;
  localparam [4:0] DATA_ZERO = 5'd10;
  localparam [4:0] WAIT_WORD = 5'd11;
  localparam [4:0] SYNC_OPEN = 5'd12;
  localparam [4:0] SYNC_CLOSED = 5'd13;
  localparam [4:0] STREAM_OPEN = 5'd14;
  localparam [4:0] DRAIN_PENDING = 5'd15;
  localparam [4:0] FINAL = 5'd16;
  localparam [4:0] DATA_TRAIL = 5'd17;
  localparam [4:0] DATA_EXIT = 5'd18;
  localparam [4:0] WAIT_CLK_STOP = 5'd19;
  localparam [4:0] CLK_TRAIL = 5'd20;
  localparam [4:0] CLK_EXIT = 5'd21;
  localparam [4:0] RETURN = 5'd22;
  localparam [4:0] ABORT_EXIT = 5'd23;
  localparam [4:0] HALTED = 5'd24;
  reg [4:0] state;
  reg [2:0] cause;
  reg [2:0] fault;
  reg nominal_load;
  reg [3:0] nominal_sel;
  wire recovery = (state == ABORT_EXIT) || (state == HALTED);
  wire rx_open = (state == WAIT_WORD) || (state == SYNC_OPEN) || (state == STREAM_OPEN);
  wire bad_pipe =
    ((state == WAIT_WORD) && (p_valid || a_valid)) ||
    ((state == SYNC_OPEN || state == SYNC_CLOSED) &&
      (!p_valid || a_valid || (p_last != (state == SYNC_CLOSED)))) ||
    ((state == STREAM_OPEN || state == DRAIN_PENDING) &&
      (!p_valid || !a_valid || a_last || (p_last != (state == DRAIN_PENDING)))) ||
    ((state == FINAL) && (!a_valid || !a_last || p_valid));
  wire bad_protocol =
    (valid && (!rx_open || !grant)) ||
    (ct && !(state == WAIT_CLK_STOP || state == CLK_TRAIL || state == CLK_EXIT || state == RETURN)) ||
    (dt && !(state == SYNC_CLOSED || state == DRAIN_PENDING || state == FINAL ||
      state == DATA_TRAIL || state == DATA_EXIT || state == WAIT_CLK_STOP || state == RETURN)) ||
    (ds && !((state >= WAIT_DATA && state <= WAIT_CLK_STOP) || state == RETURN)) ||
    (cs && !((state >= IDLE && state <= WAIT_CLK_STOP) || state == RETURN)) ||
    ((state >= CLK_LPX && state <= DATA_EXIT) && !cs) ||
    ((state == DATA_LPX || state == DATA_PREP || state == DATA_ZERO ||
      state == WAIT_WORD || state == SYNC_OPEN || state == STREAM_OPEN) && !ds) ||
    (grant && !((state >= DATA_ZERO && state <= DATA_TRAIL) || state == RETURN)) ||
    ((state == SYNC_OPEN || state == STREAM_OPEN) && !grant) ||
    ((state == FINAL) && !dt);
  assign phy_error = (cause != 0);
  assign error_code = cause;

  // Nominal selector validation precedes the fault override. This avoids
  // feeding effective TIME_SEL_OK back through the abort selector.
  always @(*) begin
    nominal_load = 0;
    nominal_sel = 0;
    case (state)
      BOOT: begin nominal_load=1; nominal_sel=0; end
      IDLE: if (cs) begin nominal_load=1; nominal_sel=1; end
      CLK_LPX: if (time_last) begin nominal_load=1; nominal_sel=2; end
      CLK_PREP: if (time_last) begin nominal_load=1; nominal_sel=3; end
      CLK_ZERO: if (time_last) begin nominal_load=1; nominal_sel=4; end
      WAIT_DATA: if (ds) begin nominal_load=1; nominal_sel=1; end
      DATA_LPX: if (time_last) begin nominal_load=1; nominal_sel=5; end
      DATA_PREP: if (time_last) begin nominal_load=1; nominal_sel=6; end
      FINAL: begin nominal_load=1; nominal_sel=7; end
      DATA_TRAIL: if (time_last) begin nominal_load=1; nominal_sel=8; end
      WAIT_CLK_STOP: if (ct && post_last) begin nominal_load=1; nominal_sel=9; end
      CLK_TRAIL: if (time_last) begin nominal_load=1; nominal_sel=8; end
      default: begin end
    endcase
  end

  always @(*) begin
    fault=0;
    if (state > HALTED) fault=5;
    else if (nominal_load && nominal_sel > 9) fault=6;
    else if (bad_pipe) fault=4;
    else if (rx_open && valid && !mask_ok) fault=1;
    else if (bad_protocol) fault=3;
    else if ((state == SYNC_OPEN || state == STREAM_OPEN) && !valid) fault=2;
  end

  always @(posedge clk) begin
    if (rst) begin state<=BOOT; cause<=0; end
    else if (state == ABORT_EXIT) begin
      if (time_last) state<=HALTED;
    end else if (state == HALTED) begin end
    else if (phy_abort) state<=ABORT_EXIT;
    else if (fault != 0) begin
      state<=ABORT_EXIT;
      if (cause == 0) cause<=fault;
    end else begin
      case (state)
        BOOT: state<=INIT;
        INIT: if (time_last) state<=IDLE;
        IDLE: if (cs) state<=CLK_LPX;
        CLK_LPX: if (time_last) state<=CLK_PREP;
        CLK_PREP: if (time_last) state<=CLK_ZERO;
        CLK_ZERO: if (time_last) state<=CLK_PRE;
        CLK_PRE: if (time_last) state<=WAIT_DATA;
        WAIT_DATA: if (ds) state<=DATA_LPX;
        DATA_LPX: if (time_last) state<=DATA_PREP;
        DATA_PREP: if (time_last) state<=DATA_ZERO;
        DATA_ZERO: if (time_last) state<=WAIT_WORD;
        WAIT_WORD: if (valid) state<=last ? SYNC_CLOSED : SYNC_OPEN;
        SYNC_OPEN, STREAM_OPEN: state<=last ? DRAIN_PENDING : STREAM_OPEN;
        SYNC_CLOSED, DRAIN_PENDING: state<=FINAL;
        FINAL: state<=DATA_TRAIL;
        DATA_TRAIL: if (time_last) state<=DATA_EXIT;
        DATA_EXIT: if (time_last) state<=WAIT_CLK_STOP;
        WAIT_CLK_STOP: if (ct && post_last) state<=CLK_TRAIL;
        CLK_TRAIL: if (time_last) state<=CLK_EXIT;
        CLK_EXIT: if (time_last) state<=RETURN;
        RETURN: if (!(cs || ds || dt || ct || grant)) state<=IDLE;
        default: state<=ABORT_EXIT;
      endcase
    end
  end

  always @(*) begin
    capture=0; move=0; retire=0; clear_pipe=0;
    sel_word=0; time_sel=nominal_sel; time_load=nominal_load;
    time_step=0; post_load=0; post_step=0;
    clk_prepared=0; data_prepared=0; data_stopped=0; clk_stopped=0;
    local_stop=0; hs_data_on=0; hs_clk_on=0; clk_toggle=0;
    lp_clk=2'b11; lp_d0=2'b11; lp_d1=2'b11;
    case (state)
      INIT, CLK_LPX, CLK_PREP, CLK_ZERO, CLK_PRE, DATA_LPX,
      DATA_PREP, DATA_ZERO, DATA_TRAIL, DATA_EXIT, CLK_TRAIL,
      CLK_EXIT, ABORT_EXIT: time_step=1;
      default: begin end
    endcase
    if (state >= CLK_ZERO && state <= CLK_TRAIL) begin hs_clk_on=1; lp_clk=0; end
    if (state >= CLK_PRE && state <= WAIT_CLK_STOP) clk_toggle=1;
    if (state >= DATA_ZERO && state <= DATA_TRAIL) begin hs_data_on=1; lp_d0=0; lp_d1=0; end
    if (state >= WAIT_DATA && state <= WAIT_CLK_STOP) clk_prepared=1;
    if (state >= WAIT_WORD && state <= FINAL) data_prepared=1;
    if (state >= WAIT_CLK_STOP && state <= RETURN) data_stopped=1;
    if (state == RETURN) clk_stopped=1;
    if (state == IDLE || state == RETURN || state == HALTED) local_stop=1;
    if (state == CLK_LPX) lp_clk=2'b01;
    if (state == CLK_PREP) lp_clk=0;
    if (state == DATA_LPX) begin lp_d0=2'b01; lp_d1=2'b01; end
    if (state == DATA_PREP) begin lp_d0=0; lp_d1=0; end
    if (state == SYNC_OPEN || state == SYNC_CLOSED) sel_word=1;
    if (state == STREAM_OPEN || state == DRAIN_PENDING || state == FINAL) sel_word=2;
    if (state == DATA_TRAIL) sel_word=3;
    if (rx_open && valid && grant && mask_ok) capture=1;
    if (state == SYNC_OPEN || state == SYNC_CLOSED || state == STREAM_OPEN || state == DRAIN_PENDING) move=1;
    if (state == STREAM_OPEN || state == DRAIN_PENDING || state == FINAL) retire=1;
    if (state == BOOT || (state == IDLE && cs)) clear_pipe=1;
    if (state == DATA_TRAIL && time_last) post_load=1;
    if (state == DATA_EXIT || state == WAIT_CLK_STOP) post_step=1;

    if (recovery) begin
      capture=0; move=0; retire=0; clear_pipe=0;
      time_load=0; time_sel=0; post_load=0; post_step=0;
    end else if (phy_abort || fault != 0) begin
      capture=0; move=0; retire=0; clear_pipe=1;
      time_load=1; time_sel=8; time_step=0; post_load=0; post_step=0;
    end
    if (rst || phy_abort) begin
      capture=0; move=0; retire=0;
      hs_clk_on=0; clk_toggle=0; hs_data_on=0;
      lp_clk=2'b11; lp_d0=2'b11; lp_d1=2'b11;
      clk_prepared=0; data_prepared=0; data_stopped=0; clk_stopped=0;
      local_stop=!rst && state == HALTED;
    end
    if (rst) begin
      clear_pipe=0; time_load=0; time_step=0; post_load=0; post_step=0;
    end
  end
endmodule
