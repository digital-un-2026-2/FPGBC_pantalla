`timescale 1ns/1ps
module lp_target_TB;
  parameter ENABLE_LP = 1;
  reg clk = 0;
  reg reset_n = 1;
  always #12.5 clk = ~clk;
  wire [2:0] lp_p, lp_n, hs_p, hs_n;
  wire backlight_en, backlight_pwm;
  wire [1:0] d0 = {lp_p[0], lp_n[0]};
  integer p, b, bit_n, c, n, offset, fin_datos, total;
  integer bytes_ok = 0;
  reg [7:0] valor, recibido;
  reg [1:0] esperado;
  realtime fin_anterior = 0;

  fpgbc_lp_init dut(
      .clk40(clk), .global_rst_n(reset_n), .dsi_lp_p(lp_p), .dsi_lp_n(lp_n),
      .dsi_hs_p(hs_p), .dsi_hs_n(hs_n)
`ifdef TEST_BACKLIGHT
      , .backlight_en(backlight_en), .backlight_pwm(backlight_pwm)
`endif
  );
  // Solo se acorta la espera inicial de alimentación. Las esperas de 9/65 ms,
  // los timeouts y el reposo inicial LP conservan sus valores de producción.
  defparam dut.secuenciador.T_ESTABILIZACION = 23'd2;

  function integer longitud(input integer paso);
    case (paso)
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

  function integer espera(input integer paso);
    case (paso)
      4, 9: espera = 2600000;
      17: espera = 0;
      default: espera = 360000;
    endcase
  endfunction

  // Vectores de captura, independientes de las ROM del DUT.
  function [175:0] paquete(input integer paso);
    case (paso)
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

  task aislado;
    begin
      if (lp_p !== 3'bzzz || lp_n !== 3'bzzz ||
          hs_p !== 3'bzzz || hs_n !== 3'bzzz)
        $fatal(1, "Pads conduciendo durante aislamiento");
    end
  endtask

  task resetear;
    begin
      @(negedge clk); #2;
      reset_n = 0;
      repeat (5) @(negedge clk);
      #1; aislado;
      repeat (20) begin
        @(negedge clk); #1; aislado;
        if (dut.sys_rst !== 1) $fatal(1, "Botón no mantiene reset global");
      end
      #2; reset_n = 1;
      repeat (10) begin
        @(negedge clk); #1; aislado;
        if (dut.sys_rst !== 1) $fatal(1, "Reset se liberó demasiado pronto");
      end
      wait (dut.sys_rst === 0);
    end
  endtask

  // Comprobación sobre los pads en todos los ciclos, no solo los bytes útiles.
  always @(negedge clk) begin
    #1;
    if (hs_p !== 3'bzzz || hs_n !== 3'bzzz)
      $fatal(1, "HS está conduciendo");
    if (dut.lp_oe === 3'b111) begin
      if (lp_p[2:1] !== 2'b11 || lp_n[2:1] !== 2'b11)
        $fatal(1, "D1/CLK fuera de LP-11");
      if (dut.lp_preparada && d0 !== dut.estado_D0)
        $fatal(1, "Retardo entre motor y pad");
    end else if (dut.lp_oe === 0) begin
      if (lp_p !== 3'bzzz || lp_n !== 3'bzzz)
        $fatal(1, "OE no retira conducción LP");
    end else $fatal(1, "OE indeterminado");
    if (dut.terminado && d0 !== 2'b11)
      $fatal(1, "Terminado antes del retorno físico simulado a LP-11");
    if (ENABLE_LP && (!dut.init_completa || dut.sys_rst || dut.fallo) &&
        {backlight_en, backlight_pwm} !== 2'b00)
      $fatal(1, "Backlight activo antes de terminar INIT o durante reset/fallo");
  end

  initial begin
    #1; aislado;
    if (!ENABLE_LP) begin
      repeat (1000) begin @(negedge clk); #2; aislado; end
      if (dut.sys_rst !== 1) $fatal(1, "Variante aislada liberó reset");
      $display("PASS: target aislado por defecto");
      $finish;
    end

    wait (dut.sys_rst === 0);
    wait (dut.aceptado === 1);
    repeat (20) @(negedge clk);
    resetear; // Aborto por reset durante transmisión.

    wait (dut.aceptado === 1);
    repeat (20) @(negedge clk);
    #2; force dut.fallo = 1'b1;
    #1; aislado; // Inhibición antes del posedge.
    repeat (2) @(posedge clk);
    #2; release dut.fallo;
    repeat (10) begin @(negedge clk); #2; aislado; end
    if (!dut.fallo || !dut.rst_motor) $fatal(1, "Fallo no enclavado");
    resetear;

    for (p = 0; p < 18; p = p + 1) begin
      wait (dut.aceptado === 1); #1;
      n = longitud(p);
      fin_datos = 16 + (n + 1) * 64;
      total = fin_datos + 4;
      recibido = 0;
      for (c = 0; c <= total; c = c + 1) begin
        @(negedge clk); #2;
        if (c == 0 && p > 0 &&
            $realtime - fin_anterior != (espera(p - 1) + 9) * 25)
          $fatal(1, "Espera física simulada incorrecta en paso %0d", p);
        if (c < 4) esperado = 2'b10;
        else if (c < 8) esperado = 2'b00;
        else if (c < 12) esperado = 2'b01;
        else if (c < 16) esperado = 2'b00;
        else if (c < fin_datos) begin
          offset = c - 16;
          b = offset / 64;
          bit_n = (offset % 64) / 8;
          valor = b == 0 ? 8'h87 : paquete(p) >> (8 * (n - b));
          esperado = offset % 8 >= 4 ? 2'b00 : (valor[bit_n] ? 2'b10 : 2'b01);
          if (offset % 8 == 3) recibido[bit_n] = lp_p[0];
          if (offset % 64 == 63) begin
            if (recibido !== valor) $fatal(1, "Byte incorrecto paso %0d byte %0d", p, b);
            if (b != 0) bytes_ok = bytes_ok + 1;
          end
        end else if (c < total) esperado = 2'b10;
        else esperado = 2'b11;
        if (d0 !== esperado || dut.fallo)
          $fatal(1, "LPDT paso %0d ciclo %0d: D0=%b esperado=%b valor=%h fallo=%b",
                 p, c, d0, esperado, valor, dut.fallo);
      end
      fin_anterior = $realtime;
      wait (dut.aceptado === 0);
      $display("PASS: pads paso %0d, %0d bytes", p, n);
    end
    wait (dut.init_completa === 1);
    @(posedge clk);
    #1;
    if ({backlight_en, backlight_pwm} !== 2'b10)
      $fatal(1, "Enable debe subir antes del primer pulso PWM");
    @(posedge clk);
    for (c = 0; c < 80001; c = c + 1) begin
      @(negedge clk); #2;
      if (backlight_en !== 1'b1 || backlight_pwm !== (c % 40000 < 20000))
        $fatal(1, "Backlight: PWM incorrecto en el ciclo %0d", c);
    end
    force dut.fallo = 1'b1;
    #1;
    if ({backlight_en, backlight_pwm} !== 2'b00)
      $fatal(1, "El fallo no apagó el backlight durante un pulso");
    release dut.fallo;
    repeat (10) begin
      @(negedge clk); #2;
      if (lp_p !== 3'b111 || lp_n !== 3'b111 || dut.solicitud || dut.fallo)
        $fatal(1, "Reposo final incorrecto");
    end
    if (bytes_ok != 204) $fatal(1, "No se reconstruyeron 204 bytes");
    $display("PASS: 18 paquetes / 204 bytes desde pads, pausas reales y abortos");
    resetear;
    wait (dut.aceptado === 1);
    // Volver a comprobar el selector y el primer paquete completo tras LISTO.
    n = longitud(0);
    fin_datos = 16 + (n + 1) * 64;
    total = fin_datos + 4;
    for (c = 0; c <= total; c = c + 1) begin
      @(negedge clk); #2;
      if (c < 4) esperado = 2'b10;
      else if (c < 8) esperado = 2'b00;
      else if (c < 12) esperado = 2'b01;
      else if (c < 16) esperado = 2'b00;
      else if (c < fin_datos) begin
        offset = c - 16;
        b = offset / 64;
        bit_n = (offset % 64) / 8;
        valor = b == 0 ? 8'h87 : paquete(0) >> (8 * (n - b));
        esperado = offset % 8 >= 4 ? 2'b00 : (valor[bit_n] ? 2'b10 : 2'b01);
      end else if (c < total) esperado = 2'b10;
      else esperado = 2'b11;
      if (d0 !== esperado || dut.fallo)
        $fatal(1, "No se reinició el primer paquete tras el botón");
    end
    $display("PASS: botón físico aborta, mantiene reset y reinicia desde paso 0 tras LISTO");
    $finish;
  end

  initial begin
    #300000000;
    $fatal(1, "Timeout de integración");
  end
endmodule
