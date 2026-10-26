module motor_control (
    input clk,
    input rst,
    input z_byte,
    input z_t,
    input z_bit,
    input permiso_arranque,
    input [2:0] idx,
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
    output [2:0] pos
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
  wire ready = (state == IDLE) & permiso_arranque & !rst;
  wire A = solicitud & ready;
  wire fin_paquete = !enviando_selector & z_bit & z_byte;

  // Anticipar la lectura durante el byte anterior, no al incrementar idx.
  // Al cargar DATA[0], el flag selector ya cambió en posedge, pero idx sigue 0.
  // No solicitar idx+1 durante esa media fase ni fuera del último byte válido.
  assign pos = (rst || state == IDLE || enviando_selector || rst_byte) ? 3'd0 :
               (ld_byte && !sel_87 && !inc_byte) ? idx :
               (!z_byte ? idx + 3'd1 : idx);

  // La FSM entrega órdenes en posedge; el datapath las captura en negedge.
  // El temporizador ascendente carga 0 con ld_t y activa z_t al llegar a 3.
  // No realimentar z_t combinacionalmente hacia controles del mismo negedge.
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      enviando_selector <= 1'b0;
      salida_pendiente <= 1'b0;
      ld_len <= 1'b0;
      sel_87 <= 1'b0;
      ld_byte <= 1'b0;
      rst_byte <= 1'b1;
      inc_byte <= 1'b0;
      rst_bit <= 1'b1;
      inc_bit <= 1'b0;
      ld_t <= 1'b1;
      inc_t <= 1'b0;
      sel_fijo <= 1'b1;
      lp_fijo <= 2'b11;
      ld_lp <= 1'b1;
      aceptado <= 1'b0;
      ocupado <= 1'b0;
      terminado <= 1'b0;
    end else begin
      // Valores de retención del datapath: no habilitar cargas ni avances.
      ld_len <= 1'b0;
      sel_87 <= 1'b0;
      ld_byte <= 1'b0;
      rst_byte <= 1'b0;
      inc_byte <= 1'b0;
      rst_bit <= 1'b0;
      inc_bit <= 1'b0;
      ld_t <= 1'b0;
      inc_t <= 1'b0;
      sel_fijo <= 1'b1;
      lp_fijo <= 2'b11;
      ld_lp <= 1'b0;
      aceptado <= 1'b0;
      terminado <= 1'b0;

      case (state)
        IDLE: begin
          ocupado <= 1'b0;
          if (A) begin
            state <= ESC_10;
            enviando_selector <= 1'b1;
            salida_pendiente <= 1'b0;
            aceptado <= 1'b1;
            ocupado <= 1'b1;
            ld_len <= 1'b1;
            sel_87 <= 1'b1;
            ld_byte <= 1'b1;
            rst_byte <= 1'b1;
            rst_bit <= 1'b1;
            ld_t <= 1'b1;
            lp_fijo <= 2'b10;
            ld_lp <= 1'b1;
          end
        end
        ESC_10, ESC_00_A, ESC_01, ESC_00_B: begin
          ocupado <= 1'b1;
          inc_t <= !z_t;
          ld_t <= z_t;
          ld_lp <= z_t;
          case (state)
            ESC_10: begin
              lp_fijo <= 2'b00;
              if (z_t) state <= ESC_00_A;
            end
            ESC_00_A: begin
              lp_fijo <= 2'b01;
              if (z_t) state <= ESC_01;
            end
            ESC_01: begin
              lp_fijo <= 2'b00;
              if (z_t) state <= ESC_00_B;
            end
            ESC_00_B: begin
              sel_fijo <= 1'b0;
              if (z_t) state <= MARK;
            end
          endcase
        end
        MARK: begin
          ocupado <= 1'b1;
          inc_t <= !z_t;
          ld_t <= z_t;
          ld_lp <= z_t;
          lp_fijo <= 2'b00;
          if (z_t) begin
            state <= SPACE;
            // Flags e índices aún describen el Mark terminado.
            salida_pendiente <= fin_paquete;
            inc_bit <= !z_bit;
            rst_bit <= z_bit;
            ld_byte <= z_bit & !fin_paquete;
            inc_byte <= z_bit & !enviando_selector & !z_byte;
            if (z_bit) enviando_selector <= 1'b0;
          end
        end
        SPACE: begin
          ocupado <= 1'b1;
          inc_t <= !z_t;
          ld_t <= z_t;
          ld_lp <= z_t;
          sel_fijo <= salida_pendiente;
          lp_fijo <= 2'b10;
          if (z_t) begin
            if (salida_pendiente) state <= EXIT_10;
            else state <= MARK;
          end
        end
        EXIT_10: begin
          ocupado <= 1'b1;
          inc_t <= !z_t;
          ld_lp <= z_t;
          lp_fijo <= 2'b11;
          if (z_t) state <= DONE;
        end
        DONE: begin
          // El negedge anterior ya cargó LP-11: no adelantar el aviso.
          state <= IDLE;
          ocupado <= 1'b0;
          terminado <= 1'b1;
        end
        default: begin
          state <= IDLE;
          enviando_selector <= 1'b0;
          salida_pendiente <= 1'b0;
          ocupado <= 1'b0;
          rst_byte <= 1'b1;
          rst_bit <= 1'b1;
          ld_t <= 1'b1;
          ld_lp <= 1'b1;
        end
      endcase
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
