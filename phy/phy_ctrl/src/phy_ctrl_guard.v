// Corte físico sin CLK_BYTE y estado sincronizado para la lógica.
// El supervisor aserta RST_BYTE si faltan flancos aunque LOCK_RAW quede alto.
module phy_ctrl_guard #(
    parameter [2:0] SAFE_STATE = 3'b000
) (
    input CLK_BYTE,
    input RST_BYTE,
    input LOCK_RAW,
    input [2:0] STATE,

    output LOCK,
    output RUN,
    output ISO
);
  wire CUT_RAW = RST_BYTE || !LOCK_RAW;
  reg RST_SEEN, ARMED;
  (* async_reg = "true" *) reg [1:0] LOCK_PIPE, ARM_PIPE;

  // Requiere reset común también tras una pérdida de lock que no haya
  // coincidido con un flanco. El supervisor garantiza el par ↑/↓ de reset.
  always @(negedge CLK_BYTE or negedge LOCK_RAW) begin
    if (!LOCK_RAW) RST_SEEN <= 1'b0;
    else if (RST_BYTE) RST_SEEN <= 1'b1;
  end

  // Un retorno de LOCK_RAW por sí solo no vuelve a habilitar los drivers.
  // El rearme ocurre con la FSM ya en SAFE, no en una fase activa.
  always @(negedge CLK_BYTE or posedge CUT_RAW) begin
    if (CUT_RAW) ARMED <= 1'b0;
    else if ((STATE == SAFE_STATE) && LOCK && RST_SEEN) ARMED <= 1'b1;
  end

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      LOCK_PIPE <= 2'b00;
      ARM_PIPE <= 2'b00;
    end else begin
      LOCK_PIPE <= {LOCK_PIPE[0], LOCK_RAW};
      ARM_PIPE <= {ARM_PIPE[0], ARMED};
    end
  end

  assign LOCK = LOCK_PIPE[1];
  assign RUN = LOCK && ARM_PIPE[1];
  assign ISO = CUT_RAW || !ARMED || !RUN;
endmodule
