`timescale 1ns / 1fs

`ifdef FPGBC_WHITE
  `define TB_SEQ board.seq
  `define TB_VIDEO board.video
  `define TB_PHY board.link
  `define TB_SUPERVISOR board.supervisor
`else
  `define TB_SEQ seq
  `define TB_VIDEO video
  `define TB_PHY phy
  `define TB_SUPERVISOR supervisor
`endif

module mipi_tx_TB #(
    parameter integer PROFILE = 0,
    parameter integer INIT_HZ = 55_000_000,
    parameter DELAY = 1'b0
`ifdef PHY_SUPERVISED
    , parameter integer OSC_HZ = 25_000_000
`endif
`ifdef FPGBC_WHITE
    , parameter bit WHITE = 1
`endif
);
`ifdef PHY_GOWIN
  localparam integer P = INIT_HZ / 1000;
  localparam realtime BYTE_PERIOD = 1000.0 / 55.0;
  localparam integer LP_DIV = 6, T_LPX = 4, T_PREP = 3, T_ZERO = 7,
                     T_TRAIL = 4, C_LINE = 1166, T_CLK_START = 27;
  reg CLK_REF = 0;
  wire CLK_BYTE;
`ifdef PHY_SUPERVISED
  reg REF_ENABLED = 0;
  wire RESET, RST_BYTE, LOCK_RAW;
  always #12.5 if (REF_ENABLED) CLK_REF = !CLK_REF;
`ifndef FPGBC_WHITE
  reg RST_SUP = 0, RST_LINK = 0;
  phy_supervisor supervisor (
      .CLK_REF(CLK_REF), .CLK_BYTE(CLK_BYTE), .LOCK_RAW(LOCK_RAW),
      .RST_SUP(RST_SUP), .RST_LINK(RST_LINK), .RESET(RESET), .RST_BYTE(RST_BYTE)
  );
  defparam supervisor.oscillator.TEST_HZ = OSC_HZ;
`endif
`else
  reg RESET = 1;
  always #12.5 CLK_REF = !CLK_REF;
`endif
`else
  localparam integer P = (PROFILE == 0) ? 1 : 5;  // Ciclos de CLK_BYTE por ms simulado.
  localparam integer HALF_NS = 500_000 / P;
  localparam realtime BYTE_PERIOD = 2 * HALF_NS;
  localparam integer LP_DIV = (PROFILE == 0) ? 1 : 3;
  localparam integer T_LPX = (PROFILE == 0) ? 1 : 5;
  localparam integer T_PREP = (PROFILE == 0) ? 1 : 3;
  localparam integer T_ZERO = (PROFILE == 0) ? 1 : 7;
  localparam integer T_TRAIL = (PROFILE == 0) ? 1 : 4;
  localparam integer C_LINE = (PROFILE == 0) ? 1091 : 1166;
  localparam integer T_CLK_START = 0;
  reg CLK_BYTE = 0;
  always #(HALF_NS) CLK_BYTE = !CLK_BYTE;
`endif

  localparam integer PACKETS = 18, DSI_BYTES = 204, ROM_WORDS = 223;
  localparam [2:0] ROM_BYTE = 3'b000, ROM_WAIT = 3'b011;  // {OP, LAST}.
  localparam [10:0] ROM_END = 11'h400;
  localparam integer PIX_BYTES = 2160, PIX_WORDS = PIX_BYTES / 2;
  localparam integer CRC_TAKE = 1 + 2 + PIX_WORDS;  // Índice de consumo: SoT, W0, W1, PIX, CRC.
  localparam integer HS_WORDS = CRC_TAKE + 1, ABORT_READS = 17;

