`timescale 1ns / 1ps

module secuenciador_init_TB;
  reg clk = 0;
  always #12.5 clk = !clk;
  reg rst = 1;
  reg lp_preparada = 0;
  wire preparar_lp, solicitud, permiso_arranque, rst_motor;
  wire aceptado, ocupado, terminado;
  wire init_en_curso, init_completa, fallo;
  wire [2:0] codigo_fallo;
  wire [4:0] pos, cantidad_bytes;
  wire [7:0] byte_almacen;
  wire [1:0] estado_D0;
  reg [7:0] recibidos [0:21];
  reg [7:0] reconstruido;
  reg [7:0] valor;
  reg [1:0] lp_esperado;
  reg [15:0] crc;
  integer paso, n, c, offset, bit_n, byte_n, fin_datos, total;
  integer i, j, wc;
  integer envios = 0, descriptores = 0;
  integer ecc_validos = 0, crc_validos = 0;
  time inicio_espera;
  realtime fin_lp_anterior = 0;

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("secuenciador_init_TB.fst");
      $dumpvars(0, secuenciador_init_TB);
    end
  end

  secuenciador_init #(
      .T_ESTABILIZACION(23'd2),
      .T_REPOSO_INICIAL(23'd3),
      .TIMEOUT_PREPARACION(23'd8)
  ) dut (
      .clk(clk), .rst(rst),
      .lp_preparada(lp_preparada), .preparar_lp(preparar_lp),
      .aceptado(aceptado), .ocupado(ocupado), .terminado(terminado),
      .pos(pos), .solicitud(solicitud), .permiso_arranque(permiso_arranque),
      .cantidad_bytes(cantidad_bytes), .byte_almacen(byte_almacen), .rst_motor(rst_motor),
      .init_en_curso(init_en_curso), .init_completa(init_completa),
      .fallo(fallo), .codigo_fallo(codigo_fallo)
  );

  motor_lpdt #(.ANCHO_LONGITUD(5)) motor (
      .clk(clk), .rst(rst_motor), .permiso_arranque(permiso_arranque),
      .solicitud(solicitud), .cantidad_bytes(cantidad_bytes), .byte_almacen(byte_almacen),
      .aceptado(aceptado), .ocupado(ocupado), .terminado(terminado),
      .pos(pos), .estado_D0(estado_D0)
  );

  function integer longitud(input integer p);
    case (p)
      1: longitud = 12;
      2: longitud = 10;
      4, 11: longitud = 4;
      5: longitud = 9;
      6: longitud = 19;
      7: longitud = 18;
      8, 13: longitud = 15;
      14: longitud = 22;
      15: longitud = 20;
      default: longitud = 8;
    endcase
  endfunction

  function integer espera(input integer p);
    case (p)
      4, 9: espera = 2600000;
      17: espera = 0;
      default: espera = 360000;
    endcase
  endfunction

  // Vectores fijos independientes de la ROM, extraídos de la captura LP.
  function [175:0] paquete(input integer p);
    case (p)
      0: paquete = 64'h29020000B000D6CA;
      1: paquete = 96'h29060023E400000000088716;
      2: paquete = 80'h2904003FD0454571429E;
      3: paquete = 64'h090200150000B8F0;
      4: paquete = 32'h05114504;
      5: paquete = 72'h2903001AD0524A25BB;
      6: paquete = 152'h290D0000B902007600BABBBFCCE3468131D0E5;
      7: paquete = 144'h290C001ABDFFFEFEFEFEFEFE802000002AE3;
      8: paquete = 120'h29090023BEFF0F00180404005DE7C4;
      9: paquete = 64'h29020000B0034DF8;
      10: paquete = 64'h090200150000B8F0;
      11: paquete = 32'h0529031F;
      12: paquete = 64'h29020000B000D6CA;
      13: paquete = 120'h29090023BEFF0F00180404005DE7C4;
      14: paquete = 176'h2910003AB7180018180C09AC095C090C090010004432;
      15: paquete = 160'h290E0006B8F8DA6DFBFFFF4F1F7F9FBFDFFFAB18;
      16: paquete = 64'h29020000BB2F8BF7;
      17: paquete = 64'h29020000B0034DF8;
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

  always @(negedge clk) begin
    if (!rst) begin
      if (aceptado) envios = envios + 1;
      if (dut.w_ld_desc) descriptores = descriptores + 1;
      #1;
      if (dut.ctrl.state == dut.ctrl.ESPERAR_COMANDO && estado_D0 !== 2'b11)
        $fatal(1, "FAIL: no se mantuvo LP-11 durante la espera");
    end
  end

  initial begin
    @(posedge clk);
    @(negedge clk); #1;
    if (!rst_motor || codigo_fallo !== 0 || cantidad_bytes !== 0 || dut.w_paso !== 0)
      $fatal(1, "FAIL: reset integrado");
    rst = 0;
    wait (preparar_lp === 1'b1);
    @(negedge clk); #1;
    lp_preparada = 1;

    for (paso = 0; paso < 18; paso = paso + 1) begin
      wait (aceptado === 1'b1); #1;
      n = longitud(paso);
      if (cantidad_bytes !== n[4:0] || dut.w_paso !== paso[4:0])
        $fatal(1, "FAIL: descriptor integrado paso %0d", paso);
      fin_datos = 16 + (n + 1) * 64;
      total = fin_datos + 4;
      reconstruido = 0;

      for (c = 0; c <= total; c = c + 1) begin
        @(negedge clk); #1;
        // Intervalo real en D0: espera ROM más 9 ciclos de handshake/control.
        if (c == 0 && paso > 0 &&
            $realtime - fin_lp_anterior != (espera(paso - 1) + 9) * 25)
          $fatal(1, "FAIL: intervalo LP-11 a Escape paso %0d: %0.1f ns",
                 paso, $realtime - fin_lp_anterior);
        if (c < 4) lp_esperado = 2'b10;
        else if (c < 8) lp_esperado = 2'b00;
        else if (c < 12) lp_esperado = 2'b01;
        else if (c < 16) lp_esperado = 2'b00;
        else if (c < fin_datos) begin
          offset = c - 16;
          bit_n = (offset % 64) / 8;
          byte_n = offset / 64;
          valor = byte_n == 0 ? 8'h87 : byte_esperado(paso, byte_n - 1);
          lp_esperado = offset % 8 >= 4 ? 2'b00 : (valor[bit_n] ? 2'b10 : 2'b01);
          if (offset % 8 == 3) reconstruido[bit_n] = estado_D0[1];
          if (offset % 64 == 63) begin
            if (reconstruido !== valor) $fatal(1, "FAIL: byte paso %0d indice %0d", paso, byte_n);
            if (byte_n != 0) recibidos[byte_n - 1] = reconstruido;
          end
        end else if (c < total) lp_esperado = 2'b10;
        else lp_esperado = 2'b11;

        if (estado_D0 !== lp_esperado || pos >= cantidad_bytes || fallo || init_completa)
          $fatal(1, "FAIL: LPDT paso %0d ciclo %0d", paso, c);
        if (dut.w_paso !== paso[4:0] || cantidad_bytes !== n[4:0] || dut.w_ld_desc)
          $fatal(1, "FAIL: paquete alterado durante envio");
      end
      fin_lp_anterior = $realtime;

      if (recibidos[3] !== ecc({recibidos[2], recibidos[1], recibidos[0]}))
        $fatal(1, "FAIL: ECC paso %0d", paso);
      ecc_validos = ecc_validos + 1;
      if (recibidos[0] == 8'h29 || recibidos[0] == 8'h09) begin
        wc = {recibidos[2], recibidos[1]};
        if (wc + 6 != n) $fatal(1, "FAIL: WC paso %0d", paso);
        crc = 16'hffff;
        for (i = 0; i < wc; i = i + 1) begin
          crc = crc ^ {8'd0, recibidos[4 + i]};
          for (j = 0; j < 8; j = j + 1)
            crc = crc[0] ? (crc >> 1) ^ 16'h8408 : crc >> 1;
        end
        if ({recibidos[n-1], recibidos[n-2]} !== crc)
          $fatal(1, "FAIL: CRC paso %0d", paso);
        crc_validos = crc_validos + 1;
      end

      @(posedge clk); #1;
      if (!terminado || ocupado) $fatal(1, "FAIL: fin de motor");
      @(posedge clk); #1;
      if (dut.ctrl.state !== dut.ctrl.ESPERAR_COMANDO || !dut.w_rst_t || dut.w_inc_t)
        $fatal(1, "FAIL: inicio de espera integrada");
      inicio_espera = $time;
      wait (dut.ctrl.state != dut.ctrl.ESPERAR_COMANDO); #1;
      if ($time - inicio_espera != (espera(paso) + 1) * 25 || fallo)
        $fatal(1, "FAIL: espera integrada paso %0d", paso);
      $display("PASS: paso %0d, %0d bytes reconstruidos, ECC/CRC y espera %0d ciclos", paso, n, espera(paso));
    end

    if (!init_completa || init_en_curso || codigo_fallo !== 0 ||
        envios != 18 || descriptores != 18 || ecc_validos != 18 || crc_validos != 16)
      $fatal(1, "FAIL: secuencia integrada completa");
    repeat (5) begin
      @(posedge clk); #1;
      if (aceptado || solicitud || permiso_arranque || !init_completa || estado_D0 !== 2'b11)
        $fatal(1, "FAIL: duplicados tras inicializar");
    end
    @(negedge clk); #1;
    lp_preparada = 0;
    @(posedge clk);
    @(negedge clk); #1;
    if (!fallo || codigo_fallo !== 5 || !rst_motor || init_completa)
      $fatal(1, "FAIL: perdida LP integrada");
    rst = 1;
    @(posedge clk);
    @(negedge clk); #1;
    if (codigo_fallo !== 0 || fallo || cantidad_bytes !== 0 || dut.w_paso !== 0)
      $fatal(1, "FAIL: reset tras fallo integrado");
    $display("PASS: secuenciador_init_TB; ROM y datapath reales, motor LPDT externo real");
    $finish;
  end

  initial begin
    #300000000;
    $fatal(1, "FAIL: timeout secuenciador_init_TB");
  end
endmodule
