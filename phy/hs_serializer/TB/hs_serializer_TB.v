`timescale 1ps / 1ps

module hs_serializer_TB;
  localparam integer UI = 2273;
  localparam integer HS_PERIOD = 2 * UI, BYTE_PERIOD = 8 * UI;
  localparam integer CRC_SLOT = 1083;
  localparam [1:0] OFF = 2'b00, ZERO = 2'b01, WORD = 2'b10, TRAIL = 2'b11;

  reg CLK_BYTE = 0, CLK_HS = 0, CLOCKS_RUN = 1;
  reg RST_BYTE = 0, ISO = 0;
  reg [1:0] SER_MODE = OFF;
  reg [15:0] PHY_WORD = 0;
  wire HS_D0, HS_D1;
  integer clock_tick = 0;
  time first_fast_rise;

  hs_serializer d0 (CLK_BYTE, CLK_HS, RST_BYTE, ISO, SER_MODE, PHY_WORD[7:0], HS_D0);
  hs_serializer d1 (CLK_BYTE, CLK_HS, RST_BYTE, ISO, SER_MODE, PHY_WORD[15:8], HS_D1);
`ifdef GOWIN_VENDOR_SIM
  GSR GSR (.GSRI(1'b1));  // Referencia jerárquica de prim_sim, aun con GSREN desactivado.
`endif

  // Cada flanco de CLK_BYTE coincide con una subida de FCLK.
  always #UI begin
    if (CLOCKS_RUN) begin
      CLK_HS = !CLK_HS;
      if (clock_tick % 4 == 0) CLK_BYTE = !CLK_BYTE;
      clock_tick = clock_tick + 1;
    end
  end

  function automatic [15:0] packet_word(input integer index, input bit swap_crc);
    case (index)
      0: packet_word = 16'h703E;
      1: packet_word = 16'h1308;
      2: packet_word = 16'h0000;
      3: packet_word = 16'hFFFF;
      4: packet_word = 16'hB8B8;
      // Patrones de CRC inyectados: prueban el transporte, no el cálculo.
      5, 1082: packet_word = swap_crc ? 16'hEE7E : 16'h7EEE;
      default: packet_word = {8'(index * 29 + 13), 8'(index * 97 + 43)};
    endcase
  endfunction

  function automatic time first_bit(input time captured);
    time earliest, phase_anchor;
    begin
      // Con flancos coincidentes, la transferencia observa la carga
      // anterior; la primera salida posible es PCLK + 5 periodos rápidos.
      earliest = captured + BYTE_PERIOD / 2 + 5 * HS_PERIOD;
      phase_anchor = first_fast_rise + 3 * HS_PERIOD;
      first_bit = earliest + (BYTE_PERIOD - (earliest - phase_anchor) % BYTE_PERIOD) % BYTE_PERIOD;
    end
  endfunction

  task automatic expect_zero;
    if ({HS_D1, HS_D0} !== 2'b00)
      $fatal(1, "Quedó carga vieja o indefinida en Q0: %b%b", HS_D1, HS_D0);
  endtask

  task automatic release_abort(input integer phase_shift);
    SER_MODE = OFF;
    PHY_WORD = 16'h956A;
    CLOCKS_RUN = 1;
    repeat (2) @(negedge CLK_BYTE);
    @(posedge CLK_BYTE);
    repeat (phase_shift) @(posedge CLK_HS);
    #1;
    expect_zero();
    RST_BYTE = 0;
    ISO = 0;
    @(posedge CLK_HS);
    first_fast_rise = $time;
    #1;
    repeat (4 * 8) begin
      expect_zero();
      #UI;
    end
  endtask

  task automatic check_stream(input time start, input bit swap_crc, input integer trail_slots);
    integer slot, bit_index;
    reg [7:0] received_d0, received_d1;
    reg [15:0] expected, crc;
    begin
      crc = packet_word(1082, swap_crc);
      // Incluye el último ZERO y dos OFF. No se busca SoT por contenido.
      #(first_bit(start) - BYTE_PERIOD - $time + 1);
      for (slot = -1; slot <= CRC_SLOT + trail_slots + 2; slot = slot + 1) begin
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
          if (CLK_HS !== !bit_index[0])
            $fatal(1, "Fase DDR incorrecta en slot %0d bit %0d", slot, bit_index);
          received_d0[bit_index] = HS_D0;
          received_d1[bit_index] = HS_D1;
          #UI;
        end
        if (slot == 0) expected = 16'hB8B8;
        else if (slot >= 1 && slot <= CRC_SLOT) expected = packet_word(slot - 1, swap_crc);
        else if (slot > CRC_SLOT && slot <= CRC_SLOT + trail_slots)
          expected = {{8{~crc[15]}}, {8{~crc[7]}}};
        else expected = 0;

        if ({received_d1, received_d0} !== expected)
          $fatal(1, "Slot %0d: se reconstruyó D0/D1=%02h/%02h, se esperaba %02h/%02h",
                 slot, received_d0, received_d1, expected[7:0], expected[15:8]);
      end
      $display("PASS D0/D1: SoT + 1083 palabras, CRC %02h/%02h, %0d slots TRAIL; δ=%0d ps",
               crc[7:0], crc[15:8], trail_slots, first_bit(start) - start);
    end
  endtask

  task automatic burst(input bit swap_crc, input integer trail_slots);
    time start;
    integer index;
    begin
      @(posedge CLK_BYTE); SER_MODE <= ZERO;
      repeat (2) @(negedge CLK_BYTE);
      PHY_WORD <= 16'hB8B8;  // ↓−1: el serializador todavía está en ZERO.
      @(posedge CLK_BYTE); SER_MODE <= WORD;
      @(negedge CLK_BYTE); start = $time; PHY_WORD <= packet_word(0, swap_crc);
      fork
        check_stream(start, swap_crc, trail_slots);
        begin
          for (index = 1; index <= 1082; index = index + 1) begin
            @(negedge CLK_BYTE); PHY_WORD <= packet_word(index, swap_crc);
          end
          // HS_REQ baja en el ↑ intermedio. PHY_CTRL conserva WORD en ↓1083.
          @(negedge CLK_BYTE); PHY_WORD <= 16'h0000;
          @(posedge CLK_BYTE); SER_MODE <= TRAIL;
          @(negedge CLK_BYTE); PHY_WORD <= 16'hA669;  // Veneno: TRAIL ignora HS_BYTE.
          repeat (trail_slots - 1) @(negedge CLK_BYTE);
          @(posedge CLK_BYTE); SER_MODE <= OFF;
        end
      join
    end
  endtask

  task automatic abort_in_word(input bit with_iso);
    time capture;
    begin
      @(negedge CLK_BYTE); PHY_WORD <= 16'hFFFF;
      @(posedge CLK_BYTE); SER_MODE <= WORD;
      @(negedge CLK_BYTE); capture = $time;
      // Corta a mitad de un byte con ambos carriles en uno y datos en cola.
      #(first_bit(capture) + 3 * UI + UI / 2 - $time);
      if ({HS_D1, HS_D0} !== 2'b11) $fatal(1, "No hay WORD HS activo para abortar");
      CLOCKS_RUN = 0;
      if (with_iso) ISO = 1;
      else RST_BYTE = 1;
      #1;
      expect_zero();
      if ({d0.LAST_BIT, d0.SLOT_Q, d1.LAST_BIT, d1.SLOT_Q} !== 18'b0)
        $fatal(1, "El aborto no borró los registros de slot sin reloj");
      #(2 * BYTE_PERIOD);
      expect_zero();
      $display("PASS aborto por %0s sin flancos", with_iso ? "ISO" : "RST_BYTE");
    end
  endtask

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("hs_serializer_TB.fst");
      $dumpvars(1, hs_serializer_TB, d0, d1);
    end
    #1; RST_BYTE = 1;
    release_abort(0);
    burst(0, 1);
    burst(1, 4);  // Cierre normal seguido de otra ráfaga sin reset.
    abort_in_word(1);
    release_abort(1);
    burst(0, 4);
    abort_in_word(0);
    release_abort(2);
    burst(1, 1);
    abort_in_word(1);
    release_abort(3);
    burst(0, 4);
    $finish;
  end

  initial begin
    #(8000 * BYTE_PERIOD);
    $fatal(1, "El banco no terminó");
  end
endmodule
