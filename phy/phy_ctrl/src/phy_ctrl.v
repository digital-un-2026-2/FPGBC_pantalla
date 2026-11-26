// Control de modo interno al PHY. No recibe ni inspecciona los bytes.
// T_ZERO y T_TRAIL son límites lógicos compartidos con LINK_FSM (PR #11).
module phy_ctrl #(
    parameter integer T_ZERO = 1,
    parameter integer T_TRAIL = 1
) (
    input CLK_BYTE,
    input RST_BYTE,
    input LOCK_RAW,
    input HS_REQ,
    input CLK_REQ,

    output LOCK,
    output READY,
    output LP_EN,
    output HS_EN,
    output CLK_EN,
    output CLK_ARM,
    output ISO,
    output reg [1:0] SER_MODE
);
  localparam [2:0] SAFE = 3'b000, LP = 3'b010, ARM_CLK = 3'b011, ZERO = 3'b111,
                   STREAM = 3'b101, TRAIL = 3'b100, POST_CLK = 3'b110;
  localparam [1:0] SLOT_OFF = 2'b00, SLOT_LP = 2'b01, SLOT_CLK = 2'b10, SLOT_HS_CLK = 2'b11;
  localparam [1:0] SER_OFF = 2'b00, SER_ZERO = 2'b01, SER_WORD = 2'b10, SER_TRAIL = 2'b11;
  localparam integer N_MAX = (T_ZERO > T_TRAIL) ? T_ZERO : T_TRAIL;
  localparam integer W = (N_MAX > 1) ? $clog2(N_MAX + 1) : 1;

  // La ventana de conducción HS es un bit de estado, estable de ZERO a POST_CLK.
  (* fsm_encoding = "none" *) reg [2:0] STATE;
  reg ENTER_T;
  reg HS_Q, CLK_Q;
  reg [1:0] SLOT, SLOT_D;
  reg LOAD_T;
  reg [W-1:0] N;
  wire RUN, DONE;
  wire RST_CTRL = RST_BYTE || !RUN;

  phy_ctrl_guard #(.SAFE_STATE(SAFE)) guard (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .LOCK_RAW(LOCK_RAW), .STATE(STATE),
      .LOCK(LOCK), .RUN(RUN), .ISO(ISO)
  );

  phy_ctrl_timer #(.W(W)) timer (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .RUN(RUN),
      .LOAD_T(LOAD_T), .N(N), .DONE(DONE)
  );

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) {HS_Q, CLK_Q} <= 2'b00;
    else {HS_Q, CLK_Q} <= {HS_REQ, CLK_REQ};

    if (RST_CTRL) SLOT <= SLOT_OFF;
    else SLOT <= SLOT_D;
  end

  always @(posedge CLK_BYTE) begin
    ENTER_T <= 1'b0;
    if (RST_CTRL) STATE <= SAFE;
    else begin
      case (STATE)
        SAFE: if (!HS_Q && !CLK_Q) STATE <= LP;
        LP: begin
          if (HS_Q) STATE <= SAFE;  // No se preparó el reloj.
          else if (CLK_Q) STATE <= ARM_CLK;
        end
        ARM_CLK: begin
          if (!CLK_Q) STATE <= HS_Q ? SAFE : LP;
          else if (HS_Q) begin
            STATE <= ZERO;
            ENTER_T <= 1'b1;
          end
        end
        ZERO: begin
          if (!HS_Q) STATE <= SAFE;  // Retiro antes de iniciar WORD.
          else if (DONE) STATE <= STREAM;
        end
        STREAM: if (!HS_Q) begin
          // En el ↓ que muestreó la caída, WORD aún cargó el CRC registrado.
          STATE <= TRAIL;
          ENTER_T <= 1'b1;
        end
        TRAIL: if (DONE) STATE <= POST_CLK;
        POST_CLK: if (!HS_Q && !CLK_Q) STATE <= LP;
        default: STATE <= SAFE;
      endcase
    end
  end

  // En las transiciones normales las ventanas cierran en ↑ y el siguiente
  // propietario se aplica en ↓. SLOT conserva HS hasta finalizar el trail.
  assign LP_EN = !ISO && !STATE[2] && STATE[1] && (SLOT == SLOT_LP);
  assign HS_EN = !ISO && STATE[2] && (SLOT == SLOT_HS_CLK);
  assign CLK_EN = !ISO && STATE[2] && SLOT[1];
  assign CLK_ARM = !ISO && (STATE[2] || (&STATE[1:0]));
  assign READY = !RST_CTRL && (STATE == LP) && (SLOT == SLOT_LP);

  always @(*) begin
    SLOT_D = SLOT_OFF;
    LOAD_T = 1'b0;
    N = 0;
    SER_MODE = SER_OFF;
    case (STATE)
      LP, ARM_CLK: SLOT_D = SLOT_LP;
      ZERO: begin
        SLOT_D = SLOT_HS_CLK;
        LOAD_T = ENTER_T;
        N = T_ZERO[W-1:0];
        SER_MODE = SER_ZERO;
      end
      STREAM: begin
        SLOT_D = SLOT_HS_CLK;
        SER_MODE = SER_WORD;
      end
      TRAIL: begin
        SLOT_D = SLOT_HS_CLK;
        LOAD_T = ENTER_T;
        N = T_TRAIL[W-1:0];
        SER_MODE = SER_TRAIL;
      end
      POST_CLK: SLOT_D = SLOT_CLK;
      default: begin end
    endcase
    if (ISO) SER_MODE = SER_OFF;
  end

`ifndef SYNTHESIS
  initial begin
    if (T_ZERO < 1 || T_TRAIL < 1) $fatal(1, "T_ZERO y T_TRAIL deben ser >= 1");
  end
`endif
endmodule
