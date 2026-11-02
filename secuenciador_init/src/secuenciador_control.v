module secuenciador_control (
    input clk,
    input rst,

    //entradas datapath interno
    input ultimo_paso,
    input descriptor_valido,
    input fin_t,

    //entrada de interfaz fisica
    input lp_preparada,
    //entrada desde motor_lpdt
    input aceptado,
    input ocupado,
    input terminado,

    //Salidas datapath interno
    output reg rst_paso,
    output reg inc_paso,
    output reg ld_desc,
    output reg [2:0] sel_t,
    output reg rst_t,
    output reg inc_t,
    output reg ld_causa,
    output reg [2:0] causa_fsm,

    //Salida a motor_lpdt
    output reg solicitud,
    output reg permiso_arranque,

    //Salida interfaz fisica
    output reg preparar_lp,
    output reg abortar_motor,


    //Salida a exterior
    output reg init_en_curso,
    output reg init_completa,
    output reg fallo
);

  parameter ARRANQUE            = 4'd0;
  parameter ESTABILIZAR         = 4'd1;
  parameter ARMAR_PREPARACION   = 4'd2;
  parameter PREPARAR_LP         = 4'd3;
  parameter REPOSO_INICIAL      = 4'd4;
  parameter CARGAR_DESCRIPTOR   = 4'd5;
  parameter VALIDAR_DESCRIPTOR  = 4'd6;
  parameter PREPARAR_PAQUETE    = 4'd7;
  parameter ARMAR_ACEPTACION    = 4'd8;
  parameter SOLICITAR           = 4'd9;
  parameter TRANSMITIR          = 4'd10;
  parameter ESPERAR_COMANDO     = 4'd11;
  parameter AVANZAR             = 4'd12;
  parameter LISTO               = 4'd13;
  parameter FALLO               = 4'd14;

  reg [3:0] state;
  reg reinicio;
  reg fin_t_reg;
  reg reiniciar_intervalo;
  reg capturar_causa;
  reg [2:0] causa_reg;

  wire error_lp = (state >= REPOSO_INICIAL) && (state <= LISTO) && !lp_preparada;
  wire error_protocolo =
      (state == SOLICITAR) ? (terminado || (aceptado ^ ocupado)) :
      (state == TRANSMITIR) ? (aceptado || (ocupado == terminado)) :
      ((state >= ARMAR_PREPARACION) && (state <= LISTO)) ?
          (aceptado || ocupado || terminado) : 1'b0;
  wire error_descriptor = (state == VALIDAR_DESCRIPTOR) && !descriptor_valido;
  wire timeout_preparacion = (state == PREPARAR_LP) && fin_t && !lp_preparada;
  wire timeout_aceptacion = (state == SOLICITAR) && fin_t && !aceptado;
  wire timeout_transmision = (state == TRANSMITIR) && fin_t && !terminado;

  always @(posedge clk) begin
    if (rst) begin
      state <= ARRANQUE;
      reinicio <= 1'b1;
      fin_t_reg <= 1'b0;
      reiniciar_intervalo <= 1'b0;
      capturar_causa <= 1'b0;
      causa_reg <= 3'd0;
    end else begin
      reinicio <= 1'b0;
      fin_t_reg <= fin_t;
      reiniciar_intervalo <= 1'b0;
      capturar_causa <= 1'b0;

      if (error_lp || error_protocolo || error_descriptor ||
          timeout_preparacion || timeout_aceptacion || timeout_transmision) begin
        state <= FALLO;
        if (state != FALLO) begin
          capturar_causa <= 1'b1;
          if (error_lp) causa_reg <= 3'd5;
          else if (error_protocolo) causa_reg <= 3'd6;
          else if (error_descriptor) causa_reg <= 3'd4;
          else if (timeout_preparacion) causa_reg <= 3'd1;
          else if (timeout_aceptacion) causa_reg <= 3'd2;
          else if (timeout_transmision) causa_reg <= 3'd3;
        end
      end else begin
        case (state)
          ARRANQUE: state <= ESTABILIZAR;
          ESTABILIZAR: begin
            if (fin_t) state <= ARMAR_PREPARACION;
          end
          ARMAR_PREPARACION: state <= PREPARAR_LP;
          PREPARAR_LP: begin
            if (lp_preparada) begin
              state <= REPOSO_INICIAL;
              reiniciar_intervalo <= 1'b1;
            end
          end
          REPOSO_INICIAL: begin
            if (fin_t) state <= CARGAR_DESCRIPTOR;
          end
          CARGAR_DESCRIPTOR: state <= VALIDAR_DESCRIPTOR;
          VALIDAR_DESCRIPTOR: begin
            if (descriptor_valido) state <= PREPARAR_PAQUETE;
          end
          PREPARAR_PAQUETE: state <= ARMAR_ACEPTACION;
          ARMAR_ACEPTACION: state <= SOLICITAR;
          SOLICITAR: begin
            if (aceptado && ocupado) begin
              state <= TRANSMITIR;
              reiniciar_intervalo <= 1'b1;
            end
          end
          TRANSMITIR: begin
            if (terminado && !ocupado) begin
              state <= ESPERAR_COMANDO;
              reiniciar_intervalo <= 1'b1;
            end
          end
          ESPERAR_COMANDO: begin
            if (fin_t) state <= ultimo_paso ? LISTO : AVANZAR;
          end
          AVANZAR: state <= CARGAR_DESCRIPTOR;
          LISTO: state <= LISTO;
          FALLO: state <= FALLO;
          default: state <= ARRANQUE;
        endcase
      end
    end
  end

  always @(*) begin
    rst_paso = 1'b0;
    inc_paso = 1'b0;
    ld_desc = 1'b0;
    sel_t = 3'd0;
    rst_t = 1'b0;
    inc_t = 1'b0;
    ld_causa = 1'b0;
    causa_fsm = causa_reg;
    solicitud = 1'b0;
    permiso_arranque = 1'b0;
    preparar_lp = 1'b1;
    abortar_motor = 1'b0;
    init_en_curso = 1'b1;
    init_completa = 1'b0;
    fallo = 1'b0;

    case (state)
      ARRANQUE: begin
        rst_paso = 1'b1;
        rst_t = 1'b1;
        preparar_lp = 1'b0;
      end
      ESTABILIZAR: begin
        sel_t = 3'd0;
        inc_t = !fin_t_reg;
        preparar_lp = 1'b0;
      end
      ARMAR_PREPARACION: begin
        sel_t = 3'd3;
        rst_t = 1'b1;
      end
      PREPARAR_LP: begin
        sel_t = 3'd3;
        inc_t = !fin_t_reg;
      end
      REPOSO_INICIAL: begin
        sel_t = 3'd1;
        inc_t = !fin_t_reg;
      end
      CARGAR_DESCRIPTOR: begin
        ld_desc = 1'b1;
      end
      VALIDAR_DESCRIPTOR: begin
        ld_desc = 1'b0;
      end
      PREPARAR_PAQUETE: begin
        solicitud = 1'b0;
        permiso_arranque = 1'b0;
      end
      ARMAR_ACEPTACION: begin
        sel_t = 3'd4;
        rst_t = 1'b1;
      end
      SOLICITAR: begin
        solicitud = 1'b1;
        permiso_arranque = 1'b1;
        sel_t = 3'd4;
        inc_t = !fin_t_reg;
      end
      TRANSMITIR: begin
        sel_t = 3'd5;
        inc_t = !fin_t_reg;
      end
      ESPERAR_COMANDO: begin
        sel_t = 3'd2;
        inc_t = !fin_t_reg;
      end
      AVANZAR: begin
        inc_paso = 1'b1;
      end
      LISTO: begin
        init_en_curso = 1'b0;
        init_completa = 1'b1;
      end
      FALLO: begin
        fallo = 1'b1;
        init_en_curso = 1'b0;
        abortar_motor = 1'b1;
        ld_causa = capturar_causa;
      end
      default: begin
        rst_paso = 1'b1;
        rst_t = 1'b1;
        preparar_lp = 1'b0;
      end
    endcase

    if (reiniciar_intervalo && (state != FALLO)) begin
      rst_t = 1'b1;
      inc_t = 1'b0;
    end

    if (reinicio) begin
      rst_paso = 1'b1;
      inc_paso = 1'b0;
      ld_desc = 1'b0;
      sel_t = 3'd0;
      rst_t = 1'b1;
      inc_t = 1'b0;
      ld_causa = 1'b0;
      causa_fsm = 3'd0;
      solicitud = 1'b0;
      permiso_arranque = 1'b0;
      preparar_lp = 1'b0;
      abortar_motor = 1'b0;
      init_en_curso = 1'b0;
      init_completa = 1'b0;
      fallo = 1'b0;
    end
  end

`ifdef BENCH
  reg [8*40:1] state_name;
  always @(*) begin
    case (state)
      ARRANQUE: state_name = "ARRANQUE";
      ESTABILIZAR: state_name = "ESTABILIZAR";
      ARMAR_PREPARACION: state_name = "ARMAR_PREPARACION";
      PREPARAR_LP: state_name = "PREPARAR_LP";
      REPOSO_INICIAL: state_name = "REPOSO_INICIAL";
      CARGAR_DESCRIPTOR: state_name = "CARGAR_DESCRIPTOR";
      VALIDAR_DESCRIPTOR: state_name = "VALIDAR_DESCRIPTOR";
      PREPARAR_PAQUETE: state_name = "PREPARAR_PAQUETE";
      ARMAR_ACEPTACION: state_name = "ARMAR_ACEPTACION";
      SOLICITAR: state_name = "SOLICITAR";
      TRANSMITIR: state_name = "TRANSMITIR";
      ESPERAR_COMANDO: state_name = "ESPERAR_COMANDO";
      AVANZAR: state_name = "AVANZAR";
      LISTO: state_name = "LISTO";
      FALLO: state_name = "FALLO";
      default: state_name = "INVALID";
    endcase
  end
`endif

endmodule