`ifndef PHY_SUPERVISED
  reg RST_BYTE = 1;
`endif
  integer cycle = 0;
  always @(negedge CLK_BYTE) cycle <= cycle + 1;

  wire INIT_REQ, INIT_READY, INIT_LAST, INIT_NEXT, INIT_DONE_TX, INIT_DONE;
  wire [7:0] INIT_BYTE;
  wire VID_REQ, VID_LINE_RDY, VID_RD;
  wire [15:0] VID_WORD, source_word;
  wire HS_REQ, CLK_REQ, READY, LOCK;
  wire [2:0] LP_P, LP_N;
  wire [7:0] HS_BYTE0, HS_BYTE1;

  wire [1:0] D0_LP, D1_LP, CLK_LP;
  wire hs_activity;
  wire [15:0] registered_word = {HS_BYTE1, HS_BYTE0};

  // Referencia para el comparador, jamás alimenta el RTL. Se lee el HEX
  // original; el secuenciador usa la tabla generada por su objetivo rom.
  reg [10:0] reference_rom [0:ROM_WORDS-1];
  integer init_next_count;
  reg vid_rd_sample;

`ifdef FPGBC_WHITE
  `include "white_target_link.vh"
`else
  init_sequencer #(.CLK_BYTE_HZ(1000 * P)) seq (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_REQ(INIT_REQ), .INIT_READY(INIT_READY), .INIT_DONE_TX(INIT_DONE_TX),
      .INIT_BYTE(INIT_BYTE), .INIT_LAST(INIT_LAST), .INIT_NEXT(INIT_NEXT), .INIT_DONE(INIT_DONE)
  );

  video_source video (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .INIT_DONE(INIT_DONE),
      .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY), .VID_WORD(source_word), .VID_RD(VID_RD)
  );

  mipi_tx #(
      .LP_DIV(LP_DIV), .T_LPX(T_LPX), .T_PREP(T_PREP), .T_ZERO(T_ZERO),
      .T_TRAIL(T_TRAIL), .C_LINE(C_LINE), .T_CLK_START(T_CLK_START)
  ) dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_REQ(INIT_REQ), .INIT_READY(INIT_READY), .INIT_DONE_TX(INIT_DONE_TX),
      .INIT_BYTE(INIT_BYTE), .INIT_LAST(INIT_LAST), .INIT_NEXT(INIT_NEXT),
      .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY), .VID_WORD(VID_WORD), .VID_RD(VID_RD),
      .READY(READY), .LOCK(LOCK), .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ),
      .LP_P(LP_P), .LP_N(LP_N), .HS_BYTE0(HS_BYTE0), .HS_BYTE1(HS_BYTE1)
  );

`ifdef PHY_GOWIN
  wire [1:0] D0_HS, D1_HS, CLK_HS_PAD;
  reg white_line = 0;
  assign VID_WORD = white_line ? 16'hffff : source_word;
  assign hs_activity = {D0_HS, D1_HS, CLK_HS_PAD} !== 6'bzzzzzz;
  phy #(.USE_IODELAY(DELAY), .STATIC_DELAY_TAPS(32)) phy (
      .CLK_REF(CLK_REF), .RESET(RESET), .RST_BYTE(RST_BYTE),
`ifdef PHY_SUPERVISED
      .LOCK_RAW(LOCK_RAW),
`endif
      .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ), .CLK_BYTE(CLK_BYTE), .READY(READY), .LOCK(LOCK),
      .LP_P(LP_P), .LP_N(LP_N), .HS_BYTE0(HS_BYTE0), .HS_BYTE1(HS_BYTE1),
      .LP_D0_P(D0_LP[1]), .LP_D0_N(D0_LP[0]), .LP_D1_P(D1_LP[1]), .LP_D1_N(D1_LP[0]),
      .LP_CLK_P(CLK_LP[1]), .LP_CLK_N(CLK_LP[0]),
      .HS_D0_P(D0_HS[1]), .HS_D0_N(D0_HS[0]), .HS_D1_P(D1_HS[1]), .HS_D1_N(D1_HS[0]),
      .HS_CLK_P(CLK_HS_PAD[1]), .HS_CLK_N(CLK_HS_PAD[0])
  );
