module init_sequencer_d_count #(
    parameter integer CLK_BYTE_HZ = 1000
) (
    input CLK_BYTE,
    input RST_ALL,
    input [7:0] DELAY_MS,
    input START_DELAY,
    input COUNT_DELAY,

    output DONE_DELAY
);
  localparam integer P = CLK_BYTE_HZ / 1000;
  localparam integer W = (P > 1) ? $clog2(P) : 1;
  localparam integer LAST_PHASE = P - 1;

  reg [W-1:0] PHASE;
  reg [7:0] MS_LEFT;
  assign DONE_DELAY = (MS_LEFT == 8'd0);

  // Habilitación para ↓, no un reloj. El ↓ de carga es el primero
  // de los P ciclos; para P=1 ya cuenta como un tick entero.
  wire TICK_MS = !RST_ALL &&
                 (START_DELAY ? ((P == 1) && (DELAY_MS != 8'd0)) :
                  (COUNT_DELAY && !DONE_DELAY && (PHASE == LAST_PHASE[W-1:0])));

  always @(negedge CLK_BYTE) begin
    if (RST_ALL) begin
      PHASE <= 0;
      MS_LEFT <= 0;
    end else if (START_DELAY) begin
      PHASE <= (P > 1) ? 1 : 0;
      MS_LEFT <= TICK_MS ? DELAY_MS - 1'b1 : DELAY_MS;
    end else if (COUNT_DELAY && !DONE_DELAY) begin
      if (TICK_MS) begin
        PHASE <= 0;
        MS_LEFT <= MS_LEFT - 1'b1;
      end else PHASE <= PHASE + 1'b1;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (CLK_BYTE_HZ < 1000 || (CLK_BYTE_HZ % 1000) != 0)
      $fatal(1, "CLK_BYTE_HZ=%0d debe ser un múltiplo positivo de 1000", CLK_BYTE_HZ);
  end
`endif
endmodule
