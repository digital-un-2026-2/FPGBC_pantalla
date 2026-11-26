`timescale 1ps / 1ps

module clock_ddr_TB;
  localparam integer UI = 2273, HS_PERIOD = 2 * UI, BYTE_PERIOD = 8 * UI;
  localparam integer TEST_TAPS = 32, MODEL_DELAY = 25 * TEST_TAPS;
  reg CLK_HS = 0, RUN = 1, ISO = 0;
  reg CLK_ARM = 0, CLK_EN = 0;
  wire HS_CLK, HS_CLK_DELAYED;
  wire PANEL_CLK_MODEL = CLK_EN && !ISO ? HS_CLK_DELAYED : 1'bz;
  time last_direct_edge, last_pclk_rise, iso_released, first_edge;
  integer edge_count = 0, panel_edges = 0, word_index, edges_at_close;
  reg check_period = 0, check_delay = 0;

  clock_ddr direct (.CLK_HS(CLK_HS), .ISO(ISO), .HS_CLK(HS_CLK));
  clock_ddr #(.USE_IODELAY(1'b1), .STATIC_DELAY_TAPS(TEST_TAPS)) delayed (
      .CLK_HS(CLK_HS), .ISO(ISO), .HS_CLK(HS_CLK_DELAYED)
  );
`ifdef GOWIN_VENDOR_SIM
  GSR GSR (.GSRI(1'b1));
`endif

  always #UI if (RUN) CLK_HS = !CLK_HS;

  always @(HS_CLK) begin
    if (check_period) begin
      if ($time - last_direct_edge != UI || HS_CLK !== CLK_HS)
        $fatal(1, "Alternancia o fase lógica incorrecta en Q0: t=%0t", $time);
    end
    edge_count = edge_count + 1;
    last_direct_edge = $time;
  end

  always @(HS_CLK_DELAYED) begin
    if (check_delay && ($time - last_direct_edge != MODEL_DELAY || HS_CLK_DELAYED !== HS_CLK))
      $fatal(1, "La variante IODELAY no sigue el retardo del modelo: t=%0t", $time);
  end

  always @(posedge direct.PCLK_110) begin
    if (check_period && $time - last_pclk_rise != 2 * HS_PERIOD)
      $fatal(1, "PCLK local no divide CLK_HS por dos");
    last_pclk_rise = $time;
  end

  always @(PANEL_CLK_MODEL)
    if (CLK_EN && !ISO && PANEL_CLK_MODEL !== 1'bz) panel_edges = panel_edges + 1;

  task automatic arm_and_enable(input integer release_offset);
    integer previous_edges;
    begin
      #(release_offset);
      ISO = 0;
      iso_released = $time;
      // Separación nominal de la integración: ISO↓ → OE ≥ 3 slots.
      fork
        begin
          @(posedge HS_CLK);
          first_edge = $time;
          if (first_edge - iso_released > 8 * HS_PERIOD)
            $fatal(1, "OSER4 no arrancó dentro del presupuesto del modelo");
          #1;
          check_period = 1;
          @(posedge HS_CLK_DELAYED);
          #1;
          check_delay = 1;
        end
        begin
          #(BYTE_PERIOD + BYTE_PERIOD / 2);
          CLK_ARM = 1;
          #1;
          if (PANEL_CLK_MODEL !== 1'bz)
            $fatal(1, "ARM no debe conducir el reloj");
        end
      join

      #(iso_released + 3 * BYTE_PERIOD - $time);
      if (!check_period || !CLK_ARM || PANEL_CLK_MODEL !== 1'bz)
        $fatal(1, "OE antes de tener reloj listo");
      // OE ideal en fase baja. La alineación del OE real queda en integración.
      @(negedge HS_CLK_DELAYED);
      #1;
      previous_edges = panel_edges;
      CLK_EN = 1;
      #(BYTE_PERIOD);
      if (panel_edges - previous_edges != 9)
        $fatal(1, "El reloj no adelantó un slot al SoT modelado");
      $display("PASS arranque: ISO↓ a Q0 = %0t ps", first_edge - iso_released);
    end
  endtask

  task automatic expect_clock_slot;
    integer previous_edges;
    begin
      previous_edges = panel_edges;
      #(BYTE_PERIOD);
      if (panel_edges - previous_edges != 8)
        $fatal(1, "Faltan flancos en un slot conducido");
    end
  endtask

  task automatic abort_without_edges(input bit high);
    integer previous_edges;
    begin
      if (high) @(posedge HS_CLK_DELAYED);
      else      @(negedge HS_CLK_DELAYED);
      #1;
      if (PANEL_CLK_MODEL !== high) $fatal(1, "Precondición de aborto");
      RUN = 0;
      check_period = 0;
      check_delay = 0;
      ISO = 1;
      #1;
      if (PANEL_CLK_MODEL !== 1'bz || HS_CLK !== 0)
        $fatal(1, "ISO no corta el OE ideal y Q0 sin flancos");
      previous_edges = edge_count;
      #(HS_PERIOD + MODEL_DELAY);
      if (edge_count != previous_edges || HS_CLK_DELAYED !== 0)
        $fatal(1, "Quedaron flancos o datos viejos después de ISO");
      CLK_ARM = 0;
      CLK_EN = 0;
      RUN = 1;
      @(negedge CLK_HS);
      $display("PASS aborto sin flancos de entrada, nivel previo %b", high);
    end
  endtask

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("clock_ddr_TB.fst");
      $dumpvars(0, clock_ddr_TB);
    end
    #1;
    ISO = 1;
    @(negedge CLK_HS);
    arm_and_enable(1);
    // SoT y 1083 palabras de reloj, incluida la última palabra (CRC).
    for (word_index = 0; word_index < 1084; word_index = word_index + 1)
      expect_clock_slot();
    repeat (7) expect_clock_slot();  // Trail programado en el modelo de ventana.
    repeat (10) expect_clock_slot(); // Retención ideal tras trail.
    if (PANEL_CLK_MODEL !== 0) $fatal(1, "Cierre normal antes de terminar el pulso alto");
    CLK_EN = 0;
    CLK_ARM = 0;
    edges_at_close = edge_count;
    #(BYTE_PERIOD);
    if (PANEL_CLK_MODEL !== 1'bz || edge_count - edges_at_close != 8)
      $fatal(1, "El cierre normal debe aislar sin detener CLOCK_DDR");
    $display("PASS cierre: reloj continuo durante SoT, palabras, CRC, trail y retención");

    // Otra ráfaga sin reinicio entre cierres normales; no se rearma OSER4.
    CLK_ARM = 1;
    @(negedge HS_CLK_DELAYED);
    #1 CLK_EN = 1;
    abort_without_edges(1);
    arm_and_enable(UI + 1);
    abort_without_edges(0);
    arm_and_enable(37);
    expect_clock_slot();
    $display("PASS CLOCK_DDR (directo y con retardo funcional)");
    $finish;
  end

  initial begin
    #100_000_000;
    $fatal(1, "Timeout de CLOCK_DDR");
  end
endmodule
