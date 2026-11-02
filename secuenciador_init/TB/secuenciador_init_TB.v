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
  wire [3:0] pos, cantidad_bytes;
  wire [7:0] byte_almacen;
  wire [1:0] estado_D0;
  reg [7:0] recibidos [0:14];
  reg [7:0] reconstruido;
  reg [7:0] valor;
  reg [1:0] lp_esperado;
  reg [15:0] crc;
  integer paso, n, c, offset, bit_n, byte_n, fin_datos, total;
  integer i, j, wc;
  integer envios = 0, descriptores = 0;
  time inicio_espera;

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

  motor_lpdt #(.ANCHO_LONGITUD(4)) motor (
      .clk(clk), .rst(rst_motor), .permiso_arranque(permiso_arranque),
      .solicitud(solicitud), .cantidad_bytes(cantidad_bytes), .byte_almacen(byte_almacen),
      .aceptado(aceptado), .ocupado(ocupado), .terminado(terminado),
      .pos(pos), .estado_D0(estado_D0)
  );

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

  always @(negedge clk) begin
    if (!rst) begin
      if (aceptado) envios = envios + 1;
      if (dut.w_ld_desc) descriptores = descriptores + 1;
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

    for (paso = 0; paso < 11; paso = paso + 1) begin
      wait (aceptado === 1'b1); #1;
      n = longitud(paso);
      if (cantidad_bytes !== n[3:0] || dut.w_paso !== paso[3:0])
        $fatal(1, "FAIL: descriptor integrado paso %0d", paso);
      fin_datos = 16 + (n + 1) * 64;
      total = fin_datos + 4;
      reconstruido = 0;

      for (c = 0; c <= total; c = c + 1) begin
        @(negedge clk); #1;
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
        if (dut.w_paso !== paso[3:0] || cantidad_bytes !== n[3:0] || dut.w_ld_desc)
          $fatal(1, "FAIL: paquete alterado durante envio");
      end

      if (recibidos[3] !== ecc({recibidos[2], recibidos[1], recibidos[0]}))
        $fatal(1, "FAIL: ECC paso %0d", paso);
      if (recibidos[0] == 8'h39) begin
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

    if (!init_completa || init_en_curso || codigo_fallo !== 0 || envios != 11 || descriptores != 11)
      $fatal(1, "FAIL: secuencia integrada completa");
    repeat (5) begin
      @(posedge clk); #1;
      if (aceptado || solicitud || permiso_arranque || !init_completa)
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
