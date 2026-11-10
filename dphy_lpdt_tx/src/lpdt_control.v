module lpdt_control #(
    parameter ANCHO_LONGITUD = 3
) (
    input clk,
    input rst,
    input z_byte,
    input z_t,
    input z_bit,
    input permiso_arranque,
    input [ANCHO_LONGITUD-1:0] idx,
    input solicitud,

    output reg ld_len,
    output reg sel_87,
    output reg ld_byte,
    output reg rst_byte,
    output reg inc_byte,
    output reg rst_bit,
    output reg inc_bit,
    output reg ld_t,
    output reg inc_t,
    output reg sel_fijo,
    output reg [1:0] lp_fijo,
    output reg ld_lp,
    output reg aceptado,
    output reg ocupado,
    output reg terminado,
    output [ANCHO_LONGITUD-1:0] pos
);
  parameter IDLE     = 4'b0000;
  parameter ESC_10   = 4'b0001;
  parameter ESC_00_A = 4'b0010;
  parameter ESC_01   = 4'b0011;
  parameter ESC_00_B = 4'b0100;
  parameter MARK     = 4'b0101;
  parameter SPACE    = 4'b0110;
  parameter EXIT_10  = 4'b0111;
  parameter DONE     = 4'b1000;

  reg [3:0] state;
  reg enviando_selector;
  reg salida_pendiente;
  reg reinicio;
  reg inicio;
  reg avance_fase;
  reg ultimo_bit;
  reg ultimo_byte;
  reg selector_previo;
  reg fin_transaccion;
  localparam [ANCHO_LONGITUD-1:0] UNO = 1;
  wire ready = (state == IDLE) & permiso_arranque & !rst;
  wire start = solicitud & ready;
  wire fin_paquete = !enviando_selector & z_bit & z_byte;

  assign pos = (rst || state == IDLE || enviando_selector || rst_byte) ? {ANCHO_LONGITUD{1'b0}} :
               (ld_byte && !sel_87 && !inc_byte) ? idx :
                (!z_byte ? idx + UNO : idx);

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      enviando_selector <= 1'b0;
      salida_pendiente <= 1'b0;
      reinicio <= 1'b1;
      inicio <= 1'b0;
      avance_fase <= 1'b0;
      ultimo_bit <= 1'b0;
      ultimo_byte <= 1'b0;
      selector_previo <= 1'b0;
      fin_transaccion <= 1'b0;
    end else begin
      reinicio <= 1'b0;
      inicio <= 1'b0;
      avance_fase <= 1'b0;
      fin_transaccion <= 1'b0;

      case (state)
        IDLE: begin
          if (start) begin
            state <= ESC_10;
            enviando_selector <= 1'b1;
            salida_pendiente <= 1'b0;
            inicio <= 1'b1;
          end else begin
            state <= IDLE;
          end
        end
        ESC_10, ESC_00_A, ESC_01, ESC_00_B: begin
          avance_fase <= z_t;
          if (z_t) begin
            case (state)
              ESC_10: state <= ESC_00_A;
              ESC_00_A: state <= ESC_01;
              ESC_01: state <= ESC_00_B;
              ESC_00_B: state <= MARK;
            endcase
          end
        end
        MARK: begin
          avance_fase <= z_t;
          if (z_t) begin
            state <= SPACE;
            salida_pendiente <= fin_paquete;
            ultimo_bit <= z_bit;
            ultimo_byte <= z_byte;
            selector_previo <= enviando_selector;
            if (z_bit) enviando_selector <= 1'b0;
          end
        end
        SPACE: begin
          avance_fase <= z_t;
          if (z_t) begin
            if (salida_pendiente) state <= EXIT_10;
            else state <= MARK;
          end
        end
        EXIT_10: begin
          avance_fase <= z_t;
          if (z_t) state <= DONE;
        end
        DONE: begin
          state <= IDLE;
          fin_transaccion <= 1'b1;
        end
        default: begin
          state <= IDLE;
          enviando_selector <= 1'b0;
          salida_pendiente <= 1'b0;
          reinicio <= 1'b1;
        end
      endcase
    end
  end

  always @(*) begin
    ld_len = 1'b0;
    sel_87 = 1'b0;
    ld_byte = 1'b0;
    rst_byte = 1'b0;
    inc_byte = 1'b0;
    rst_bit = 1'b0;
    inc_bit = 1'b0;
    ld_t = 1'b0;
    inc_t = 1'b0;
    sel_fijo = 1'b1;
    lp_fijo = 2'b11;
    ld_lp = 1'b0;
    aceptado = 1'b0;
    ocupado = 1'b0;
    terminado = 1'b0;

    case (state)
      IDLE: begin
        terminado = fin_transaccion;
      end
      ESC_10, ESC_00_A, ESC_01, ESC_00_B, MARK, SPACE, EXIT_10: begin
        ocupado = 1'b1;
        inc_t = !avance_fase && !inicio;
        ld_t = avance_fase || inicio;
        ld_lp = avance_fase || inicio;
        case (state)
          ESC_10: begin
            lp_fijo = 2'b10;
            aceptado = inicio;
            ld_len = inicio;
            sel_87 = inicio;
            ld_byte = inicio;
            rst_byte = inicio;
            rst_bit = inicio;
          end
          ESC_00_A: lp_fijo = 2'b00;
          ESC_01: lp_fijo = 2'b01;
          ESC_00_B: lp_fijo = 2'b00;
          MARK: sel_fijo = 1'b0;
          SPACE: begin
            lp_fijo = 2'b00;
            inc_bit = avance_fase && !ultimo_bit;
            rst_bit = avance_fase && ultimo_bit;
            ld_byte = avance_fase && ultimo_bit && !salida_pendiente;
            inc_byte = avance_fase && ultimo_bit && !selector_previo && !ultimo_byte;
          end
          EXIT_10: lp_fijo = 2'b10;
        endcase
      end
      DONE: begin
        ocupado = 1'b1;
        ld_lp = avance_fase;
      end
      default: begin
        rst_byte = 1'b1;
        rst_bit = 1'b1;
        ld_t = 1'b1;
        ld_lp = 1'b1;
      end
    endcase

    if (reinicio) begin
      ld_len = 1'b0;
      sel_87 = 1'b0;
      ld_byte = 1'b0;
      rst_byte = 1'b1;
      inc_byte = 1'b0;
      rst_bit = 1'b1;
      inc_bit = 1'b0;
      ld_t = 1'b1;
      inc_t = 1'b0;
      sel_fijo = 1'b1;
      lp_fijo = 2'b11;
      ld_lp = 1'b1;
      aceptado = 1'b0;
      ocupado = 1'b0;
      terminado = 1'b0;
    end
  end

`ifdef BENCH
  reg [8*40:1] state_name;
  always @(*) begin
    case (state)
      IDLE:     state_name = "IDLE";
      ESC_10:   state_name = "ESC_10";
      ESC_00_A: state_name = "ESC_00_A";
      ESC_01:   state_name = "ESC_01";
      ESC_00_B: state_name = "ESC_00_B";
      MARK:     state_name = "MARK";
      SPACE:    state_name = "SPACE";
      EXIT_10:  state_name = "EXIT_10";
      DONE:     state_name = "DONE";
      default:  state_name = "INVALID";
    endcase
  end
`endif
endmodule
