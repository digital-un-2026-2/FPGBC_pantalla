`timescale 1ps / 1fs

module clock_gen_TB;
  localparam realtime T_HS_PS = 1000000.0 / 220.0;
  localparam realtime T_BYTE_PS = 1000000.0 / 55.0;
  reg CLK_REF = 0, REF_RUN = 0, RESET = 1;
  wire CLK_HS, CLK_BYTE, LOCK_RAW;
  integer HS_UP = 0, HS_DOWN = 0, BYTE_EDGES = 0;

  clock_gen dut (
      .CLK_REF(CLK_REF), .RESET(RESET),
      .CLK_BYTE(CLK_BYTE), .CLK_HS(CLK_HS), .LOCK_RAW(LOCK_RAW)
  );

  always #12500 if (REF_RUN) CLK_REF = !CLK_REF;
  always @(posedge CLK_HS) HS_UP = HS_UP + 1;
  always @(negedge CLK_HS) HS_DOWN = HS_DOWN + 1;
  always @(CLK_BYTE) BYTE_EDGES = BYTE_EDGES + 1;

  task automatic check_period(input string clock_name, input realtime dt, t_expected);
    // Tolerancia para redondeo del modelo a 1 fs, no un presupuesto de jitter.
    if (dt < t_expected - 1.0 || dt > t_expected + 1.0)
      $fatal(1, "%s: periodo %0.3f ps, esperado %0.3f ps", clock_name, dt, t_expected);
  endtask

  task automatic check_clocks(input integer n);
    fork
      begin : check_hs
        realtime t;
        @(posedge CLK_HS);
        t = $realtime;
        repeat (4 * n) begin
          @(posedge CLK_HS);
          check_period("CLK_HS", $realtime - t, T_HS_PS);
          t = $realtime;
        end
      end
      begin : check_byte
        integer up, down;
        realtime t;
        @(posedge CLK_BYTE); #1;
        t = $realtime;
        up = HS_UP;
        down = HS_DOWN;
        repeat (n) begin
          @(posedge CLK_BYTE); #1;
          check_period("CLK_BYTE", $realtime - t, T_BYTE_PS);
          if (HS_UP - up != 4 || HS_DOWN - down != 4)
            $fatal(1, "CLK_BYTE: no hubo cuatro ↑ y cuatro ↓ HS por periodo");
          t = $realtime;
          up = HS_UP;
          down = HS_DOWN;
        end
      end
    join
  endtask

  task automatic check_model_stopped;
    integer edges;
    edges = HS_UP + HS_DOWN + BYTE_EDGES;
    #50000;
    if (HS_UP + HS_DOWN + BYTE_EDGES != edges || {CLK_HS, CLK_BYTE, LOCK_RAW} !== 3'b000)
      $fatal(1, "El wrapper no reproduce el estado detenido del modelo");
  endtask

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("clock_gen_TB.fst");
      $dumpvars(0, CLK_REF, RESET, CLK_HS, CLK_BYTE, LOCK_RAW);
    end

    #1;
    check_model_stopped();
    RESET = 0;
    check_model_stopped();  // El modelo aún espera el primer flanco de CLK_REF.
    REF_RUN = 1;
    @(posedge CLK_BYTE); #1;
    if (LOCK_RAW !== 0)
      $fatal(1, "Se ocultaron flancos del modelo previos a LOCK_RAW");
    check_clocks(8);
    if (LOCK_RAW !== 1)
      $fatal(1, "No se propagó el lock inicial del modelo");

    // Cambio entre flancos de CLK_BYTE. No se debe sincronizar el estado
    // crudo ni usarlo para cortar los relojes. No se interrumpe CLK_REF.
    @(negedge CLK_BYTE); #500;
    dut.pll.DROP_LOCK = 1;
    #1;
    if (LOCK_RAW !== 0)
      $fatal(1, "LOCK_RAW no bajó sin flanco de CLK_BYTE");
    check_clocks(4);
    @(negedge CLK_BYTE); #500;
    dut.pll.DROP_LOCK = 0;
    #1;
    if (LOCK_RAW !== 1)
      $fatal(1, "LOCK_RAW no subió sin flanco de CLK_BYTE");

    // Reset de la primitiva estando en marcha; la referencia sigue activa.
    @(posedge CLK_BYTE); #1000;
    RESET = 1;
    #1;
    if (LOCK_RAW !== 0)
      $fatal(1, "El estado crudo del modelo no se reinició");
    check_model_stopped();
    RESET = 0;
    @(posedge LOCK_RAW);
    @(posedge CLK_BYTE); #1;
    @(negedge CLK_BYTE); #1;
    if (LOCK_RAW !== 1)
      $fatal(1, "No volvió el par de flancos de byte con lock");
    check_clocks(8);

    $display("PASS CLOCK_GEN: 220/55 MHz 4:1, LOCK_RAW directo y rearme del modelo");
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "Tiempo agotado esperando flancos o LOCK_RAW");
  end
endmodule
