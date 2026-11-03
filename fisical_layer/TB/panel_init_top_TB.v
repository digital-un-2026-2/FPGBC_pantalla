`timescale 1ns / 1ps

module panel_init_top_TB;
  reg clk = 0;
  always #12.5 clk = !clk;
  reg rst = 1;
  tri D0_P, D0_N;
  wire CLK_P, CLK_N, D1_P, D1_N;
  wire [5:0] hs_pads;
  wire d0_pad_p, d0_pad_n;
  wire init_en_curso, init_completa, fallo;
  wire [2:0] codigo_fallo;
  reg [7:0] recibidos [0:14];
  integer paso;
  integer envios = 0;
  integer finales = 0;
  integer envios_antes, finales_antes;
  time habilitacion_inicial;

  // Solo se acortan arranque y timeout de preparacion. La ROM conserva los
  // 285 ms reales de esperas DCS y el motor conserva todas sus fases LP.
  panel_init_top #(
      .T_ESTABILIZACION(23'd2),
      .T_REPOSO_INICIAL(23'd3),
      .TIMEOUT_PREPARACION(23'd8)
  ) dut (
      .clk(clk), .rst(rst), .D0_P(D0_P), .D0_N(D0_N),
      .CLK_P(CLK_P), .CLK_N(CLK_N), .D1_P(D1_P), .D1_N(D1_N),
      .hs_pads(hs_pads), .d0_pad_p(d0_pad_p), .d0_pad_n(d0_pad_n),
      .init_en_curso(init_en_curso), .init_completa(init_completa),
      .fallo(fallo), .codigo_fallo(codigo_fallo)
  );

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("panel_init_top_TB.fst");
      $dumpvars(0, panel_init_top_TB);
    end
  end

  // Comprobacion por eventos, tambien entre flancos: sin registro de salida
  // adicional ni condicionamiento por permiso_arranque durante el envio.
  always @(D0_P or D0_N or CLK_P or CLK_N or D1_P or D1_N or hs_pads or
           d0_pad_p or d0_pad_n or dut.w_estado_D0 or dut.w_rst_motor or
           dut.w_preparar_lp or dut.w_liberar_d0 or dut.w_lp_preparada) begin
    #0.001;
    if (dut.w_rst_motor === 1'b1 || dut.w_preparar_lp === 1'b0) begin
      if ({D0_P, D0_N, CLK_P, CLK_N, D1_P, D1_N} !== 6'bzzzzzz || dut.w_lp_preparada !== 1'b0)
        $fatal(1, "FAIL: salidas LP no liberadas al deshabilitar");
    end else if (dut.w_rst_motor === 1'b0 && dut.w_preparar_lp === 1'b1) begin
      if ({CLK_P, CLK_N, D1_P, D1_N} !== 4'b1111)
        $fatal(1, "FAIL: CLK/D1 fuera de LP-11");
      if (dut.w_liberar_d0) begin
        if ({D0_P, D0_N} !== 2'bzz || dut.w_lp_preparada !== 1'b0)
          $fatal(1, "FAIL: liberacion D0 integrada");
      end else if ({D0_P, D0_N} !== dut.w_estado_D0 || dut.w_lp_preparada !== 1'b1) begin
        $fatal(1, "FAIL: D0 no sigue directamente al motor");
      end
    end
    if ({d0_pad_p, d0_pad_n} !== {D0_P, D0_N})
      $fatal(1, "FAIL: lectura de pads integrada");
    if (hs_pads !== 6'bzzzzzz || dut.w_hs_oen !== 6'b111111)
      $fatal(1, "FAIL: rama HS no liberada");
  end

  always @(posedge dut.w_lp_preparada) begin
    #0.001;
    if ({D0_P, D0_N} !== 2'b11)
      $fatal(1, "FAIL: D0 no estaba inicializado en LP-11 al habilitar");
  end

  always @(negedge clk) begin
    if (!rst) begin
      if (dut.w_aceptado) envios = envios + 1;
      if (dut.w_terminado) finales = finales + 1;
    end
  end

  function integer longitud(input integer p);
    case (p)
      2: longitud = 12;
      3, 6: longitud = 10;
      7: longitud = 15;
      default: longitud = 4;
    endcase
  endfunction

  function integer espera(input integer p);
    case (p)
      0, 9: espera = 800000;
      1: espera = 200000;
      5, 10: espera = 4800000;
      default: espera = 0;
    endcase
  endfunction

  // Vectores de referencia independientes de las salidas de las ROM del DUT.
  function [119:0] paquete(input integer p);
    case (p)
      0: paquete = 32'h05010010;
      1: paquete = 32'h15B0003A;
      2: paquete = 96'h39060030E400000000088716;
      3: paquete = 80'h3904002CD0454571429E;
      4: paquete = 32'h156F012B;
      5: paquete = 32'h05110036;
      6: paquete = 80'h3904002CD0524A711A14;
      7: paquete = 120'h39090030BEFF0F00180404005DE7C4;
      8: paquete = 32'h15BB2F39;
      9: paquete = 32'h15B02F1A;
      10: paquete = 32'h0529001C;
      default: paquete = 0;
    endcase
  endfunction

  function [7:0] byte_esperado(input integer p, input integer b);
    byte_esperado = paquete(p) >> (8 * (longitud(p) - 1 - b));
  endfunction

  function [7:0] ecc(input [23:0] header);
    begin
      ecc[0] = ^(header & 24'hF12CB7);
      ecc[1] = ^(header & 24'hF2555B);
      ecc[2] = ^(header & 24'h749A6D);
      ecc[3] = ^(header & 24'hB8E38E);
      ecc[4] = ^(header & 24'hDF03F0);
      ecc[5] = ^(header & 24'hEFFC00);
      ecc[7:6] = 0;
    end
  endfunction

  // Decodificador de prueba dependiente de las fases LP conocidas del motor.
  // Lee los puertos D0 despues de los IOBUF, no estado_D0 interno.
  task recibir_paquete(input integer p);
    integer n, c, offset, bit_n, byte_n, fin_datos, total, i, j, wc;
    reg [7:0] valor, reconstruido;
    reg [1:0] esperado;
    reg [15:0] crc;
    begin
      wait (dut.w_aceptado === 1'b1); #1;
      n = longitud(p);
      if (dut.w_cantidad_bytes !== n[3:0] || dut.init.w_paso !== p[3:0])
        $fatal(1, "FAIL: descriptor del top paso %0d", p);
      fin_datos = 16 + (n + 1) * 64;
      total = fin_datos + 4;
      reconstruido = 0;
      for (c = 0; c <= total; c = c + 1) begin
        @(negedge clk); #1;
        if (c < 4) esperado = 2'b10;
        else if (c < 8) esperado = 2'b00;
        else if (c < 12) esperado = 2'b01;
        else if (c < 16) esperado = 2'b00;
        else if (c < fin_datos) begin
          offset = c - 16;
          bit_n = (offset % 64) / 8;
          byte_n = offset / 64;
          valor = byte_n == 0 ? 8'h87 : byte_esperado(p, byte_n - 1);
          esperado = offset % 8 >= 4 ? 2'b00 : (valor[bit_n] ? 2'b10 : 2'b01);
          if (offset % 8 == 3) reconstruido[bit_n] = D0_P;
          if (offset % 64 == 63) begin
            if (reconstruido !== valor)
              $fatal(1, "FAIL: byte en pads paso %0d indice %0d", p, byte_n);
            if (byte_n != 0) recibidos[byte_n - 1] = reconstruido;
          end
        end else if (c < total) esperado = 2'b10;
        else esperado = 2'b11;
        if ({D0_P, D0_N} !== esperado || fallo || init_completa || !dut.w_lp_preparada)
          $fatal(1, "FAIL: LPDT en pads paso %0d ciclo %0d", p, c);
        if (dut.init.w_paso !== p[3:0] || dut.w_cantidad_bytes !== n[3:0])
          $fatal(1, "FAIL: descriptor cambio durante envio");
      end
      if (recibidos[3] !== ecc({recibidos[2], recibidos[1], recibidos[0]}))
        $fatal(1, "FAIL: ECC desde pads paso %0d", p);
      if (recibidos[0] == 8'h39) begin
        wc = {recibidos[2], recibidos[1]};
        if (wc + 6 != n) $fatal(1, "FAIL: WC desde pads paso %0d", p);
        crc = 16'hffff;
        for (i = 0; i < wc; i = i + 1) begin
          crc = crc ^ {8'd0, recibidos[4 + i]};
          for (j = 0; j < 8; j = j + 1)
            crc = crc[0] ? (crc >> 1) ^ 16'h8408 : crc >> 1;
        end
        if ({recibidos[n-1], recibidos[n-2]} !== crc)
          $fatal(1, "FAIL: CRC desde pads paso %0d", p);
      end
      @(posedge clk); #1;
      if (!dut.w_terminado || dut.w_ocupado || {D0_P, D0_N} !== 2'b11)
        $fatal(1, "FAIL: fin de envio en pads");
    end
  endtask

  task esperar_comando(input integer p);
    time inicio;
    begin
      @(posedge clk); #1;
      if (dut.init.ctrl.state !== dut.init.ctrl.ESPERAR_COMANDO)
        $fatal(1, "FAIL: no inicio espera del comando");
      inicio = $time;
      wait (dut.init.ctrl.state != dut.init.ctrl.ESPERAR_COMANDO); #1;
      if ($time - inicio != (espera(p) + 1) * 25 || fallo)
        $fatal(1, "FAIL: espera DCS del top paso %0d", p);
      $display("PASS: top paso %0d, %0d bytes desde pads, ECC/CRC y espera %0d ciclos", p, longitud(p), espera(p));
    end
  endtask

  task comprobar_liberadas;
    begin
      #1;
      if ({D0_P, D0_N, CLK_P, CLK_N, D1_P, D1_N} !== 6'bzzzzzz || dut.w_lp_preparada)
        $fatal(1, "FAIL: LP no liberada");
    end
  endtask

  task aplicar_reset;
    begin
      rst = 1;
      comprobar_liberadas;
      @(posedge clk);
      @(negedge clk); #1;
      if (fallo || codigo_fallo !== 0 || dut.w_estado_D0 !== 2'b11 || dut.w_terminado)
        $fatal(1, "FAIL: reset coordinado del top");
      rst = 0;
    end
  endtask

  initial begin
    aplicar_reset;
    wait (dut.w_lp_preparada === 1'b1);
    habilitacion_inicial = $time;
    wait (dut.w_aceptado === 1'b1);
    if ($time - habilitacion_inicial < 3 * 25)
      $fatal(1, "FAIL: no se respeto el reposo inicial");

    for (paso = 0; paso < 11; paso = paso + 1) begin
      recibir_paquete(paso);
      esperar_comando(paso);
    end
    if (!init_completa || init_en_curso || fallo || codigo_fallo !== 0 || envios != 11 || finales != 11)
      $fatal(1, "FAIL: inicializacion completa del top");
    repeat (8) begin
      @(posedge clk); #1;
      if (dut.w_aceptado || dut.w_solicitud || !init_completa)
        $fatal(1, "FAIL: envio duplicado en LISTO");
    end

    // Inyeccion de fallo, no una interfaz BTA: perder preparacion en LISTO.
    @(negedge clk); #1;
    force dut.w_liberar_d0 = 1'b1;
    @(posedge clk);
    @(negedge clk); #1;
    if (!fallo || codigo_fallo !== 5 || !dut.w_rst_motor || init_completa)
      $fatal(1, "FAIL: perdida LP en LISTO");
    release dut.w_liberar_d0;
    comprobar_liberadas;
    repeat (8) @(posedge clk);
    if (!fallo || envios != 11) $fatal(1, "FAIL: recuperacion automatica inesperada");

    // Reset durante una transmision: aborto sin pulso terminado.
    @(negedge clk); #1;
    aplicar_reset;
    wait (dut.w_aceptado === 1'b1);
    repeat (32) @(negedge clk);
    #2;
    finales_antes = finales;
    aplicar_reset;
    if (finales != finales_antes) $fatal(1, "FAIL: terminado espurio al abortar");
    recibir_paquete(0);

    // Reset durante la espera DCS: el siguiente envio vuelve a Software Reset.
    @(posedge clk); #1;
    if (dut.init.ctrl.state !== dut.init.ctrl.ESPERAR_COMANDO)
      $fatal(1, "FAIL: no se alcanzo espera DCS antes del reset");
    @(negedge clk); #1;
    aplicar_reset;
    wait (dut.w_aceptado === 1'b1);
    repeat (24) @(negedge clk);
    #1;
    finales_antes = finales;
    force dut.w_liberar_d0 = 1'b1;
    @(posedge clk);
    @(negedge clk); #1;
    if (!fallo || codigo_fallo !== 5 || dut.w_terminado || finales != finales_antes)
      $fatal(1, "FAIL: perdida LP durante transmision");
    release dut.w_liberar_d0;
    comprobar_liberadas;

    // Bloquear preparacion desde arranque causa timeout 1, sin ningun envio.
    aplicar_reset;
    envios_antes = envios;
    force dut.w_liberar_d0 = 1'b1;
    wait (fallo === 1'b1);
    @(negedge clk); #1;
    if (codigo_fallo !== 1 || envios != envios_antes || !dut.w_rst_motor)
      $fatal(1, "FAIL: timeout preparacion del top");
    release dut.w_liberar_d0;
    comprobar_liberadas;

    // Solo reset permite salir de FALLO; no se recupera el panel por suposicion.
    aplicar_reset;
    recibir_paquete(0);
    $display("PASS: panel_init_top_TB; 11 paquetes, 285 ms DCS, LP/HS, fallos y reset. Sin modelo de panel ni BTA.");
    $finish;
  end

  initial begin
    #310000000;
    $fatal(1, "FAIL: timeout panel_init_top_TB");
  end
endmodule
