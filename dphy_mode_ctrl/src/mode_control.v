`timescale 1ns / 1ps

module mode_control (
    input clk, input rst,
    input lp_fire, input hs_fire, input hs_fault, input pll_locked,
    input lp_done, input hs_done,
    input clk_prepared, input data_prepared, input hs_data_ready,
    input data_stopped, input clk_stopped, input stop_ready, input clear_error,
    output reg arb_libre, output reg hs_active,
    output reg fault_active, output reg busy_ctrl, output reg [5:0] intents,
    output reg take_lp, output reg take_hs,
    output reg ld_err, output reg [1:0] sel_err, output reg pll_cause,
    output reg fin_lp_evt, output reg fin_hs_evt
);
  localparam [3:0] IDLE = 4'd0;
  localparam [3:0] LP_OWNED = 4'd1;
  localparam [3:0] LP_RETURN = 4'd2;
  localparam [3:0] HS_CLK_PREPARE = 4'd3;
  localparam [3:0] HS_DATA_PREPARE = 4'd4;
  localparam [3:0] HS_TRANSFER = 4'd5;
  localparam [3:0] HS_DATA_STOP = 4'd6;
  localparam [3:0] HS_CLK_STOP = 4'd7;
  localparam [3:0] HS_RETURN = 4'd8;
  localparam [3:0] FAULT = 4'd9;

  // Accion decidida en posedge, aplicada por el datapath en el negedge siguiente.
  // Conserva tambien la causa aunque PLL/error cambien despues del posedge.
  localparam [3:0] A_NONE = 4'd0;
  localparam [3:0] A_TAKE_LP = 4'd1;
  localparam [3:0] A_TAKE_HS = 4'd2;
  localparam [3:0] A_PLL_ERROR = 4'd3;
  localparam [3:0] A_HS_ERROR = 4'd4;
  localparam [3:0] A_INVALID = 4'd5;
  localparam [3:0] A_CLEAR = 4'd6;
  localparam [3:0] A_FIN_LP = 4'd7;
  localparam [3:0] A_FIN_HS = 4'd8;

  reg [3:0] state;
  reg [3:0] action;

  // Transiciones exclusivamente secuenciales. No hay next_state combinacional.
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      action <= A_NONE;
    end else begin
      action <= A_NONE;
      if (hs_fault) begin
        state <= FAULT;
        action <= !pll_locked ? A_PLL_ERROR : A_HS_ERROR;
      end else begin
        case (state)
          IDLE: begin
            if (lp_fire) begin
              state <= LP_OWNED;
              action <= A_TAKE_LP;
            end else if (hs_fire) begin
              state <= HS_CLK_PREPARE;
              action <= A_TAKE_HS;
            end
          end
          LP_OWNED: if (lp_done) state <= LP_RETURN;
          LP_RETURN: begin
            if (stop_ready) begin state <= IDLE; action <= A_FIN_LP; end
          end
          HS_CLK_PREPARE: if (clk_prepared) state <= HS_DATA_PREPARE;
          HS_DATA_PREPARE: begin
            if (data_prepared && hs_data_ready) state <= HS_TRANSFER;
          end
          HS_TRANSFER: if (hs_done) state <= HS_DATA_STOP;
          HS_DATA_STOP: if (data_stopped) state <= HS_CLK_STOP;
          HS_CLK_STOP: if (clk_stopped) state <= HS_RETURN;
          HS_RETURN: begin
            if (stop_ready) begin state <= IDLE; action <= A_FIN_HS; end
          end
          FAULT: begin
            if (clear_error && stop_ready) begin state <= IDLE; action <= A_CLEAR; end
          end
          default: begin state <= FAULT; action <= A_INVALID; end
        endcase
      end
    end
  end

  // Todas las senales de control de la FSM son combinacionales.
  always @(*) begin
    arb_libre = 0;
    hs_active = 0;
    fault_active = 0;
    busy_ctrl = 1;
    intents = 6'b000000;
    take_lp = 0;
    take_hs = 0;
    ld_err = 0;
    sel_err = 2'd0;
    pll_cause = 0;
    fin_lp_evt = 0;
    fin_hs_evt = 0;
    case (state)
      IDLE: begin arb_libre = 1; busy_ctrl = 0; end
      LP_OWNED: intents = 6'b100000;
      LP_RETURN: intents = 6'b000000;
      HS_CLK_PREPARE: begin hs_active = 1; intents = 6'b001000; end
      HS_DATA_PREPARE: begin hs_active = 1; intents = 6'b001100; end
      HS_TRANSFER: begin hs_active = 1; intents = 6'b011100; end
      HS_DATA_STOP: begin hs_active = 1; intents = 6'b001010; end
      HS_CLK_STOP: begin hs_active = 1; intents = 6'b000001; end
      HS_RETURN: hs_active = 1;
      FAULT: fault_active = 1;
      default: begin end
    endcase
    if (!rst) begin
      case (action)
        A_TAKE_LP: take_lp = 1;
        A_TAKE_HS: take_hs = 1;
        A_PLL_ERROR: begin ld_err = 1; sel_err = 2'd1; pll_cause = 1; end
        A_HS_ERROR: begin ld_err = 1; sel_err = 2'd1; end
        A_INVALID: begin ld_err = 1; sel_err = 2'd2; end
        A_CLEAR: ld_err = 1;
        A_FIN_LP: fin_lp_evt = 1;
        A_FIN_HS: fin_hs_evt = 1;
        default: begin end
      endcase
    end
  end
endmodule
