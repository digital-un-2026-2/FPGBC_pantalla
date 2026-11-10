`timescale 1ns/1ps
// UC_SUP: six UC bits. No burst scheduling or timing counters here.
module gowin_tx_control #(parameter PROFILE_OK=0) (
    input ref_clk, rst, lock_raw, lock_sync, phy_abort, abort_ref, ev_ref, ready_ref,
    output release_safe, uc_block, ev_raw, output reg clock_fault,
    output reg run_started
);
  localparam [2:0] RESET=3'b000, WAIT_LOCK=3'b001, RELEASE=3'b011,
      WAIT_READY=3'b010, ACTIVE=3'b110, BLOCKED=3'b111;
  (* fsm_encoding="none" *) reg [2:0] state;
  reg abort_seen;
  wire state_ok = state==RESET || state==WAIT_LOCK || state==RELEASE ||
      state==WAIT_READY || state==ACTIVE || state==BLOCKED;
  wire boot_condition = PROFILE_OK && lock_sync && !abort_ref && !ev_ref;
  wire fault = ev_ref || (run_started && (!lock_sync || abort_ref || !PROFILE_OK)) ||
      (state==ACTIVE && !ready_ref);
  wire boot_fire = !rst && state==WAIT_LOCK && boot_condition && !fault;
  wire set_abort = !rst && run_started && phy_abort;
  wire set_pll = !rst && run_started && !lock_raw;
  assign ev_raw = abort_seen | clock_fault;
  assign uc_block = state==BLOCKED || !state_ok;
  assign release_safe = state==RELEASE && !rst && PROFILE_OK && lock_sync &&
      lock_raw && !phy_abort && !ev_raw;

  always @(posedge ref_clk) begin
    if (rst) begin state <= RESET; run_started <= 0; end
    else begin
      if (!state_ok || fault) state <= BLOCKED;
      else case (state)
        RESET: state <= WAIT_LOCK;
        WAIT_LOCK: if (boot_condition) state <= RELEASE;
        RELEASE: state <= WAIT_READY;
        WAIT_READY: if (ready_ref) state <= ACTIVE;
        ACTIVE: state <= ACTIVE;
        BLOCKED: state <= BLOCKED;
        default: state <= BLOCKED;
      endcase
      if (boot_fire) run_started <= 1;
    end
  end
  // Async SET, synchronous reset at REF. SET includes !rst, so coordinated
  // rst has priority. Pulses between REF edges survive loss of FCLK/PCLK.
  always @(posedge ref_clk or posedge set_abort) begin
    if (set_abort) abort_seen <= 1;
    else if (rst) abort_seen <= 0;
  end
  always @(posedge ref_clk or posedge set_pll) begin
    if (set_pll) clock_fault <= 1;
    else if (rst) clock_fault <= 0;
  end
endmodule
