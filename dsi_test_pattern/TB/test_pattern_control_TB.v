`timescale 1ns / 1ps

module test_pattern_control_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst = 0, start = 0, ready = 0, is_b = 0, x_end = 0, y_end = 0;
  wire init, step_comp, step_pixel, step_line, start_ready, valid, busy, done;
  test_pattern_control dut (
      .clk(clk), .rst(rst), .start_valid(start), .tx_byte_ready(ready),
      .is_b(is_b), .x_end(x_end), .y_end(y_end),
      .init(init), .step_comp(step_comp), .step_pixel(step_pixel), .step_line(step_line),
      .start_ready(start_ready), .tx_byte_valid(valid), .busy(busy), .frame_done(done)
  );
  integer c;
  reg old_state, old_done, next_state, finish;
  reg [3:0] expected_loads;
  initial begin
    // Inyeccion solo en esta prueba de UC; matriz de todos los valores binarios.
    for (c = 0; c < 256; c = c + 1) begin
      @(negedge clk);
      {old_state, old_done, rst, start, ready, is_b, x_end, y_end} = c[7:0];
      dut.state = old_state;
      dut.frame_done = old_done;
      expected_loads = 0; finish = 0; next_state = old_state;
      if (rst) next_state = 0;
      else if (!old_state) begin
        if (start) begin expected_loads = 4'b1000; next_state = 1; end
      end else if (ready) begin
        if (!is_b) expected_loads = 4'b0100;
        else if (!x_end) expected_loads = 4'b0010;
        else if (!y_end) expected_loads = 4'b0001;
        else begin finish = 1; next_state = 0; end
      end
      #2;
      if ({init, step_comp, step_pixel, step_line} !== expected_loads ||
          start_ready !== (!rst && !old_state) || valid !== (!rst && old_state) ||
          busy !== old_state || done !== old_done || dut.finish !== finish)
        $fatal(1, "UC: combinacion %0d incorrecta", c);
      @(posedge clk); #2;
      if (dut.state !== next_state || done !== finish || busy !== next_state)
        $fatal(1, "UC: transicion/R_DONE incorrectos en caso %0d", c);
    end
    $display("PASS UC: 256 combinaciones, cargas en el mismo flanco y prioridad de reset");
    $finish;
  end
endmodule
