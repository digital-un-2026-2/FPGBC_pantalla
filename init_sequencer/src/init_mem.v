module init_mem (
    input [7:0] ADDR,

    output [1:0] OP,
    output LAST,
    output [7:0] INIT_BYTE,
    output [7:0] DELAY_MS
);
  reg [10:0] WORD;

  always @(*) begin
    case (ADDR)
`include "init_mem_table.vh"
      default: WORD = 11'h600;  // OP reservado; no es una entrada de la ROM.
    endcase
  end

  assign {OP, LAST, INIT_BYTE} = WORD;
  assign DELAY_MS = WORD[7:0];
endmodule
