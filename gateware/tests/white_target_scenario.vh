  always @(BL_EN or BL_PWM or INIT_DONE or RST_BYTE) begin
    #(SETTLE);
    if ((RST_BYTE || !INIT_DONE) && {BL_EN, BL_PWM} !== 2'b00)
      $fatal(1, "Backlight encendido antes de END o durante reset");
  end

  always @(negedge BL_EN) begin
    #(SETTLE);
    if (INIT_DONE && !board.rst_sup && !RST_BYTE && !board.iso)
      $fatal(1, "EN cayó con el enlace sano entre ráfagas");
  end

  task automatic check_pwm;
    realtime enable_time, start_time;
    @(posedge BL_EN);
    enable_time = $realtime;
    if (!INIT_DONE || BL_PWM !== 1'b0) $fatal(1, "Secuencia de habilitación incorrecta");
    @(posedge BL_PWM);
    start_time = $realtime;
    if (start_time - enable_time != 25) $fatal(1, "El PWM no esperó un ciclo tras EN");
    @(negedge BL_PWM);
    if ($realtime - start_time != 500_000) $fatal(1, "Pulso de PWM distinto de 500 µs");
    @(posedge BL_PWM);
    if ($realtime - start_time != 1_000_000) $fatal(1, "PWM distinto de 1 kHz");
  endtask

  initial begin : scenario
    string init_hex;
    integer first_line, second_line;
    if (!$value$plusargs("init_hex=%s", init_hex)) $fatal(1, "Falta ROM de referencia");
    $readmemh(init_hex, reference_rom);

    #500 GLOBAL_RST_N = 1;
    #10000;
    expect_isolated();
    if (RESET !== 1'b1) $fatal(1, "La PLL salió de reset sin referencia");
    REF_ENABLED = 1;
    wait (LOCK_RAW === 1'b1);
    check_rearm($realtime);
    check_init("TOP desde el arranque");
    fork
      check_pwm();
      begin
        full_line(WHITE, first_line);
        full_line(WHITE, second_line);
        if (second_line - first_line != C_LINE) $fatal(1, "Periodo de línea incorrecto");
      end
    join
    $display("PASS TOP: dos líneas desde pads y PWM a 1 kHz, 50 %%");

    if (WHITE) begin
      active_payload();
      if ({BL_EN, BL_PWM} !== 2'b11 || READY !== 1'b0)
        $fatal(1, "Backlight no sostenido durante la ráfaga previa al corte");
      stop_clock(0);
      check_init("TOP tras perder CLK_REF");

      active_payload();
      if (BL_EN !== 1'b1) $fatal(1, "No se habilitó tras el nuevo END");
      stop_clock(1);
      check_init("TOP tras perder CLK_BYTE");
      full_line(WHITE, first_line);

      active_payload();
      if (BL_EN !== 1'b1) $fatal(1, "Backlight apagado antes de probar botón");
      REF_ENABLED = 0;
      GLOBAL_RST_N = 0;
      #(SETTLE);
      expect_isolated();
      $display("PASS botón FPGA: corte asíncrono con CLK_REF detenido");
    end
    $finish;
  end

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("fpgbc_white.fst");
      $dumpvars(1, mipi_tx_TB, board, board.control, board.supervisor, board.link);
    end
    #900_000_000;
    $fatal(1, "Tiempo agotado en el banco del TOP");
  end
