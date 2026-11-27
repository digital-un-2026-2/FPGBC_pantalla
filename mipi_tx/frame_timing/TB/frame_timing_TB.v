`timescale 1ns / 1ps

module frame_timing_TB #(
    parameter integer PROFILE = 0
);
  localparam integer T_CLK = 20;
  // El reloj del banco es lógico. PROFILE=1 prueba la separación aprobada
  // de admisiones, no genera ni mide las señales del PHY a 55 MHz.
  localparam integer C_LINE = (PROFILE == 0) ? 1 : 1168;
  localparam integer PERIODS = 743;
  localparam [1:0] VSS = 2'b00, HSS = 2'b01, RGB = 2'b10;

  reg CLK_BYTE = 0;
  always #(T_CLK/2) CLK_BYTE = !CLK_BYTE;
  reg RST_BYTE = 1, BURST_START = 0;
  wire [1:0] BURST_KIND;

  frame_timing dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .BURST_START(BURST_START),
      .BURST_KIND(BURST_KIND)
  );

  // Referencia como receta expandida, independiente de los comparadores RTL.
  reg [1:0] recipe [0:PERIODS-1];
  integer expected_next = 0;
  reg [1:0] expected_kind = VSS;
  integer starts = 0, reset_samples = 0;
  integer checked_edges = 0;

  task automatic check_registers(input string event_name);
    if (dut.NEXT_PERIOD !== expected_next[9:0] || BURST_KIND !== expected_kind)
      $fatal(1, "p%0d %s: indice/tipo=%0d/%b, esperado %0d/%b",
             PROFILE, event_name, dut.NEXT_PERIOD, BURST_KIND, expected_next, expected_kind);
  endtask

  // Se comprueba primero el valor presentado antes del flanco y, aparte,
  // el valor publicado tras las asignaciones no bloqueantes.
  always @(negedge CLK_BYTE) begin
    if (checked_edges != 0) check_registers("antes de ↓");
    if (RST_BYTE) begin
      expected_next = 0;
      expected_kind = VSS;
      reset_samples = reset_samples + 1;
    end else if (BURST_START) begin
      expected_kind = recipe[expected_next];
      expected_next = (expected_next + 1) % PERIODS;
      starts = starts + 1;
    end
    #1;
    check_registers("despues de ↓");
    checked_edges = checked_edges + 1;
  end

  always @(posedge CLK_BYTE) begin
    #1;
    if (checked_edges != 0) check_registers("↑ no actualiza datapath");
  end

  task automatic idle(input integer cycles);
    BURST_START = 0;
    repeat (cycles) begin
      @(negedge CLK_BYTE);
      #2;
    end
  endtask

  // Emula un control publicado tras ↑, estable antes del ↓ de captura.
  task automatic admit;
    integer old_next, old_starts;
    reg [1:0] old_kind;
    old_next = expected_next;
    old_kind = expected_kind;
    old_starts = starts;
    @(posedge CLK_BYTE);
    #2;
    BURST_START = 1;
    #1;
    if (dut.NEXT_PERIOD !== old_next[9:0] || BURST_KIND !== old_kind)
      $fatal(1, "BURST_START cambio el datapath antes de ↓");
    @(negedge CLK_BYTE);
    #2;
    if (starts != old_starts + 1)
      $fatal(1, "Se perdio la admision");
    BURST_START = 0;
  endtask

  // Reset común mantenido en ↑ y ↓; también se prueba inicio concurrente.
  task automatic reset_frame(input bit competing_start);
    integer old_next, old_starts;
    reg [1:0] old_kind;
    old_next = expected_next;
    old_kind = expected_kind;
    old_starts = starts;
    RST_BYTE = 1;
    BURST_START = competing_start;
    @(posedge CLK_BYTE);
    #2;
    if (dut.NEXT_PERIOD !== old_next[9:0] || BURST_KIND !== old_kind)
      $fatal(1, "Reset sincrono en ↓ actuo antes del flanco");
    @(negedge CLK_BYTE);
    #2;
    if (expected_next != 0 || BURST_KIND !== VSS || starts != old_starts)
      $fatal(1, "Reset no gano al inicio");
    BURST_START = 0;
    RST_BYTE = 0;
    idle(3);
  endtask

  task automatic check_two_frames;
    integer n_vss, n_hss, n_rgb, before_starts;
    time last_start;
    before_starts = starts;
    last_start = 0;
    for (integer frame = 0; frame < 2; frame = frame + 1) begin
      n_vss = 0;
      n_hss = 0;
      n_rgb = 0;
      for (integer n = 0; n < PERIODS; n = n + 1) begin
        if (expected_next != n) $fatal(1, "Salto de periodo entre admisiones");
        admit();
        if (last_start != 0 && $time - last_start != C_LINE * T_CLK)
          $fatal(1, "Separacion de admisiones distinta de C_LINE");
        last_start = $time;
        case (BURST_KIND)
          VSS: n_vss = n_vss + 1;
          HSS: n_hss = n_hss + 1;
          RGB: n_rgb = n_rgb + 1;
          default: $fatal(1, "Descriptor reservado");
        endcase
        idle(C_LINE - 1);
      end
      if (n_vss != 3 || n_hss != 20 || n_rgb != 720 || expected_next != 0 ||
          BURST_KIND !== HSS)
        $fatal(1, "Cuadro %0d incorrecto: VSS/HSS/RGB=%0d/%0d/%0d",
               frame, n_vss, n_hss, n_rgb);
    end
    if (starts - before_starts != 2 * PERIODS)
      $fatal(1, "Numero de admisiones incorrecto");
    $display("PASS p%0d: dos cuadros de 743 periodos, 3 VSS / 20 HSS / 720 RGB, C_LINE=%0d",
             PROFILE, C_LINE);
  endtask

  task automatic reset_at_boundary(input integer pending_period);
    reset_frame(0);
    repeat (pending_period) admit();
    if (expected_next != pending_period)
      $fatal(1, "El escenario no alcanzo la frontera de reset");
    idle(7);
    reset_frame(1);
    admit();
    if (expected_next != 1 || BURST_KIND !== VSS)
      $fatal(1, "La primera admision tras reset no fue el periodo 0");
  endtask

  initial begin : scenario
    integer cursor;
    cursor = 0;
    repeat (3) begin recipe[cursor] = VSS; cursor = cursor + 1; end
    repeat (8) begin recipe[cursor] = HSS; cursor = cursor + 1; end
    repeat (720) begin recipe[cursor] = RGB; cursor = cursor + 1; end
    repeat (12) begin recipe[cursor] = HSS; cursor = cursor + 1; end
    if (cursor != PERIODS) $fatal(1, "Referencia de cuadro incompleta");

    repeat (2) @(negedge CLK_BYTE);
    #2;
    RST_BYTE = 0;
    idle(11);
    check_two_frames();
    // El periodo pendiente es VSS, pero el tipo actual debe seguir HSS.
    idle(2 * C_LINE + 3);
    if (BURST_KIND !== HSS || expected_next != 0)
      $fatal(1, "El descriptor no se retuvo al cruzar de cuadro sin admision");
    admit();
    if (BURST_KIND !== VSS) $fatal(1, "Falta VSS tras el segundo cuadro");
    $display("PASS p%0d: retencion sin inicio y publicacion de inicio en ↑", PROFILE);

    reset_at_boundary(0);
    reset_at_boundary(3);
    reset_at_boundary(11);
    reset_at_boundary(371);
    reset_at_boundary(731);
    reset_at_boundary(742);
    // Reiniciar despues de consumir el ultimo periodo del cuadro.
    reset_at_boundary(0);
    repeat (742) admit();
    if (BURST_KIND !== HSS || expected_next != 0)
      $fatal(1, "No se alcanzo el final de cuadro antes del reset");
    reset_frame(1);
    $display("PASS p%0d: reset prioritario en fronteras, mitad RGB y fin de cuadro (%0d muestras)",
             PROFILE, reset_samples);

    // Contrato por nivel muestreado: tres ↓ con inicio alto son tres
    // admisiones, no una deteccion del flanco ascendente de la peticion.
    @(posedge CLK_BYTE); #2;
    BURST_START = 1;
    repeat (3) begin @(negedge CLK_BYTE); #2; end
    BURST_START = 0;
    if (expected_next != 3 || BURST_KIND !== VSS)
      $fatal(1, "BURST_START se trato como flanco en vez de habilitacion");
    admit();
    if (expected_next != 4 || BURST_KIND !== HSS)
      $fatal(1, "Frontera VSS/HSS incorrecta con admisiones consecutivas");
    $display("PASS p%0d: habilitacion por ↓ y descriptor del indice anterior", PROFILE);
    $finish;
  end

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("frame_timing_TB.fst");
      $dumpvars(1, frame_timing_TB, dut, dut.count, dut.kind);
    end
    #(T_CLK * (2 * PERIODS * C_LINE + 10 * C_LINE + 20_000));
    $fatal(1, "Tiempo agotado en frame_timing_TB");
  end
endmodule
