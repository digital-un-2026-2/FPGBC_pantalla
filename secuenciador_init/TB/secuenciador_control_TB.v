`timescale 1ns / 1ps

module secuenciador_control_TB;
  localparam ARRANQUE = 4'd0;
  localparam ESTABILIZAR = 4'd1;
  localparam ARMAR_PREPARACION = 4'd2;
  localparam PREPARAR_LP = 4'd3;
  localparam REPOSO_INICIAL = 4'd4;
  localparam CARGAR_DESCRIPTOR = 4'd5;
  localparam VALIDAR_DESCRIPTOR = 4'd6;
  localparam PREPARAR_PAQUETE = 4'd7;
  localparam ARMAR_ACEPTACION = 4'd8;
  localparam SOLICITAR = 4'd9;
  localparam TRANSMITIR = 4'd10;
  localparam ESPERAR_COMANDO = 4'd11;
  localparam AVANZAR = 4'd12;
  localparam LISTO = 4'd13;
  localparam FALLO = 4'd14;

  reg clk = 0;
  always #12.5 clk = !clk;
  reg rst = 1;
  reg lp_habilitada = 1;
  reg descriptor_valido = 1;
  reg manual = 0;
  reg ack_manual = 0, ocupado_manual = 0, terminado_manual = 0;
  reg ack_modelo = 0, ocupado_modelo = 0, terminado_modelo = 0;
  wire aceptado = manual ? ack_manual : ack_modelo;
  wire ocupado = manual ? ocupado_manual : ocupado_modelo;
  wire terminado = manual ? terminado_manual : terminado_modelo;
  wire rst_paso, inc_paso, ld_desc, rst_t, inc_t, ld_causa;
  wire [2:0] sel_t, causa_fsm;
  wire solicitud, permiso_arranque, preparar_lp, abortar_motor;
  wire init_en_curso, init_completa, fallo;
  reg [3:0] paso = 0;
  reg [3:0] paso_activo = 0;
  reg [3:0] longitud_activa = 0;
  reg [15:0] espera_activa = 0;
  reg [15:0] tiempo = 0;
  reg [2:0] causa = 0;
  reg [15:0] t_est = 2, t_reposo = 2, t_preparacion = 8;
  reg [15:0] t_aceptacion = 8, t_transmision = 40;
  reg [15:0] limite;
  integer retardo_aceptacion = 2;
  integer cuenta_aceptacion = 0;
  integer cuenta_transmision = 0;
  integer envios = 0, descriptores = 0, avances = 0, capturas = 0;
  integer estados_visitados = 0;
  integer ciclos_espera = 0;
  integer espera_guardada = 0;
  integer fase, combinacion, caso;
  reg [3:0] estado_anterior;
  reg [18:0] controles_antes;
  wire [18:0] controles = {
      rst_paso, inc_paso, ld_desc, sel_t, rst_t, inc_t, ld_causa, causa_fsm,
      solicitud, permiso_arranque, preparar_lp, abortar_motor,
      init_en_curso, init_completa, fallo
  };
  wire fin_t = tiempo == limite;

  secuenciador_control dut (
      .clk(clk), .rst(rst), .ultimo_paso(paso == 10),
      .descriptor_valido(descriptor_valido), .fin_t(fin_t),
      .lp_preparada(lp_habilitada && preparar_lp),
      .aceptado(aceptado), .ocupado(ocupado), .terminado(terminado),
      .rst_paso(rst_paso), .inc_paso(inc_paso), .ld_desc(ld_desc),
      .sel_t(sel_t), .rst_t(rst_t), .inc_t(inc_t),
      .ld_causa(ld_causa), .causa_fsm(causa_fsm),
      .solicitud(solicitud), .permiso_arranque(permiso_arranque),
      .preparar_lp(preparar_lp), .abortar_motor(abortar_motor),
      .init_en_curso(init_en_curso), .init_completa(init_completa), .fallo(fallo)
  );

  always @(*) begin
    case (sel_t)
      3'd0: limite = t_est;
      3'd1: limite = t_reposo;
      3'd2: limite = espera_activa;
      3'd3: limite = t_preparacion;
      3'd4: limite = t_aceptacion;
      3'd5: limite = t_transmision;
      default: limite = 16'hffff;
    endcase
  end

  function [3:0] longitud(input [3:0] indice);
    case (indice)
      2: longitud = 12;
      3, 6: longitud = 10;
      7: longitud = 15;
      default: longitud = 4;
    endcase
  endfunction

  always @(negedge clk) begin
    if (rst || rst_paso) paso <= 0;
    else if (inc_paso) paso <= paso + 1'b1;
    if (rst || rst_t) tiempo <= 0;
    else if (inc_t) tiempo <= tiempo + 1'b1;
    if (rst) begin
      causa <= 0;
      paso_activo <= 0;
      longitud_activa <= 0;
      espera_activa <= 0;
    end else begin
      if (ld_causa) begin
        causa <= causa_fsm;
        capturas = capturas + 1;
      end
      if (ld_desc) begin
        if (paso !== descriptores[3:0]) $fatal(1, "FAIL: orden de descriptores");
        paso_activo <= paso;
        longitud_activa <= longitud(paso);
        espera_activa <= paso[0] ? 16'd3 : 16'd0;
        descriptores = descriptores + 1;
      end
      if (inc_paso) avances = avances + 1;
      if (aceptado && !manual) begin
        if (paso_activo !== envios[3:0] || longitud_activa !== longitud(paso_activo))
          $fatal(1, "FAIL: descriptor antes de aceptar");
        envios = envios + 1;
      end
    end
  end

  always @(posedge clk) begin
    if (rst || abortar_motor || manual) begin
      ack_modelo <= 0;
      ocupado_modelo <= 0;
      terminado_modelo <= 0;
      cuenta_aceptacion <= 0;
      cuenta_transmision <= 0;
    end else begin
      ack_modelo <= 0;
      terminado_modelo <= 0;
      if (!ocupado_modelo) begin
        if (solicitud && permiso_arranque) begin
          if (cuenta_aceptacion == retardo_aceptacion) begin
            ack_modelo <= 1;
            ocupado_modelo <= 1;
            cuenta_aceptacion <= 0;
            cuenta_transmision <= 0;
          end else cuenta_aceptacion <= cuenta_aceptacion + 1;
        end else cuenta_aceptacion <= 0;
      end else begin
        if (cuenta_transmision == longitud_activa + 2) begin
          ocupado_modelo <= 0;
          terminado_modelo <= 1;
        end else cuenta_transmision <= cuenta_transmision + 1;
      end
    end
  end

  always @(posedge clk) begin
    estado_anterior = dut.state;
    #1;
    if ((^controles) === 1'bx) $fatal(1, "FAIL: controles desconocidos");
    if ((rst_t && inc_t) || (rst_paso && inc_paso))
      $fatal(1, "FAIL: reset e incremento simultaneos");
    if (solicitud !== permiso_arranque) $fatal(1, "FAIL: solicitud sin permiso");
    estados_visitados = estados_visitados | (1 << dut.state);
    if (!rst) begin
      if (estado_anterior == ESPERAR_COMANDO) begin
        ciclos_espera = ciclos_espera + 1;
        if (dut.state != ESPERAR_COMANDO && dut.state != FALLO &&
            ciclos_espera != espera_guardada + 1)
          $fatal(1, "FAIL: espera %0d ciclos, esperado %0d", ciclos_espera, espera_guardada + 1);
      end
      if (estado_anterior != ESPERAR_COMANDO && dut.state == ESPERAR_COMANDO) begin
        ciclos_espera = 0;
        espera_guardada = espera_activa;
        if (!rst_t || inc_t || sel_t != 2)
          $fatal(1, "FAIL: inicio de espera");
      end
      if (ocupado && !manual && (paso !== paso_activo || ld_desc || inc_paso))
        $fatal(1, "FAIL: descriptor alterado durante envio");
    end
  end

  always @(negedge clk) begin
    controles_antes = controles;
    #1;
    if (!rst && controles !== controles_antes)
      $fatal(1, "FAIL: controles cambiaron al capturar el datapath");
  end

  task tick;
    begin
      @(posedge clk); #2;
      @(negedge clk); #2;
    end
  endtask

  task preparar_caso(input modo_manual);
    begin
      rst = 1;
      manual = modo_manual;
      ack_manual = 0;
      ocupado_manual = 0;
      terminado_manual = 0;
      lp_habilitada = 1;
      descriptor_valido = 1;
      t_est = 2;
      t_reposo = 2;
      t_preparacion = 8;
      t_aceptacion = 8;
      t_transmision = 40;
      retardo_aceptacion = 2;
      tick;
      if (dut.state !== ARRANQUE || !rst_paso || !rst_t || solicitud ||
          permiso_arranque || preparar_lp || fallo || init_completa || init_en_curso ||
          paso !== 0 || causa !== 0 || ld_causa)
        $fatal(1, "FAIL: reset");
      envios = 0;
      descriptores = 0;
      avances = 0;
      capturas = 0;
      rst = 0;
    end
  endtask

  task esperar_estado(input [3:0] esperado);
    integer n;
    begin
      n = 0;
      while (dut.state !== esperado) begin
        if (fallo || n >= 2000)
          $fatal(1, "FAIL: esperando estado %0d, actual %0d, causa %0d", esperado, dut.state, causa);
        tick;
        n = n + 1;
      end
    end
  endtask

  task comprobar_fallo(input [2:0] esperado);
    integer n;
    begin
      n = 0;
      while (!fallo) begin
        tick;
        n = n + 1;
        if (n >= 2000) $fatal(1, "FAIL: timeout esperando fallo %0d", esperado);
      end
      if (causa !== esperado || !abortar_motor || !preparar_lp || solicitud ||
          permiso_arranque || init_en_curso || init_completa || ld_desc || inc_paso ||
          inc_t || rst_t || rst_paso || capturas != 1)
        $fatal(1, "FAIL: causa esperada %0d, observada %0d", esperado, causa);
      manual = 1;
      ack_manual = 1;
      ocupado_manual = 1;
      terminado_manual = 1;
      lp_habilitada = 1;
      descriptor_valido = 1;
      repeat (3) tick;
      if (causa !== esperado || causa_fsm !== esperado || capturas != 1 || ld_causa || !fallo)
        $fatal(1, "FAIL: primera causa no enclavada");
    end
  endtask

  task entrar_transmision;
    begin
      esperar_estado(SOLICITAR);
      ack_manual = 1;
      ocupado_manual = 1;
      tick;
      if (dut.state !== TRANSMITIR || !rst_t || inc_t || sel_t != 5 || solicitud || permiso_arranque)
        $fatal(1, "FAIL: entrada en transmision");
      ack_manual = 0;
    end
  endtask

  initial begin
    $dumpfile("secuenciador_control_TB.vcd");
    $dumpvars(0, secuenciador_control_TB);
    tick;

    for (caso = 0; caso < 2; caso = caso + 1) begin
      preparar_caso(0);
      if (caso == 1) begin
        t_est = 0;
        t_reposo = 0;
        retardo_aceptacion = 4;
      end
      esperar_estado(LISTO);
      if (!init_completa || init_en_curso || !preparar_lp || paso != 10 ||
          envios != 11 || descriptores != 11 || avances != 10 || capturas != 0)
        $fatal(1, "FAIL: secuencia completa");
      repeat (10) tick;
      if (envios != 11 || solicitud || permiso_arranque || !init_completa)
        $fatal(1, "FAIL: envios duplicados en LISTO");
    end
    $display("PASS: 11 pasos, esperas exactas, aceptacion retrasada y ausencia de duplicados");

    preparar_caso(1);
    lp_habilitada = 0;
    esperar_estado(PREPARAR_LP);
    repeat (2) tick;
    if (!preparar_lp || solicitud || dut.state != PREPARAR_LP)
      $fatal(1, "FAIL: espera de preparacion LP");
    lp_habilitada = 1;
    tick;
    if (dut.state != REPOSO_INICIAL || sel_t != 1 || !rst_t || inc_t)
      $fatal(1, "FAIL: entrada a reposo inicial");

    preparar_caso(1);
    lp_habilitada = 0;
    comprobar_fallo(1);
    preparar_caso(1);
    comprobar_fallo(2);
    preparar_caso(1);
    t_transmision = 3;
    entrar_transmision;
    comprobar_fallo(3);
    preparar_caso(1);
    descriptor_valido = 0;
    comprobar_fallo(4);
    $display("PASS: preparacion LP retrasada, tres timeouts y descriptor invalido");

    for (fase = REPOSO_INICIAL; fase <= LISTO; fase = fase + 1) begin
      preparar_caso(0);
      esperar_estado(fase[3:0]);
      lp_habilitada = 0;
      comprobar_fallo(5);
    end
    $display("PASS: perdida LP desde REPOSO_INICIAL hasta LISTO");

    for (combinacion = 0; combinacion < 8; combinacion = combinacion + 1) begin
      if (combinacion != 0 && combinacion != 6) begin
        preparar_caso(1);
        esperar_estado(SOLICITAR);
        {ack_manual, ocupado_manual, terminado_manual} = combinacion[2:0];
        comprobar_fallo(6);
      end
      if (combinacion != 1 && combinacion != 2) begin
        preparar_caso(1);
        entrar_transmision;
        {ack_manual, ocupado_manual, terminado_manual} = combinacion[2:0];
        comprobar_fallo(6);
      end
    end
    for (fase = ARMAR_PREPARACION; fase <= LISTO; fase = fase + 1) begin
      if (fase != SOLICITAR && fase != TRANSMITIR) begin
        preparar_caso(0);
        esperar_estado(fase[3:0]);
        manual = 1;
        ack_manual = 1;
        comprobar_fallo(6);
      end
    end
    $display("PASS: incoherencias de handshake por estado");

    preparar_caso(1);
    esperar_estado(VALIDAR_DESCRIPTOR);
    descriptor_valido = 0;
    ack_manual = 1;
    comprobar_fallo(6);
    preparar_caso(1);
    esperar_estado(VALIDAR_DESCRIPTOR);
    descriptor_valido = 0;
    ack_manual = 1;
    lp_habilitada = 0;
    comprobar_fallo(5);
    preparar_caso(1);
    t_preparacion = 0;
    lp_habilitada = 0;
    esperar_estado(PREPARAR_LP);
    ack_manual = 1;
    comprobar_fallo(6);
    $display("PASS: prioridades de causa 5 > 6 > 4 y 6 > timeout");

    preparar_caso(1);
    t_preparacion = 0;
    t_aceptacion = 0;
    t_transmision = 0;
    entrar_transmision;
    ocupado_manual = 0;
    terminado_manual = 1;
    tick;
    if (dut.state != ESPERAR_COMANDO || !rst_t || inc_t || sel_t != 2)
      $fatal(1, "FAIL: terminado prioritario al timeout");
    terminado_manual = 0;
    $display("PASS: preparacion, aceptacion y terminado antes del timeout simultaneo");

    for (fase = ARRANQUE; fase <= FALLO; fase = fase + 1) begin
      preparar_caso(0);
      if (fase == FALLO) descriptor_valido = 0;
      esperar_estado(fase[3:0]);
      rst = 1;
      manual = 1;
      ack_manual = 1;
      ocupado_manual = 1;
      terminado_manual = 1;
      lp_habilitada = 0;
      tick;
      if (dut.state !== ARRANQUE || causa !== 0 || fallo || ld_causa ||
          solicitud || permiso_arranque || init_completa || !rst_paso || !rst_t)
        $fatal(1, "FAIL: reset en estado %0d", fase);
    end
    preparar_caso(0);
    esperar_estado(LISTO);
    if (envios != 11 || !init_completa) $fatal(1, "FAIL: recuperacion tras reset");
    if ((estados_visitados & 32767) != 32767) $fatal(1, "FAIL: estados sin visitar");
    $display("PASS: reset prioritario en los 15 estados y secuencia posterior");
    $display("PASS: secuenciador_control_TB; control con datapath y motor modelados");
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "FAIL: timeout secuenciador_control_TB");
  end
endmodule
