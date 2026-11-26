module init_sequencer_ctrl (
    input CLK_BYTE,
    input RST_BYTE,
    input [1:0] OP,
    input LAST,
    input INIT_READY,
    input INIT_NEXT,
    input INIT_DONE_TX,
    input DONE_DELAY,

    output reg INIT_REQ,
    output reg INIT_DONE,
    output reg INC_A,
    output reg START_DELAY,
    output reg COUNT_DELAY
);
  localparam [2:0] READ = 3'd0, REQUEST = 3'd1, TX = 3'd2, LOAD_DELAY = 3'd3,
                   DELAY = 3'd4, ADV_WAIT = 3'd5, DONE = 3'd6;

  wire IS_BYTE = (OP == 2'b00) && !LAST;
  wire IS_WAIT = (OP == 2'b01) && LAST;
  wire IS_END  = (OP == 2'b10) && !LAST;
  reg [2:0] STATE;
  reg ADV_BYTE;

  always @(posedge CLK_BYTE) begin
    ADV_BYTE <= 1'b0;
    if (RST_BYTE) STATE <= READ;
    else begin
      case (STATE)
        READ: if (IS_BYTE) STATE <= REQUEST;
        REQUEST: if (INIT_REQ && INIT_READY) STATE <= TX;
        TX: begin
          // LP_TX puede retirar INIT_NEXT en el ↓ que consume esta orden.
          ADV_BYTE <= IS_BYTE && INIT_NEXT;
          if (IS_WAIT && INIT_DONE_TX) STATE <= LOAD_DELAY;
        end
        LOAD_DELAY: STATE <= DONE_DELAY ? ADV_WAIT : DELAY;
        DELAY: if (DONE_DELAY) STATE <= ADV_WAIT;
        ADV_WAIT: begin
          // Aquí ya ocurrió el único ↓ que incrementa tras la pausa.
          if (IS_BYTE) STATE <= REQUEST;
          else if (IS_END) STATE <= DONE;
          else STATE <= READ;
        end
        DONE: begin end
        default: STATE <= READ;
      endcase
    end
  end

  always @(*) begin
    INIT_REQ = 1'b0;
    INIT_DONE = 1'b0;
    INC_A = 1'b0;
    START_DELAY = 1'b0;
    COUNT_DELAY = 1'b0;

    if (!RST_BYTE) begin
      case (STATE)
        REQUEST:    INIT_REQ = 1'b1;
        TX:         INC_A = ADV_BYTE;
        LOAD_DELAY: START_DELAY = 1'b1;
        DELAY:      COUNT_DELAY = 1'b1;
        ADV_WAIT:   INC_A = 1'b1;
        DONE:       INIT_DONE = 1'b1;
        default: begin end
      endcase
    end
  end
endmodule
