`timescale 1ns / 1ps

module motor_control_TB;
  reg clk = 0;
  always #12.5 clk = !clk;  // 40 MHz.

  reg rst = 1;
  reg solicitud = 0;
  reg permiso_arranque = 0;
  reg [2:0] cantidad_bytes = 4;
  reg [7:0] paquete [0:3];
  wire ld_len, sel_87, ld_byte, rst_byte, inc_byte;
  wire rst_bit, inc_bit, ld_t, inc_t, sel_fijo, ld_lp;
  wire aceptado, ocupado, terminado;
  wire [1:0] lp_fijo;
  wire [2:0] pos;

  // Modelo de contrato del datapath, no instancias de los módulos de src/.
  // Contador ascendente: cargar 0; 0 -> 1 -> 2 -> 3 -> cambio de fase.
  // z_t se observa ANTES del flanco de cambio: cuatro periodos por fase.
  reg [1:0] tiempo = 0;
  reg [2:0] indice_bit = 0;
  reg [2:0] idx = 0;
  reg [2:0] longitud = 0;
  reg [7:0] byte_actual = 0;
  reg [1:0] estado_D0 = 2'b11;
  wire z_t = (tiempo == 3);
  wire z_bit = (indice_bit == 7);
  wire z_byte = (idx + 1 == longitud);

  motor_control dut (
      .clk(clk), .rst(rst), .z_byte(z_byte), .z_t(z_t), .z_bit(z_bit),
      .permiso_arranque(permiso_arranque), .idx(idx), .solicitud(solicitud),
      .ld_len(ld_len), .sel_87(sel_87), .ld_byte(ld_byte),
      .rst_byte(rst_byte), .inc_byte(inc_byte), .rst_bit(rst_bit), .inc_bit(inc_bit),
      .ld_t(ld_t), .inc_t(inc_t), .sel_fijo(sel_fijo), .lp_fijo(lp_fijo),
      .ld_lp(ld_lp), .aceptado(aceptado), .ocupado(ocupado), .terminado(terminado),
      .pos(pos)
  );

  always @(negedge clk) begin
    if (rst) begin
      tiempo <= 0;
      indice_bit <= 0;
      idx <= 0;
      longitud <= 0;
      byte_actual <= 0;
      estado_D0 <= 2'b11;
    end else begin
      if (ld_t) tiempo <= 0;
      else if (inc_t) tiempo <= tiempo + 1'b1;
      if (rst_bit) indice_bit <= 0;
      else if (inc_bit) indice_bit <= indice_bit + 1'b1;
      if (rst_byte) idx <= 0;
      else if (inc_byte) idx <= idx + 1'b1;
      if (ld_len) longitud <= cantidad_bytes;
      // Lectura anticipada idealizada: el siguiente byte ya está disponible.
      if (ld_byte) begin
        if (sel_87) byte_actual <= 8'h87;
        else begin
          if (pos >= longitud)
            $fatal(1, "FAIL: lectura fuera del paquete");
          byte_actual <= paquete[pos];
        end
      end
      if (ld_lp)
        estado_D0 <= sel_fijo ? lp_fijo : {byte_actual[indice_bit], !byte_actual[indice_bit]};
    end
  end

  // Detectar X y controles incompatibles una vez estabilizada cada fase.
  always @(negedge clk) begin
    if (!rst) begin
      if ((^{ld_len, sel_87, ld_byte, rst_byte, inc_byte, rst_bit, inc_bit,
             ld_t, inc_t, sel_fijo, lp_fijo, ld_lp, aceptado, ocupado, terminado}) === 1'bx)
        $fatal(1, "FAIL: salida de control desconocida");
      if ((ld_t && inc_t) || (rst_bit && inc_bit) || (rst_byte && inc_byte))
        $fatal(1, "FAIL: controles simultáneos incompatibles");
    end
  end

  // Referencia temporal independiente de state, flags e índices del DUT.
  reg [1:0] lp_esperado = 2'b11;
  reg [7:0] byte_decodificado = 0;
  integer ciclo = 0;
  integer caso = 0;
  integer fase_reset;
  integer patron;

  function [7:0] byte_esperado(input integer numero);
    begin
      byte_esperado = (numero == 0) ? 8'h87 : paquete[numero - 1];
    end
  endfunction

  function [1:0] nivel_esperado(input integer c, input integer fin_datos);
    integer desplazamiento, numero_byte, numero_bit;
    reg [7:0] valor;
    begin
      if (c < 4) nivel_esperado = 2'b10;
      else if (c < 8) nivel_esperado = 2'b00;
      else if (c < 12) nivel_esperado = 2'b01;
      else if (c < 16) nivel_esperado = 2'b00;
      else if (c < fin_datos) begin
        desplazamiento = c - 16;
        numero_byte = desplazamiento / 64;
        numero_bit = (desplazamiento % 64) / 8;
        valor = byte_esperado(numero_byte);
        if (desplazamiento % 8 >= 4) nivel_esperado = 2'b00;
        else nivel_esperado = valor[numero_bit] ? 2'b10 : 2'b01;
      end else if (c < fin_datos + 4) nivel_esperado = 2'b10;
      else nivel_esperado = 2'b11;
    end
  endfunction

  task reiniciar;
    begin
      @(negedge clk); #1;
      rst = 1;
      solicitud = 0;
      permiso_arranque = 0;
      @(posedge clk); #1;
      @(negedge clk); #1;
      if (dut.state !== dut.IDLE || estado_D0 !== 2'b11 ||
          aceptado !== 0 || terminado !== 0 || ocupado !== 0 ||
          dut.enviando_selector !== 0 || dut.salida_pendiente !== 0)
        $fatal(1, "FAIL: reset o aborto incorrecto");
      rst = 0;
    end
  endtask

  task enviar_y_comprobar;
    integer fin_datos, fin_envio, desplazamiento, numero_bit, numero_byte;
    begin
      caso = caso + 1;
      fin_datos = 16 + (cantidad_bytes + 1) * 64;
      fin_envio = fin_datos + 4;
      @(negedge clk);
      solicitud = 1;
      permiso_arranque = 1;
      for (ciclo = 0; ciclo <= fin_envio + 2; ciclo = ciclo + 1) begin
        @(posedge clk);
        @(negedge clk); #1;
        lp_esperado = nivel_esperado(ciclo, fin_datos);
        if (estado_D0 !== lp_esperado)
          $fatal(1, "FAIL: caso=%0d ciclo=%0d PN=%b esperado=%b",
                 caso, ciclo, estado_D0, lp_esperado);
        if (aceptado !== (ciclo == 0) || terminado !== (ciclo == fin_envio + 1) ||
            ocupado !== (ciclo <= fin_envio))
          $fatal(1, "FAIL: handshake caso=%0d ciclo=%0d", caso, ciclo);

        // Decodificar P/N en el último ciclo de cada Mark (LSB primero).
        if (ciclo >= 16 && ciclo < fin_datos) begin
          desplazamiento = ciclo - 16;
          numero_bit = (desplazamiento % 64) / 8;
          numero_byte = desplazamiento / 64;
          if (desplazamiento % 8 == 3) begin
            case (estado_D0)
              2'b10: byte_decodificado[numero_bit] = 1'b1;
              2'b01: byte_decodificado[numero_bit] = 1'b0;
              default: $fatal(1, "FAIL: Mark inválido");
            endcase
          end
          if (desplazamiento % 64 == 63 && byte_decodificado !== byte_esperado(numero_byte))
            $fatal(1, "FAIL: byte %0d decodificado=%h esperado=%h",
                   numero_byte, byte_decodificado, byte_esperado(numero_byte));
        end
        // Una segunda solicitud durante ocupado no debe reiniciar el envío.
        solicitud = (ciclo >= 100 && ciclo <= 105);
      end
      $display("PASS: caso %0d, %0d bytes DSI, %0d ciclos hasta LP-11",
               caso, cantidad_bytes, fin_envio);
    end
  endtask

  initial begin
    $dumpfile("motor_control_TB.vcd");
    $dumpvars(0, motor_control_TB);
    paquete[0] = 8'h05;
    paquete[1] = 8'h01;
    paquete[2] = 8'h00;
    paquete[3] = 8'h10;
    reiniciar;

    // Solicitud sin permiso: conservar LP-11 y no aceptar.
    solicitud = 1;
    repeat (5) begin
      @(posedge clk); #1;
      if (aceptado !== 0 || ocupado !== 0 || terminado !== 0 || estado_D0 !== 2'b11)
        $fatal(1, "FAIL: operación sin permiso");
    end
    @(negedge clk); solicitud = 0;
    enviar_y_comprobar;  // 87 05 01 00 10: 340 ciclos, 8,5 us.

    // Longitudes y patrones que ejercitan límites, ceros y unos consecutivos.
    for (patron = 0; patron < 4; patron = patron + 1) begin
      cantidad_bytes = patron + 1;
      paquete[0] = 8'h00;
      paquete[1] = 8'hff;
      paquete[2] = 8'h55;
      paquete[3] = 8'haa;
      enviar_y_comprobar;
    end

    // Reset en cada estado activo y en DONE; sin terminado por aborto.
    for (fase_reset = 1; fase_reset <= 8; fase_reset = fase_reset + 1) begin
      @(negedge clk);
      solicitud = 1;
      permiso_arranque = 1;
      @(posedge clk); #1;
      @(negedge clk); solicitud = 0;
      while (dut.state !== fase_reset[3:0]) begin
        @(posedge clk); #1;
      end
      reiniciar;
    end
    enviar_y_comprobar;  // Recuperación con una nueva transacción completa.
    $display("PASS: motor_control_TB (FSM con datapath modelado; sin validación eléctrica)");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "FAIL: timeout motor_control_TB");
  end
endmodule
