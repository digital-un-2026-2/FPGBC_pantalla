module secuenciador_init #(
    parameter W = 23,
    parameter [W-1:0] T_ESTABILIZACION = 800000,
    parameter [W-1:0] T_REPOSO_INICIAL = 8000,
    parameter [W-1:0] TIMEOUT_PREPARACION = 40000,
    parameter [W-1:0] TIMEOUT_ACEPTACION = 16,
    parameter [W-1:0] TIMEOUT_TRANSMISION = 2048
) (
    input clk,
    input rst,

    input lp_preparada,
    output preparar_lp,

    input aceptado,
    input ocupado,
    input terminado,
    input [3:0] pos,
    output solicitud,
    output permiso_arranque,
    output [3:0] cantidad_bytes,
    output [7:0] byte_almacen,
    output rst_motor,

    output init_en_curso,
    output init_completa,
    output fallo,
    output [2:0] codigo_fallo
);

  wire w_rst_paso;
  wire w_inc_paso;
  wire [3:0] w_paso;
  wire w_ultimo_paso;

  wire [33:0] w_descriptor;
  wire [33:0] w_desc_activo;
  wire w_ld_desc;
  wire [6:0] w_base_activa;
  wire [W-1:0] w_espera_activa;
  wire w_descriptor_valido;
  wire [6:0] w_direccion;

  wire [2:0] w_sel_t;
  wire w_rst_t;
  wire w_inc_t;
  wire [W-1:0] w_limite_t;
  wire [W-1:0] w_tiempo;
  wire w_fin_t;

  wire w_ld_causa;
  wire [2:0] w_causa_fsm;
  wire w_abortar_motor;

  assign w_base_activa = w_desc_activo[33:27];
  assign cantidad_bytes = w_desc_activo[26:23];
  assign w_espera_activa = w_desc_activo[22:0];
  assign w_direccion = w_base_activa + {3'b000, pos};
  assign rst_motor = rst | w_abortar_motor;

  count #(
      .BITS(4)
  ) paso (
      .clk(clk),
      .rst(rst | w_rst_paso),
      .inc(w_inc_paso),
      .count_out(w_paso)
  );

  comp #(
      .BITS(4)
  ) ultimo_paso (
      .A(w_paso),
      .B(4'd10),
      .z(w_ultimo_paso)
  );

  rom_descriptores descriptores (
      .paso(w_paso),
      .descriptor(w_descriptor)
  );

  reg_0 #(
      .BITS(34),
      .RESET_VALUE(34'd0)
  ) desc_activo (
      .clk(clk),
      .rst(rst),
      .reg_in(w_descriptor),
      .ld(w_ld_desc),
      .reg_out(w_desc_activo)
  );

  validador_descriptor validador (
      .paso(w_paso),
      .base_activa(w_base_activa),
      .longitud_activa(cantidad_bytes),
      .descriptor_valido(w_descriptor_valido)
  );

  rom_paquetes paquetes (
      .direccion(w_direccion),
      .dato(byte_almacen)
  );

  mux #(
      .INPUTS(6),
      .BITS(W)
  ) limite_t (
      .data_in({TIMEOUT_TRANSMISION, TIMEOUT_ACEPTACION, TIMEOUT_PREPARACION,
                w_espera_activa, T_REPOSO_INICIAL, T_ESTABILIZACION}),
      .sel(w_sel_t),
      .data_out(w_limite_t)
  );

  count #(
      .BITS(W)
  ) tiempo (
      .clk(clk),
      .rst(rst | w_rst_t),
      .inc(w_inc_t),
      .count_out(w_tiempo)
  );

  comp #(
      .BITS(W)
  ) fin_t (
      .A(w_tiempo),
      .B(w_limite_t),
      .z(w_fin_t)
  );

  reg_0 #(
      .BITS(3),
      .RESET_VALUE(3'd0)
  ) causa_fallo (
      .clk(clk),
      .rst(rst),
      .reg_in(w_causa_fsm),
      .ld(w_ld_causa),
      .reg_out(codigo_fallo)
  );

  secuenciador_control ctrl (
      .clk(clk),
      .rst(rst),
      .ultimo_paso(w_ultimo_paso),
      .descriptor_valido(w_descriptor_valido),
      .fin_t(w_fin_t),
      .lp_preparada(lp_preparada),
      .aceptado(aceptado),
      .ocupado(ocupado),
      .terminado(terminado),
      .rst_paso(w_rst_paso),
      .inc_paso(w_inc_paso),
      .ld_desc(w_ld_desc),
      .sel_t(w_sel_t),
      .rst_t(w_rst_t),
      .inc_t(w_inc_t),
      .ld_causa(w_ld_causa),
      .causa_fsm(w_causa_fsm),
      .solicitud(solicitud),
      .permiso_arranque(permiso_arranque),
      .preparar_lp(preparar_lp),
      .abortar_motor(w_abortar_motor),
      .init_en_curso(init_en_curso),
      .init_completa(init_completa),
      .fallo(fallo)
  );

endmodule
