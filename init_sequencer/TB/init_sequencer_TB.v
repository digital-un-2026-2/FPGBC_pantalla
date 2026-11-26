`timescale 1ns / 1ps

module init_sequencer_TB #(
    parameter integer PROFILE = 0
);
  localparam integer P = (PROFILE == 0) ? 1 : 5;
  localparam integer LP_DIV = (PROFILE == 0) ? 1 : 3;
  localparam integer HALF_NS = 500_000 / P;
  localparam integer PACKETS = 18, BYTE_COUNT = 204, END_ADDR = 222;
  localparam [10:0] END_WORD = 11'h400;

  // Oráculo de Docs/init_mem_map.csv: bytes DSI por paquete, sin selector.
  // El banco no reutiliza el generador de la ROM ni necesita archivos al correr.
  localparam [8*BYTE_COUNT-1:0] EXPECTED_BYTES = {
      64'h29_02_00_00_b0_00_d6_ca,
      96'h29_06_00_23_e4_00_00_00_00_08_87_16,
      80'h29_04_00_3f_d0_45_45_71_42_9e,
      64'h09_02_00_15_00_00_b8_f0,
      32'h05_11_45_04,
      72'h29_03_00_1a_d0_52_4a_25_bb,
      152'h29_0d_00_00_b9_02_00_76_00_ba_bb_bf_cc_e3_46_81_31_d0_e5,
      144'h29_0c_00_1a_bd_ff_fe_fe_fe_fe_fe_fe_80_20_00_00_2a_e3,
      120'h29_09_00_23_be_ff_0f_00_18_04_04_00_5d_e7_c4,
      64'h29_02_00_00_b0_03_4d_f8,
      64'h09_02_00_15_00_00_b8_f0,
      32'h05_29_03_1f,
      64'h29_02_00_00_b0_00_d6_ca,
      120'h29_09_00_23_be_ff_0f_00_18_04_04_00_5d_e7_c4,
      176'h29_10_00_3a_b7_18_00_18_18_0c_09_ac_09_5c_09_0c_09_00_10_00_44_32,
      160'h29_0e_00_06_b8_f8_da_6d_fb_ff_ff_4f_1f_7f_9f_bf_df_ff_ab_18,
      64'h29_02_00_00_bb_2f_8b_f7,
      64'h29_02_00_00_b0_03_4d_f8
  };
  localparam [5*PACKETS-1:0] EXPECTED_LENGTHS = {
      5'd8, 5'd12, 5'd10, 5'd8, 5'd4, 5'd9, 5'd19, 5'd18, 5'd15,
      5'd8, 5'd8, 5'd4, 5'd8, 5'd15, 5'd22, 5'd20, 5'd8, 5'd8
  };

  reg CLK_BYTE = 0;
  always #(HALF_NS) CLK_BYTE = !CLK_BYTE;

  reg RST_BYTE = 0;
  reg INIT_READY = 0, INIT_NEXT = 0, INIT_DONE_TX = 0;
  reg LP_START = 0, LP_DONE = 0;  // Señales internas de los vecinos modelados.
  wire INIT_REQ, INIT_LAST, INIT_DONE;
  wire [7:0] INIT_BYTE;
  integer packets_accepted, bytes_loaded, waits_checked;

  init_sequencer #(.CLK_BYTE_HZ(1000 * P)) dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_READY(INIT_READY), .INIT_NEXT(INIT_NEXT), .INIT_DONE_TX(INIT_DONE_TX),
      .INIT_REQ(INIT_REQ), .INIT_BYTE(INIT_BYTE), .INIT_LAST(INIT_LAST), .INIT_DONE(INIT_DONE)
  );

  function automatic [10:0] byte_word(input integer index);
    byte_word = {3'b000, EXPECTED_BYTES[8*(BYTE_COUNT-index)-1 -: 8]};
  endfunction

  function automatic [10:0] wait_word(input integer packet);
    case (packet)
      5, 10: wait_word = 11'h341;
      18:    wait_word = 11'h307;
      default: wait_word = 11'h309;
    endcase
  endfunction

  task automatic expect_entry(input integer addr, input [10:0] word);
    if (dut.ADDR !== addr[7:0] || {dut.OP, INIT_LAST, INIT_BYTE} !== word ||
        dut.DELAY_MS !== word[7:0])
      $fatal(1, "[%0t] ROM: esperaba dir. %0d=%03h, leí dir. %0d=%03h, DELAY_MS=%02h",
             $time, addr, word, dut.ADDR, {dut.OP, INIT_LAST, INIT_BYTE}, dut.DELAY_MS);
  endtask

  task automatic expect_controls(input bit req, input bit done);
    if ({INIT_REQ, INIT_DONE} !== {req, done})
      $fatal(1, "[%0t] dir. %0d: REQ/DONE=%b/%b, esperaba %b/%b",
             $time, dut.ADDR, INIT_REQ, INIT_DONE, req, done);
  endtask

  task automatic expect_tx(input integer addr, input [10:0] word);
    expect_entry(addr, word);
    expect_controls(0, 0);
    if ({dut.START_DELAY, dut.COUNT_DELAY} !== 2'b00)
      $fatal(1, "[%0t] D_COUNT se habilitó antes de recibir INIT_DONE_TX", $time);
  endtask

  // Empieza después de un ↑ y termina después de otro ↑.
  task automatic hold_tx(input integer cycles, input integer addr, input [10:0] word);
    repeat (cycles) begin
      @(negedge CLK_BYTE); #1;
      expect_tx(addr, word);
      @(posedge CLK_BYTE); #1;
      expect_tx(addr, word);
    end
  endtask

  task automatic reset_and_read;
    RST_BYTE = 1;
    {INIT_READY, INIT_NEXT, INIT_DONE_TX, LP_START, LP_DONE} = 0;
    {packets_accepted, bytes_loaded, waits_checked} = 0;
    #1;
    expect_controls(0, 0);
    if ({dut.INC_A, dut.START_DELAY, dut.COUNT_DELAY} !== 3'b000)
      $fatal(1, "Reset no enmascaró una orden del CTRL");
    // También cubre un ↓ con una orden pendiente antes de reiniciar CTRL en ↑.
    @(negedge CLK_BYTE); #1;
    expect_entry(0, byte_word(0));
    expect_controls(0, 0);
    if (dut.d_count.PHASE !== 0 || dut.d_count.MS_LEFT !== 8'd0)
      $fatal(1, "D_COUNT no se limpió en el primer ↓ de reset");
    @(posedge CLK_BYTE); #1;
    if (dut.ctrl.ADV_BYTE !== 1'b0) $fatal(1, "Orden pendiente tras el ↑ de reset");
    @(negedge CLK_BYTE); #1;
    RST_BYTE = 0;
    expect_controls(0, 0);
    @(posedge CLK_BYTE); #1;
    expect_entry(0, byte_word(0));
    expect_controls(1, 0);
  endtask

  // LINK_FSM admite en ↑; LP_TX lee LP_START en el ↑ posterior.
  // Los primeros 20*LP_DIV ciclos publican entrada y 87, sin INIT_NEXT.
  task automatic admit_and_enter(input integer ready_stall);
    integer addr;
    reg [10:0] word;
    addr = bytes_loaded + waits_checked;
    word = byte_word(bytes_loaded);
    if (ready_stall != 0) INIT_READY = 0;
    repeat (ready_stall) begin
      @(negedge CLK_BYTE); #1;
      expect_entry(addr, word);
      expect_controls(1, 0);
      @(posedge CLK_BYTE); #1;
      expect_entry(addr, word);
      expect_controls(1, 0);
    end

    @(negedge CLK_BYTE); #1;
    INIT_READY = 1;
    @(posedge CLK_BYTE);
    expect_entry(addr, word);
    expect_controls(1, 0);
    LP_START <= 1;
    INIT_READY <= 0;
    packets_accepted = packets_accepted + 1;
    #1;
    expect_tx(addr, word);

    @(posedge CLK_BYTE);
    if (LP_START !== 1'b1) $fatal(1, "Faltó LP_START tras la admisión modelada");
    LP_START <= 0;
    #1;
    expect_tx(addr, word);
    hold_tx(20*LP_DIV, addr, word);
  endtask

  // LP_TX mira LAST en el ↑ anterior a la carga. Solo consume BYTE en ↓,
  // y publica INIT_NEXT de ↓ a ↓. Devuelve el control en el ↑ intermedio.
  task automatic load_byte;
    integer addr;
    reg [10:0] word;
    addr = bytes_loaded + waits_checked;
    word = byte_word(bytes_loaded);
    expect_tx(addr, word);
    @(negedge CLK_BYTE);
    expect_tx(addr, word);
    INIT_NEXT <= 1;
    bytes_loaded = bytes_loaded + 1;
    #1;
    expect_tx(addr, word);
    if (dut.INC_A !== 1'b0) $fatal(1, "CTRL avanzó sin leer INIT_NEXT en ↑");
    @(posedge CLK_BYTE); #1;
    expect_tx(addr, word);
    if (dut.INC_A !== 1'b1) $fatal(1, "CTRL no armó el avance de INIT_NEXT en ↑");
  endtask

  // Al bajar el pulso, el nuevo dato tiene que salir en ese ↓. La
  // siguiente frontera se decide 16*LP_DIV ciclos después de la anterior.
  task automatic advance_byte(input integer addr, input [10:0] word);
    @(negedge CLK_BYTE);
    INIT_NEXT <= 0;
    #1;
    expect_tx(addr, word);
    @(posedge CLK_BYTE); #1;
    expect_tx(addr, word);
    if (dut.INC_A !== 1'b0) $fatal(1, "Un INIT_NEXT armó más de un avance");
    hold_tx(16*LP_DIV-2, addr, word);
  endtask

  task automatic close_packet(input [10:0] word);
    integer addr;
    addr = bytes_loaded + waits_checked;
    expect_tx(addr, word);  // ↑ de frontera: ve LAST=1 y no carga ARG.
    hold_tx(2*LP_DIV, addr, word);  // Salida a LP11, sin pulsar INIT_NEXT.
    @(negedge CLK_BYTE);
    LP_DONE <= 1;
    #1;
    expect_tx(addr, word);

    @(posedge CLK_BYTE);
    if (LP_DONE !== 1'b1) $fatal(1, "Faltó LP_DONE modelado");
    INIT_DONE_TX <= 1;  // LINK_FSM entra en LP_ACK: CTRL aún no lo lee.
    #1;
    expect_tx(addr, word);
    @(negedge CLK_BYTE);
    LP_DONE <= 0;
    #1;
    expect_tx(addr, word);
    @(posedge CLK_BYTE);
    INIT_DONE_TX <= 0;  // Se lee el 1 previo en este ↑.
    INIT_READY <= 1;    // LINK_FSM puede quedar listo durante todo el WAIT.
    #1;
    expect_entry(addr, word);
    expect_controls(0, 0);
    if ({dut.START_DELAY, dut.COUNT_DELAY, dut.INC_A} !== 3'b100 ||
        dut.d_count.MS_LEFT !== 8'd0)
      $fatal(1, "CTRL no inició el WAIT solo tras leer el fin del paquete en ↑");
  endtask

  task automatic send_packet(input integer packet);
    integer length, index, next_addr;
    reg [10:0] next_word;
    length = int'(EXPECTED_LENGTHS[5*(PACKETS-packet+1)-1 -: 5]);
    admit_and_enter((packet == 1) ? 4 : ((packet % 3 == 0) ? 2 : 0));
    for (index = 0; index < length; index = index+1) begin
      next_word = (index == length-1) ? wait_word(packet) : byte_word(bytes_loaded+1);
      next_addr = bytes_loaded + waits_checked + 1;
      load_byte();
      advance_byte(next_addr, next_word);
    end
    close_packet(wait_word(packet));
  endtask

  // "cycle" cuenta los ↓ posteriores a ↑ de INIT_DONE_TX. La fase de
  // referencia se deriva del tiempo desde ese ↑, no del estado del DUT.
  task automatic delay_cycle(input integer cycle, input [10:0] word);
    integer addr, ms, remaining;
    bit expired;
    addr = bytes_loaded + waits_checked;
    ms = int'(word[7:0]);
    remaining = ms - cycle/P;
    expired = (cycle == ms*P);

    @(negedge CLK_BYTE);
    expect_entry(addr, word);
    expect_controls(0, 0);
    if (dut.START_DELAY !== (cycle == 1) || dut.d_count.TICK_MS !== (cycle % P == 0) ||
        dut.INC_A !== 1'b0)
      $fatal(1, "[%0t] WAIT %0d ms: carga, tick o avance erróneo en ↓ del ciclo %0d",
             $time, ms, cycle);
    #1;
    expect_entry(addr, word);
    expect_controls(0, 0);
    if (dut.d_count.MS_LEFT !== remaining[7:0] || dut.d_count.PHASE !== (cycle % P))
      $fatal(1, "WAIT %0d ms: contador erróneo en ↓ del ciclo %0d", ms, cycle);

    @(posedge CLK_BYTE);
    if (dut.DONE_DELAY !== expired)
      $fatal(1, "WAIT %0d ms: fin incorrecto en ↑ del ciclo %0d de %0d", ms, cycle, ms*P);
    #1;
    expect_entry(addr, word);
    expect_controls(0, 0);
    if (dut.INC_A !== expired) $fatal(1, "Avance tras WAIT no coincide con DONE_DELAY");
  endtask

  task automatic finish_wait(input integer packet);
    integer ms, cycle, next_addr;
    time ack_time;
    reg [10:0] word, next_word;
    bit final_packet;
    ack_time = $time;
    word = wait_word(packet);
    ms = int'(word[7:0]);
    final_packet = (packet == PACKETS);
    next_word = final_packet ? END_WORD : byte_word(bytes_loaded);
    for (cycle = 1; cycle <= ms*P; cycle = cycle+1) delay_cycle(cycle, word);
    if ($time - ack_time != ms * 1_000_000)
      $fatal(1, "WAIT %0d ms: duración incorrecta con el reloj del banco", ms);

    @(negedge CLK_BYTE); #1;
    waits_checked = waits_checked + 1;
    next_addr = bytes_loaded + waits_checked;
    expect_entry(next_addr, next_word);
    expect_controls(0, 0);  // La nueva entrada está presente, aún no leída por CTRL.
    @(posedge CLK_BYTE); #1;
    expect_entry(next_addr, next_word);
    expect_controls(!final_packet, final_packet);
  endtask

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("init_sequencer_TB.fst");
      $dumpvars(1, init_sequencer_TB);
      $dumpvars(1, dut.ctrl, dut.d_count);
    end
    repeat (25_000) @(posedge CLK_BYTE);
    $fatal(1, "Tiempo de prueba agotado");
  end

  initial begin : scenario
    integer packet, cycle;
    #1;  // El primer reset es una afirmación antes del primer ↑.
    reset_and_read();

    admit_and_enter(4);
    load_byte();
    advance_byte(1, byte_word(1));
    load_byte();       // INIT_NEXT leído, el segundo avance todavía no ocurrió.
    reset_and_read();  // Abortamos con ADDR=1 e INC_A pendiente.

    send_packet(1);
    for (cycle = 1; cycle <= P+1; cycle = cycle+1) delay_cycle(cycle, wait_word(1));
    reset_and_read();  // Abortamos con la pausa de 9 ms aún en curso.

    for (packet = 1; packet <= PACKETS; packet = packet+1) begin
      send_packet(packet);
      finish_wait(packet);
    end
    if (packets_accepted != PACKETS || bytes_loaded != BYTE_COUNT || waits_checked != PACKETS)
      $fatal(1, "Totales incorrectos: %0d paquetes, %0d bytes, %0d pausas",
             packets_accepted, bytes_loaded, waits_checked);

    repeat (2*P+2) begin
      @(negedge CLK_BYTE); #1;
      expect_entry(END_ADDR, END_WORD);
      expect_controls(0, 1);
      @(posedge CLK_BYTE); #1;
      expect_entry(END_ADDR, END_WORD);
      expect_controls(0, 1);
    end
    reset_and_read();  // También se borra INIT_DONE, que es un nivel.

    $display("OK P=%0d LP_DIV=%0d: 18 paquetes, 204 bytes DSI, 18 WAIT exactos y END",
             P, LP_DIV);
    $display("  INIT_READY tardío, reset con avance pendiente, durante WAIT y después de END");
    $finish;
  end
endmodule
