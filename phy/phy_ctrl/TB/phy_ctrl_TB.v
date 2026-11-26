`timescale 1ns / 1ps

module phy_ctrl_TB #(
    parameter integer PROFILE = 0
);
  localparam integer T_LPX = (PROFILE == 0) ? 1 : 5;
  localparam integer T_PREP = (PROFILE == 0) ? 1 : 3;
  localparam integer T_ZERO = (PROFILE == 0) ? 1 : 7;
  localparam integer T_TRAIL = (PROFILE == 0) ? 1 : 4;
  localparam integer N_WORDS = 1083;  // W0..W1082, aparte de SoT.
  localparam [15:0] SOT = 16'hb8b8, CRC = 16'ha65d;
  localparam [1:0] OFF = 2'b00, ZERO = 2'b01, WORD = 2'b10, TRAIL = 2'b11;

  reg CLK_BYTE = 0, CLK_CARRIER = 0, CLOCK_RUNNING = 1;
  always #10 if (CLOCK_RUNNING) CLK_BYTE = !CLK_BYTE;
  always #2 if (CLOCK_RUNNING) CLK_CARRIER = !CLK_CARRIER;
  reg RST_BYTE = 1, LOCK_RAW = 0;
  reg HS_REQ = 0, CLK_REQ = 0;
  wire LOCK, READY, LP_EN, HS_EN, CLK_EN, CLK_ARM, ISO;
  wire [1:0] SER_MODE;

  reg [3:0] LP_D = 4'b1111;  // {D1P,D1N,D0P,D0N}. LP de CLK siempre 11.
  reg [15:0] WORD_D = 0;
  reg [2:0] LP_P, LP_N;
  reg [15:0] HS_WORD_IF;
  wire [1:0] SERIAL_SLOT;
  wire [15:0] SERIAL_WORD;
  wire [2:0] PAD_P, PAD_N;
  integer CARGAS = 0;

  phy_ctrl #(.T_ZERO(T_ZERO), .T_TRAIL(T_TRAIL)) dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .LOCK_RAW(LOCK_RAW),
      .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ), .LOCK(LOCK), .READY(READY),
      .LP_EN(LP_EN), .HS_EN(HS_EN), .CLK_EN(CLK_EN), .CLK_ARM(CLK_ARM),
      .ISO(ISO), .SER_MODE(SER_MODE)
  );

  phy_ctrl_neighbors_model vecinos (
      .CLK_BYTE(CLK_BYTE), .CLK_CARRIER(CLK_CARRIER), .LP_P(LP_P), .LP_N(LP_N),
      .HS_BYTE0(HS_WORD_IF[7:0]), .HS_BYTE1(HS_WORD_IF[15:8]),
      .LP_EN(LP_EN), .HS_EN(HS_EN), .CLK_EN(CLK_EN), .CLK_ARM(CLK_ARM), .ISO(ISO),
      .SER_MODE(SER_MODE), .SERIAL_SLOT(SERIAL_SLOT), .SERIAL_WORD(SERIAL_WORD),
      .PAD_P(PAD_P), .PAD_N(PAD_N)
  );

  // El estímulo cambia después de ↑ como LINK_FSM. Estos registros publican
  // en ↓ como PHY_IF, en el mismo flanco que el serializador lee el valor previo.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      LP_P <= 3'b111;
      LP_N <= 3'b111;
      HS_WORD_IF <= 16'h0000;
    end else begin
      LP_P <= {1'b1, LP_D[3], LP_D[1]};
      LP_N <= {1'b1, LP_D[2], LP_D[0]};
      HS_WORD_IF <= WORD_D;
    end
    if (!ISO && SER_MODE == WORD) CARGAS <= CARGAS + 1;
  end

  always @(LP_EN or HS_EN or CLK_EN)
    if (LP_EN === 1'b1 && (HS_EN === 1'b1 || CLK_EN === 1'b1))
      $fatal(1, "LP y HS/CLK se habilitaron simultáneamente");

  function [15:0] palabra(input integer i);
    case (i)
      0: palabra = 16'h703e;
      1: palabra = 16'h1308;
      2: palabra = 16'h0000;  // Datos legales, no indicadores de control.
      3: palabra = SOT;
      4: palabra = CRC;
      N_WORDS - 1: palabra = CRC;  // CRC de prueba, no calculado por PHY_CTRL.
      default: palabra = 16'h173c + 16'h01b3 * i[15:0];
    endcase
  endfunction

  task automatic subir;
    @(posedge CLK_BYTE); #1;
  endtask

  task automatic bajar;
    @(negedge CLK_BYTE); #1;
  endtask

  task automatic presentar(input bit hs, clk, input [3:0] lp, input [15:0] datos);
    {HS_REQ, CLK_REQ} = {hs, clk};
    LP_D = lp;
    WORD_D = datos;
  endtask

  task automatic comprobar_oe(input [2:0] habilitaciones);
    reg [1:0] par;
    begin
      if ({LP_EN, HS_EN, CLK_EN} !== habilitaciones)
        $fatal(1, "[%0t] LP_EN/HS_EN/CLK_EN = %b; esperado %b",
               $time, {LP_EN, HS_EN, CLK_EN}, habilitaciones);
      for (integer i = 0; i < 3; i = i + 1) begin
        par = {PAD_P[i], PAD_N[i]};
        if (habilitaciones[2]) begin
          if (par !== {LP_P[i], LP_N[i]})
            $fatal(1, "[%0t] par %0d no reproduce LP", $time, i);
        end else if (i == 2 ? habilitaciones[0] : habilitaciones[1]) begin
          if (par !== 2'b01 && par !== 2'b10)
            $fatal(1, "[%0t] par %0d no está habilitado en HS/CLK: %b", $time, i, par);
        end else if (par !== 2'bzz)
          $fatal(1, "[%0t] par %0d no está aislado: %b", $time, i, par);
      end
    end
  endtask

  task automatic comprobar_slot(input [1:0] modo, input [15:0] datos);
    if (SERIAL_SLOT !== modo || (modo == WORD && SERIAL_WORD !== datos))
      $fatal(1, "[%0t] slot serial = %b/%04h; esperado %b/%04h",
             $time, SERIAL_SLOT, SERIAL_WORD, modo, datos);
  endtask

  task automatic comprobar_corte;
    comprobar_oe(3'b000);
    if ({ISO, CLK_ARM, SER_MODE, SERIAL_SLOT, SERIAL_WORD} !== {1'b1, 1'b0, OFF, OFF, 16'h0000})
      $fatal(1, "[%0t] el corte no inhibió los drivers y descartó el slot", $time);
  endtask

  task automatic reset_comun;
    bit lock_antes_de_ready;
    begin
      RST_BYTE = 1;
      subir();
      presentar(0, 0, 4'b1111, 16'h0000);
      bajar();
      comprobar_corte();
      if ({LOCK, READY} !== 2'b00) $fatal(1, "Estado de admisión durante reset");
      RST_BYTE = 0;
      lock_antes_de_ready = 0;
      for (integer i = 0; i < 12 && READY !== 1'b1; i = i + 1) begin
        bajar();
        if ({LOCK, READY} === 2'b10) lock_antes_de_ready = 1;
        comprobar_oe(READY ? 3'b100 : 3'b000);
        comprobar_slot(OFF, 0);
      end
      if (!lock_antes_de_ready || {LOCK, READY, HS_REQ, CLK_REQ} !== 4'b1100)
        $fatal(1, "READY no se habilitó de forma independiente a HS_REQ/CLK_REQ");
    end
  endtask

  task automatic probar_lp;
    reg [1:0] pn;
    integer inicio;
    begin
      inicio = CARGAS;
      for (integer i = 0; i < 4; i = i + 1) begin
        pn = i[1:0];
        subir();
        presentar(0, 0, {2'b11, pn}, SOT);
        bajar();
        comprobar_oe(3'b100);
        comprobar_slot(OFF, 0);
        if ({PAD_P[0], PAD_N[0]} !== pn || {PAD_P[2:1], PAD_N[2:1]} !== 4'b1111)
          $fatal(1, "Símbolo de LP o carril incorrecto");
      end
      // Cancelar CLK_REQ en preámbulo sin pedir HS: nunca conduce HS ni CLK.
      subir();
      presentar(0, 1, 4'b0101, SOT);
      bajar();
      subir();
      if ({READY, CLK_ARM} !== 2'b01) $fatal(1, "No reservó la ruta de reloj");
      presentar(0, 0, 4'b1111, 16'h0000);
      bajar();
      comprobar_oe(3'b100);
      subir();
      if ({READY, CLK_ARM} !== 2'b10 || CARGAS != inicio)
        $fatal(1, "Cancelar el preámbulo no volvió a LP sin cargas");
    end
  endtask

  // Guion de flancos del PR #11, independiente de los estados del DUT.
  task automatic preambulo;
    reg [3:0] lp;
    begin
      if ({LOCK, READY} !== 2'b11) $fatal(1, "El estímulo HS requiere admisión");
      for (integer i = 0; i < T_LPX + T_PREP; i = i + 1) begin
        lp = (i < T_LPX) ? 4'b0101 : 4'b0000;
        subir();
        presentar(0, 1, lp, 16'hcafe);
        bajar();
        comprobar_oe(3'b100);
        comprobar_slot(OFF, 0);
        if ((i != 0) && {READY, CLK_ARM} !== 2'b01)
          $fatal(1, "CLK_REQ no preparó el reloj antes que HS_REQ");
      end

      subir();
      presentar(1, 1, 4'b0000, 16'hcafe);
      bajar();  // ↓z: todavía LP, primera muestra de HS_REQ.
      comprobar_oe(3'b100);
      comprobar_slot(OFF, 0);
      for (integer i = 0; i < T_ZERO; i = i + 1) begin
        subir();
        if (i == 0) comprobar_oe(3'b000);  // ↑z: separar los drivers.
        presentar(1, 1, 4'b0000, (i == T_ZERO - 1) ? SOT : 16'hcafe);
        bajar();
        comprobar_oe(3'b011);
        comprobar_slot(ZERO, 0);
      end
      if (HS_WORD_IF !== SOT) $fatal(1, "El SoT debe estar publicado antes de la primera carga");
    end
  endtask

  task automatic publicar_palabras(input integer n);
    for (integer i = 0; i < n; i = i + 1) begin
      subir();
      presentar(1, 1, 4'b0000, palabra(i));
      bajar();
      comprobar_oe(3'b011);
      comprobar_slot(WORD, (i == 0) ? SOT : palabra(i - 1));
    end
  endtask

  task automatic cerrar_hs(input bit retirar_clk_antes);
    begin
      if (HS_WORD_IF !== CRC) $fatal(1, "El CRC debe estar publicado antes del drenaje");
      subir();
      presentar(0, !retirar_clk_antes, 4'b0000, 16'h0000);
      #1;
      comprobar_oe(3'b011);
      if (SER_MODE !== WORD) $fatal(1, "El descenso de HS_REQ canceló la carga pendiente");
      bajar();  // ↓f: toma CRC aunque HS_REQ=0. El nuevo registro ya es 00/00.
      comprobar_oe(3'b011);
      comprobar_slot(WORD, CRC);
      if (HS_WORD_IF !== 16'h0000) $fatal(1, "El banco no sustituyó el registro del CRC");

      for (integer i = 0; i < T_TRAIL; i = i + 1) begin
        subir();
        comprobar_oe(3'b011);
        if (i == 0) begin
          // El modo para el próximo ↓ ya cambió, pero no altera el slot del CRC.
          comprobar_slot(WORD, CRC);
          if (SER_MODE !== TRAIL) $fatal(1, "No se preparó trail tras el CRC");
        end
        presentar(0, !retirar_clk_antes, 4'b0000, palabra(0));
        bajar();
        comprobar_oe(3'b011);
        comprobar_slot(TRAIL, 0);
      end

      subir();
      comprobar_oe(3'b011);
      comprobar_slot(TRAIL, 0);
      presentar(0, 0, 4'b1111, palabra(0));
      bajar();  // ↓r: se ha completado el último slot de trail.
      comprobar_oe(3'b001);
      comprobar_slot(OFF, 0);
      subir();  // ↑r: cae el reloj; todavía no se habilita LP.
      comprobar_oe(3'b000);
      if (READY !== 1'b0) $fatal(1, "READY se anticipó al retorno LP");
      bajar();
      comprobar_oe(3'b100);
      comprobar_slot(OFF, 0);
      if ({LOCK, READY} !== 2'b11) $fatal(1, "No volvió a anunciar READY en LP");
    end
  endtask

  task automatic rafaga(input bit retirar_clk_antes);
    integer inicio;
    begin
      inicio = CARGAS;
      preambulo();
      publicar_palabras(N_WORDS);
      cerrar_hs(retirar_clk_antes);
      repeat (3) begin
        bajar();
        comprobar_slot(OFF, 0);
      end
      if (CARGAS - inicio != N_WORDS + 1)
        $fatal(1, "Se esperaban %0d cargas entre SoT y CRC; hubo %0d", N_WORDS + 1, CARGAS - inicio);
    end
  endtask

  task automatic abortar_por_reset;
    integer pendientes;
    begin
      preambulo();
      publicar_palabras(N_WORDS);
      subir();
      presentar(0, 1, 4'b0000, 16'h0000);  // La carga de CRC sería en el próximo ↓.
      comprobar_oe(3'b011);
      pendientes = CARGAS;
      CLOCK_RUNNING = 0;
      #2;
      RST_BYTE = 1;
      #1;
      comprobar_corte();
      #43;
      comprobar_corte();
      if (CLK_BYTE !== 1'b1) $fatal(1, "CLK_BYTE no quedó detenido al abortar por reset");
      CLOCK_RUNNING = 1;
      reset_comun();
      if (CARGAS != pendientes) $fatal(1, "El reset permitió drenar el CRC o reanudar datos");
    end
  endtask

  task automatic abortar_por_lock;
    integer pendientes;
    begin
      preambulo();
      publicar_palabras(3);
      subir();
      comprobar_oe(3'b011);
      pendientes = CARGAS;
      CLOCK_RUNNING = 0;
      #2;
      LOCK_RAW = 0;
      #1;
      comprobar_corte();
      #43;
      LOCK_RAW = 1;  // El fallo entero ocurre sin flancos de byte.
      #1;
      comprobar_corte();
      if (CLK_BYTE !== 1'b1) $fatal(1, "CLK_BYTE no quedó detenido durante la pérdida de lock");
      CLOCK_RUNNING = 1;
      repeat (8) begin
        bajar();
        comprobar_corte();  // La petición antigua sigue a 1; no es otra ráfaga.
      end
      if ({LOCK, READY} !== 2'b10)
        $fatal(1, "Recuperar LOCK no debe recuperar READY sin reset común");
      subir();
      presentar(0, 0, 4'b1110, SOT);
      repeat (4) begin
        bajar();
        comprobar_corte();  // Incluso 00 en peticiones no sustituye RST_BYTE.
      end
      reset_comun();
      if (CARGAS != pendientes) $fatal(1, "Se reanudó la ráfaga que perdió lock");
    end
  endtask

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("phy_ctrl_TB.fst");
      $dumpvars(1, phy_ctrl_TB, dut, dut.guard, dut.timer, vecinos);
    end
    repeat (3) begin
      bajar();
      comprobar_corte();
    end
    LOCK_RAW = 1;
    reset_comun();
    probar_lp();
    rafaga(0);
    abortar_por_reset();
    abortar_por_lock();
    rafaga(1);  // Además prueba retirar CLK_REQ antes de trail, fuera del guion normal.
    $display("PASS PHY_CTRL p%0d: admisión, LP, SoT..CRC, trail, CLK y abortos con reloj detenido",
             PROFILE);
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "Tiempo máximo del banco PHY_CTRL excedido");
  end
endmodule
