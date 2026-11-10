`timescale 1ns / 1ps

// Arnes de simulacion: un descriptor RGB888 por linea, sin planificador RTL.
module test_pattern_link_TB;
  localparam WIDTH = 720, HEIGHT = 2, WC = 3*WIDTH;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 1, start = 0, cmd_valid = 0, out_ready = 0;
  wire start_ready, payload_valid, payload_ready, line_last, frame_last;
  wire pattern_busy, frame_done, cmd_ready, out_valid, out_last, packet_busy, packet_done;
  wire [7:0] payload, out_data;
  dsi_test_pattern #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) source (
      .clk(clk), .rst(rst), .start_valid(start), .start_ready(start_ready),
      .tx_byte_data(payload), .tx_byte_valid(payload_valid), .tx_byte_ready(payload_ready),
      .tx_line_last(line_last), .tx_frame_last(frame_last),
      .busy(pattern_busy), .frame_done(frame_done)
  );
  dsi_long_packet_tx packet (
      .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .cmd_vc(2'd2),
      .cmd_dt(6'h3e), .cmd_wc(16'd2160), .cmd_ready(cmd_ready),
      .payload_data(payload), .payload_valid(payload_valid), .payload_ready(payload_ready),
      .tx_byte_data(out_data), .tx_byte_valid(out_valid), .tx_byte_last(out_last),
      .tx_byte_ready(out_ready), .busy(packet_busy), .packet_done(packet_done)
  );

  function [7:0] reference_byte;
    input integer n;
    reg [23:0] color;
    begin
      case ((n / 3) * 8 / WIDTH)
        0: color = 24'hffffff; 1: color = 24'hffff00;
        2: color = 24'h00ffff; 3: color = 24'h00ff00;
        4: color = 24'hff00ff; 5: color = 24'hff0000;
        6: color = 24'h0000ff; default: color = 24'h000000;
      endcase
      reference_byte = color >> (16 - 8*(n % 3));
    end
  endfunction

  // Oraculo ECC por columnas de sindrome y CRC en direccion MSB (1021),
  // independiente de las ecuaciones XOR y del CRC reflejado del preparador.
  function [7:0] reference_ecc;
    input [23:0] header;
    integer b;
    reg [7:0] syndrome;
    begin
      reference_ecc = 0;
      for (b = 0; b < 24; b = b + 1) begin
        case (b)
          0: syndrome=8'h07; 1: syndrome=8'h0b; 2: syndrome=8'h0d; 3: syndrome=8'h0e;
          4: syndrome=8'h13; 5: syndrome=8'h15; 6: syndrome=8'h16; 7: syndrome=8'h19;
          8: syndrome=8'h1a; 9: syndrome=8'h1c; 10: syndrome=8'h23; 11: syndrome=8'h25;
          12: syndrome=8'h26; 13: syndrome=8'h29; 14: syndrome=8'h2a; 15: syndrome=8'h2c;
          16: syndrome=8'h31; 17: syndrome=8'h32; 18: syndrome=8'h34; 19: syndrome=8'h38;
          20: syndrome=8'h1f; 21: syndrome=8'h2f; 22: syndrome=8'h37; default: syndrome=8'h3b;
        endcase
        if (header[b]) reference_ecc = reference_ecc ^ syndrome;
      end
    end
  endfunction
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
    input [15:0] value;
    integer b;
    begin
      for (b = 0; b < 16; b = b + 1) reflect16[b] = value[15-b];
    end
  endfunction

  localparam [23:0] HEADER = {16'd2160, 2'd2, 6'h3e};
  integer received = 0, output_index = 0, packets = 0, frames = 0, source_index = 0;
  reg expected_packet_done = 0, expected_frame_done = 0, active = 0;
  reg [15:0] crc = 16'hffff, reflected_crc;
  reg [31:0] header;
  reg [7:0] expected_byte;
  reg stalled = 0;
  reg [8:0] held;
  always @(posedge clk) begin
    if (!rst) begin
      expected_packet_done = 0; expected_frame_done = 0;
      if (start && start_ready) source_index = 0;
      if (cmd_valid && cmd_ready) begin
        if (active) $fatal(1, "Descriptor durante paquete activo");
        received = 0; output_index = 0; crc = 16'hffff;
        header = {reference_ecc(HEADER), HEADER}; active = 1;
      end
      if (payload_valid && payload_ready) begin
        if (!active || received >= WC || payload !== reference_byte(received) ||
            line_last !== (received == WC-1) ||
            frame_last !== (source_index == WC*HEIGHT-1))
          $fatal(1, "Payload/marcas no coinciden con descriptor de linea");
        received = received + 1; source_index = source_index + 1;
        if (frame_last) begin expected_frame_done = 1; frames = frames + 1; end
      end
      if (stalled && (!out_valid || {out_data, out_last} !== held))
        $fatal(1, "Paquete inestable con backpressure");
      if (out_valid) begin
        if (!active) $fatal(1, "Salida sin descriptor");
        reflected_crc = reflect16(crc);
        if (output_index < 4) expected_byte = header[8*output_index +: 8];
        else if (output_index < WC+4) begin
          if (output_index-4 >= received) $fatal(1, "Salida adelanta payload");
          expected_byte = reference_byte(output_index-4);
        end else if (output_index == WC+4) expected_byte = reflected_crc[7:0];
        else if (output_index == WC+5) expected_byte = reflected_crc[15:8];
        else $fatal(1, "Byte extra en paquete");
        if (out_data !== expected_byte || out_last !== (output_index == WC+5))
          $fatal(1, "Paquete %0d: byte %0d incorrecto %02h != %02h",
                 packets, output_index, out_data, expected_byte);
        if (out_ready) begin
          if (output_index >= 4 && output_index < WC+4)
            crc = crc_msb_update(crc, expected_byte);
          if (out_last) begin
            if (received != WC) $fatal(1, "WC incorrecto");
            active = 0; expected_packet_done = 1; packets = packets + 1;
          end
          output_index = output_index + 1;
        end
      end
      stalled = out_valid && !out_ready; held = {out_data, out_last};
      #1;
      if (packet_done !== expected_packet_done || frame_done !== expected_frame_done)
        $fatal(1, "Eventos de fin incorrectos");
    end
  end

  integer tick = 0;
  always @(negedge clk) begin
    tick = tick + 1;
    out_ready = tick % 13 > 3;
  end
  integer f, row;
  initial begin
    repeat (2) @(negedge clk);
    rst = 0;
    for (f = 0; f < 2; f = f + 1) begin
      start = 1;
      @(negedge clk); start = 0;
      for (row = 0; row < HEIGHT; row = row + 1) begin
        // Pausa explicita entre lineas; el preparador regula payload_ready.
        repeat (7) @(negedge clk);
        cmd_valid = 1;
        @(negedge clk); cmd_valid = 0;
        wait (packet_done);
        @(negedge clk);
      end
    end
    repeat (4) @(negedge clk);
    if (packets != 4 || frames != 2 || pattern_busy || packet_busy)
      $fatal(1, "Numero incorrecto de cuadros/paquetes");
    $display("PASS enlace: 2 cuadros 720x2, 4 paquetes, 8640 bytes RGB, cabeceras/ECC/CRC y pausas");
    $finish;
  end
  initial begin
    #2000000;
    $fatal(1, "Timeout enlace");
  end
endmodule
