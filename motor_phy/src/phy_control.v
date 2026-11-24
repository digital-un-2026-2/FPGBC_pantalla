// Solo el estado se registra en posedge. Todos los controles son combinacionales.
module phy_control (
    input clk,
    input rst,
    input preparar_lp,
    input fallo_init,
    input z_t,

    output reg rst_t,
    output reg inc_t,
    output reg en_lp,
    output reg sel_d0,
    output reg listo_ctrl,
    output reg estado_valido,
    output reg fallo_activo
);
  localparam AISLADO     = 3'd0;
  localparam PRECARGAR   = 3'd1;
  localparam ESTABILIZAR = 3'd2;
  localparam LISTO       = 3'd3;
  localparam FALLO       = 3'd4;

  reg [2:0] state;

  always @(posedge clk) begin
    if (rst) state <= AISLADO;
    else if (fallo_init || !estado_valido || fallo_activo) state <= FALLO;
    else if (!preparar_lp) state <= AISLADO;
    else begin
      case (state)
        AISLADO: state <= PRECARGAR;
        PRECARGAR: state <= ESTABILIZAR;
        ESTABILIZAR: begin
          if (z_t) state <= LISTO;
          else state <= ESTABILIZAR;
        end
        LISTO: state <= LISTO;
        FALLO: state <= FALLO;
        default: state <= FALLO;
      endcase
    end
  end

  always @(*) begin
    rst_t = 1'b0;
    inc_t = 1'b0;
    en_lp = 1'b0;
    sel_d0 = 1'b0;
    listo_ctrl = 1'b0;
    estado_valido = 1'b0;
    fallo_activo = 1'b0;

    case (state)
      AISLADO, PRECARGAR: begin
        estado_valido = 1'b1;
        rst_t = 1'b1;
      end
      ESTABILIZAR: begin
        estado_valido = 1'b1;
        inc_t = !z_t;
        en_lp = 1'b1;
      end
      LISTO: begin
        estado_valido = 1'b1;
        en_lp = 1'b1;
        sel_d0 = 1'b1;
        listo_ctrl = 1'b1;
      end
      FALLO: begin
        estado_valido = 1'b1;
        fallo_activo = 1'b1;
        rst_t = 1'b1;
      end
      default: begin
        // Estado no válido: todos los controles a cero y pads inhibidos.
      end
    endcase
  end

`ifdef BENCH
  reg [8*40:1] state_name;
  always @(*) begin
    case (state)
      AISLADO: state_name = "AISLADO";
      PRECARGAR: state_name = "PRECARGAR";
      ESTABILIZAR: state_name = "ESTABILIZAR";
      LISTO: state_name = "LISTO";
      FALLO: state_name = "FALLO";
      default: state_name = "INVALID";
    endcase
  end
`endif
endmodule
