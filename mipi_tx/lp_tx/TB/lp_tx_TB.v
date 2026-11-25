`timescale 1ns / 1ps

module lp_tx_TB #(
    parameter integer LP_DIV = 1
);
  localparam [1:0] LP00 = 2'b00, LP01 = 2'b01, LP10 = 2'b10, LP11 = 2'b11;
  // Dos paquetes iniciales de INIT_MEM. El 87 del segundo es CRC bajo.
  localparam [63:0] PAQUETE_1 = 64'h29_02_00_00_b0_00_d6_ca;
  localparam [95:0] PAQUETE_2 = 96'h29_06_00_23_e4_00_00_00_00_08_87_16;
  localparam integer WAIT_1 = 8, BASE_2 = WAIT_1 + 1, WAIT_2 = BASE_2 + 12;
  localparam [8:0] ESPERA_9 = {1'b1, 8'h09};

  reg CLK_BYTE = 0;
  always #10 CLK_BYTE = !CLK_BYTE;
  reg RST_BYTE = 1;
  reg LP_START = 0;
  reg seleccion_lpdt = 0;
  reg omitir_espera = 0;

  integer direccion;
  wire [8:0] entrada = leer_rom(direccion);
  wire INIT_LAST = entrada[8];
  wire [7:0] INIT_BYTE = entrada[7:0];
  wire INIT_NEXT, LP_DONE;
  wire [1:0] LP_D0;
  reg [1:0] d0_phy;
  reg [1:0] simbolo_anterior = LP11;
  time ultimo_negedge = 0;

  lp_tx #(.LP_DIV(LP_DIV)) dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .LP_START(LP_START),
      .INIT_BYTE(INIT_BYTE), .INIT_LAST(INIT_LAST), .INIT_NEXT(INIT_NEXT),
      .LP_DONE(LP_DONE), .LP_D0(LP_D0)
  );

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("lp_tx_TB.fst");
      $dumpvars(1, lp_tx_TB);
      $dumpvars(2, dut);
    end
  end

  function [8:0] leer_rom(input integer pos);
    if (pos < WAIT_1) leer_rom = {1'b0, PAQUETE_1[8*(WAIT_1-1-pos) +: 8]};
    else if (pos == WAIT_1 || pos == WAIT_2) leer_rom = ESPERA_9;
    else if (pos < WAIT_2) leer_rom = {1'b0, PAQUETE_2[8*(WAIT_2-1-pos) +: 8]};
    else leer_rom = 9'hxxx;
  endfunction

  function [1:0] marca(input valor_bit);
    marca = valor_bit ? LP10 : LP01;
  endfunction

  // Modelo de fuente: la ROM presenta el BYTE/WAIT de la dirección
  // vigente. Se avanza en ↑ tras consumir INIT_NEXT; no hay temporizador.
  always @(posedge CLK_BYTE) begin
    if (RST_BYTE) direccion <= 0;
    else if (INIT_NEXT) begin
      if (INIT_LAST !== 1'b0) $fatal(1, "FAIL: INIT_NEXT no puede consumir WAIT");
      direccion <= direccion + 1;
    end else if (omitir_espera) begin
      if (INIT_LAST !== 1'b1) $fatal(1, "FAIL: la fuente no está en WAIT");
      direccion <= direccion + 1;
    end
  end

  // Muestreo lógico del consumidor: capta el LP_D0 anterior al ↓.
  always @(negedge CLK_BYTE) begin
    ultimo_negedge = $time;
    d0_phy <= (RST_BYTE || !seleccion_lpdt) ? LP11 : LP_D0;
  end

  always @(LP_D0)
    if ($time != ultimo_negedge)
      $fatal(1, "FAIL: LP_D0 cambió fuera de negedge en %0t", $time);

  always @(INIT_NEXT or LP_DONE)
    if (!RST_BYTE && $time != ultimo_negedge)
      $fatal(1, "FAIL: NEXT/DONE cambiaron fuera de negedge en %0t", $time);

  task comprobar_ciclo(input [1:0] simbolo, input pulso_next, fin);
    reg [1:0] captura;
    begin
      @(negedge CLK_BYTE);
      captura = (RST_BYTE || !seleccion_lpdt) ? LP11 : simbolo_anterior;
      #1;
      if ({LP_D0, d0_phy, INIT_NEXT, LP_DONE} !== {simbolo, captura, pulso_next, fin})
        $fatal(1, "FAIL: D=%0d ↓ t=%0t addr=%0d: D0/PHY=%b/%b NEXT/DONE=%b/%b; esperado %b/%b %b/%b",
               LP_DIV, $time, direccion, LP_D0, d0_phy, INIT_NEXT, LP_DONE,
               simbolo, captura, pulso_next, fin);
      simbolo_anterior = simbolo;
      @(posedge CLK_BYTE);
      if ({INIT_NEXT, LP_DONE} !== {pulso_next, fin})
        $fatal(1, "FAIL: NEXT/DONE no se pueden leer en ↑ en %0t", $time);
      #1;
      if ({INIT_NEXT, LP_DONE} !== {pulso_next, fin})
        $fatal(1, "FAIL: NEXT/DONE deben conservarse hasta el ↓ siguiente en %0t", $time);
    end
  endtask

  task comprobar_fase(input [1:0] simbolo);
    repeat (LP_DIV) comprobar_ciclo(simbolo, 0, 0);
  endtask

  // dir = -1 para el selector (sin consumir ROM).
  task comprobar_marca_inicial(input [7:0] valor, input integer dir);
    begin
      if (dir >= 0 && (direccion !== dir || entrada !== {1'b0, valor}))
        $fatal(1, "FAIL: BYTE %02h no presentado en dirección %0d", valor, dir);
      comprobar_ciclo(marca(valor[0]), (dir >= 0), 0);
      // Si es el último byte, WAIT ya figura en la ROM mientras sale b0.
      if (dir >= 0 && (direccion !== (dir+1) || entrada !== leer_rom(dir+1)))
        $fatal(1, "FAIL: la ROM no avanzó justo tras la carga de dirección %0d", dir);
      repeat (LP_DIV - 1) comprobar_ciclo(marca(valor[0]), 0, 0);
    end
  endtask

  task comprobar_byte(input [7:0] valor, input integer dir);
    integer b;
    begin
      comprobar_marca_inicial(valor, dir);
      comprobar_fase(LP00);
      for (b = 1; b < 8; b = b + 1) begin
        comprobar_fase(marca(valor[b]));
        comprobar_fase(LP00);
      end
    end
  endtask

  task iniciar_lpdt;
    begin
      // Los estímulos se presentan después de ↑; se aceptan en el próximo ↑.
      seleccion_lpdt = 1;
      LP_START = 1;
      comprobar_ciclo(LP11, 0, 0);
      LP_START = 0;
      comprobar_fase(LP10);
      comprobar_fase(LP00);
      comprobar_fase(LP01);
      comprobar_fase(LP00);
      comprobar_byte(8'h87, -1);
    end
  endtask

  task enviar_paquete(input integer base, espera);
    integer pos;
    reg [8:0] palabra;
    begin
      iniciar_lpdt;
      for (pos = base; pos < espera; pos = pos + 1) begin
        palabra = leer_rom(pos);
        comprobar_byte(palabra[7:0], pos);
      end
      comprobar_fase(LP10);
      comprobar_fase(LP11);
      comprobar_ciclo(LP11, 0, 1);
      if (d0_phy !== LP11 || direccion !== espera || entrada !== ESPERA_9)
        $fatal(1, "FAIL: al leer LP_DONE se requiere LP11 capturado y WAIT sin consumir");
      seleccion_lpdt = 0;  // Después del ↑ en que LINK_FSM leería LP_DONE.
      comprobar_ciclo(LP11, 0, 0);
      comprobar_fase(LP11);
    end
  endtask

  task pasar_al_segundo_paquete;
    begin
      LP_START = 1;  // En reposo con WAIT todavía presentado: no hay arranque.
      comprobar_ciclo(LP11, 0, 0);
      LP_START = 0;
      comprobar_ciclo(LP11, 0, 0);
      omitir_espera = 1;
      comprobar_ciclo(LP11, 0, 0);
      omitir_espera = 0;
      if (direccion !== BASE_2) $fatal(1, "FAIL: no se presentó el segundo paquete");
    end
  endtask

  task abortar_con_reset;
    begin
      iniciar_lpdt;
      comprobar_marca_inicial(8'h29, 0);
      comprobar_fase(LP00);
      comprobar_ciclo(LP01, 0, 0);  // Marca de b1 de 29; byte a medio emitir.
      RST_BYTE = 1;
      #1;
      if ({LP_D0, INIT_NEXT, LP_DONE} !== {LP01, 1'b0, 1'b0})
        $fatal(1, "FAIL: reset no debe cambiar LP_D0 antes de ↓ ni emitir pulsos");
      comprobar_ciclo(LP11, 0, 0);  // Reset del datapath y luego de la FSM en ↑.
      comprobar_ciclo(LP11, 0, 0);  // Reset también cubre el ↓ posterior.
      RST_BYTE = 0;
      seleccion_lpdt = 0;
      comprobar_fase(LP11);
    end
  endtask

  initial begin
    comprobar_ciclo(LP11, 0, 0);
    RST_BYTE = 0;
    comprobar_ciclo(LP11, 0, 0);

    abortar_con_reset;
    enviar_paquete(0, WAIT_1);
    $display("PASS D=%0d: reset y reenvío de 87 | 29 02 00 00 B0 00 D6 CA", LP_DIV);
    pasar_al_segundo_paquete;
    enviar_paquete(BASE_2, WAIT_2);
    $display("PASS D=%0d: 87 de CRC intacto, WAIT sin emitir y LP11 antes de soltar LPDT", LP_DIV);
    $finish;
  end

  initial #(20000 * (LP_DIV + 1)) $fatal(1, "FAIL: timeout de lp_tx");
endmodule
