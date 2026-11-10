`timescale 1ns / 1ps

module pattern_case #(parameter WIDTH = 8, parameter HEIGHT = 1) (output reg done = 0);
  reg clk = 0;
  initial begin
    while (!done) begin #12.5; clk = ~clk; end
  end
  reg rst = 1, start_valid = 0, ready = 0;
  wire start_ready, valid, line_last, frame_last, busy, frame_done;
  wire [7:0] data;
  dsi_test_pattern #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (
      .clk(clk), .rst(rst), .start_valid(start_valid), .start_ready(start_ready),
      .tx_byte_data(data), .tx_byte_valid(valid), .tx_byte_ready(ready),
      .tx_line_last(line_last), .tx_frame_last(frame_last),
      .busy(busy), .frame_done(frame_done)
  );
  localparam TOTAL = WIDTH * HEIGHT * 3;
  integer index = 0, lines = 0, completed = 0, starts = 0, aborted = 0;
  integer stalls = 0, cycles = 0;
  reg active = 0, expected_done = 0;
  reg stalled = 0;
  reg [9:0] held;
  reg [13:0] between_edges;
  reg previous_rst = 1;

  // Referencia por indice lineal. No observa contadores ni estado del DUT.
  function [7:0] reference_byte;
    input integer n;
    integer column, component, band;
    reg [23:0] color;
    begin
      column = (n / 3) % WIDTH;
      component = n % 3;
      band = (column * 8) / WIDTH;
      case (band)
        0: color = 24'hffffff;
        1: color = 24'hffff00;
        2: color = 24'h00ffff;
        3: color = 24'h00ff00;
        4: color = 24'hff00ff;
        5: color = 24'hff0000;
        6: color = 24'h0000ff;
        default: color = 24'h000000;
      endcase
      reference_byte = color >> (16 - 8 * component);
    end
  endfunction

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (rst) begin
      if ({start_ready, valid, data, line_last, frame_last} !== 12'b0)
        $fatal(1, "%0dx%0d: salidas activas en reset", WIDTH, HEIGHT);
      if (active) aborted = aborted + 1;
      active = 0; expected_done = 0; index = 0; lines = 0; stalled = 0;
    end else begin
      if (busy !== active || start_ready !== !active || valid !== active)
        $fatal(1, "%0dx%0d: handshake/ocupacion incorrectos", WIDTH, HEIGHT);
      if (stalled && {data, line_last, frame_last} !== held)
        $fatal(1, "Salida inestable con ready=0");
      expected_done = 0;
      if (valid) begin
        if (data !== reference_byte(index) ||
            line_last !== (index % (3*WIDTH) == 3*WIDTH-1) ||
            frame_last !== (index == TOTAL-1))
          $fatal(1, "%0dx%0d: byte/marcas incorrectos en %0d: %02h",
                 WIDTH, HEIGHT, index, data);
        if (ready) begin
          index = index + 1;
          if (line_last) lines = lines + 1;
          if (frame_last) begin
            if (index != TOTAL || lines != HEIGHT) $fatal(1, "Cantidad incorrecta");
            active = 0; expected_done = 1; completed = completed + 1;
          end
        end else stalls = stalls + 1;
      end else if ({data, line_last, frame_last} !== 10'b0)
        $fatal(1, "Datos/marcas sin valid");
      if (start_valid && start_ready) begin
        active = 1; index = 0; lines = 0; starts = starts + 1;
      end
      stalled = valid && !ready;
      held = {data, line_last, frame_last};
    end
    #1;
    if (frame_done !== expected_done || busy !== active || valid !== (active && !rst))
      $fatal(1, "%0dx%0d: resultado del posedge incorrecto", WIDTH, HEIGHT);
    if (!valid && {data, line_last, frame_last} !== 10'b0)
      $fatal(1, "Mascara no aplicada al terminar/resetear");
    between_edges = {busy, frame_done, start_ready, valid, data, line_last, frame_last};
    previous_rst = rst;
  end

  // Los estimulos cambian en negedge; las salidas no avanzan en ese flanco.
  always @(negedge clk) begin
    #1;
    if (!rst && !previous_rst &&
        {busy, frame_done, start_ready, valid, data, line_last, frame_last} !== between_edges)
      $fatal(1, "Actualizacion fuera de posedge");
  end

  task reset_block;
    reg old_busy, old_done;
    begin
      @(negedge clk);
      old_busy = busy; old_done = frame_done;
      rst = 1; start_valid = 1; ready = 1;
      #2;
      if ({start_ready, valid, data, line_last, frame_last} !== 12'b0 ||
          busy !== old_busy || frame_done !== old_done)
        $fatal(1, "Reset: mascara inmediata o memoria sincrona incorrecta");
      @(posedge clk); #2;
      @(negedge clk);
      rst = 0; start_valid = 0; ready = 0;
    end
  endtask

  integer tick, target, position, paused_index = -1, pause_left = 0;
  reg [31:0] rng = 32'h43f1a9bc;
  initial begin
    reset_block();
    repeat (3) @(negedge clk);
    // Dos cuadros con solicitud sostenida. El primero no tiene pausas;
    // el segundo se pausa en R/G/B y durante tres ciclos en cada fin de linea.
    start_valid = 1; ready = 1;
    tick = 0;
    while (completed < 2) begin
      @(negedge clk);
      tick = tick + 1;
      rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
      ready = completed == 0 || ((tick % 19 > 2) && rng[0]);
      if (completed == 1 && valid && (index < 3 || line_last)) begin
        if (paused_index != index) begin
          paused_index = index;
          pause_left = 3;
        end
        if (pause_left > 0) begin
          ready = 0;
          pause_left = pause_left - 1;
        end
      end
      if (tick > 10*TOTAL+100) $fatal(1, "Timeout de cuadro");
    end
    start_valid = 0; ready = 0;
    repeat (4) @(negedge clk);
    if (starts != 2 || stalls == 0) $fatal(1, "Cobertura de repeticion/pausa insuficiente");

    // Reset en cada componente y limites; sin inyectar estado interno.
    if (WIDTH <= 24) begin
      for (position = 0; position < 6; position = position + 1) begin
        start_valid = 1; ready = 1;
        @(negedge clk);
        start_valid = 0;
        case (position)
          0: target = 0;           // primer R
          1: target = 1;           // G
          2: target = 2;           // B
          3: target = 3*WIDTH-1;   // ultimo B de linea
          4: target = TOTAL-2;     // ultimo G
          default: target = TOTAL-1; // ultimo B, listo para aceptarse
        endcase
        while (index < target) @(negedge clk);
        ready = 0;
        repeat (3) @(negedge clk);
        reset_block();
        if (completed != 2 || frame_done) $fatal(1, "Reset produjo exito falso");
      end
      // Solicitud de un ciclo durante STREAM se ignora y no queda en cola.
      start_valid = 1; ready = 1;
      @(negedge clk); start_valid = 0;
      @(negedge clk); start_valid = 1;
      @(negedge clk); start_valid = 0;
      while (completed < 3) @(negedge clk);
      repeat (4) @(negedge clk);
      if (busy || !start_ready || valid || aborted != 6 || starts != 9)
        $fatal(1, "Solicitud en STREAM/reset/reinicio incorrectos");
    end
    $display("PASS RTL %0dx%0d: %0d cuadros, %0d abortos, %0d pausas, bytes y marcas exactos",
             WIDTH, HEIGHT, completed, aborted, stalls);
    done = 1;
  end
endmodule

module dsi_test_pattern_TB;
  wire [3:0] done;
  pattern_case #(.WIDTH(8), .HEIGHT(1)) p0 (.done(done[0]));
  pattern_case #(.WIDTH(16), .HEIGHT(2)) p1 (.done(done[1]));
  pattern_case #(.WIDTH(24), .HEIGHT(3)) p2 (.done(done[2]));
  pattern_case #(.WIDTH(720), .HEIGHT(720)) p3 (.done(done[3]));
  initial begin
    wait (&done);
    $display("PASS dsi_test_pattern: todos los perfiles");
    $finish;
  end
  initial begin
    #400000000;
    $fatal(1, "Timeout global");
  end
endmodule
