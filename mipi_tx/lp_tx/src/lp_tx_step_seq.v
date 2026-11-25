module lp_tx_step_seq (
    input CLK_BYTE,
    input RST_BYTE,
    input LP_START,
    input INIT_LAST,
    input TICK,
    input MARK0,
    input SPACE_NEXT,

    output LP_DONE,
    output INIT_NEXT,
    output reg DIV_EN,
    output reg BIT_EN,
    output reg SEL_CMD,
    output reg LD_BYTE,
    output reg USE_MARK,
    output reg [1:0] FIX_CODE,
    output reg LP_WE
);
  localparam [2:0] IDLE  = 3'd0;
  localparam [2:0] ENTRY = 3'd1;
  localparam [2:0] CMD   = 3'd2;
  localparam [2:0] DATA  = 3'd3;
  localparam [2:0] EXIT  = 3'd4;
  localparam [2:0] ENTRY_END = 3'd4, EXIT_DONE = 3'd7;

  reg [2:0] STATE;
  reg [2:0] FIX_IDX;
  reg FIX_STEP;
  reg TAKEN;

  always @(posedge CLK_BYTE) begin
    if (RST_BYTE) STATE <= IDLE;
    else begin
      case (STATE)
        IDLE:  if (LP_START && !INIT_LAST) STATE <= ENTRY;
        ENTRY: if (TICK && (FIX_IDX == ENTRY_END)) STATE <= CMD;
        // Se entra con TICK=1: el primer ↓ emite b0 antes de volver a
        // evaluar MARK0 en ↑. MARK0 reaparece tras el espacio de b7.
        CMD:   if (TICK && MARK0) STATE <= DATA;
        DATA:  if (TICK && MARK0 && INIT_LAST) STATE <= EXIT;
        EXIT:  if (FIX_IDX == EXIT_DONE) STATE <= IDLE;
        default: STATE <= IDLE;
      endcase
    end
  end

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      FIX_IDX <= 3'd0;
      TAKEN <= 1'b0;
    end else begin
      if (STATE == IDLE) FIX_IDX <= 3'd0;
      else if (FIX_STEP) FIX_IDX <= FIX_IDX + 3'd1;
      TAKEN <= LD_BYTE && (STATE == DATA);
    end
  end

  // El ↑ intermedio consume cada pulso. LP_DONE sube al confirmar LP11
  // (FIX_IDX 6 -> 7) y baja en el primer ↓ en IDLE, no en su ↑ de entrada.
  assign INIT_NEXT = !RST_BYTE && TAKEN;
  assign LP_DONE = !RST_BYTE && (FIX_IDX == EXIT_DONE);

  always @(*) begin
    DIV_EN = 1'b0;
    BIT_EN = 1'b0;
    SEL_CMD = 1'b0;
    LD_BYTE = 1'b0;
    USE_MARK = 1'b0;
    FIX_CODE = 2'b00;
    LP_WE = 1'b0;
    FIX_STEP = 1'b0;

    if (!RST_BYTE) begin
      case (STATE)
        ENTRY: begin
          DIV_EN = 1'b1;
          FIX_STEP = TICK && (FIX_IDX < ENTRY_END);
          case (FIX_IDX)
            3'd0: FIX_CODE = 2'b10;
            3'd2: FIX_CODE = 2'b01;
            default: FIX_CODE = 2'b00;
          endcase
        end
        CMD: begin
          DIV_EN = 1'b1;
          BIT_EN = TICK;
          SEL_CMD = 1'b1;
        end
        DATA: begin
          DIV_EN = 1'b1;
          // WAIT puede presentarse mientras el byte capturado sigue saliendo.
          BIT_EN = TICK && (!MARK0 || !INIT_LAST);
        end
        EXIT: begin
          DIV_EN = 1'b1;
          FIX_STEP = TICK && (FIX_IDX < EXIT_DONE);
          // 4: LP10; 5: publica LP11; 6: un tick posterior, confirma LP11.
          FIX_CODE = (FIX_IDX == ENTRY_END) ? 2'b10 : 2'b11;
        end
        default: begin end  // Reposo: se conserva el LP11 registrado.
      endcase
      LD_BYTE = BIT_EN && MARK0;
      USE_MARK = BIT_EN && !SPACE_NEXT;
      LP_WE = BIT_EN || FIX_STEP;
    end
  end
endmodule
