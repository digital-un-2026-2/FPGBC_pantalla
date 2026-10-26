`timescale 1ns / 1ps

// Integración real de FSM, contadores, registros, comparadores y muxes.
module motor_lpdt_TB;
  reg clk = 0;
  always #12.5 clk = !clk;
  reg rst = 1;
  reg permiso_arranque = 0;
  reg solicitud = 0;
  reg [2:0] cantidad_bytes = 4;
  reg [7:0] byte_almacen = 0;
  reg [7:0] paquete [0:6];
  wire aceptado, ocupado, terminado;
  wire [2:0] pos;
  wire [1:0] estado_D0;
  reg [1:0] lp_esperado = 2'b11;
  reg [7:0] byte_decodificado = 0;
  integer ciclo, longitud, fase, i;

  motor_lpdt dut (
      .clk(clk), .rst(rst), .permiso_arranque(permiso_arranque), .solicitud(solicitud),
      .cantidad_bytes(cantidad_bytes), .byte_almacen(byte_almacen),
      .aceptado(aceptado), .ocupado(ocupado), .terminado(terminado),
      .pos(pos), .estado_D0(estado_D0)
  );

  // Almacén de prueba con lectura síncrona en posedge, no de latencia cero.
  // POS debe estar anticipado antes del posedge que prepara la carga negedge.
  always @(posedge clk) begin
    if (pos < cantidad_bytes) byte_almacen <= paquete[pos];
    else byte_almacen <= 8'hxx;
  end

  reg [1:0] lp_antes;
  always @(posedge clk) begin
    lp_antes = estado_D0;
    #1;
    if (estado_D0 !== lp_antes) $fatal(1, "FAIL: salida LP cambió en posedge");
    if (terminado && estado_D0 !== 2'b11)
      $fatal(1, "FAIL: terminado antes del regreso a LP-11");
  end

  function [7:0] esperado(input integer n);
    esperado = (n == 0) ? 8'h87 : paquete[n - 1];
  endfunction

  function [1:0] nivel(input integer c, input integer fin_datos);
    integer offset;
    reg [7:0] valor;
    begin
      if (c < 4) nivel = 2'b10;
      else if (c < 8) nivel = 2'b00;
      else if (c < 12) nivel = 2'b01;
      else if (c < 16) nivel = 2'b00;
      else if (c < fin_datos) begin
        offset = c - 16;
        valor = esperado(offset / 64);
        nivel = (offset % 8 >= 4) ? 2'b00 :
                (valor[(offset % 64) / 8] ? 2'b10 : 2'b01);
      end else if (c < fin_datos + 4) nivel = 2'b10;
      else nivel = 2'b11;
    end
  endfunction

  task resetear;
    begin
      @(negedge clk); #1;
      rst = 1;
      solicitud = 0;
      permiso_arranque = 0;
      @(posedge clk);
      @(negedge clk); #1;
      lp_esperado = 2'b11;
      if (estado_D0 !== 2'b11 || aceptado !== 0 || ocupado !== 0 || terminado !== 0 ||
          dut.w_indice_byte !== 0 || dut.w_sel_bit_contador !== 0 || dut.tiempo_out !== 0)
        $fatal(1, "FAIL: reset integrado");
      rst = 0;
    end
  endtask

  task enviar;
    integer fin_datos, total, offset, bit_n, byte_n;
    time inicio_lp;
    begin
      fin_datos = 16 + (cantidad_bytes + 1) * 64;
      total = fin_datos + 4;
      @(negedge clk); #1;
      solicitud = 1;
      permiso_arranque = 1;
      @(posedge clk); #1;
      if (aceptado !== 1 || ocupado !== 1) $fatal(1, "FAIL: aceptación integrada");
      for (ciclo = 0; ciclo <= total; ciclo = ciclo + 1) begin
        @(negedge clk); #1;
        if (ciclo == 0) inicio_lp = $time;
        lp_esperado = nivel(ciclo, fin_datos);
        if (estado_D0 !== lp_esperado)
          $fatal(1, "FAIL: longitud=%0d ciclo=%0d PN=%b esperado=%b",
                 cantidad_bytes, ciclo, estado_D0, lp_esperado);
        if (pos >= cantidad_bytes) $fatal(1, "FAIL: posición fuera del paquete");
        if (aceptado !== (ciclo == 0) || ocupado !== 1 || terminado !== 0)
          $fatal(1, "FAIL: avisos durante transmisión ciclo=%0d", ciclo);
        if (ciclo >= 16 && ciclo < fin_datos) begin
          offset = ciclo - 16;
          bit_n = (offset % 64) / 8;
          byte_n = offset / 64;
          if (offset % 8 == 3) byte_decodificado[bit_n] = estado_D0[1];
          if (offset % 64 == 63 && byte_decodificado !== esperado(byte_n))
            $fatal(1, "FAIL: byte decodificado %0d", byte_n);
        end
        // Solicitud adicional ignorada mientras ocupado.
        solicitud = (ciclo >= 100 && ciclo < 105);
      end
      if ($time - inicio_lp != total * 25) $fatal(1, "FAIL: duración integrada");
      @(posedge clk); #1;
      if (terminado !== 1 || ocupado !== 0) $fatal(1, "FAIL: aviso final");
      @(posedge clk); #1;
      if (terminado !== 0 || aceptado !== 0) $fatal(1, "FAIL: duración de los avisos");
      $display("PASS: motor_lpdt %0d bytes DSI, %0d ciclos LP, memoria síncrona",
               cantidad_bytes, total);
    end
  endtask

  initial begin
    $dumpfile("motor_lpdt_TB.vcd");
    $dumpvars(0, motor_lpdt_TB);
    paquete[0] = 8'h05;
    paquete[1] = 8'h01;
    paquete[2] = 8'h00;
    paquete[3] = 8'h10;
    for (i = 4; i < 7; i = i + 1) paquete[i] = 8'h55;
    resetear;
    // No aceptar sin permiso ni con longitud nula.
    solicitud = 1;
    repeat (3) begin
      @(posedge clk); #1;
      if (aceptado !== 0 || ocupado !== 0 || estado_D0 !== 2'b11)
        $fatal(1, "FAIL: aceptación sin permiso");
    end
    @(negedge clk); #1;
    cantidad_bytes = 0;
    permiso_arranque = 1;
    repeat (3) begin
      @(posedge clk); #1;
      if (aceptado !== 0 || ocupado !== 0) $fatal(1, "FAIL: longitud nula aceptada");
    end
    @(negedge clk); #1;
    solicitud = 0;
    cantidad_bytes = 4;
    enviar;
    paquete[0] = 8'h00;
    paquete[1] = 8'hff;
    paquete[2] = 8'h55;
    paquete[3] = 8'haa;
    for (longitud = 1; longitud <= 7; longitud = longitud + 1) begin
      cantidad_bytes = longitud;
      enviar;
    end
    for (fase = 1; fase <= 8; fase = fase + 1) begin
      @(negedge clk); #1;
      solicitud = 1;
      permiso_arranque = 1;
      @(posedge clk); #1;
      @(negedge clk); #1; solicitud = 0;
      while (dut.ctrl.state !== fase[3:0]) begin
        @(posedge clk); #1;
      end
      resetear;
    end
    enviar;
    $display("PASS: motor_lpdt_TB; integración lógica, no validación eléctrica");
    $finish;
  end

  initial begin
    #300000;
    $fatal(1, "FAIL: timeout motor_lpdt_TB");
  end
endmodule
