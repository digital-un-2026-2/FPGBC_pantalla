  wire [11:0] all_pads = {D0_LP, D1_LP, CLK_LP, D0_HS, D1_HS, CLK_HS_PAD};
  integer ref_edges = 0, byte_edges = 0, hs_edges = 0;
  realtime last_ref_edge, last_byte_edge;

  always @(CLK_REF) begin
    ref_edges = ref_edges + 1;
    last_ref_edge = $realtime;
  end
  always @(CLK_BYTE) begin
    byte_edges = byte_edges + 1;
    last_byte_edge = $realtime;
  end
  always @(`TB_PHY.CLK_HS) hs_edges = hs_edges + 1;

  task automatic expect_isolated;
    if ({RST_BYTE, READY, all_pads} !== {2'b10, {12{1'bz}}})
      $fatal(1, "Corte incompleto: RST_BYTE=%b, READY=%b, pads=%b", RST_BYTE, READY, all_pads);
`ifdef FPGBC_WHITE
    if ({BL_EN, BL_PWM} !== 2'b00) $fatal(1, "Backlight activo durante aislamiento");
`endif
  endtask

  always @(all_pads or RST_BYTE or READY) begin
    #(SETTLE);
    if (RST_BYTE) expect_isolated();
  end

  task automatic check_rearm(input realtime stable_since);
    wait (`TB_SUPERVISOR.ALLOW === 1'b1);
    if ($realtime - stable_since < 2_000_000 || RESET !== 1'b0)
      $fatal(1, "Permiso antes de 2 ms continuos: %0.3f ns", $realtime - stable_since);

    // P2 ya pasó; estos son el par explícito P3 ↑/↓ y el ↑ P4 de salida.
    @(posedge `TB_SUPERVISOR.rearm.PERMIT[1]);
    @(posedge CLK_BYTE);
    if ({RST_BYTE, LOCK_RAW} !== 2'b11) $fatal(1, "No hubo reset y lock en P3 ↑");
    @(negedge CLK_BYTE);
    if ({RST_BYTE, LOCK_RAW} !== 2'b11) $fatal(1, "No hubo reset y lock en P3 ↓");
    #(SETTLE);
    if (`TB_SEQ.ADDR !== 8'd0 || `TB_VIDEO.ADDR !== 11'd0 || registered_word !== 16'd0)
      $fatal(1, "El par de rearme no descartó la posición o el paquete anterior");
`ifdef FPGBC_FRAME
    if (board.tx.link.frame.timing.NEXT_PERIOD !== 0 ||
        board.tx.BURST_KIND !== 2'b00)
      $fatal(1, "El rearme no reinicio el encuadre desde el periodo 0");
`endif
    @(posedge CLK_BYTE);
    if (RST_BYTE !== 1'b1) $fatal(1, "RST_BYTE se anticipó a P4 ↑");
    #(SETTLE);
    if (RST_BYTE !== 1'b0 || READY !== 1'b0)
      $fatal(1, "Liberación incorrecta: RST_BYTE debe caer tras P4 sin esperar a READY");
  endtask

  task automatic active_payload;
    integer reads_before;
`ifdef FPGBC_FRAME
    // Los primeros periodos son sincronismos. Esperar lecturas reales, no
    // interpretar como RGB la primera reserva de reloj del cuadro.
    wait (VID_RD === 1'b0);
    @(posedge VID_RD);
    reads_before = total_reads;
    repeat (ABORT_READS) begin @(negedge CLK_BYTE); #(SETTLE); end
`else
    @(posedge CLK_REQ);
    reads_before = total_reads;
    decode_words(3 + ABORT_READS);
`endif
    if (total_reads - reads_before < ABORT_READS || !LOCK_RAW || !VID_RD ||
        D0_HS === PAD_Z || D1_HS === PAD_Z || CLK_HS_PAD === PAD_Z)
      $fatal(1, "Se requiere tráfico HS real en curso antes del fallo de prueba");
  endtask

  task automatic stop_clock(input bit stop_byte);
    integer other_before, byte_before;
    realtime last_edge;
    @(negedge CLK_BYTE);
    #1;
    `TB_PHY.clocks.pll.HOLD_LOCK_HIGH = 1'b1;
    byte_before = byte_edges;
    if (stop_byte) begin
      `TB_PHY.clocks.pll.PAUSE_BYTE = 1'b1;
      other_before = hs_edges;
      last_edge = last_byte_edge;
    end else begin
      REF_ENABLED = 1'b0;
      other_before = byte_edges;
      last_edge = last_ref_edge;
    end
    #(2 * BYTE_PERIOD);
    if (!LOCK_RAW || RST_BYTE || !hs_activity ||
        (stop_byte ? (byte_edges != byte_before || hs_edges == other_before)
                   : byte_edges == other_before))
      $fatal(1, "Fallo mal inyectado: el reloj restante y LOCK_RAW deben seguir activos");

    @(posedge RESET);
    if (LOCK_RAW !== 1'b1 || (stop_byte ? `TB_SUPERVISOR.BYTE_OK : `TB_SUPERVISOR.REF_OK) !== 1'b0 ||
        (stop_byte ? `TB_SUPERVISOR.REF_OK : `TB_SUPERVISOR.BYTE_OK) !== 1'b1)
      $fatal(1, "El watchdog debe detectar el reloj detenido por sí solo, con LOCK_RAW=1");
    #(SETTLE);
    expect_isolated();
    if (!LOCK_RAW || $realtime - last_edge > 3700.0 || (stop_byte && byte_edges != byte_before))
      $fatal(1, "Corte tardío o dependiente de CLK_BYTE: %0.3f ns", $realtime - last_edge);
    $display("PASS pérdida independiente de %s con LOCK_RAW alto: corte a %0.1f ns",
             stop_byte ? "CLK_BYTE" : "CLK_REF ", $realtime - last_edge);
    #500;
    expect_isolated();
    `TB_PHY.clocks.pll.HOLD_LOCK_HIGH = 1'b0;
    #(SETTLE);
    if (stop_byte) `TB_PHY.clocks.pll.PAUSE_BYTE = 1'b0;
    else REF_ENABLED = 1'b1;
    wait (LOCK_RAW === 1'b1);
    check_rearm($realtime);
  endtask

`ifdef FPGBC_WHITE
  `include "white_target_scenario.vh"
`else
  initial begin : scenario
    string init_hex;
    realtime started;
    integer first_line, stopped_ref_edges;
    if (!$value$plusargs("init_hex=%s", init_hex)) $fatal(1, "Falta +init_hex=<ROM original>");
    $readmemh(init_hex, reference_rom);

    #1 RST_SUP = 1'b1;
    #500 RST_SUP = 1'b0;
    stopped_ref_edges = ref_edges;
    #10000;
    expect_isolated();
    if (RESET !== 1'b1 || ref_edges != stopped_ref_edges || supervisor.REF_OK !== 1'b0)
      $fatal(1, "La PLL no debe salir de reset sin CLK_REF");
    $display("PASS arranque sin CLK_REF: PLL y dominio byte en reset");

    phy.clocks.pll.PAUSE_BYTE = 1'b1;
    REF_ENABLED = 1'b1;
    wait (RESET === 1'b0);
    started = $realtime;
    @(posedge RESET);
    // El modelo cuantiza cada semiperiodo a 1 fs (error acumulado <1 ns).
    if ($realtime - started < 3_999_999 || $realtime - started > 6_530_000 ||
        LOCK_RAW !== 1'b1 || supervisor.BYTE_OK !== 1'b0 || RST_BYTE !== 1'b1)
      $fatal(1, "No reintentó ante CLK_BYTE ausente durante adquisición");
    phy.clocks.pll.PAUSE_BYTE = 1'b0;
    wait (LOCK_RAW === 1'b1);
    $display("PASS reintento con LOCK_RAW alto y sin CLK_BYTE en adquisición");

    // Dos caídas separadas, una de ellas completamente entre muestras de CLK_WD.
    repeat (2) begin
      #1_700_000;
      @(negedge supervisor.CLK_WD);
      #3 phy.clocks.pll.DROP_LOCK = 1'b1;
      #2 phy.clocks.pll.DROP_LOCK = 1'b0;
      expect_isolated();
      if (supervisor.ALLOW !== 1'b0) $fatal(1, "Lock inestable liberó tráfico");
    end
    check_rearm($realtime);
    $display("PASS LOCK_RAW inestable y bajos entre muestras: ventana completa tras el último bajo");
    check_init("arranque supervisado");

    active_payload();
    stop_clock(0);
    check_init("tras pérdida de CLK_REF");

    active_payload();
    stop_clock(1);
    check_init("tras pérdida exclusiva de CLK_BYTE");

    active_payload();
    @(posedge CLK_BYTE);
    #2 RST_LINK = 1'b1;
    #(SETTLE);
    expect_isolated();
    if ({RESET, LOCK_RAW} !== 2'b01)
      $fatal(1, "El reset lógico no debe resetear la PLL con ambos relojes sanos");
    #7_000_000;
    expect_isolated();
    if ({RESET, LOCK_RAW} !== 2'b01) $fatal(1, "RST_LINK mantenido reinició la PLL");
    RST_LINK = 1'b0;
    check_rearm($realtime);
    check_init("tras reset lógico durante payload");
    full_line(0, first_line);
    $display("PASS reset durante HS: descarta lo parcial, repite ROM y reinicia SoT/W0/P0");
    $finish;
  end
  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("phy_supervisor.fst");
      $dumpvars(1, mipi_tx_TB, supervisor, supervisor.control, supervisor.rearm,
                supervisor.ref_watch, supervisor.byte_watch, phy, phy.control, seq);
    end
    #(4 * 272 * P * BYTE_PERIOD + 50_000_000);
    $fatal(1, "Tiempo agotado en la prueba del supervisor a %0d Hz", OSC_HZ);
  end
`endif
