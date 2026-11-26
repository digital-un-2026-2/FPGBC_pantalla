  // Extensión del banco del PR #11. El receptor usa exclusivamente los
  // pads modelados para reconstruir los bytes; las señales lógicas solo
  // sirven para comprobar flancos de petición, lectura y rearme.
  localparam realtime UI = BYTE_PERIOD / 8.0, SETTLE = 0.010;
  localparam [1:0] PAD_Z = 2'bzz;
  integer total_reads = 0;
  bit track_clock = 0;
  realtime first_clock, last_clock, data_off, clock_off, last_crc;
  reg prev_clock = 1'bz;

  always @(negedge CLK_BYTE) if (VID_RD) total_reads <= total_reads + 1;

  task automatic check_pair(input [1:0] lp, hs);
    if (hs !== PAD_Z &&
        (lp !== 2'b00 || (hs !== 2'b01 && hs !== 2'b10)))
      $fatal(1, "Par incompatible: LP=%b HS=%b en %0.3f ns", lp, hs, $realtime);
  endtask

  always @(D0_LP or D1_LP or CLK_LP or D0_HS or D1_HS or CLK_HS_PAD or INIT_DONE) begin
    #(SETTLE);
    check_pair(D0_LP, D0_HS);
    check_pair(D1_LP, D1_HS);
    check_pair(CLK_LP, CLK_HS_PAD);
    if (!INIT_DONE && hs_activity)
      $fatal(1, "Excitación diferencial antes de END");
  end

  always @(CLK_HS_PAD[1]) begin
    if (track_clock) begin
      case (CLK_HS_PAD[1])
        1'b0: if (prev_clock === 1'b1) begin
          if ($realtime - last_clock < UI - SETTLE || $realtime - last_clock > UI + SETTLE)
            $fatal(1, "Pulso alto recortado o extendido en CLK");
          last_clock = $realtime;
        end
        1'b1: begin
          if (prev_clock !== 1'b0)
            $fatal(1, "CLK se habilitó en alto");
          if (first_clock == 0) first_clock = $realtime;
          else if ($realtime - last_clock < UI - SETTLE || $realtime - last_clock > UI + SETTLE)
            $fatal(1, "Hueco o pulso bajo incorrecto en CLK");
          last_clock = $realtime;
        end
        1'bz: begin
          if (prev_clock !== 1'b0) $fatal(1, "CLK se aisló en alto");
          clock_off = $realtime;
        end
        default: $fatal(1, "Nivel desconocido en CLK");
      endcase
    end
    prev_clock = CLK_HS_PAD[1];
  end

`ifndef PHY_SUPERVISED
  task automatic cut_and_reset(input bit aborting);
    reg prev_byte, prev_hs;
    if (aborting) begin
      track_clock = 0;
      if (!hs_activity || !VID_RD || !phy.LOCK_RAW)
        $fatal(1, "Precondición: abortar con ambos relojes activos y payload en curso");
      phy.clocks.pll.PAUSE_OUTPUTS = 1;
      prev_byte = CLK_BYTE;
      prev_hs = phy.CLK_HS;
      #(2 * BYTE_PERIOD);
      if ({CLK_BYTE, phy.CLK_HS, phy.LOCK_RAW} !== {prev_byte, prev_hs, 1'b1} ||
          !hs_activity)
        $fatal(1, "La pérdida inyectada debe parar CLK_BYTE y CLK_HS sin bajar LOCK_RAW");
    end else begin
      // Arranque: RESET de PLL se libera antes que el reset lógico común.
      #50 RESET = 0;
      wait (phy.LOCK_RAW === 1'b1);
    end

    RST_BYTE = 1;
    #(SETTLE);
    if ({D0_LP, D1_LP, CLK_LP, D0_HS, D1_HS, CLK_HS_PAD} !== {12{1'bz}})
      $fatal(1, "ISO no llegó a todos los pads con los relojes detenidos");
    if (aborting) begin
      #(2 * BYTE_PERIOD);
      if ({CLK_BYTE, phy.CLK_HS} !== {prev_byte, prev_hs} || READY !== 1'b0)
        $fatal(1, "Cambió un reloj durante el corte o hubo rearme en reset");
      phy.clocks.pll.PAUSE_OUTPUTS = 0;
    end
    @(posedge CLK_BYTE); #1;
    if ({INIT_REQ, INIT_DONE_TX, INIT_NEXT, INIT_DONE, VID_REQ, VID_LINE_RDY, HS_REQ, CLK_REQ} !== 0)
      $fatal(1, "Quedaron peticiones activas tras reset");
    sample_negedge();
    if ({LP_P, LP_N, registered_word, VID_RD, dut.PK_DONE,
         seq.ADDR, video.ADDR, video.RGB_PHASE} !== {6'b111111, 39'b0})
      $fatal(1, "El reset no limpió los registros o las direcciones de la transacción");
    if (READY !== 1'b0 || hs_activity)
      $fatal(1, "Hubo una reanudación de HS durante reset");
    RST_BYTE = 0;
  endtask
`endif

  task automatic trace_slots(output integer first_lp01);
    reg [1:0] want_dat, want_clk;
    bit dat_on, clk_on;
    for (integer d = 0; d <= 1159; d = d + 1) begin
      @(negedge CLK_BYTE);
      #1;
      if (d == 27) first_lp01 = cycle;
      if (d < 27 || d >= 1135) want_dat = 2'b11;
      else if (d < 31) want_dat = 2'b01;
      else if (d == 32 || d == 1134) want_dat = PAD_Z;
      else want_dat = 2'b00;
      if (d <= 0 || d >= 1153) want_clk = 2'b11;
      else if (d < 5) want_clk = 2'b01;
      else if (d == 6 || d == 1152) want_clk = PAD_Z;
      else want_clk = 2'b00;
      dat_on = d >= 35 && d < 1133;
      clk_on = d >= 8 && d < 1151;
      if ({D0_LP, D1_LP, CLK_LP} !== {want_dat, want_dat, want_clk} ||
          (D0_HS !== PAD_Z) != dat_on || (D1_HS !== PAD_Z) != dat_on ||
          (CLK_HS_PAD !== PAD_Z) != clk_on ||
          READY !== (d == 1159))
        $fatal(1, "d%0d: LP=%b/%b/%b HS=%b/%b/%b READY=%b fuera de la tabla",
               d, D0_LP, D1_LP, CLK_LP, D0_HS, D1_HS, CLK_HS_PAD, READY);
      if (d == 8 && CLK_HS_PAD !== 2'b01)
        $fatal(1, "CLK no comenzó en HS-0");
      if (d == 27 && (first_clock == 0 || $realtime - 1.0 - first_clock < 8 * UI))
        $fatal(1, "T_CLK-PRE insuficiente antes de LP01 de datos");
      if (d >= 35 && d <= 42 && {D0_HS, D1_HS} !== 4'b0101)
        $fatal(1, "Falta HS-0 en la entrada de datos");
      if (d == 25 && (first_clock == 0 || last_clock - first_clock < 2 * UI - SETTLE))
        $fatal(1, "El primer período de CLK no se completó en la ventana de arranque");
      if (d == 1147 && CLK_HS_PAD !== 2'b01)
        $fatal(1, "CLK no volvió a HS-0 en la ventana de cierre");
    end
  endtask

  task automatic sample_bit(output reg [1:0] bits);
    @(CLK_HS_PAD[1]);
    #(SETTLE);
    if (CLK_HS_PAD === PAD_Z)
      $fatal(1, "Se retiró CLK antes de terminar los datos");
    bits = {D1_HS[1], D0_HS[1]};
  endtask

  task automatic decode_words(input integer words);
    integer zero_bits, offset;
    reg [1:0] bits, trail;
    reg [15:0] actual, expected, reference_crc;
    zero_bits = 0;
    wait (D0_HS !== PAD_Z);
    do begin
      sample_bit(bits);
      if (bits === 2'b00) zero_bits = zero_bits + 1;
    end while (bits === 2'b00);
    if (zero_bits * UI < 145.0 - SETTLE || bits !== 2'b11)
      $fatal(1, "SoT desalineado entre carriles o HS-0 insuficiente");

    reference_crc = 16'hffff;
    for (integer n = 0; n < words; n = n + 1) begin
      actual = (n == 0) ? 16'h0808 : 16'h0000;
      // El primer 1 detectado es b3 del SoT; siguen b4…b7.
      for (integer b = (n == 0) ? 4 : 0; b < 8; b = b + 1) begin
        sample_bit(bits);
        {actual[8+b], actual[b]} = bits;
      end
      case (n)
        0: expected = 16'hb8b8;
        1: expected = 16'h703e;
        2: expected = 16'h1308;
        CRC_TAKE: begin
          expected = reflect16(reference_crc);
          if (expected !== (white_line ? 16'h3425 : 16'h7eee))
            $fatal(1, "CRC esperado distinto del perfil de prueba");
        end
        default: begin
          offset = 2 * (n - 3);
          expected = white_line ? 16'hffff : {rgb_byte(offset + 1), rgb_byte(offset)};
          // Cálculo de referencia bit a bit con bytes reconstruidos, D0 primero.
          reference_crc = crc_msb_byte(reference_crc, actual[7:0]);
          reference_crc = crc_msb_byte(reference_crc, actual[15:8]);
        end
      endcase
      if (actual !== expected)
        $fatal(1, "Palabra %0d en pads: %04h, esperado %04h", n, actual, expected);
    end

    if (words == HS_WORDS) begin
      last_crc = $realtime;
      trail = ~{actual[15], actual[7]};
      fork
        begin
          do begin
            sample_bit(bits);
            if (bits !== trail && bits !== 2'bzz)
              $fatal(1, "Trail incorrecto: D1/D0=%b, esperado %b", bits, trail);
          end while (bits !== 2'bzz);
        end
        begin
          wait ({D1_HS, D0_HS} === 4'bzzzz);
          data_off = $realtime;
        end
      join
      if (data_off - last_crc - UI < 60.0 + 4.0 * UI)
        $fatal(1, "Trail físico insuficiente tras el último bit real del CRC");
      $display("  %s: CRC D0/D1=%02h/%02h; trail >= %0.2f ns",
               white_line ? "blanco" : "barras", actual[7:0], actual[15:8], data_off - last_crc - UI);
    end
  endtask

  task automatic full_line(input bit white, output integer first_lp01);
    integer reads_before;
`ifdef FPGBC_WHITE
    if (white != WHITE) $fatal(1, "Patrón de prueba distinto de la variante exportada");
`else
    white_line = white;
`endif
    @(posedge CLK_REQ);
    if (!READY || !INIT_DONE) $fatal(1, "La reserva no llegó desde un reposo disponible");
    reads_before = total_reads;
    first_clock = 0;
    last_clock = 0;
    clock_off = 0;
    track_clock = 1;
    fork
      trace_slots(first_lp01);
      decode_words(HS_WORDS);
    join
    track_clock = 0;
    if (last_clock - data_off < 60.0 + 52.0 * UI || clock_off - last_clock < 60.0)
      $fatal(1, "T_CLK-POST o T_CLK-TRAIL insuficiente en pads");
    if (total_reads - reads_before != PIX_WORDS)
      $fatal(1, "Línea con %0d lecturas, esperaba 1080", total_reads - reads_before);
    $display("  1080 lecturas, post=%0.2f ns, CLK en HS-0 tras último pulso=%0.2f ns",
             last_clock - data_off, clock_off - last_clock);
  endtask

`ifdef PHY_SUPERVISED
  `include "supervised_link.vh"
`else
  initial begin : scenario
    string init_hex;
    integer first, second, restarted, previous_reads;
    if (!$value$plusargs("init_hex=%s", init_hex)) $fatal(1, "Falta +init_hex=<ROM original>");
    $readmemh(init_hex, reference_rom);
    if (reference_rom[ROM_WORDS-1] !== ROM_END) $fatal(1, "Falta END en la ROM de referencia");

    cut_and_reset(0);
    check_init("arranque Gowin");
    full_line(0, first);
    full_line(1, second);
    if (second - first != C_LINE) $fatal(1, "Las líneas no están separadas por C_LINE");
    $display("PASS dos líneas consecutivas desde pads, C_LINE=%0d", C_LINE);

    white_line = 0;
    @(posedge CLK_REQ);
    previous_reads = total_reads;
    decode_words(3 + ABORT_READS);
    if (total_reads - previous_reads < ABORT_READS)
      $fatal(1, "El aborto no entró en el payload");
    cut_and_reset(1);
    check_init("tras parada de CLK_BYTE/CLK_HS con LOCK_RAW alto");
    full_line(0, restarted);
    $display("PASS corte sin flancos y rearme: LP desde ROM, SoT/W0 y primer píxel intactos");
    $finish;
  end

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("phy_integration.fst");
      $dumpvars(1, mipi_tx_TB, phy, phy.control, phy.d0, phy.d1, phy.forwarded, phy.pads);
    end
    #(2 * 272 * P * BYTE_PERIOD + 1_000_000);
    $fatal(1, "Tiempo agotado en la prueba de pads");
  end
`endif
