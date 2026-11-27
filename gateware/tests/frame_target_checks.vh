  // Referencia basada en el orden de paquetes aprobado; no consulta los
  // indices/tipos internos para decidir lo que se espera de los pads.
  bit startup_lp11_seen = 0, startup_escape_seen = 0;
  realtime startup_lp11_at;
  always @(D0_LP or D1_LP or CLK_LP or RST_BYTE) begin
    if (RST_BYTE) begin
      startup_lp11_seen = 0;
      startup_escape_seen = 0;
    end else begin
      if (!startup_lp11_seen && {D0_LP, D1_LP, CLK_LP} === 6'b111111) begin
        startup_lp11_seen = 1;
        startup_lp11_at = $realtime;
      end
      if (startup_lp11_seen && !startup_escape_seen && D0_LP === 2'b10) begin
        startup_escape_seen = 1;
        $display("LP11 fisico modelado antes del primer escape: %0.3f ns", $realtime - startup_lp11_at);
        if ($test$plusargs("check_tinit") && $realtime - startup_lp11_at < 100000)
          $fatal(1, "Primer LPDT sin 100 us de LP11 conducido");
        if ($test$plusargs("probe_startup")) $finish;
      end
    end
  end

  function automatic integer frame_kind(input integer period);
    if (period < 3) frame_kind = 0;
    else if (period >= 11 && period <= 730) frame_kind = 2;
    else frame_kind = 1;
  endfunction

  task automatic trace_frame_slots(input integer delta, output integer first_lp01);
`ifdef DATA_TIMING
    reg [1:0] want_dat;
    bit sampled_rd, long_burst, dat_on;
    integer last_slot, data_off_slot, lp11_slot;
    long_burst = delta == 8;
    last_slot = long_burst ? 1155 : 33;
    data_off_slot = long_burst ? 1139 : 26;
    lp11_slot = long_burst ? 1154 : 32;
    for (integer d = 0; d <= last_slot; d = d + 1) begin
      @(negedge CLK_BYTE);
      sampled_rd = VID_RD;
      #1;
      if (d == 0) first_lp01 = cycle;
      if (sampled_rd !== (long_burst && d >= 26 && d <= 1105))
        $fatal(1, "DATA_TIMING d%0d: lectura fuera del flanco esperado", d);
      if (board.tx.PK_DONE !== (d == (long_burst ? 1106 : 17)))
        $fatal(1, "DATA_TIMING d%0d: PK_DONE incorrecto", d);
      if (d < 5) want_dat = 2'b01;
      else if (d == 6 || d == data_off_slot + 1) want_dat = PAD_Z;
      else if (d >= lp11_slot) want_dat = 2'b11;
      else want_dat = 2'b00;
      dat_on = d >= 9 && d < data_off_slot;
      if ({D0_LP, D1_LP, CLK_LP} !== {want_dat, want_dat, 2'b00} ||
          (D0_HS !== PAD_Z) != dat_on || (D1_HS !== PAD_Z) != dat_on ||
          CLK_HS_PAD !== PAD_Z || READY !== (d == last_slot))
        $fatal(1, "DATA_TIMING d%0d largo=%b: LP=%b/%b HS=%b/%b READY=%b",
               d, long_burst, D0_LP, D1_LP, D0_HS, D1_HS, READY);
      if (d >= 9 && d <= 16 && {D0_HS, D1_HS} !== 4'b0101)
        $fatal(1, "DATA_TIMING: entrada sin ZERO suficiente");
    end
`else
    reg [1:0] want_dat, want_clk;
    bit dat_on, clk_on;
    bit sampled_rd;
    for (integer d = 0; d <= 1159 + delta; d = d + 1) begin
      @(negedge CLK_BYTE);
      sampled_rd = VID_RD;
      #1;
      if (sampled_rd !== (delta == 8 && d >= 52 && d <= 1131))
        $fatal(1, "d%0d delta=%0d: lectura fuera del flanco RGB aprobado", d, delta);
      if (board.tx.PK_DONE !== (d == 1124 + delta))
        $fatal(1, "d%0d: fin anterior/posterior al ultimo WORD registrado", d);
      if (d == 27) first_lp01 = cycle;
      if (d < 27 || d >= 1135 + delta) want_dat = 2'b11;
      else if (d < 31) want_dat = 2'b01;
      else if (d == 32 || d == 1134 + delta) want_dat = PAD_Z;
      else want_dat = 2'b00;
      if (d == 0 || d >= 1153 + delta) want_clk = 2'b11;
      else if (d < 5) want_clk = 2'b01;
      else if (d == 6 || d == 1152 + delta) want_clk = PAD_Z;
      else want_clk = 2'b00;
      dat_on = d >= 35 && d < 1133 + delta;
      clk_on = d >= 8 && d < 1151 + delta;
`ifdef DATA_ONLY
      want_clk = 2'b00;
      clk_on = 0;
`endif
      if ({D0_LP, D1_LP, CLK_LP} !== {want_dat, want_dat, want_clk} ||
          (D0_HS !== PAD_Z) != dat_on || (D1_HS !== PAD_Z) != dat_on ||
          (CLK_HS_PAD !== PAD_Z) != clk_on || READY !== (d == 1159 + delta))
        $fatal(1, "d%0d delta=%0d: pads/READY fuera del presupuesto de cuadro", d, delta);
`ifndef DATA_ONLY
      if (d == 27 && (first_clock == 0 || $realtime - 1.0 - first_clock < 8 * UI))
        $fatal(1, "CLK-PRE insuficiente");
`endif
      if (d >= 35 && d <= 42 && {D0_HS, D1_HS} !== 4'b0101)
        $fatal(1, "Entrada HS sin ZERO");
`ifndef DATA_ONLY
      if (d == 25 && (first_clock == 0 || last_clock - first_clock < 2 * UI - SETTLE))
        $fatal(1, "CLK no arranco antes de datos");
      if (d == 1147 + delta && CLK_HS_PAD !== 2'b01)
        $fatal(1, "CLK no regreso a HS-0");
`endif
    end
`endif
  endtask

`ifdef DATA_TIMING
  // Medición por cambios de los pads, independiente de los slots internos.
  function automatic realtime measured_abs(input realtime value);
    measured_abs = value < 0 ? -value : value;
  endfunction
  bit measured_line_seen = 0, measured_idle_seen = 0;
  reg [1:0] measured_previous_lp = PAD_Z;
  realtime measured_line_at, measured_idle_at;
  always @(D0_LP or RST_BYTE) begin
    if (RST_BYTE) begin
      measured_line_seen = 0;
      measured_idle_seen = 0;
      measured_previous_lp = PAD_Z;
    end else if (INIT_DONE) begin
      if (D0_LP === 2'b11 && measured_previous_lp !== 2'b11) begin
        measured_idle_seen = 1;
        measured_idle_at = $realtime;
      end
      if (D0_LP === 2'b01 && measured_previous_lp === 2'b11) begin
        if (measured_line_seen) begin
          if (measured_abs(($realtime - measured_line_at) - 1166 * BYTE_PERIOD) > 0.02)
            $fatal(1, "DATA_TIMING: periodo de pads distinto de 21,20 us");
          if (!measured_idle_seen ||
              (measured_abs(($realtime - measured_idle_at) - 12 * BYTE_PERIOD) > 0.02 &&
               measured_abs(($realtime - measured_idle_at) - 1134 * BYTE_PERIOD) > 0.02))
            $fatal(1, "DATA_TIMING: reposo de pads incorrecto (%0.3f ns)", $realtime - measured_idle_at);
        end
        measured_line_seen = 1;
        measured_line_at = $realtime;
        measured_idle_seen = 0;
      end
      measured_previous_lp = D0_LP;
    end
  end
`endif

  task automatic decode_frame_words(input integer kind);
    integer words, zero_bits, offset;
    reg [1:0] bits, trail;
    reg [15:0] actual, expected, reference_crc, blank_crc;
    words = (kind == 2) ? 1092 : 3;  // SoT por carril + paquetes.
    zero_bits = 0;
    wait (D0_HS !== PAD_Z);
    do begin
      sample_bit(bits);
      if (bits === 2'b00) zero_bits = zero_bits + 1;
    end while (bits === 2'b00);
    if (zero_bits * UI < 145.0 - SETTLE || bits !== 2'b11)
      $fatal(1, "SoT sin ZERO suficiente o carriles desalineados");
    eye_active = 1;
    reference_crc = 16'hffff;
    blank_crc = 16'hffff;
    for (integer n = 0; n < words; n = n + 1) begin
      actual = (n == 0) ? 16'h0808 : 16'h0000;
      for (integer b = (n == 0) ? 4 : 0; b < 8; b = b + 1) begin
        sample_bit(bits);
        {actual[8+b], actual[b]} = bits;
      end
      case (n)
        0: expected = 16'hb8b8;
        1: expected = (kind == 0) ? 16'h0001 : 16'h0021;
        2: expected = (kind == 0) ? 16'h0700 : 16'h1200;
        3: expected = 16'h0619;
        4: expected = 16'h2500;
        5, 6, 7: begin
          expected = 0;
          blank_crc = crc_msb_byte(crc_msb_byte(blank_crc, actual[7:0]), actual[15:8]);
        end
        8: begin
          expected = reflect16(blank_crc);
          if (expected !== 16'h0870) $fatal(1, "CRC Blanking de referencia incorrecto");
        end
        9: expected = 16'h703e;
        10: expected = 16'h1308;
        1091: begin
          expected = reflect16(reference_crc);
          if (expected !== (WHITE ? 16'h3425 : 16'h7eee))
            $fatal(1, "CRC de referencia RGB incorrecto");
        end
        default: begin
          offset = 2 * (n - 11);
          expected = WHITE ? 16'hffff : {rgb_byte(offset + 1), rgb_byte(offset)};
          reference_crc = crc_msb_byte(reference_crc, actual[7:0]);
          reference_crc = crc_msb_byte(reference_crc, actual[15:8]);
        end
      endcase
      if (actual !== expected)
        $fatal(1, "tipo %0d palabra %0d: pads %04h, esperado %04h", kind, n, actual, expected);
    end
    eye_active = 0;
    // sample_bit vuelve tras la guarda cuando se verifica el ojo; referir
    // los tiempos de cierre al flanco real de muestreo, no al retorno.
    last_crc = $realtime - ($test$plusargs("check_eye") ? (0.5 - SETTLE) : 0);
    trail = ~{actual[15], actual[7]};
    fork
      begin
        do begin
          sample_bit(bits);
          if (bits !== trail && bits !== 2'bzz)
            $fatal(1, "Trail incorrecto despues del ultimo bit de paquete");
        end while (bits !== 2'bzz);
      end
      begin
        wait ({D1_HS, D0_HS} === 4'bzzzz);
        data_off = $realtime;
      end
    join
    if (data_off - last_crc - UI < 60.0 + 4.0 * UI)
      $fatal(1, "Trail insuficiente");
  endtask

  task automatic frame_period(input integer kind, output integer first_lp01);
    integer reads_before, delta;
    @(posedge CLK_REQ);
    if (!READY || !LOCK || !INIT_DONE) $fatal(1, "Readmision sin PHY disponible");
    reads_before = total_reads;
    first_clock = 0;
    last_clock = 0;
    clock_off = 0;
`ifdef DATA_ONLY
    track_clock = 0;
`else
    track_clock = 1;
`endif
    delta = (kind == 2) ? 8 : -1081;
    fork
      trace_frame_slots(delta, first_lp01);
      decode_frame_words(kind);
    join
    track_clock = 0;
`ifndef DATA_ONLY
    if (last_clock - data_off < 60.0 + 52.0 * UI || clock_off - last_clock < 60.0)
      $fatal(1, "CLK-POST o CLK-TRAIL insuficiente");
`endif
    if (total_reads - reads_before != ((kind == 2) ? 1080 : 0))
      $fatal(1, "tipo %0d: %0d lecturas inesperadas", kind, total_reads - reads_before);
  endtask

  task automatic check_frames;
    integer first, previous, frame_start, old_frame_start, reads_before, active;
    previous = -1;
    old_frame_start = -1;
    reads_before = total_reads;
    for (integer f = 0; f < 2; f = f + 1) begin
      active = 0;
      for (integer p = 0; p < 743; p = p + 1) begin
        frame_period(frame_kind(p), first);
        if (previous >= 0 && first - previous != C_LINE)
          $fatal(1, "Cuadro %0d periodo %0d: separacion %0d, esperado %0d",
                 f, p, first - previous, C_LINE);
        previous = first;
        if (p == 0) frame_start = first;
        if (frame_kind(p) == 2) active = active + 1;
      end
      if (active != 720 || (f == 1 && frame_start - old_frame_start != 743 * C_LINE))
        $fatal(1, "Encuadre incorrecto");
      old_frame_start = frame_start;
      $display("PASS cuadro %0d desde pads: 743 periodos, 720 RGB, CRC %s, C_LINE=%0d",
               f, WHITE ? "25/34" : "EE/7E", C_LINE);
    end
    if (total_reads - reads_before != 2 * 720 * 1080)
      $fatal(1, "Lecturas totales incorrectas en dos cuadros");
    $display("PASS dos cuadros: 1555200 lecturas RGB, cero en sincronismos");
  endtask

  task automatic check_restarted_frame;
    integer first, previous;
    previous = -1;
    for (integer p = 0; p <= 11; p = p + 1) begin
      frame_period(frame_kind(p), first);
      if (previous >= 0 && first - previous != C_LINE)
        $fatal(1, "Periodo incorrecto tras rearme");
      previous = first;
    end
    $display("PASS rearme: periodo 0 VSS y primera linea RGB completa desde pads");
  endtask
