// Solo banco: consume pares de bytes, no serializa ni valida niveles físicos.
// No conoce la longitud del paquete, el contenido ni los controles internos.
module mipi_tx_phy_model #(
    parameter integer T_ZERO = 1,
    parameter integer T_TRAIL = 1
) (
    input CLK_BYTE,
    input RST_BYTE,
    input HS_REQ,
    input CLK_REQ,
    input [2:0] LP_P,
    input [2:0] LP_N,
    input [7:0] HS_BYTE0,
    input [7:0] HS_BYTE1,
    output READY,
    output LOCK,

    // Observación para el banco, no señales de vuelta a MIPI_TX.
    output [1:0] D0_LP,
    output [1:0] D1_LP,
    output [1:0] CLK_LP,
    output reg TAKE,
    output reg LAST,
    output reg TRAIL,
    output reg [15:0] TAKEN_WORD
);
  // Siempre disponible fuera de reset; no espera HS_REQ ni CLK_REQ.
  assign READY = !RST_BYTE;
  assign LOCK = !RST_BYTE;
  assign D0_LP = {LP_P[0], LP_N[0]};
  assign D1_LP = {LP_P[1], LP_N[1]};
  assign CLK_LP = {LP_P[2], LP_N[2]};

  reg prev_hs_req;
  integer zero_left, trail_left;

  always @(negedge CLK_BYTE) begin
    TAKE <= 0;
    LAST <= 0;
    TRAIL <= 0;
    if (RST_BYTE) begin
      prev_hs_req <= 0;
      zero_left <= 0;
      trail_left <= 0;
      TAKEN_WORD <= 16'h0000;
    end else begin
      prev_hs_req <= HS_REQ;
      if (HS_REQ || prev_hs_req) begin
        if (CLK_REQ !== 1'b1 || trail_left != 0)
          $fatal(1, "PHY modelo: HS sin CLK_REQ o durante trail");
        if (!prev_hs_req) zero_left <= T_ZERO;  // Primer ↓ con petición.
        else if (zero_left != 0) begin
          if (!HS_REQ) $fatal(1, "PHY modelo: fin de HS antes del primer consumo");
          zero_left <= zero_left - 1;
        end else begin
          // Se lee el registro previo de PHY_IF, incluso en el ↓ de caída.
          // El reset tiene prioridad y no se interpreta como cierre normal.
          TAKEN_WORD <= {HS_BYTE1, HS_BYTE0};
          TAKE <= 1;
          LAST <= !HS_REQ;
          if (!HS_REQ) trail_left <= T_TRAIL;
        end
      end else if (trail_left != 0) begin
        if (CLK_REQ !== 1'b1) $fatal(1, "PHY modelo: CLK_REQ cayó antes del fin de trail");
        TRAIL <= 1;
        trail_left <= trail_left - 1;
      end
    end
  end
endmodule
