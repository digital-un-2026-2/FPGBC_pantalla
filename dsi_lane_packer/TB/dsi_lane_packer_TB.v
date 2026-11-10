`timescale 1ns / 1ps

module dsi_lane_packer_TB;
  reg clk = 0;
  always #12.5 clk = !clk;
  reg rst = 0;
  // 0: inyección; 1: preparador corto; 2: preparador largo.
  reg [1:0] source = 0;
  reg [7:0] inject_data = 0;
  reg inject_valid = 0, inject_last = 0;
  wire [7:0] short_data, long_data;
  wire short_valid, short_last, long_valid, long_last;
  wire byte_ready;
  wire [7:0] byte_data = source == 1 ? short_data : source == 2 ? long_data : inject_data;
  wire byte_valid = source == 1 ? short_valid : source == 2 ? long_valid : inject_valid;
  wire byte_last = source == 1 ? short_last : source == 2 ? long_last : inject_last;
  wire [15:0] word_data;
  wire [1:0] word_keep;
  wire word_valid, word_last;
  reg word_ready = 0;
  // 0: pausa sostenida; 1: siempre listo; 2: pausas pseudoaleatorias.
  integer receiver_mode = 1;
  reg [31:0] rng = 32'h4a8713b9;
  always @(negedge clk) begin
    rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
    word_ready = receiver_mode == 1 || (receiver_mode == 2 && rng[0] && rng[3]);
  end

  dsi_lane_packer dut (
      .clk(clk), .rst(rst), .tx_byte_data(byte_data),
      .tx_byte_valid(byte_valid), .tx_byte_last(byte_last), .tx_byte_ready(byte_ready),
      .tx_word_data(word_data), .tx_word_keep(word_keep),
      .tx_word_valid(word_valid), .tx_word_last(word_last), .tx_word_ready(word_ready)
  );

  reg short_cmd = 0, short_has_param = 0;
  reg [7:0] short_opcode = 0, short_param = 0;
  wire short_cmd_ready;
  dsi_lp_packet_tx short_tx (
      .clk(clk), .rst(rst), .cmd_valid(short_cmd), .cmd_ready(short_cmd_ready),
      .cmd_opcode(short_opcode), .cmd_has_param(short_has_param), .cmd_param(short_param),
      .tx_byte_data(short_data), .tx_byte_valid(short_valid), .tx_byte_last(short_last),
      .tx_byte_ready(byte_ready && source == 1), .busy(), .packet_done()
  );
  reg long_cmd = 0, payload_valid = 0;
  reg [1:0] vc = 0;
  reg [5:0] dt = 6'h39;
  reg [15:0] wc = 0;
  reg [7:0] payload_data = 0;
  wire long_cmd_ready, payload_ready;
  dsi_long_packet_tx long_tx (
      .clk(clk), .rst(rst), .cmd_valid(long_cmd), .cmd_ready(long_cmd_ready),
      .cmd_vc(vc), .cmd_dt(dt), .cmd_wc(wc),
      .payload_data(payload_data), .payload_valid(payload_valid), .payload_ready(payload_ready),
      .tx_byte_data(long_data), .tx_byte_valid(long_valid), .tx_byte_last(long_last),
      .tx_byte_ready(byte_ready && source == 2), .busy(), .packet_done()
  );

  // Modelo independiente: cola de bytes aceptados, sin consultar el estado RTL.
  reg [7:0] expected_data [0:131071];
  reg expected_last [0:131071];
  integer wr = 0, rd = 0;
  integer packets = 0, words = 0, accepted_bytes = 0, resets = 0;
  integer partial_words = 0, stall_cycles = 0;
  reg stalled = 0;
  reg [15:0] held_data;
  reg [1:0] held_keep;
  reg held_last;
  reg [15:0] wanted_data;
  reg [1:0] wanted_keep;
  reg wanted_last;
  integer take;
  always @(posedge clk) begin
    if (rst) begin
      if (byte_ready !== 0 || word_valid !== 0) $fatal(1, "Handshake durante reset");
      wr = 0; rd = 0; stalled = 0;
    end else begin
      if (stalled && (word_valid !== 1 || word_data !== held_data ||
                      word_keep !== held_keep || word_last !== held_last))
        $fatal(1, "Salida inestable con backpressure");
      if (word_valid && byte_ready) $fatal(1, "Entrada habilitada con salida pendiente");
      if (byte_valid && byte_ready) begin
        if (wr >= 131072) $fatal(1, "Cola de referencia llena");
        expected_data[wr] = byte_data;
        expected_last[wr] = byte_last;
        wr = wr + 1;
        accepted_bytes = accepted_bytes + 1;
      end
      if (word_valid) begin
        if (rd >= wr) $fatal(1, "Palabra sin entrada");
        if (expected_last[rd]) begin
          wanted_data = {8'h00, expected_data[rd]};
          wanted_keep = 2'b01; wanted_last = 1; take = 1;
        end else begin
          if (rd + 1 >= wr) $fatal(1, "Par incompleto publicado");
          wanted_data = {expected_data[rd+1], expected_data[rd]};
          wanted_keep = 2'b11; wanted_last = expected_last[rd+1]; take = 2;
        end
        if (word_data !== wanted_data || word_keep !== wanted_keep || word_last !== wanted_last)
          $fatal(1, "Grupo incorrecto: %h/%b/%b esperado %h/%b/%b", word_data,
                 word_keep, word_last, wanted_data, wanted_keep, wanted_last);
        if (word_ready) begin
          rd = rd + take; words = words + 1;
          if (word_last) packets = packets + 1;
          if (word_keep == 1) partial_words = partial_words + 1;
        end
      end
      stalled = word_valid && !word_ready;
      if (stalled) stall_cycles = stall_cycles + 1;
      held_data = word_data; held_keep = word_keep; held_last = word_last;
    end
  end

  task reset_all;
    begin
      @(negedge clk);
      rst = 1; inject_valid = 0; short_cmd = 0; long_cmd = 0; payload_valid = 0;
      #1;
      if (byte_ready !== 0 || word_valid !== 0) $fatal(1, "Reset no bloquea inmediatamente");
      repeat (2) @(negedge clk);
      rst = 0; resets = resets + 1;
      #1;
      if (byte_ready !== 1 || word_valid !== 0) $fatal(1, "Reposo tras reset");
    end
  endtask

  task send_byte(input [7:0] value, input last);
    begin
      @(negedge clk);
      inject_data = value; inject_last = last; inject_valid = 1;
      @(posedge clk);
      while (!byte_ready) @(posedge clk);
      @(negedge clk); inject_valid = 0;
    end
  endtask

  task await_packet(input integer target);
    begin
      @(negedge clk);
      while (packets < target) @(negedge clk);
      if (rd != wr) $fatal(1, "Bytes pendientes al finalizar paquete");
    end
  endtask

  task short_packet(input [7:0] opcode, input has_param, input [7:0] param);
    integer target;
    begin
      target = packets + 1;
      @(negedge clk); source = 1;
      short_opcode = opcode; short_has_param = has_param; short_param = param; short_cmd = 1;
      @(posedge clk); while (!short_cmd_ready) @(posedge clk);
      @(negedge clk); short_cmd = 0;
      await_packet(target);
    end
  endtask

  task long_packet(input integer length, input integer channel, input integer dtype);
    integer i, target;
    begin
      target = packets + 1;
      @(negedge clk); source = 2; wc = length; vc = channel; dt = dtype; long_cmd = 1;
      @(posedge clk); while (!long_cmd_ready) @(posedge clk);
      @(negedge clk); long_cmd = 0;
      for (i = 0; i < length; i = i + 1) begin
        repeat (rng[2:1]) @(negedge clk);
        @(negedge clk); payload_valid = 1; payload_data = (i * 37 + length) & 255;
        @(posedge clk); while (!payload_ready) @(posedge clk);
        @(negedge clk); payload_valid = 0;
      end
      await_packet(target);
    end
  endtask

  integer length, i, target;
  time first_accept;
  initial begin
    // Aplicar reset con un cambio real antes del primer posedge.
    #1; rst = 1;
    reset_all();
    // Sin valid, ni siquiera last alto crea una salida.
    inject_last = 1;
    repeat (8) @(negedge clk);
    if (word_valid || wr != 0) $fatal(1, "Paquete vacío publicado");
    // Paquetes consecutivos; tamaños pares/impares y patrones diferenciables.
    for (length = 1; length <= 33; length = length + 1) begin
      receiver_mode = length % 2 ? 2 : 1;
      target = packets + 1;
      for (i = 0; i < length; i = i + 1) begin
        repeat (rng[2:1]) @(negedge clk);
        send_byte((i * 19 + length) & 255, i == length - 1);
      end
      await_packet(target);
    end
    // Fuente siempre válida: par cada tres ciclos, sin aceptación en OUTPUT.
    receiver_mode = 1;
    @(negedge clk); inject_valid = 1; inject_data = 8'h91; inject_last = 0;
    @(posedge clk); first_accept = $time;
    @(negedge clk); inject_data = 8'ha2; inject_last = 1;
    @(posedge clk);
    @(negedge clk); inject_data = 8'hb3; inject_last = 1;
    @(posedge clk); if (byte_ready) $fatal(1, "Aceptación en entrega");
    @(posedge clk);
    if (!byte_ready || $time - first_accept != 75) $fatal(1, "Cadencia incorrecta");
    @(negedge clk); inject_valid = 0;
    target = packets + 1;
    await_packet(target);

    // Reset en EMPTY, HALF y OUTPUT (parcial y completo retenidos).
    reset_all();
    send_byte(8'h55, 0);
    repeat (5) @(negedge clk);
    if (word_valid) $fatal(1, "Se publica medio par sin last");
    reset_all();
    receiver_mode = 0;
    send_byte(8'h66, 1);
    repeat (20) @(negedge clk);
    if (!word_valid || word_keep != 1) $fatal(1, "Parcial no retenido");
    reset_all();
    send_byte(8'h77, 0); send_byte(8'h88, 1);
    repeat (20) @(negedge clk);
    if (!word_valid || word_keep != 3) $fatal(1, "Par no retenido");
    reset_all();
    receiver_mode = 1;
    repeat (8) @(negedge clk);
    if (word_valid) $fatal(1, "Salida residual después de reset");
    target = packets + 1; send_byte(8'h99, 1); await_packet(target);

    // Integración real: encabezados completos, carga útil y CRC cruzan el packer.
    receiver_mode = 2;
    short_packet(8'h01, 0, 0);
    // Vector fijo documentado de Software Reset: 05 01 00 10.
    if (wr != 5 || expected_data[1] !== 8'h05 || expected_data[2] !== 8'h01 ||
        expected_data[3] !== 8'h00 || expected_data[4] !== 8'h10)
      $fatal(1, "Vector corto fijo incorrecto");
    short_packet(8'h3a, 1, 8'h77);
    short_packet(8'h29, 0, 0);
    for (length = 0; length < 10; length = length + 1)
      long_packet(length, length % 4, 6'h39);
    long_packet(255, 0, 6'h39);
    long_packet(256, 1, 6'h39);
    long_packet(257, 2, 6'h39);
    long_packet(2160, 0, 6'h3e);
    long_packet(65535, 3, 6'h39);
    repeat (10) @(negedge clk);
    if (wr != rd || word_valid) $fatal(1, "Salida sobrante");
    if (packets != 54 || partial_words == 0 || stall_cycles < 40)
      $fatal(1, "Cobertura insuficiente: paquetes=%0d", packets);
    $display("PASS: %0d paquetes, %0d palabras, %0d bytes aceptados, %0d parciales, %0d ciclos de pausa, %0d resets",
             packets, words, accepted_bytes, partial_words, stall_cycles, resets);
    $finish;
  end

  initial begin
    #100000000;
    $fatal(1, "Timeout global");
  end
endmodule
