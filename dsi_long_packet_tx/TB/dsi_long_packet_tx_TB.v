`timescale 1ns / 1ps

module dsi_long_packet_tx_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 1, cmd_valid = 0, payload_valid = 0, tx_byte_ready = 0;
  reg [1:0] cmd_vc = 0;
  reg [5:0] cmd_dt = 0;
  reg [15:0] cmd_wc = 0;
  reg [7:0] payload_data = 0;
  wire cmd_ready, payload_ready, tx_byte_valid, tx_byte_last, busy, packet_done;
  wire [7:0] tx_byte_data;
  dsi_long_packet_tx dut (
      .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .cmd_vc(cmd_vc),
      .cmd_dt(cmd_dt), .cmd_wc(cmd_wc), .cmd_ready(cmd_ready),
      .payload_data(payload_data), .payload_valid(payload_valid),
      .payload_ready(payload_ready), .tx_byte_data(tx_byte_data),
      .tx_byte_valid(tx_byte_valid), .tx_byte_last(tx_byte_last),
      .tx_byte_ready(tx_byte_ready), .busy(busy), .packet_done(packet_done)
  );

  // Oráculo CRC en dirección MSB: 1021, entrada y resultado reflejados.
  function [15:0] crc_msb_update;
    input [15:0] crc;
    input [7:0] data;
    reg [15:0] c;
    integer b;
    begin
      c = crc;
      for (b = 0; b < 8; b = b + 1) begin
        if (c[15] ^ data[b]) c = (c << 1) ^ 16'h1021;
        else c = c << 1;
      end
      crc_msb_update = c;
    end
  endfunction

  function [15:0] reflect16;
    input [15:0] v;
    integer b;
    begin
      for (b = 0; b < 16; b = b + 1) reflect16[b] = v[15-b];
    end
  endfunction

  function [7:0] reference_ecc;
    input [23:0] header;
    integer bit_index;
    reg [7:0] syndrome;
    begin
      reference_ecc = 8'h00;
      for (bit_index = 0; bit_index < 24; bit_index = bit_index + 1) begin
        case (bit_index)
          0: syndrome = 8'h07;  1: syndrome = 8'h0b;
          2: syndrome = 8'h0d;  3: syndrome = 8'h0e;
          4: syndrome = 8'h13;  5: syndrome = 8'h15;
          6: syndrome = 8'h16;  7: syndrome = 8'h19;
          8: syndrome = 8'h1a;  9: syndrome = 8'h1c;
          10: syndrome = 8'h23; 11: syndrome = 8'h25;
          12: syndrome = 8'h26; 13: syndrome = 8'h29;
          14: syndrome = 8'h2a; 15: syndrome = 8'h2c;
          16: syndrome = 8'h31; 17: syndrome = 8'h32;
          18: syndrome = 8'h34; 19: syndrome = 8'h38;
          20: syndrome = 8'h1f; 21: syndrome = 8'h2f;
          22: syndrome = 8'h37; 23: syndrome = 8'h3b;
          default: syndrome = 8'h00;
        endcase
        if (header[bit_index]) reference_ecc = reference_ecc ^ syndrome;
      end
    end
  endfunction


  reg [15:0] probe_crc = 0;
  reg [7:0] probe_data = 0;
  wire [15:0] probe_result;
  long_packet_crc16 crc_probe (
      .crc_in(probe_crc), .byte_in(probe_data), .crc_out(probe_result)
  );
  reg [23:0] probe_header = 0;
  wire [7:0] probe_ecc;
  long_packet_ecc ecc_probe (.header(probe_header), .ecc(probe_ecc));

  reg active = 0, expected_done = 0;
  reg [31:0] expected_header;
  reg [15:0] expected_crc;
  reg [7:0] payload_queue [0:65534];
  integer wc, received, out_index;
  integer accepted = 0, completed = 0, aborted = 0;
  reg stalled = 0;
  reg [7:0] stalled_data;
  reg stalled_last;
  reg [7:0] expected_byte;
  reg [15:0] reflected_crc;

  // Scoreboard de puertos públicos, sin observar estado ni registros del DUT.
  always @(posedge clk) begin
    if (rst) begin
      if (cmd_ready !== 0 || payload_ready !== 0 || tx_byte_valid !== 0)
        $fatal(1, "Handshake activo durante reset");
      if (active) aborted = aborted + 1;
      active = 0;
      expected_done = 0;
      stalled = 0;
      received = 0;
      out_index = 0;
    end else begin
      if (busy !== active || cmd_ready !== !active)
        $fatal(1, "busy/cmd_ready incorrectos a t=%0t", $time);
      if (stalled && (!tx_byte_valid || tx_byte_data !== stalled_data ||
                      tx_byte_last !== stalled_last))
        $fatal(1, "Salida cambió durante backpressure");
      expected_done = 0;
      if (cmd_valid && cmd_ready) begin
        if (active) $fatal(1, "Descriptor aceptado mientras ocupado");
        expected_header[23:0] = {cmd_wc, cmd_vc, cmd_dt};
        expected_header[31:24] = reference_ecc(expected_header[23:0]);
        wc = cmd_wc;
        received = 0;
        out_index = 0;
        expected_crc = 16'hffff;
        active = 1;
        accepted = accepted + 1;
      end
      if (payload_ready && (!active || received >= wc))
        $fatal(1, "Se solicita carga útil fuera de WC");
      if (payload_valid && payload_ready) begin
        payload_queue[received] = payload_data;
        received = received + 1;
      end
      if (tx_byte_valid) begin
        if (!active) $fatal(1, "Byte sin paquete activo");
        reflected_crc = reflect16(expected_crc);
        if (out_index < 4) expected_byte = expected_header[8*out_index +: 8];
        else if (out_index < wc + 4) begin
          if (out_index - 4 >= received) $fatal(1, "Byte no aceptado del productor");
          expected_byte = payload_queue[out_index-4];
        end else if (out_index == wc + 4) expected_byte = reflected_crc[7:0];
        else if (out_index == wc + 5) expected_byte = reflected_crc[15:8];
        else $fatal(1, "Byte extra");
        if (tx_byte_data !== expected_byte || tx_byte_last !== (out_index == wc+5))
          $fatal(1, "Byte %0d/%0d: dato %02h != %02h, last=%b, t=%0t",
                 out_index, wc+6, tx_byte_data, expected_byte, tx_byte_last, $time);
        if (tx_byte_ready) begin
          if (out_index >= 4 && out_index < wc+4)
            expected_crc = crc_msb_update(expected_crc, expected_byte);
          if (out_index == wc+5) begin
            if (received != wc) $fatal(1, "Cantidad de carga útil incorrecta");
            active = 0;
            completed = completed + 1;
            expected_done = 1;
          end
          out_index = out_index + 1;
        end
      end
      stalled = tx_byte_valid && !tx_byte_ready;
      stalled_data = tx_byte_data;
      stalled_last = tx_byte_last;
    end
    #1;
    if (packet_done !== expected_done) $fatal(1, "packet_done incorrecto");
    if (busy !== active) $fatal(1, "Estado de ocupación incorrecto tras flanco");
    if (rst && (cmd_ready !== 0 || payload_ready !== 0 || tx_byte_valid !== 0))
      $fatal(1, "Reset no bloquea los puertos");
  end

  reg [31:0] rng = 32'h9614a3f7;
  task randomize;
    begin
      rng = rng ^ (rng << 13);
      rng = rng ^ (rng >> 17);
      rng = rng ^ (rng << 5);
    end
  endtask

  task reset_block;
    begin
      @(negedge clk);
      rst = 1; cmd_valid = 1; payload_valid = 1; tx_byte_ready = 1;
      @(posedge clk); #2;
      @(negedge clk);
      rst = 0; cmd_valid = 0; payload_valid = 0; tx_byte_ready = 0;
    end
  endtask

  // abort_cycle recorre también estados sin salida (CHECK y WAIT).
  // abort_byte fuerza reset con un byte válido y ready=1 antes de transferirlo.
  task run_packet;
    input [15:0] length;
    input [1:0] vc;
    input [5:0] dt;
    input integer mode;
    input integer abort_cycle;
    input integer abort_byte;
    integer sent, cycles, target_completed;
    reg pay_was_accepted;
    begin
      target_completed = completed + 1;
      @(negedge clk);
      cmd_valid = 1; cmd_wc = length; cmd_vc = vc; cmd_dt = dt;
      payload_valid = 0; tx_byte_ready = 0;
      @(posedge clk); #2;
      sent = 0; cycles = 0;
      begin : transfer_loop
        while (completed < target_completed) begin
          @(negedge clk);
          cycles = cycles + 1;
          if (cycles == abort_cycle ||
              (abort_byte >= 0 && tx_byte_valid && out_index == abort_byte)) begin
            rst = 1; cmd_valid = 1; payload_valid = 1; tx_byte_ready = 1;
            @(posedge clk); #2;
            @(negedge clk);
            rst = 0; cmd_valid = 0; payload_valid = 0; tx_byte_ready = 0;
            disable transfer_loop;
          end
          // Una orden pendiente no puede alterar el descriptor ya capturado.
          cmd_valid = 1; cmd_wc = ~length; cmd_vc = ~vc; cmd_dt = ~dt;
          randomize;
          tx_byte_ready = (mode == 0) || ((cycles % 4) == 0) || rng[0];
          if (sent < length) begin
            // Mantener valid/dato hasta el handshake del productor.
            if (!payload_valid) begin
              payload_valid = (mode == 0) || rng[2];
              payload_data = (sent * 37 + length) & 255;
            end
          end else begin
            // Datos extra disponibles: el bloque debe dejar ready en cero.
            payload_valid = 1;
            payload_data = 8'ha5;
          end
          pay_was_accepted = payload_valid && payload_ready;
          @(posedge clk); #2;
          if (pay_was_accepted) begin
            sent = sent + 1;
            // Solo el productor actualiza sus entradas en negedge.
          end
          if (cycles > 15*length + 200) $fatal(1, "Timeout del paquete");
          if (pay_was_accepted) begin
            @(negedge clk);
            payload_valid = 0;
          end
        end
      end
      // Evitar que la orden pendiente se acepte en el siguiente flanco.
      @(negedge clk);
      cmd_valid = 0; payload_valid = 0; tx_byte_ready = 1;
      @(posedge clk); #2;
    end
  endtask

  // Traza sin pausas: comprueba los estados mediante sus puertos,
  // la orden pendiente y packet_done coincidente con cmd_ready.
  task check_continuous_trace;
    integer k;
    begin
      @(negedge clk);
      cmd_valid = 1; cmd_wc = 1; cmd_vc = 0; cmd_dt = 6'h39;
      payload_valid = 1; payload_data = 8'h9e; tx_byte_ready = 1;
      @(posedge clk); #2;
      if (!tx_byte_valid || payload_ready) $fatal(1, "Entrada a SEND_HEADER");
      @(negedge clk);
      cmd_wc = 0; cmd_vc = 2; cmd_dt = 6'h3e;
      for (k=0; k<4; k=k+1) begin
        @(posedge clk); #2;
        if (k<3 && !tx_byte_valid) $fatal(1, "Cabecera interrumpida");
      end
      if (tx_byte_valid || payload_ready) $fatal(1, "CHECK tras cabecera");
      @(posedge clk); #2;
      if (!payload_ready || tx_byte_valid) $fatal(1, "WAIT_PAYLOAD");
      @(posedge clk); #2;
      if (payload_ready || !tx_byte_valid) $fatal(1, "SEND_PAYLOAD");
      @(posedge clk); #2;
      if (tx_byte_valid || payload_ready) $fatal(1, "CHECK tras carga útil");
      @(posedge clk); #2;
      if (!tx_byte_valid || tx_byte_last) $fatal(1, "CRC bajo");
      @(posedge clk); #2;
      if (!tx_byte_valid || !tx_byte_last) $fatal(1, "CRC alto");
      @(posedge clk); #2;
      if (!packet_done || !cmd_ready || busy) $fatal(1, "Fin de paquete");
      @(posedge clk); #2;
      if (packet_done || cmd_ready || !busy || !tx_byte_valid)
        $fatal(1, "Aceptación de orden pendiente");
      reset_block;
    end
  endtask

  integer i, j;
  reg [15:0] c;
  initial begin
    // Vectores CRC fijos y contraste con modelo de dirección opuesta.
    probe_crc = 16'hffff; probe_data = 0; #1;
    if (probe_result !== 16'h0f87) $fatal(1, "Vector CRC 00");
    c = 16'hffff;
    for (i = 0; i < 9; i = i+1) begin
      probe_crc = c; probe_data = 8'h31 + i; #1; c = probe_result;
    end
    if (c !== 16'h6f91) $fatal(1, "CRC de 123456789");
    for (i = 0; i < 65536; i = i+1) begin
      probe_crc = i; probe_data = (i ^ (i >> 8)) & 255; #1;
      if (probe_result !== reflect16(crc_msb_update(reflect16(probe_crc), probe_data)))
        $fatal(1, "CRC combinacional incorrecto");
    end
    for (i = 0; i < 24; i=i+1) begin
      probe_header = 24'd1 << i; #1;
      if (probe_ecc !== reference_ecc(probe_header)) $fatal(1, "Síndrome ECC");
    end
    reset_block;
    run_packet(0, 0, 6'h39, 1, -1, -1);
    run_packet(1, 1, 6'h39, 1, -1, -1);
    run_packet(2, 2, 6'h39, 0, -1, -1);
    run_packet(9, 3, 6'h39, 1, -1, -1);
    run_packet(255, 0, 6'h39, 1, -1, -1);
    run_packet(256, 1, 6'h39, 0, -1, -1);
    run_packet(257, 2, 6'h39, 1, -1, -1);
    run_packet(2160, 0, 6'h3e, 1, -1, -1);
    run_packet(65535, 3, 6'h3e, 0, -1, -1);
    for (i=0; i<4; i=i+1)
      for (j=0; j<64; j=j+1) run_packet((i+j)%13, i, j, 1, -1, -1);
    for (i=1; i<=24; i=i+1) begin
      run_packet(3, 0, 6'h39, 0, i, -1);
      run_packet(1, 1, 6'h39, 0, -1, -1);
    end
    for (i=0; i<9; i=i+1) begin
      run_packet(3, 0, 6'h39, 1, -1, i);
      run_packet(0, 2, 6'h39, 0, -1, -1);
    end
    check_continuous_trace;
    reset_block;
    if (accepted != completed + aborted) $fatal(1, "Balance de operaciones");
    $display("PASS: %0d completados, %0d abortados; CRC, ECC, VC/DT, WC=0..65535, pausas y reset", completed, aborted);
    $finish;
  end
  initial begin
    #100000000; $fatal(1, "Timeout global");
  end
endmodule