`ifdef GOWIN_VENDOR_SIM
  GSR GSR (.GSRI(1'b1));
`endif
`else
  wire phy_take, phy_last, phy_trail;
  wire [15:0] taken_word;
  assign VID_WORD = source_word;
  assign hs_activity = phy_take || phy_trail;
  mipi_tx_phy_model #(.T_ZERO(T_ZERO), .T_TRAIL(T_TRAIL)) phy (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ),
      .LP_P(LP_P), .LP_N(LP_N), .HS_BYTE0(HS_BYTE0), .HS_BYTE1(HS_BYTE1),
      .READY(READY), .LOCK(LOCK), .D0_LP(D0_LP), .D1_LP(D1_LP), .CLK_LP(CLK_LP),
      .TAKE(phy_take), .LAST(phy_last), .TRAIL(phy_trail), .TAKEN_WORD(taken_word)
  );
`endif
`endif

  always @(posedge CLK_BYTE) begin
    if (RST_BYTE) init_next_count <= 0;
    else if (INIT_NEXT !== 1'b0) begin
      if ({INIT_NEXT, INIT_LAST, INIT_DONE} !== 3'b100)
        $fatal(1, "ciclo %0d: INIT_NEXT inválido o fuera de BYTE", cycle);
      init_next_count <= init_next_count + 1;
    end
  end

  // VID_RD se usa en el flanco, no tras el avance del packer. Para los
  // niveles de salida y el consumo del modelo esperamos las actualizaciones.
  task automatic sample_negedge;
    @(negedge CLK_BYTE);
    vid_rd_sample = VID_RD;
    #1;
  endtask

`ifndef PHY_GOWIN
  task automatic reset_link(input bit aborting);
    reg [15:0] before_reset;
    before_reset = registered_word;
    RST_BYTE = 1;
    @(posedge CLK_BYTE); #1;
    if ({INIT_REQ, INIT_DONE_TX, INIT_NEXT, INIT_DONE, VID_REQ, VID_LINE_RDY, HS_REQ, CLK_REQ} !== 0)
      $fatal(1, "ciclo %0d: quedaron peticiones o fines activos en reset", cycle);
    if (aborting && registered_word !== before_reset)
      $fatal(1, "ciclo %0d: PHY_IF cambió su registro antes del ↓ de reset", cycle);
    sample_negedge();
    if ({LP_P, LP_N} !== 6'b111111 || registered_word !== 16'h0000 ||
        {phy_take, phy_last, phy_trail, VID_RD, dut.PK_DONE} !== 5'b00000 ||
        seq.ADDR !== 8'd0 || video.ADDR !== 11'd0 || video.RGB_PHASE !== 2'd0)
      $fatal(1, "ciclo %0d: el reset no descartó datos, consumo o posiciones parciales", cycle);
    RST_BYTE = 0;
  endtask
`endif

  // LP: se decodifican las salidas del PHY (pads en la prueba Gowin).
  task automatic check_lp_idle_lanes;
    if ({D1_LP, CLK_LP} !== 4'b1111)
      $fatal(1, "ciclo %0d: LPDT debe mantener D1 y CLK en LP11", cycle);
    if ({INIT_DONE, VID_REQ, VID_LINE_RDY, vid_rd_sample, VID_RD, HS_REQ, CLK_REQ,
         hs_activity} !== 0 || registered_word !== 16'h0000)
      $fatal(1, "ciclo %0d: actividad de vídeo antes del WAIT final y END", cycle);
  endtask

  task automatic sample_lp;
    sample_negedge();
    check_lp_idle_lanes();
  endtask

  task automatic expect_d0(input [1:0] pn);
    if (D0_LP !== pn)
      $fatal(1, "ciclo %0d: D0 registrado=%b, esperado %b (dir. de init %0d)",
             cycle, D0_LP, pn, `TB_SEQ.ADDR);
  endtask

  // Empieza con el primer ↓ muestreado de una fase y deja muestreado
  // el primer ↓ de la siguiente. Así se comprueba también LP_DIV.
  task automatic take_lp_phase(input [1:0] pn);
    repeat (LP_DIV) begin
      expect_d0(pn);
      sample_lp();
    end
  endtask

  task automatic decode_lp_byte(output reg [7:0] data);
    for (integer b = 0; b < 8; b = b + 1) begin
      case (D0_LP)
        2'b01: data[b] = 0;
        2'b10: data[b] = 1;
        default: $fatal(1, "ciclo %0d: marca LP inválida en bit %0d: %b", cycle, b, D0_LP);
      endcase
      take_lp_phase(data[b] ? 2'b10 : 2'b01);
      take_lp_phase(2'b00);
    end
  endtask

  task automatic expect_rom_entry(input integer addr);
    if (`TB_SEQ.ADDR !== addr[7:0] || {`TB_SEQ.OP, INIT_LAST, INIT_BYTE} !== reference_rom[addr])
      $fatal(1, "ciclo %0d: ROM dir. %0d=%03h; esperada dir. %0d=%03h",
             cycle, `TB_SEQ.ADDR, {`TB_SEQ.OP, INIT_LAST, INIT_BYTE}, addr, reference_rom[addr]);
  endtask

  // Se entra tras el ↑ que presenta INIT_REQ y se sale en LP11,
  // un ↓ antes del ↑ en que el secuenciador lee INIT_DONE_TX.
  task automatic receive_lp_packet(input integer packet, inout integer addr, bytes_seen);
    reg [7:0] data;
    sample_negedge();
    while (packet == 1 && !READY) sample_negedge();
    check_lp_idle_lanes();
    expect_d0(2'b11);
    @(posedge CLK_BYTE);
    if ({INIT_REQ, INIT_READY} !== 2'b11 || reference_rom[addr][10:8] !== ROM_BYTE)
      $fatal(1, "ciclo %0d: paquete %0d sin admisión con primer BYTE", cycle, packet);
    expect_rom_entry(addr);
    #1;
    if ({INIT_REQ, INIT_READY} !== 2'b00)
      $fatal(1, "ciclo %0d: no se cerró la admisión LP tras ↑", cycle);
    repeat (2) begin
      sample_lp();
      expect_d0(2'b11);  // LP_START se lee en el siguiente ↑; LP10 tarda otro ↓ en registrarse.
    end
    sample_lp();
    take_lp_phase(2'b10);
    take_lp_phase(2'b00);
    take_lp_phase(2'b01);
    take_lp_phase(2'b00);
    decode_lp_byte(data);
    if (data !== 8'h87) $fatal(1, "paquete %0d: selector %02h, esperado 87", packet, data);

    while (addr < ROM_WORDS && (reference_rom[addr][10:8] === ROM_BYTE)) begin
      decode_lp_byte(data);
      if (data !== reference_rom[addr][7:0])
        $fatal(1, "paquete %0d, BYTE dir. %0d: D0 reconstruye %02h, esperado %02h",
               packet, addr, data, reference_rom[addr][7:0]);
      addr = addr + 1;
      bytes_seen = bytes_seen + 1;
    end
    // Si el WAIT se hubiera emitido como otro byte, no se vería 10→11 aquí.
    take_lp_phase(2'b10);
    expect_d0(2'b11);
    repeat (LP_DIV) begin
      @(posedge CLK_BYTE);
      if (INIT_DONE_TX !== 1'b0) $fatal(1, "paquete %0d: INIT_DONE_TX adelantado", packet);
      sample_lp();
      expect_d0(2'b11);
    end
    if (init_next_count !== bytes_seen)
      $fatal(1, "paquete %0d: %0d INIT_NEXT para %0d bytes DSI", packet, init_next_count, bytes_seen);
  endtask

  task automatic expect_wait_idle;
    if ({INIT_REQ, INIT_NEXT, INIT_DONE_TX, INIT_DONE} !== 4'b0000)
      $fatal(1, "ciclo %0d: actividad de init durante WAIT o antes de leer el siguiente OP", cycle);
  endtask

  task automatic check_wait(input integer packet, addr);
    integer ms, wait_cycles;
    realtime ack, expected_ns;
    bit final_packet;
    final_packet = packet == PACKETS;
    ms = int'(reference_rom[addr][7:0]);
    wait_cycles = ms * P;
    if (reference_rom[addr][10:8] !== ROM_WAIT ||
        (final_packet ? (ms != 7) : (ms != 9 && ms != 65)))
      $fatal(1, "paquete %0d: esperaba WAIT válido en dir. %0d", packet, addr);

    @(posedge CLK_BYTE);
    ack = $realtime;
    expected_ns = wait_cycles * BYTE_PERIOD;
    if ({INIT_DONE_TX, INIT_REQ, INIT_NEXT, INIT_DONE} !== 4'b1000)
      $fatal(1, "ciclo %0d: falta el fin de paquete %0d antes del WAIT", cycle, packet);
    expect_rom_entry(addr);
    #1;
    if (`TB_SEQ.START_DELAY !== 1'b1)
      $fatal(1, "ciclo %0d: el ↑ de INIT_DONE_TX no armó la carga del WAIT", cycle);
    expect_wait_idle();
    for (integer t = 1; t <= wait_cycles; t = t + 1) begin
      sample_lp();
      expect_d0(2'b11);
      expect_rom_entry(addr);
      expect_wait_idle();
      @(posedge CLK_BYTE);
      if (`TB_SEQ.DONE_DELAY !== (t == wait_cycles))
        $fatal(1, "paquete %0d: fin de WAIT %0d ms incorrecto a %0d/%0d ciclos de INIT_DONE_TX",
               packet, ms, t, wait_cycles);
      if (t == wait_cycles &&
          ($realtime - ack < expected_ns - BYTE_PERIOD || $realtime - ack > expected_ns + BYTE_PERIOD))
        $fatal(1, "paquete %0d: WAIT de %0d ms no coincide con el reloj del banco", packet, ms);
      #1;
      expect_wait_idle();
    end

    sample_lp();
    expect_d0(2'b11);
    expect_rom_entry(addr + 1);
    expect_wait_idle();  // El nuevo BYTE o END ya está, aún no se leyó en ↑.
    @(posedge CLK_BYTE); #1;
    if ({INIT_REQ, INIT_DONE} !== {!final_packet, final_packet})
      $fatal(1, "paquete %0d: no se publicó el siguiente INIT_REQ o INIT_DONE tras WAIT", packet);
  endtask

  task automatic check_init(input string etapa);
    integer addr, bytes_seen, long_waits;
    addr = 0;
    bytes_seen = 0;
    long_waits = 0;
    @(posedge CLK_BYTE); #1;
    expect_rom_entry(0);
    for (integer packet = 1; packet <= PACKETS; packet = packet + 1) begin
      receive_lp_packet(packet, addr, bytes_seen);
      check_wait(packet, addr);
      if (reference_rom[addr][7:0] == 8'd65) long_waits = long_waits + 1;
      addr = addr + 1;
    end
    if (addr != ROM_WORDS - 1 || bytes_seen != DSI_BYTES || long_waits != 2)
      $fatal(1, "Totales LP incorrectos: %0d bytes, %0d WAIT largos, dir. final %0d",
             bytes_seen, long_waits, addr);
    $display("PASS LP (%s, %0d ciclos/ms): 18 paquetes, 18 selectores 87, 204 bytes DSI, 18 WAIT exactos y END",
             etapa, P);
  endtask

  // Referencia por píxel y componente, no por fase de palabra del RTL.
  function automatic [7:0] rgb_byte(input integer index);
    reg [23:0] rgb;
    case (index / (90 * 3))
      0: rgb = 24'hf0e0d0;
      1: rgb = 24'hf0e030;
      2: rgb = 24'h10e0d0;
      3: rgb = 24'h10e030;
      4: rgb = 24'hf020d0;
      5: rgb = 24'hf02030;
      6: rgb = 24'h1020d0;
      7: rgb = 24'h102030;
      default: rgb = 24'hxxxxxx;
    endcase
    case (index % 3)
      0: rgb_byte = rgb[23:16];
      1: rgb_byte = rgb[15:8];
      default: rgb_byte = rgb[7:0];
    endcase
  endfunction

  // Referencia bit a bit en representación MSB (0x1021), entrada LSB
  // primero y reflexión al final; no llama a la lógica 0x8408 del DUT.
  function automatic [15:0] crc_msb_byte(input [15:0] crc, input [7:0] data);
    reg [15:0] remnant;
    reg feedback;
    remnant = crc;
    for (integer b = 0; b < 8; b = b + 1) begin
      feedback = remnant[15] ^ data[b];
      remnant = remnant << 1;
      if (feedback) remnant = remnant ^ 16'h1021;
    end
    crc_msb_byte = remnant;
  endfunction

  function automatic [15:0] reflect16(input [15:0] crc);
    for (integer b = 0; b < 16; b = b + 1) reflect16[b] = crc[15-b];
  endfunction

`ifdef PHY_GOWIN
  `include "check_hs_pads.vh"
`else
  task automatic sample_hs;
    sample_negedge();
    if ({INIT_DONE, INIT_REQ, INIT_NEXT, INIT_DONE_TX} !== 4'b1000 || CLK_LP !== 2'b11)
      $fatal(1, "ciclo %0d: init reabierta, INIT_DONE perdido o CLK LP inválido en vídeo", cycle);
  endtask

  task automatic expect_hs_control(input [1:0] pn, input bit clk, hs);
    if ({D0_LP, D1_LP, CLK_REQ, HS_REQ} !== {pn, pn, clk, hs})
      $fatal(1, "ciclo %0d: LP D0/D1=%b/%b CLK_REQ/HS_REQ=%b/%b, esperado %b/%b %b/%b",
             cycle, D0_LP, D1_LP, CLK_REQ, HS_REQ, pn, pn, clk, hs);
  endtask

  task automatic expect_no_take(input bit trail, input [15:0] registered);
    if ({phy_take, phy_last, phy_trail, vid_rd_sample} !== {2'b00, trail, 1'b0} ||
        registered_word !== registered)
      $fatal(1, "ciclo %0d: palabra extra, lectura fuera de datos o registro/trail incorrecto (HS=%04h)",
             cycle, registered_word);
  endtask

  task automatic start_hs(output integer first_lp01);
    do begin
      sample_hs();
      if ({D0_LP, D1_LP} !== 4'b0101) begin
        expect_hs_control(2'b11, 0, 0);
        expect_no_take(0, 16'h0000);
      end
    end while ({D0_LP, D1_LP} !== 4'b0101);
    first_lp01 = cycle;

    for (integer t = 0; t < T_LPX + T_PREP + T_ZERO; t = t + 1) begin
      expect_hs_control((t < T_LPX) ? 2'b01 : 2'b00, 1, t >= T_LPX + T_PREP);
      expect_no_take(0, 16'h0000);
      sample_hs();
    end
    // ↓−1: PHY_IF registra SoT, el PHY todavía no lo toma.
    expect_hs_control(2'b00, 1, 1);
    expect_no_take(0, 16'hb8b8);
    if ({dut.SOT_EN, dut.PK_START} !== 2'b10)
      $fatal(1, "ciclo %0d: SoT y PK_START no están en ↓ separados", cycle);
  endtask

  task automatic receive_hs(input integer words, output integer first_lp01, reads);
    reg [15:0] reference_crc, expected_word;
    integer offset;
    bit last, expect_read;
    start_hs(first_lp01);
    reference_crc = 16'hffff;
    reads = 0;
    for (integer n = 0; n < words; n = n + 1) begin
      sample_hs();  // n=0: ↓0, el packer empieza y el PHY consume SoT.
      last = n == CRC_TAKE;
      expect_read = n >= 2 && n < 2 + PIX_WORDS;
      expect_hs_control(2'b00, 1, !last);
      if ({phy_take, phy_last, phy_trail} !== {1'b1, last, 1'b0} ||
          vid_rd_sample !== expect_read)
        $fatal(1, "ciclo %0d, consumo HS %0d: falta/sobra palabra o VID_RD en ↓ incorrecto",
               cycle, n);
      if (vid_rd_sample) reads = reads + 1;
      if (dut.SOT_EN !== 1'b0 || dut.PK_START !== (n == 0) || dut.PK_DONE !== (n == CRC_TAKE - 1))
        $fatal(1, "ciclo %0d, ↓%0d: SOT_EN/PK_START/PK_DONE fuera de flanco", cycle, n);

      case (n)
        0: begin
          expected_word = 16'hb8b8;
          if (registered_word !== 16'h703e)
            $fatal(1, "ciclo %0d: ↓0 debe registrar W0 3E/70, no repetir SoT (HS=%04h)",
                   cycle, registered_word);
        end
        1: expected_word = 16'h703e;
        2: expected_word = 16'h1308;
        CRC_TAKE: begin
          expected_word = reflect16(reference_crc);
          if (registered_word !== 16'h0000)
            $fatal(1, "ciclo %0d: PHY_IF no salió de HS en el ↓ de drenaje del CRC", cycle);
        end
        default: begin
          offset = 2 * (n - 3);
          expected_word = {rgb_byte(offset + 1), rgb_byte(offset)};
          // CRC sobre el payload realmente consumido: reintercalar D0, luego D1.
          reference_crc = crc_msb_byte(reference_crc, taken_word[7:0]);
          reference_crc = crc_msb_byte(reference_crc, taken_word[15:8]);
        end
      endcase
      if (taken_word !== expected_word)
        $fatal(1, "ciclo %0d, consumo HS %0d: D0/D1=%02h/%02h, esperado %02h/%02h",
               cycle, n, taken_word[7:0], taken_word[15:8], expected_word[7:0], expected_word[15:8]);
    end

    if (words == HS_WORDS) begin
      if (reads != PIX_WORDS) $fatal(1, "Línea HS con %0d lecturas; esperado %0d", reads, PIX_WORDS);
      repeat (T_TRAIL) begin
        sample_hs();
        expect_hs_control(2'b00, 1, 0);
        expect_no_take(1, 16'h0000);
      end
      sample_hs();  // Primer LP11: no más consumos, tampoco durante la espera residual.
      expect_hs_control(2'b11, 0, 0);
      expect_no_take(0, 16'h0000);
      $display("  HS LP01 en ciclo %0d: %0d pares, %0d lecturas, CRC D0/D1=%02h/%02h",
               first_lp01, words, reads, expected_word[7:0], expected_word[15:8]);
    end
  endtask

  initial begin : scenario
    string init_hex;
    reg [15:0] check_crc;
    integer first, second, partial, restarted, reads;
    if (!$value$plusargs("init_hex=%s", init_hex)) $fatal(1, "Falta +init_hex=<ROM original>");
    $readmemh(init_hex, reference_rom);
    if (reference_rom[ROM_WORDS-1] !== ROM_END) $fatal(1, "Falta END en la ROM de referencia");
    check_crc = 16'hffff;
    for (integer ascii = 49; ascii <= 57; ascii = ascii + 1)  // «123456789».
      check_crc = crc_msb_byte(check_crc, ascii[7:0]);
    if (reflect16(check_crc) !== 16'h6f91) $fatal(1, "Referencia CRC16 inválida");

    reset_link(0);
    check_init("arranque");
    receive_hs(HS_WORDS, first, reads);
    receive_hs(HS_WORDS, second, reads);
    if (second - first != C_LINE)
      $fatal(1, "LP01 a LP01: %0d ciclos, esperado C_LINE=%0d", second - first, C_LINE);
    $display("PASS p%0d HS: dos ráfagas consecutivas, C_LINE=%0d, CRC drenado sin palabra extra",
             PROFILE, C_LINE);

    receive_hs(2 + ABORT_READS, partial, reads);
    if (partial - second != C_LINE)
      $fatal(1, "LP01 a LP01 antes de abortar: %0d ciclos, esperado %0d", partial - second, C_LINE);
    if (reads != ABORT_READS || {VID_RD, HS_REQ} !== 2'b11)
      $fatal(1, "El reset de prueba debe llegar en pleno payload");
    reset_link(1);
    check_init("tras reset");
    receive_hs(HS_WORDS, restarted, reads);
    $display("PASS p%0d reset: descarta la ráfaga parcial; reenvía LP y vuelve a SoT/W0/P0", PROFILE);
    $finish;
  end

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("mipi_tx_TB.fst");
      $dumpvars(1, mipi_tx_TB, dut, seq, seq.d_count, video, phy);
    end
    repeat (60_000) @(posedge CLK_BYTE);
    $fatal(1, "Tiempo agotado en mipi_tx_TB");
  end
`endif
endmodule

`undef TB_SEQ
`undef TB_VIDEO
`undef TB_PHY
`undef TB_SUPERVISOR
