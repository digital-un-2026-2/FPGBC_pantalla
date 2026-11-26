// Reproduce INIT_MEM sin modificar los bytes DSI. LP_TX añade el selector.
module init_sequencer #(
    parameter integer CLK_BYTE_HZ = 1000  // Solo para simulación; fijar al integrar.
) (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1: cubrir un ↑ y el ↓ siguiente.
    input INIT_READY,
    input INIT_NEXT,
    input INIT_DONE_TX,

    output INIT_REQ,
    output [7:0] INIT_BYTE,
    output INIT_LAST,
    output INIT_DONE
);
  wire [7:0] ADDR, DELAY_MS;
  wire [1:0] OP;
  wire INC_A, START_DELAY, COUNT_DELAY, DONE_DELAY;
  wire RST_ALL = RST_BYTE;

  init_sequencer_ctrl ctrl (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .OP(OP), .LAST(INIT_LAST),
      .INIT_READY(INIT_READY), .INIT_NEXT(INIT_NEXT), .INIT_DONE_TX(INIT_DONE_TX),
      .DONE_DELAY(DONE_DELAY), .INIT_REQ(INIT_REQ), .INIT_DONE(INIT_DONE),
      .INC_A(INC_A), .START_DELAY(START_DELAY), .COUNT_DELAY(COUNT_DELAY)
  );

  init_sequencer_a_count a_count (
      .CLK_BYTE(CLK_BYTE), .RST_ALL(RST_ALL), .INC_A(INC_A), .ADDR(ADDR)
  );

  init_sequencer_d_count #(.CLK_BYTE_HZ(CLK_BYTE_HZ)) d_count (
      .CLK_BYTE(CLK_BYTE), .RST_ALL(RST_ALL), .DELAY_MS(DELAY_MS),
      .START_DELAY(START_DELAY), .COUNT_DELAY(COUNT_DELAY), .DONE_DELAY(DONE_DELAY)
  );

  init_mem mem (
      .ADDR(ADDR), .OP(OP), .LAST(INIT_LAST), .INIT_BYTE(INIT_BYTE), .DELAY_MS(DELAY_MS)
  );
endmodule
