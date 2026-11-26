// Control de los drivers para el perfil candidato de 55 MHz (tabla_flancos.md).
// El controlador lógico del PR #12 se conserva para su banco de slots.
module phy_ctrl_gowin (
    input CLK_BYTE, RST_BYTE, LOCK_RAW, HS_REQ, CLK_REQ,
    output LOCK, READY, ISO,
    output reg [1:0] LP_DAT_MODE, LP_CLK_MODE, LP_CLK_PN,
    output reg HS_EN, CLK_EN, CLK_TOGGLE,
    output reg [1:0] SER_MODE
);
  localparam [3:0] C_SAFE = 0, C_LP = 1, C_ENTRY = 2, C_RUN = 3,
                   C_POST = 4, C_PARK = 5, C_RELEASE = 6;
  localparam [3:0] D_SAFE = 0, D_LP = 1, D_ENTRY = 2, D_PREP = 3,
                   D_ZERO = 4, D_WORD = 5, D_TRAIL = 6, D_RELEASE = 7;
  localparam [1:0] ISOLATE = 0, SYMBOL = 1, BIAS = 2;
  localparam [1:0] SER_OFF = 0, SER_ZERO = 1, SER_WORD = 2, SER_TRAIL = 3;

  localparam [4:0] CLK_START_DONE = 25, DATA_LP01 = 27, DATA_REQ = 7,
                   DATA_ZERO = 7, DATA_TRAIL = 4, OSER8_LATENCY = 3,
                   CLK_POST = 11, CLK_ZERO_AFTER_STOP = 7, LP11_GUARD = 8;

  reg [3:0] CLK_STATE, DAT_STATE, CLK_LAST, DAT_LAST;
  reg [4:0] CLK_AGE, DAT_AGE;
  reg HS_Q, CLK_Q, PROTOCOL_FAULT;
  wire [4:0] CLK_TICK = (CLK_STATE == CLK_LAST) ? CLK_AGE + 1'b1 : 5'd1;
  wire [4:0] DAT_TICK = (DAT_STATE == DAT_LAST) ? DAT_AGE + 1'b1 : 5'd1;
  wire SAFE = CLK_STATE == C_SAFE && DAT_STATE == D_SAFE;
  wire RUN, ISO_GUARD;
  wire RST_CTRL = RST_BYTE || !RUN || PROTOCOL_FAULT;
  wire ADMIT_HS = DAT_STATE == D_PREP && DAT_AGE == DATA_REQ &&
                  CLK_STATE == C_RUN && CLK_Q;

  phy_ctrl_guard guard (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .LOCK_RAW(LOCK_RAW),
      .STATE(SAFE ? 3'b000 : 3'b001), .LOCK(LOCK), .RUN(RUN), .ISO(ISO_GUARD)
  );

  assign ISO = ISO_GUARD || PROTOCOL_FAULT;
  assign READY = !ISO && !CLK_Q && !HS_Q && DAT_STATE == D_LP &&
                 LP_CLK_MODE == SYMBOL && LP_DAT_MODE == SYMBOL &&
                 (CLK_STATE == C_LP || (CLK_STATE == C_RELEASE && CLK_AGE == LP11_GUARD));

  always @(posedge CLK_BYTE) begin
    if (RST_BYTE) PROTOCOL_FAULT <= 0;
    else if (!RST_CTRL &&
             ((HS_Q && !ADMIT_HS && DAT_STATE != D_ZERO && DAT_STATE != D_WORD) ||
              (DAT_STATE == D_PREP && DAT_AGE == DATA_REQ && !HS_Q) ||
              (DAT_STATE == D_ZERO && !HS_Q)))
      PROTOCOL_FAULT <= 1;

    if (RST_CTRL) begin
      CLK_STATE <= C_SAFE;
      DAT_STATE <= D_SAFE;
    end else begin
      case (CLK_STATE)
        C_SAFE: if (!CLK_Q && !HS_Q) CLK_STATE <= C_LP;
        C_LP: if (CLK_Q && !HS_Q) CLK_STATE <= C_ENTRY;
        C_ENTRY: if (CLK_AGE == CLK_START_DONE) CLK_STATE <= C_RUN;
        // La reserva física no se libera por la caída de CLK_REQ en EOT.
        C_RUN: if (DAT_STATE == D_RELEASE && DAT_AGE == 1) CLK_STATE <= C_POST;
        C_POST: if (CLK_AGE == CLK_POST) CLK_STATE <= C_PARK;
        C_PARK: if (CLK_AGE == CLK_ZERO_AFTER_STOP) CLK_STATE <= C_RELEASE;
        C_RELEASE: if (CLK_AGE == LP11_GUARD) CLK_STATE <= C_LP;
        default: CLK_STATE <= C_SAFE;
      endcase

      case (DAT_STATE)
        D_SAFE: if (!CLK_Q && !HS_Q) DAT_STATE <= D_LP;
        D_LP: if (CLK_STATE == C_LP && CLK_Q && !HS_Q) DAT_STATE <= D_ENTRY;
        D_ENTRY: if (DAT_AGE == DATA_LP01) DAT_STATE <= D_PREP;
        D_PREP: if (ADMIT_HS && HS_Q) DAT_STATE <= D_ZERO;
        D_ZERO: if (DAT_AGE == DATA_ZERO) DAT_STATE <= D_WORD;
        // HS_Q se actualiza en el ↓ que aún carga el CRC de PHY_IF.
        D_WORD: if (!HS_Q) DAT_STATE <= D_TRAIL;
        D_TRAIL: if (DAT_AGE == DATA_TRAIL + OSER8_LATENCY) DAT_STATE <= D_RELEASE;
        D_RELEASE: if (DAT_AGE == 3) DAT_STATE <= D_LP;
        default: DAT_STATE <= D_SAFE;
      endcase
    end
  end

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) {HS_Q, CLK_Q} <= 0;
    else          {HS_Q, CLK_Q} <= {HS_REQ, CLK_REQ};

    if (RST_CTRL) begin
      CLK_LAST <= C_SAFE;
      DAT_LAST <= D_SAFE;
      {CLK_AGE, DAT_AGE} <= 0;
      {LP_DAT_MODE, LP_CLK_MODE, HS_EN, CLK_EN, CLK_TOGGLE} <= 0;
      LP_CLK_PN <= 2'b11;
    end else begin
      CLK_LAST <= CLK_STATE;
      DAT_LAST <= DAT_STATE;
      case (CLK_STATE)
        C_ENTRY, C_POST, C_PARK, C_RELEASE: CLK_AGE <= CLK_TICK;
        default: CLK_AGE <= 0;
      endcase
      case (DAT_STATE)
        D_ENTRY, D_PREP, D_ZERO, D_TRAIL, D_RELEASE: DAT_AGE <= DAT_TICK;
        default: DAT_AGE <= 0;
      endcase

      case (CLK_STATE)
        C_LP: LP_CLK_MODE <= SYMBOL;
        C_ENTRY: case (CLK_TICK)
          1: LP_CLK_PN <= 2'b01;
          5: LP_CLK_PN <= 2'b00;
          6: LP_CLK_MODE <= ISOLATE;
          7: LP_CLK_MODE <= BIAS;
          8: CLK_EN <= 1;
          22: CLK_TOGGLE <= 1;
          default: ;
        endcase
        C_POST: if (CLK_TICK == CLK_POST) CLK_TOGGLE <= 0;
        C_PARK: if (CLK_TICK == CLK_ZERO_AFTER_STOP) CLK_EN <= 0;
        C_RELEASE: case (CLK_TICK)
          1: begin
            LP_CLK_MODE <= ISOLATE;
            LP_CLK_PN <= 2'b11;
          end
          2: LP_CLK_MODE <= SYMBOL;
          default: ;
        endcase
        default: ;
      endcase

      case (DAT_STATE)
        D_LP: LP_DAT_MODE <= SYMBOL;
        D_PREP: case (DAT_TICK)
          5: LP_DAT_MODE <= ISOLATE;
          6: LP_DAT_MODE <= BIAS;
          default: ;
        endcase
        D_ZERO: HS_EN <= 1;
        D_RELEASE: case (DAT_TICK)
          1: HS_EN <= 0;
          2: LP_DAT_MODE <= ISOLATE;
          3: LP_DAT_MODE <= SYMBOL;
          default: ;
        endcase
        default: ;
      endcase
    end
  end

  always @(*) begin
    SER_MODE = SER_OFF;
    if (!ISO) begin
      case (DAT_STATE)
        D_ZERO: SER_MODE = SER_ZERO;
        D_WORD: SER_MODE = SER_WORD;
        D_TRAIL: SER_MODE = SER_TRAIL;
        default: ;
      endcase
    end
  end
endmodule
